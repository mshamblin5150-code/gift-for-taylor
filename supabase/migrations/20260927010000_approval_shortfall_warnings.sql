-- The staffing read and approval projections share the Shortfall arithmetic.
create function public.coverage_shortfalls(
  p_minimum integer,
  p_floor integer,
  p_working_count integer,
  p_floor_count integer
)
returns table(shortfall integer, floor_shortfall integer)
language sql immutable set search_path = '' as $$
  select
    case when p_minimum is null then null else greatest(
      p_minimum - p_working_count, p_floor - p_floor_count, 0) end,
    case when p_minimum is null then null else greatest(
      p_floor - p_floor_count, 0) end;
$$;

revoke all on function public.coverage_shortfalls(
  integer, integer, integer, integer
) from public, anon, authenticated;

create or replace function public.section_staffing_for_month(p_month date)
returns table(pool text, coverage_window text, work_date date, minimum integer,
  rn_floor integer, working_count integer, rn_count integer, open_count integer,
  rn_open_count integer, shortfall integer, rn_shortfall integer,
  weekday_minimum integer, date_minimum integer)
language sql stable security definer set search_path = '' as $$
  with days as (
    select day.work_date::date from generate_series(date_trunc('month', p_month)::date,
      (date_trunc('month', p_month) + interval '1 month - 1 day')::date,
      interval '1 day') as day(work_date)
  ), keys as (
    select identity.id as pool, cov.coverage_window, days.work_date
    from public.coverage_pools identity
    cross join (values ('day'), ('night')) as cov(coverage_window)
    cross join days
    cross join lateral public.coverage_pool_version_on(identity.id, days.work_date) version
    where not version.retired
  ), working_roles as (
    select cell.work_date, public.coverage_pool_on(role.job_role, cell.work_date) as pool,
      code.coverage_window, role.job_role, count(*)::integer as people
    from public.schedule_cells cell
    join public.schedule_months month on month.id = cell.schedule_month_id
      and month.release_state in ('unpublished', 'released')
    join public.staff_job_roles role on role.staff_member_id = cell.staff_member_id
      and role.effective_from <= cell.work_date
      and (role.effective_through is null or role.effective_through >= cell.work_date)
    join public.shift_codes code on code.code = upper(trim(cell.shift_code))
      and code.coverage_window is not null
    where cell.work_date in (select days.work_date from days)
      and public.is_working_shift(cell.shift_code)
    group by cell.work_date, 2, code.coverage_window, role.job_role
  ), open_roles as (
    select short.work_date,
      public.coverage_pool_on(coalesce(short.job_role, original.job_role), short.work_date) as pool,
      code.coverage_window, coalesce(short.job_role, original.job_role) as job_role,
      count(*)::integer as opened,
      count(*) filter (where short.rn_floor_critical)::integer as floor_opened
    from public.short_shifts short
    left join lateral (
      select role.job_role from public.staff_job_roles role
      where role.staff_member_id = short.staff_member_id
        and role.effective_from <= short.work_date
      order by role.effective_from desc limit 1
    ) original on true
    join public.shift_codes code on code.code = upper(trim(short.shift_code))
      and code.coverage_window is not null
    where short.work_date in (select days.work_date from days)
      and short.filled_at is null and public.is_working_shift(short.shift_code)
    group by short.work_date, 2, code.coverage_window, 4
  ), counts as (
    select keys.pool, keys.coverage_window, keys.work_date,
      coalesce(date_rule.minimum, week_rule.minimum) as minimum,
      coalesce(date_rule.rn_floor, week_rule.rn_floor, 0) as floor_minimum,
      public.coverage_floor_role_on(keys.pool, keys.coverage_window,
        keys.work_date) as floor_role,
      coalesce((select sum(people) from working_roles w where w.pool = keys.pool
        and w.coverage_window = keys.coverage_window and w.work_date = keys.work_date), 0)::integer
        as working_count,
      coalesce((select sum(people) from working_roles w where w.pool = keys.pool
        and w.coverage_window = keys.coverage_window and w.work_date = keys.work_date
        and w.job_role = public.coverage_floor_role_on(keys.pool,
          keys.coverage_window, keys.work_date)), 0)::integer
        as floor_count,
      coalesce((select sum(opened) from open_roles o where o.pool = keys.pool
        and o.coverage_window = keys.coverage_window and o.work_date = keys.work_date), 0)::integer
        as open_count,
      coalesce((select sum(floor_opened) from open_roles o where o.pool = keys.pool
        and o.coverage_window = keys.coverage_window and o.work_date = keys.work_date), 0)::integer
        as floor_open_count,
      week_rule.minimum as weekday_minimum, date_rule.minimum as date_minimum
    from keys
    left join lateral (
      select rule.* from public.pool_weekday_minimums rule
      where rule.pool = keys.pool and rule.coverage_window = keys.coverage_window
        and rule.weekday = extract(dow from keys.work_date)::integer
        and rule.effective_from <= keys.work_date
      order by rule.effective_from desc limit 1
    ) week_rule on true
    left join public.pool_date_minimums date_rule on date_rule.pool = keys.pool
      and date_rule.coverage_window = keys.coverage_window
      and date_rule.work_date = keys.work_date
  )
  select counts.pool, counts.coverage_window, counts.work_date, counts.minimum,
    counts.floor_minimum, counts.working_count, counts.floor_count,
    counts.open_count, counts.floor_open_count,
    projected.shortfall, projected.floor_shortfall,
    counts.weekday_minimum, counts.date_minimum
  from counts
  cross join lateral public.coverage_shortfalls(
    counts.minimum, counts.floor_minimum,
    counts.working_count, counts.floor_count
  ) projected
  where public.is_active_staff_member();
