-- Rule edits reconcile released future Schedules as a single reviewed batch.
create table public.coverage_rule_batches (
  id uuid primary key default gen_random_uuid(),
  actor uuid not null references public.staff_members(id),
  created_at timestamptz not null default clock_timestamp(),
  effective_from date not null,
  action text not null,
  plan jsonb not null
);
alter table public.coverage_rule_batches enable row level security;
grant select on public.coverage_rule_batches to authenticated;
create policy "staff read rule batches" on public.coverage_rule_batches
  for select using (public.is_active_staff_member());
alter table public.short_shifts add column rule_batch_id uuid
  references public.coverage_rule_batches(id);
alter table public.short_shifts drop constraint short_shifts_reason_check;
alter table public.short_shifts add constraint short_shifts_reason_check
  check (reason in ('last_day', 'request_off', 'manual', 'call_in',
    'sick_leave', 'rule_change'));
alter table public.short_shifts drop constraint short_shifts_manual_role_check;
alter table public.short_shifts add constraint short_shifts_manual_role_check
  check ((reason in ('manual', 'call_in', 'sick_leave', 'rule_change')) =
    (job_role is not null and staff_member_id is null));
alter table public.staff_notices add column rule_batch_id uuid
  references public.coverage_rule_batches(id);
alter table public.staff_notices drop constraint staff_notices_kind_check;
alter table public.staff_notices add constraint staff_notices_kind_check check (kind in (
  'month_release', 'schedule_change', 'open_shift_pickup', 'open_shift_posted',
  'request_submitted', 'request_decided', 'swap_proposed', 'swap_accepted',
  'swap_declined', 'swap_approved', 'test', 'floor_critical_call_in',
  'call_in_filled', 'open_shift_batch'
));
create or replace function public.notice_new_open_shift()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.reason <> 'rule_change' and exists (
    select 1 from public.schedule_months month
    where month.id = new.schedule_month_id and month.release_state = 'released') then
    perform public.notice_open_shift(new, public.current_staff_member_id());
  end if;
  return new;
end;
$$;

-- The counts below use all Open shifts for the new minimum, while treating
-- only unfilled rule-created rows as withdrawable. A floor row with a different
-- Job role after a membership change is ordinary under the new rule.
create function public.coverage_rule_plan()
returns jsonb language sql stable security definer set search_path = '' as $$
  with coverage as (
    select staffing.*, public.coverage_floor_role_on(staffing.pool,
      staffing.coverage_window, staffing.work_date) as floor_role
    from public.schedule_months month
    cross join lateral public.section_staffing_for_month(month.month_start) staffing
    where month.release_state = 'released' and
      staffing.work_date >= current_date
  ), rule_open as (
    select short.work_date,
      public.coverage_pool_on(short.job_role, short.work_date) as pool,
      code.coverage_window, short.job_role, short.rn_floor_critical,
      count(*)::integer as open_count
    from public.short_shifts short
    join public.shift_codes code on code.code = upper(trim(short.shift_code))
    where short.reason = 'rule_change' and short.filled_at is null
      and short.work_date >= current_date
    group by short.work_date, 2, code.coverage_window,
      short.job_role, short.rn_floor_critical
  ), counts as (
    select coverage.*,
      coalesce((select sum(open_count) from rule_open opened
        where opened.pool = coverage.pool and
          opened.coverage_window = coverage.coverage_window and
          opened.work_date = coverage.work_date), 0)::integer as rule_open,
      coalesce((select sum(open_count) from rule_open opened
        where opened.pool = coverage.pool and
          opened.coverage_window = coverage.coverage_window and
          opened.work_date = coverage.work_date and
          opened.rn_floor_critical and
          opened.job_role = coverage.floor_role), 0)::integer as rule_floor_open
    from coverage
  ), targets as (
    select counts.*,
      greatest(0, least(coalesce(counts.minimum, 0), greatest(
        coalesce(counts.minimum, 0) - counts.working_count,
        coalesce(counts.rn_floor, 0) - counts.rn_count, 0)) -
        (counts.open_count - counts.rule_open)) as target_rule,
      greatest(0, coalesce(counts.rn_floor, 0) - counts.rn_count -
        (counts.rn_open_count - counts.rule_floor_open)) as target_floor
    from counts
  ), changes as (
    select targets.*,
      least(target_rule, target_floor) as floor_target,
      greatest(target_rule - least(target_rule, target_floor), 0)
        as ordinary_target
    from targets
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'work_date', work_date, 'pool', pool, 'window', coverage_window,
    'floor_role', floor_role,
    'post_floor', greatest(floor_target - rule_floor_open, 0),
    'post_ordinary', greatest(ordinary_target - (rule_open - rule_floor_open), 0),
    'withdraw_floor', greatest(rule_floor_open - floor_target, 0),
    'withdraw_ordinary', greatest((rule_open - rule_floor_open) - ordinary_target, 0)
  ) order by work_date, pool, coverage_window), '[]'::jsonb)
  from changes where floor_target <> rule_floor_open or
    ordinary_target <> rule_open - rule_floor_open;
