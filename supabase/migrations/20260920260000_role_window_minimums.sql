-- A Section is layout and provenance, never a coverage key.
drop function public.post_open_shifts(uuid, date, text, public.job_role, integer, boolean);
drop function public.section_staffing_for_month(date);
drop function public.set_section_weekday_minimum(uuid, integer, integer);
drop function public.set_section_date_minimum(uuid, date, integer);
drop table public.section_date_minimums;
drop table public.section_weekday_minimums;

create table public.pool_weekday_minimums (
  pool text not null check (pool in ('nurses', 'cna', 'unit_clerk')),
  coverage_window text not null check (coverage_window in ('day', 'night')),
  weekday integer not null check (weekday between 0 and 6),
  minimum integer not null check (minimum between 0 and 100),
  rn_floor integer not null default 0 check (rn_floor between 0 and minimum),
  check (pool = 'nurses' or rn_floor = 0),
  primary key (pool, coverage_window, weekday)
);
create table public.pool_date_minimums (
  pool text not null check (pool in ('nurses', 'cna', 'unit_clerk')),
  coverage_window text not null check (coverage_window in ('day', 'night')),
  work_date date not null,
  minimum integer not null check (minimum between 0 and 100),
  rn_floor integer not null default 0 check (rn_floor between 0 and minimum),
  check (pool = 'nurses' or rn_floor = 0),
  primary key (pool, coverage_window, work_date)
);
alter table public.pool_weekday_minimums enable row level security;
alter table public.pool_date_minimums enable row level security;
grant select on public.pool_weekday_minimums, public.pool_date_minimums to authenticated;
create policy "staff read weekday minimums" on public.pool_weekday_minimums
  for select using (public.is_active_staff_member());
create policy "staff read date minimums" on public.pool_date_minimums
  for select using (public.is_active_staff_member());

insert into public.pool_weekday_minimums(pool, coverage_window, weekday, minimum, rn_floor)
select 'nurses', coverage.coverage_window, day.weekday, 3, 1
from (values ('day'), ('night')) as coverage(coverage_window)
cross join generate_series(0, 6) as day(weekday);

create function public.set_pool_weekday_minimum(p_pool text, p_window text,
  p_weekday integer, p_minimum integer, p_rn_floor integer default 0)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the Manager can set staffing minimums';
  end if;
  if p_pool not in ('nurses', 'cna', 'unit_clerk') or p_pool is null
    or p_window not in ('day', 'night') or p_window is null
    or p_weekday not between 0 and 6 or p_minimum not between 0 and 100
    or p_rn_floor not between 0 and p_minimum
    or (p_pool <> 'nurses' and p_rn_floor <> 0) then
    raise exception 'Invalid staffing minimum';
  end if;
  insert into public.pool_weekday_minimums(pool, coverage_window, weekday, minimum, rn_floor)
  values (p_pool, p_window, p_weekday, p_minimum, p_rn_floor)
  on conflict (pool, coverage_window, weekday) do update
    set minimum = excluded.minimum, rn_floor = excluded.rn_floor;
end;
$$;

create function public.set_pool_date_minimum(p_pool text, p_window text,
  p_date date, p_minimum integer, p_rn_floor integer default 0)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the Manager can set staffing minimums';
  end if;
  if p_pool not in ('nurses', 'cna', 'unit_clerk') or p_pool is null
    or p_window not in ('day', 'night') or p_window is null or p_date is null
    or (p_minimum is not null and
      (p_minimum not between 0 and 100 or p_rn_floor not between 0 and p_minimum
        or (p_pool <> 'nurses' and p_rn_floor <> 0))) then
    raise exception 'Invalid staffing minimum';
  end if;
  if p_minimum is null then
    delete from public.pool_date_minimums
    where pool = p_pool and coverage_window = p_window and work_date = p_date;
  else
    insert into public.pool_date_minimums(pool, coverage_window, work_date, minimum, rn_floor)
    values (p_pool, p_window, p_date, p_minimum, p_rn_floor)
    on conflict (pool, coverage_window, work_date) do update
      set minimum = excluded.minimum, rn_floor = excluded.rn_floor;
  end if;
end;
$$;

alter table public.short_shifts alter column section_id drop not null;
alter table public.short_shifts add column requires_approval boolean not null default true;
alter table public.short_shifts add column rn_floor_critical boolean not null default false;