$$;

-- Approval cards share one typed floor-Shortfall check for dated movements.
create type public.approval_shift_move as (
  work_date date,
  shift_code text,
  from_role public.job_role,
  to_role public.job_role
);

create function public.approval_moves_create_shortfall(
  p_moves public.approval_shift_move[]
)
returns boolean language sql stable security definer set search_path = '' as $$
  with moves as (
    select move.work_date, move.from_role, move.to_role,
      public.coverage_pool_on(move.from_role, move.work_date) as source_pool,
      public.coverage_pool_on(move.to_role, move.work_date) as destination_pool,
      code.coverage_window
    from unnest(coalesce(
      p_moves, array[]::public.approval_shift_move[]
    )) move
    join public.shift_codes code
      on code.code = upper(trim(move.shift_code))
      and code.coverage_window is not null
  ), impacts as (
    select move.work_date, move.source_pool as pool, move.coverage_window,
      -1 as working_delta,
      case when move.from_role = public.coverage_floor_role_on(
        move.source_pool, move.coverage_window, move.work_date
      ) then -1 else 0 end as floor_delta
    from moves move
    union all
    select move.work_date, move.destination_pool, move.coverage_window,
      1,
      case when move.to_role = public.coverage_floor_role_on(
        move.destination_pool, move.coverage_window, move.work_date
      ) then 1 else 0 end
    from moves move
  ), deltas as (
    select impact.work_date, impact.pool, impact.coverage_window,
      sum(impact.working_delta)::integer as working_delta,
      sum(impact.floor_delta)::integer as floor_delta
    from impacts impact
    group by impact.work_date, impact.pool, impact.coverage_window
  )
  select exists (
    select 1
    from deltas delta
    join lateral public.section_staffing_for_month(delta.work_date) staffing
      on staffing.work_date = delta.work_date
      and staffing.pool = delta.pool
      and staffing.coverage_window = delta.coverage_window
    cross join lateral public.coverage_shortfalls(
      staffing.minimum, staffing.rn_floor,
      staffing.working_count + delta.working_delta,
      staffing.rn_count + delta.floor_delta
    ) projected
    where projected.shortfall > staffing.shortfall
      or projected.floor_shortfall > staffing.rn_shortfall
  );