$$;
revoke all on function public.coverage_rule_plan() from public;

create function public.coverage_rule_plan_delta(p_before jsonb, p_after jsonb)
returns jsonb language sql immutable set search_path = '' as $$
  with after_rows as (
    select value as item from jsonb_array_elements(p_after)
  ), changed as (
    select after_rows.item,
      greatest((after_rows.item->>'post_floor')::integer -
        coalesce((old.item->>'post_floor')::integer, 0), 0) as post_floor,
      greatest((after_rows.item->>'post_ordinary')::integer -
        coalesce((old.item->>'post_ordinary')::integer, 0), 0) as post_ordinary,
      greatest((after_rows.item->>'withdraw_floor')::integer -
        coalesce((old.item->>'withdraw_floor')::integer, 0), 0) as withdraw_floor,
      greatest((after_rows.item->>'withdraw_ordinary')::integer -
        coalesce((old.item->>'withdraw_ordinary')::integer, 0), 0) as withdraw_ordinary
    from after_rows
    left join lateral (
      select value as item from jsonb_array_elements(p_before) prior(value)
      where value->>'work_date' = after_rows.item->>'work_date'
        and value->>'pool' = after_rows.item->>'pool'
        and value->>'window' = after_rows.item->>'window'
      limit 1
    ) old on true
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'work_date', item->>'work_date', 'pool', item->>'pool',
    'window', item->>'window', 'floor_role', item->>'floor_role',
    'post_floor', post_floor, 'post_ordinary', post_ordinary,
    'withdraw_floor', withdraw_floor, 'withdraw_ordinary', withdraw_ordinary)
    order by item->>'work_date', item->>'pool', item->>'window'), '[]'::jsonb)
  from changed where post_floor + post_ordinary +
    withdraw_floor + withdraw_ordinary > 0;
$$;
revoke all on function public.coverage_rule_plan_delta(jsonb, jsonb)
  from public;