create function public.section_staffing_for_month(p_month date)
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
    select role_pool.pool, coverage.coverage_window, days.work_date
    from (values ('nurses'), ('cna'), ('unit_clerk')) as role_pool(pool)
    cross join (values ('day'), ('night')) as coverage(coverage_window)
    cross join days
  ), working as (
    select cell.work_date,
      case when role.job_role in ('rn', 'lpn') then 'nurses' else role.job_role::text end as pool,
      code.coverage_window,
      count(*)::integer as working_count,
      count(*) filter (where role.job_role = 'rn')::integer as rn_count
    from public.schedule_cells cell
    join public.schedule_months month on month.id = cell.schedule_month_id
      and month.release_state in ('unpublished', 'released')
    join public.staff_job_roles role on role.staff_member_id = cell.staff_member_id
      and role.effective_from <= cell.work_date
      and (role.effective_through is null or role.effective_through >= cell.work_date)
    join public.shift_codes code on code.code = upper(trim(cell.shift_code))
      and code.coverage_window is not null
    where cell.work_date in (select work_date from days)
      and public.is_working_shift(cell.shift_code)
    group by cell.work_date, 2, code.coverage_window
  ), opened as (
    select short.work_date,
      case when coalesce(short.job_role, original.job_role) in ('rn', 'lpn') then 'nurses'
        else coalesce(short.job_role, original.job_role)::text end as pool,
      code.coverage_window,
      count(*)::integer as open_count,
      count(*) filter (where short.rn_floor_critical)::integer as rn_open_count
    from public.short_shifts short
    left join lateral (
      select role.job_role from public.staff_job_roles role
      where role.staff_member_id = short.staff_member_id
        and role.effective_from <= short.work_date
      order by role.effective_from desc limit 1
    ) original on true
    join public.shift_codes code on code.code = upper(trim(short.shift_code))
      and code.coverage_window is not null
    where short.work_date in (select work_date from days)
      and short.filled_at is null and public.is_working_shift(short.shift_code)
    group by short.work_date, 2, code.coverage_window
  )
  select keys.pool, keys.coverage_window, keys.work_date,
    coalesce(date_rule.minimum, week_rule.minimum),
    coalesce(date_rule.rn_floor, week_rule.rn_floor),
    coalesce(working.working_count, 0), coalesce(working.rn_count, 0),
    coalesce(opened.open_count, 0), coalesce(opened.rn_open_count, 0),
    case when coalesce(date_rule.minimum, week_rule.minimum) is null then null
      else greatest(coalesce(date_rule.minimum, week_rule.minimum) -
        coalesce(working.working_count, 0),
        coalesce(date_rule.rn_floor, week_rule.rn_floor, 0) - coalesce(working.rn_count, 0), 0)
    end,
    case when coalesce(date_rule.minimum, week_rule.minimum) is null then null
      else greatest(coalesce(date_rule.rn_floor, week_rule.rn_floor, 0) -
        coalesce(working.rn_count, 0), 0)
    end,
    week_rule.minimum, date_rule.minimum
  from keys
  left join working on working.work_date = keys.work_date and working.pool = keys.pool
    and working.coverage_window = keys.coverage_window
  left join opened on opened.work_date = keys.work_date and opened.pool = keys.pool
    and opened.coverage_window = keys.coverage_window
  left join public.pool_weekday_minimums week_rule on week_rule.pool = keys.pool
    and week_rule.coverage_window = keys.coverage_window
    and week_rule.weekday = extract(dow from keys.work_date)::integer
  left join public.pool_date_minimums date_rule on date_rule.pool = keys.pool
    and date_rule.coverage_window = keys.coverage_window and date_rule.work_date = keys.work_date
  where public.is_active_staff_member();
$$;

create function public.post_open_shifts(p_date date, p_shift_code text, p_pool text,
  p_count integer, p_fill_gap boolean, p_requires_approval boolean default true)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_month uuid;
  v_window text;
  v_count integer := p_count;
  v_floor_count integer := 0;
  v_minimum integer;
  v_rn_floor integer;
  v_working integer;
  v_rns integer;
  v_open integer;
  v_rn_open integer;
begin
  if public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the Manager can post Open shifts';
  end if;
  select code.coverage_window into v_window from public.shift_codes code
  where code.code = upper(trim(p_shift_code));
  if p_date is null or p_pool not in ('nurses', 'cna', 'unit_clerk') or p_pool is null
    or v_window is null or not public.is_working_shift(coalesce(p_shift_code, ''))
    or p_count not between 1 and 100 then
    raise exception 'A date, working Shift code with a Coverage window, pool and count are required';
  end if;
  perform pg_advisory_xact_lock(hashtext(p_pool || ':' || v_window || ':' || p_date::text));
  select id into v_month from public.schedule_months
  where month_start = date_trunc('month', p_date)::date;
  if v_month is null then raise exception 'Start this Schedule month first'; end if;
  if p_fill_gap then
    select minimum, rn_floor, working_count, rn_count, open_count, rn_open_count
      into v_minimum, v_rn_floor, v_working, v_rns, v_open, v_rn_open
    from public.section_staffing_for_month(p_date)
    where pool = p_pool and coverage_window = v_window and work_date = p_date;
    if v_minimum is null then raise exception 'Set this staffing minimum first'; end if;
    v_floor_count := greatest(v_rn_floor - v_rns - v_rn_open, 0);
    v_count := least(p_count, greatest(v_minimum - v_working - v_open,
      v_floor_count, 0));
    v_floor_count := least(v_floor_count, v_count);
  end if;
  insert into public.short_shifts(schedule_month_id, section_id, work_date, shift_code,
    reason, job_role, requires_approval, rn_floor_critical)
  select v_month, null, p_date, upper(trim(p_shift_code)), 'manual',
    case when p_pool = 'nurses' and n <= v_floor_count then 'rn'::public.job_role
      when p_pool = 'nurses' then 'lpn'::public.job_role
      else p_pool::public.job_role end,
    case when n <= v_floor_count then true else coalesce(p_requires_approval, true) end,
    n <= v_floor_count
  from generate_series(1, v_count) as series(n);
  return v_count;
end;
$$;

revoke all on function public.set_pool_weekday_minimum(text, text, integer, integer, integer),
  public.set_pool_date_minimum(text, text, date, integer, integer),
  public.section_staffing_for_month(date),
  public.post_open_shifts(date, text, text, integer, boolean, boolean) from public;
grant execute on function public.set_pool_weekday_minimum(text, text, integer, integer, integer),
  public.set_pool_date_minimum(text, text, date, integer, integer),
  public.section_staffing_for_month(date),
  public.post_open_shifts(date, text, text, integer, boolean, boolean) to authenticated;