$$;

revoke all on function public.approval_moves_create_shortfall(
  public.approval_shift_move[]
)
from public, anon, authenticated;

create function public.swap_creates_shortfall(p_swap_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.approval_moves_create_shortfall(array_agg(row(
    shift.work_date, shift.shift_code,
    source_role.job_role, destination_role.job_role
  )::public.approval_shift_move)), false)
  from public.swaps swap
  join public.swap_shifts shift on shift.swap_id = swap.id
  join public.staff_job_roles source_role
    on source_role.staff_member_id = case shift.side
      when 'requester' then swap.requester_id else swap.colleague_id end
    and source_role.effective_from <= shift.work_date
    and (source_role.effective_through is null
      or source_role.effective_through >= shift.work_date)
  join public.staff_job_roles destination_role
    on destination_role.staff_member_id = case shift.side
      when 'requester' then swap.colleague_id else swap.requester_id end
    and destination_role.effective_from <= shift.work_date
    and (destination_role.effective_through is null
      or destination_role.effective_through >= shift.work_date)
  where swap.id = p_swap_id
    and (public.current_staff_role() = 'manager'
      or public.current_staff_member_id() in (
        swap.requester_id, swap.colleague_id
      ));
$$;

create function public.open_shift_pickup_creates_shortfall(p_pickup_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.approval_moves_create_shortfall(array[
    row(short.work_date, short.shift_code,
      coalesce(short.job_role, original_role.job_role), pickup_role.job_role
    )::public.approval_shift_move
  ]), false)
  from public.open_shift_pickups pickup
  join public.short_shifts short on short.id = pickup.short_shift_id
  left join lateral (
    select role.job_role
    from public.staff_job_roles role
    where role.staff_member_id = short.staff_member_id
      and role.effective_from <= short.work_date
      and (role.effective_through is null
        or role.effective_through >= short.work_date)
    order by role.effective_from desc limit 1
  ) original_role on true
  join public.staff_job_roles pickup_role
    on pickup_role.staff_member_id = pickup.staff_member_id
    and pickup_role.effective_from <= short.work_date
    and (pickup_role.effective_through is null
      or pickup_role.effective_through >= short.work_date)
  where pickup.id = p_pickup_id
    and (public.current_staff_role() = 'manager'
      or public.current_staff_member_id() = pickup.staff_member_id);
$$;

create or replace function public.giveaway_creates_shortfall(p_giveaway_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.approval_moves_create_shortfall(array_agg(row(
    shift.work_date, shift.shift_code,
    giver_role.job_role, colleague_role.job_role
  )::public.approval_shift_move)), false)
  from public.giveaways giveaway
  join public.giveaway_shifts shift on shift.giveaway_id = giveaway.id
  join public.staff_job_roles giver_role
    on giver_role.staff_member_id = giveaway.giver_id
    and giver_role.effective_from <= shift.work_date
    and (giver_role.effective_through is null
      or giver_role.effective_through >= shift.work_date)
  join public.staff_job_roles colleague_role
    on colleague_role.staff_member_id = giveaway.colleague_id
    and colleague_role.effective_from <= shift.work_date
    and (colleague_role.effective_through is null
      or colleague_role.effective_through >= shift.work_date)
  where giveaway.id = p_giveaway_id
    and (public.current_staff_role() = 'manager'
      or public.current_staff_member_id() in (
        giveaway.giver_id, giveaway.colleague_id
      ));
$$;

revoke all on function public.swap_creates_shortfall(uuid),
  public.open_shift_pickup_creates_shortfall(uuid) from public;
grant execute on function public.swap_creates_shortfall(uuid),
  public.open_shift_pickup_creates_shortfall(uuid) to authenticated;