-- A preview applies the proposed edit inside a subtransaction, reads the
-- resulting plan, then rolls the edit back. The save recomputes and compares
-- the plan so a concurrent Schedule change cannot silently alter the batch.
create function public.preview_coverage_pools(p_effective_from date,
  p_pools jsonb, p_memberships jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_plan jsonb; v_before jsonb;
begin
  perform pg_advisory_xact_lock(hashtext('coverage-rule-configuration'));
  v_before := public.coverage_rule_plan();
  begin
    perform public.save_coverage_pools(p_effective_from, p_pools, p_memberships);
    v_plan := public.coverage_rule_plan_delta(v_before,
      public.coverage_rule_plan());
    raise exception 'preview rollback' using errcode = 'P9001';
  exception when sqlstate 'P9001' then null;
  end;
  return v_plan;
end;
$$;
create function public.preview_coverage_weekday_rule(p_pool text,
  p_window text, p_weekday integer, p_effective_from date,
  p_minimum integer, p_floor_role public.job_role, p_floor integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_plan jsonb; v_before jsonb;
begin
  perform pg_advisory_xact_lock(hashtext('coverage-rule-configuration'));
  v_before := public.coverage_rule_plan();
  begin
    perform public.set_coverage_weekday_rule(p_pool, p_window, p_weekday,
      p_effective_from, p_minimum, p_floor_role, p_floor);
    v_plan := public.coverage_rule_plan_delta(v_before,
      public.coverage_rule_plan());
    raise exception 'preview rollback' using errcode = 'P9001';
  exception when sqlstate 'P9001' then null;
  end;
  return v_plan;
end;
$$;
revoke all on function public.preview_coverage_pools(date, jsonb, jsonb),
  public.preview_coverage_weekday_rule(text, text, integer, date,
    integer, public.job_role, integer) from public;
grant execute on function public.preview_coverage_pools(date, jsonb, jsonb),
  public.preview_coverage_weekday_rule(text, text, integer, date,
    integer, public.job_role, integer) to authenticated;

create function public.apply_coverage_rule_plan(p_effective_from date,
  p_action text, p_before_plan jsonb, p_expected_plan jsonb, p_choices jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_plan jsonb := public.coverage_rule_plan_delta(p_before_plan,
    public.coverage_rule_plan());
  v_batch uuid;
  v_row jsonb;
  v_choice jsonb;
  v_date date;
  v_pool text;
  v_window text;
  v_floor_role public.job_role;
  v_ordinary_role public.job_role;
  v_floor_code text;
  v_ordinary_code text;
  v_month uuid;
  v_shift public.short_shifts%rowtype;
  v_withdraw_floor boolean;
  v_limit integer;
begin
  if p_expected_plan is distinct from v_plan then
    raise exception 'The Schedule changed since preview; review the batch again';
  end if;
  if jsonb_typeof(p_choices) is distinct from 'array' then
    raise exception 'The Open shift choices must be a list';
  end if;
  if v_plan = '[]'::jsonb then return null; end if;
  insert into public.coverage_rule_batches(actor, effective_from, action, plan)
  values (public.current_staff_member_id(), p_effective_from, p_action, v_plan)
  returning id into v_batch;
  for v_row in select value from jsonb_array_elements(v_plan) loop
    v_date := (v_row->>'work_date')::date;
    v_pool := v_row->>'pool';
    v_window := v_row->>'window';
    v_floor_role := (v_row->>'floor_role')::public.job_role;
    select month.id into v_month from public.schedule_months month
    where month.month_start = date_trunc('month', v_date)::date
      and month.release_state = 'released';
    if v_month is null or v_date < current_date then
      raise exception 'Rule batches only change current or future released Schedules';
    end if;

    -- Withdraw only unfilled rows created by an earlier rule batch. Pending
    -- applicants are told before their request is removed.
    for v_withdraw_floor, v_limit in
      select true, (v_row->>'withdraw_floor')::integer
      union all select false, (v_row->>'withdraw_ordinary')::integer
    loop
      for v_shift in
        select short.* from public.short_shifts short
        join public.shift_codes code on code.code = upper(trim(short.shift_code))
        where short.work_date = v_date and short.reason = 'rule_change'
          and short.filled_at is null
          and public.coverage_pool_on(short.job_role, short.work_date) = v_pool
          and code.coverage_window = v_window
          and (short.rn_floor_critical and short.job_role = v_floor_role)
            = v_withdraw_floor
        order by short.created_at desc, short.id
        limit v_limit for update of short
      loop
        insert into public.staff_notices(staff_member_id, kind, title, body,
          month_start)
        select pickup.staff_member_id, 'open_shift_pickup',
          'Open shift withdrawn',
          'The ' || v_shift.shift_code || ' shift on ' || v_date::text ||
            ' is no longer available.', date_trunc('month', v_date)::date
        from public.open_shift_pickups pickup
        where pickup.short_shift_id = v_shift.id and pickup.status = 'pending';
        delete from public.open_shift_pickups where short_shift_id = v_shift.id;
        update public.staff_notices set short_shift_id = null
        where short_shift_id = v_shift.id;
        delete from public.short_shifts where id = v_shift.id and filled_at is null;
        if not found then raise exception 'Open shift was filled during withdrawal'; end if;
      end loop;
    end loop;

    if (v_row->>'post_floor')::integer = 0 and
      (v_row->>'post_ordinary')::integer = 0 then continue; end if;
    select choice.value into v_choice from jsonb_array_elements(p_choices)
      as choice(value)
    where choice.value->>'work_date' = v_date::text
      and choice.value->>'pool' = v_pool
      and choice.value->>'window' = v_window;
    if v_choice is null then raise exception 'Choose a Job role and Shift code for every new set'; end if;
    v_floor_code := upper(trim(v_choice->>'floor_shift_code'));
    v_ordinary_code := upper(trim(v_choice->>'ordinary_shift_code'));
    v_ordinary_role := (v_choice->>'ordinary_role')::public.job_role;
    if (v_row->>'post_floor')::integer > 0 and
      (v_floor_role is null or v_choice->>'floor_role' <> v_floor_role::text
        or not public.is_working_shift(coalesce(v_floor_code, ''))
        or (select coverage_window from public.shift_codes
          where code = v_floor_code) is distinct from v_window) then
      raise exception 'Floor shifts need their member Job role and a working Shift code in the Coverage window';
    end if;
    if (v_row->>'post_ordinary')::integer > 0 and
      (v_ordinary_role is null or
        public.coverage_pool_on(v_ordinary_role, v_date) <> v_pool or
        not public.is_working_shift(coalesce(v_ordinary_code, '')) or
        (select coverage_window from public.shift_codes
          where code = v_ordinary_code) is distinct from v_window) then
      raise exception 'Choose a member Job role and working Shift code in the Coverage window';
    end if;
    insert into public.short_shifts(schedule_month_id, section_id, work_date,
      shift_code, reason, job_role, requires_approval, rn_floor_critical,
      rule_batch_id)
    select v_month, null, v_date, v_floor_code, 'rule_change', v_floor_role,
      true, true, v_batch
    from generate_series(1, (v_row->>'post_floor')::integer);
    insert into public.short_shifts(schedule_month_id, section_id, work_date,
      shift_code, reason, job_role, requires_approval, rn_floor_critical,
      rule_batch_id)
    select v_month, null, v_date, v_ordinary_code, 'rule_change',
      v_ordinary_role, public.open_shift_approval_default(), false, v_batch
    from generate_series(1, (v_row->>'post_ordinary')::integer);
  end loop;

  insert into public.staff_notices(staff_member_id, kind, title, body,
    month_start, rule_batch_id)
  select distinct member.id, 'open_shift_batch', 'Open shifts posted',
    'A Staffing minimum change posted ' ||
      (select count(*)::text from public.short_shifts opened
       where opened.rule_batch_id = v_batch) ||
      ' Open shifts. Open the batch to review them.',
    date_trunc('month', p_effective_from)::date, v_batch
  from public.staff_members member
  join public.staff_accounts account on account.staff_member_id = member.id
  join public.staff_job_roles role on role.staff_member_id = member.id
  join public.staff_section_assignments assignment on assignment.staff_member_id = member.id
  join public.short_shifts opened on opened.rule_batch_id = v_batch
  where member.active and member.role = 'staff_member'
    and account.accepted_invite_at is not null and account.revoked_at is null
    and role.effective_from <= opened.work_date
    and (role.effective_through is null or role.effective_through >= opened.work_date)
    and assignment.effective_from <= opened.work_date
    and (assignment.effective_through is null or assignment.effective_through >= opened.work_date)
    and (role.job_role = opened.job_role or
      role.job_role in ('rn', 'lpn') and opened.job_role in ('rn', 'lpn'))
    and not exists (select 1 from public.schedule_cells cell
      where cell.staff_member_id = member.id and cell.work_date = opened.work_date
        and cell.shift_code not in ('', 'X'));
  return v_batch;
end;
$$;
revoke all on function public.apply_coverage_rule_plan(date, text, jsonb, jsonb, jsonb)
  from public;

create function public.commit_coverage_pools(p_effective_from date,
  p_pools jsonb, p_memberships jsonb, p_expected_plan jsonb, p_choices jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_before jsonb;
begin
  perform pg_advisory_xact_lock(hashtext('coverage-rule-configuration'));
  v_before := public.coverage_rule_plan();
  perform public.save_coverage_pools(p_effective_from, p_pools, p_memberships);
  return public.apply_coverage_rule_plan(p_effective_from,
    'coverage_pools', v_before, p_expected_plan, p_choices);
end;
$$;
create function public.commit_coverage_weekday_rule(p_pool text,
  p_window text, p_weekday integer, p_effective_from date,
  p_minimum integer, p_floor_role public.job_role, p_floor integer,
  p_expected_plan jsonb, p_choices jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_before jsonb;
begin
  perform pg_advisory_xact_lock(hashtext('coverage-rule-configuration'));
  v_before := public.coverage_rule_plan();
  perform public.set_coverage_weekday_rule(p_pool, p_window, p_weekday,
    p_effective_from, p_minimum, p_floor_role, p_floor);
  return public.apply_coverage_rule_plan(p_effective_from,
    'weekday_minimum', v_before, p_expected_plan, p_choices);
end;
$$;
revoke all on function public.commit_coverage_pools(date, jsonb, jsonb,
  jsonb, jsonb), public.commit_coverage_weekday_rule(text, text, integer,
    date, integer, public.job_role, integer, jsonb, jsonb) from public;
grant execute on function public.commit_coverage_pools(date, jsonb, jsonb,
  jsonb, jsonb), public.commit_coverage_weekday_rule(text, text, integer,
    date, integer, public.job_role, integer, jsonb, jsonb) to authenticated;

-- Direct writes would bypass the preview and batch. The checked RPCs above
-- own writes from authenticated clients; internal calls retain definer access.
revoke execute on function public.save_coverage_pools(date, jsonb, jsonb),
  public.set_coverage_weekday_rule(text, text, integer, date, integer,
    public.job_role, integer) from public, authenticated;

create function public.set_coverage_date_rule(p_pool text, p_window text,
  p_date date, p_minimum integer, p_floor_role public.job_role,
  p_floor integer)
returns void language plpgsql security definer set search_path = '' as $$
declare v_before jsonb;
begin
  if public.current_staff_role() not in ('manager', 'administrator') then
    raise exception 'Only a Manager or Administrator can edit Staffing minimums';
  end if;
  if p_date is null or p_date < current_date or p_window not in ('day', 'night')
    or (public.coverage_pool_version_on(p_pool, p_date)).pool is null or
    (public.coverage_pool_version_on(p_pool, p_date)).retired or
    (p_minimum is not null and (p_minimum not between 0 and 100
      or p_floor not between 0 and p_minimum or
      (p_floor_role is not null and
        (public.coverage_pool_on(p_floor_role, p_date) <> p_pool or
        (public.coverage_pool_version_on(p_pool, p_date)).floor_role
          is distinct from p_floor_role)) or
      p_floor > 0 and p_floor_role is null)) then
    raise exception 'Invalid date Staffing minimum or floor';
  end if;
  select to_jsonb(rule) into v_before from public.pool_date_minimums rule
  where rule.pool = p_pool and rule.coverage_window = p_window
    and rule.work_date = p_date;
  if p_minimum is null then
    delete from public.pool_date_minimums where pool = p_pool
      and coverage_window = p_window and work_date = p_date;
  else
    insert into public.pool_date_minimums(pool, coverage_window, work_date,
      minimum, floor_role, rn_floor)
    values (p_pool, p_window, p_date, p_minimum, p_floor_role, p_floor)
    on conflict (pool, coverage_window, work_date) do update
      set minimum = excluded.minimum, floor_role = excluded.floor_role,
        rn_floor = excluded.rn_floor;
  end if;
  insert into public.coverage_rule_audit(actor, effective_from, action,
    before_value, after_value)
  values (public.current_staff_member_id(), p_date, 'date_minimum',
    v_before, jsonb_build_object('pool', p_pool, 'window', p_window,
      'date', p_date, 'minimum', p_minimum, 'floor_role', p_floor_role,
      'floor', p_floor));
end;
$$;
revoke all on function public.set_coverage_date_rule(text, text, date,
  integer, public.job_role, integer) from public, authenticated;

create function public.preview_coverage_date_rule(p_pool text, p_window text,
  p_date date, p_minimum integer, p_floor_role public.job_role,
  p_floor integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_plan jsonb; v_before jsonb;
begin
  perform pg_advisory_xact_lock(hashtext('coverage-rule-configuration'));
  v_before := public.coverage_rule_plan();
  begin
    perform public.set_coverage_date_rule(p_pool, p_window, p_date,
      p_minimum, p_floor_role, p_floor);
    v_plan := public.coverage_rule_plan_delta(v_before,
      public.coverage_rule_plan());
    raise exception 'preview rollback' using errcode = 'P9001';
  exception when sqlstate 'P9001' then null;
  end;
  return v_plan;
end;
$$;
create function public.commit_coverage_date_rule(p_pool text, p_window text,
  p_date date, p_minimum integer, p_floor_role public.job_role,
  p_floor integer, p_expected_plan jsonb, p_choices jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_before jsonb;
begin
  perform pg_advisory_xact_lock(hashtext('coverage-rule-configuration'));
  v_before := public.coverage_rule_plan();
  perform public.set_coverage_date_rule(p_pool, p_window, p_date,
    p_minimum, p_floor_role, p_floor);
  return public.apply_coverage_rule_plan(p_date, 'date_minimum',
    v_before, p_expected_plan, p_choices);
end;
$$;
revoke all on function public.preview_coverage_date_rule(text, text, date,
  integer, public.job_role, integer),
  public.commit_coverage_date_rule(text, text, date, integer,
    public.job_role, integer, jsonb, jsonb) from public;
grant execute on function public.preview_coverage_date_rule(text, text, date,
  integer, public.job_role, integer),
  public.commit_coverage_date_rule(text, text, date, integer,
    public.job_role, integer, jsonb, jsonb) to authenticated;

-- Compatibility RPCs remain for older clients, but they refuse any edit that
-- needs a released-Schedule batch. The new UI uses preview and commit RPCs.
create or replace function public.set_pool_weekday_minimum(p_pool text,
  p_window text, p_weekday integer, p_minimum integer,
  p_rn_floor integer default 0)
returns void language plpgsql security definer set search_path = '' as $$
declare v_floor_role public.job_role; v_plan jsonb;
begin
  if public.current_staff_role() not in ('manager', 'administrator') then
    raise exception 'Only the Manager can set staffing minimums';
  end if;
  select (public.coverage_pool_version_on(p_pool, current_date)).floor_role
    into v_floor_role;
  if p_window not in ('day', 'night') or p_weekday not between 0 and 6
    or p_minimum not between 0 and 100 or p_rn_floor not between 0 and p_minimum
    or p_rn_floor > 0 and v_floor_role is null then
    raise exception 'Invalid staffing minimum';
  end if;
  v_plan := public.preview_coverage_weekday_rule(p_pool, p_window, p_weekday,
    current_date, p_minimum, v_floor_role, p_rn_floor);
  if v_plan <> '[]'::jsonb then
    raise exception 'Review the Open shift batch in Unit settings first';
  end if;
  perform public.commit_coverage_weekday_rule(p_pool, p_window, p_weekday,
    current_date, p_minimum, v_floor_role, p_rn_floor, v_plan, '[]'::jsonb);
end;
$$;
create or replace function public.set_pool_date_minimum(p_pool text,
  p_window text, p_date date, p_minimum integer,
  p_rn_floor integer default 0)
returns void language plpgsql security definer set search_path = '' as $$
declare v_floor_role public.job_role; v_plan jsonb;
begin
  if public.current_staff_role() not in ('manager', 'administrator') then
    raise exception 'Only the Manager can set staffing minimums';
  end if;
  if p_date is null or p_date < current_date then
    raise exception 'Date overrides cannot change past Schedules';
  end if;
  v_floor_role := public.coverage_floor_role_on(p_pool, p_window, p_date);
  if p_window not in ('day', 'night') or
    (p_minimum is not null and (p_minimum not between 0 and 100
      or p_rn_floor not between 0 and p_minimum or
      p_rn_floor > 0 and v_floor_role is null)) then
    raise exception 'Invalid staffing minimum';
  end if;
  v_plan := public.preview_coverage_date_rule(p_pool, p_window, p_date,
    p_minimum, v_floor_role, coalesce(p_rn_floor, 0));
  if v_plan <> '[]'::jsonb then
    raise exception 'Review the Open shift batch on the staffing sheet first';
  end if;
  perform public.commit_coverage_date_rule(p_pool, p_window, p_date,
    p_minimum, v_floor_role, coalesce(p_rn_floor, 0), v_plan, '[]'::jsonb);
end;
$$;
