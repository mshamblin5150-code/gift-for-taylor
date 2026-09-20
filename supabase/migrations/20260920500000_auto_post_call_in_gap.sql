-- Share the locked Staffing minimum calculation without granting Staff members
-- the Manager's discretionary hand-posting RPC.
create function public.open_shift_gap(p_date date, p_shift_code text, p_pool text,
  p_limit integer)
returns table (posting_count integer, floor_count integer)
language plpgsql security definer set search_path = '' as $$
declare
  v_window text;
  v_minimum integer;
  v_floor integer;
  v_working integer;
  v_rns integer;
  v_open integer;
  v_rn_open integer;
begin
  select coverage_window into v_window from public.shift_codes
  where code = upper(trim(p_shift_code));
  perform pg_advisory_xact_lock(hashtext(p_pool || ':' || v_window || ':' || p_date::text));
  select minimum, rn_floor, working_count, rn_count, open_count, rn_open_count
    into v_minimum, v_floor, v_working, v_rns, v_open, v_rn_open
  from public.section_staffing_for_month(p_date)
  where pool = p_pool and coverage_window = v_window and work_date = p_date;
  if v_minimum is null then
    return query select null::integer, null::integer;
    return;
  end if;
  floor_count := greatest(coalesce(v_floor, 0) - v_rns - v_rn_open, 0);
  posting_count := least(p_limit, v_minimum,
    greatest(v_minimum - v_working - v_open, floor_count, 0));
  floor_count := least(floor_count, posting_count);
  return next;
end;
$$;
revoke all on function public.open_shift_gap(date, text, text, integer) from public;

create or replace function public.post_open_shifts(p_date date, p_shift_code text, p_pool text,
  p_count integer, p_fill_gap boolean, p_requires_approval boolean default null)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_month uuid;
  v_window text;
  v_count integer := p_count;
  v_floor_count integer := 0;
begin
  if public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the Manager can post Open shifts';
  end if;
  select coverage_window into v_window from public.shift_codes
  where code = upper(trim(p_shift_code));
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
    select posting_count, floor_count into v_count, v_floor_count
    from public.open_shift_gap(p_date, p_shift_code, p_pool, p_count);
    if v_count is null then raise exception 'Set this staffing minimum first'; end if;
  end if;
  insert into public.short_shifts(schedule_month_id, section_id, work_date, shift_code,
    reason, job_role, requires_approval, rn_floor_critical)
  select v_month, null, p_date, upper(trim(p_shift_code)), 'manual',
    case when p_pool = 'nurses' and n <= v_floor_count then 'rn'::public.job_role
      when p_pool = 'nurses' then 'lpn'::public.job_role
      else p_pool::public.job_role end,
    case when n <= v_floor_count then true
      else coalesce(p_requires_approval, public.open_shift_approval_default()) end,
    n <= v_floor_count
  from generate_series(1, v_count) as series(n);
  return v_count;
end;
$$;

alter table public.short_shifts drop constraint short_shifts_reason_check;
alter table public.short_shifts add constraint short_shifts_reason_check
  check (reason in ('last_day', 'request_off', 'manual', 'call_in', 'sick_leave'));
alter table public.short_shifts drop constraint short_shifts_manual_role_check;
alter table public.short_shifts add constraint short_shifts_manual_role_check
  check ((reason in ('manual', 'call_in', 'sick_leave')) =
    (job_role is not null and staff_member_id is null));
alter table public.staff_notices drop constraint staff_notices_kind_check;
alter table public.staff_notices add constraint staff_notices_kind_check check (kind in (
  'month_release', 'schedule_change', 'open_shift_pickup', 'open_shift_posted',
  'request_submitted', 'request_decided', 'swap_proposed', 'swap_accepted',
  'swap_declined', 'swap_approved', 'test', 'floor_critical_call_in'
));

-- This function is invoked both on posting and when an unpublished month is
-- released. The existing Staff-facing filter remains in notice_open_shift.
create or replace function public.notice_open_shift(p_short public.short_shifts, p_actor uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_role public.job_role;
begin
  select coalesce(p_short.job_role, (select role.job_role from public.staff_job_roles role
    where role.staff_member_id = p_short.staff_member_id
      and role.effective_from <= p_short.work_date
      and (role.effective_through is null or role.effective_through >= p_short.work_date)
    order by role.effective_from desc limit 1)) into v_role;
  if v_role is null then return; end if;
  insert into public.staff_notices(staff_member_id, kind, title, body, month_start, short_shift_id)
  select distinct member.id, 'open_shift_posted', 'Open shift posted',
    p_short.shift_code || ' on ' || p_short.work_date::text || ' is open for pickup.',
    date_trunc('month', p_short.work_date)::date, p_short.id
  from public.staff_members member
  join public.staff_accounts account on account.staff_member_id = member.id
  join public.staff_job_roles role on role.staff_member_id = member.id
  join public.staff_section_assignments assignment on assignment.staff_member_id = member.id
  where member.active and member.role = 'staff_member' and member.id <> p_actor
    and member.id is distinct from p_short.staff_member_id
    and account.accepted_invite_at is not null and account.revoked_at is null
    and role.effective_from <= p_short.work_date
    and (role.effective_through is null or role.effective_through >= p_short.work_date)
    and assignment.effective_from <= p_short.work_date
    and (assignment.effective_through is null or assignment.effective_through >= p_short.work_date)
    and (role.job_role = v_role or
      (role.job_role in ('rn', 'lpn') and v_role in ('rn', 'lpn')))
    and not exists (select 1 from public.schedule_cells cell
      where cell.staff_member_id = member.id and cell.work_date = p_short.work_date
        and cell.shift_code not in ('', 'X'));
  if p_short.rn_floor_critical and p_short.reason in ('call_in', 'sick_leave') then
    insert into public.staff_notices(staff_member_id, kind, title, body, month_start, short_shift_id)
    select manager.id, 'floor_critical_call_in', 'RN floor needs approval',
      'An RN-floor Open shift on ' || p_short.work_date::text || ' needs approval.',
      date_trunc('month', p_short.work_date)::date, p_short.id
    from public.staff_members manager where manager.active and manager.role = 'manager';
  end if;
end;
$$;

create function public.auto_post_absence_gap()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_role public.job_role;
  v_pool text;
  v_count integer;
  v_floor_count integer;
begin
  if new.new_shift_code not in ('C/I', 'S/L')
    or not public.is_working_shift(new.old_shift_code) then return new; end if;
  select job_role into v_role from public.staff_job_roles
  where staff_member_id = new.staff_member_id and effective_from <= new.work_date
    and (effective_through is null or effective_through >= new.work_date)
  order by effective_from desc limit 1;
  if v_role is null then return new; end if;
  v_pool := case when v_role in ('rn', 'lpn') then 'nurses' else v_role::text end;
  select posting_count, floor_count into v_count, v_floor_count
  from public.open_shift_gap(new.work_date, new.old_shift_code, v_pool, 100);
  if coalesce(v_count, 0) = 0 then return new; end if;
  insert into public.short_shifts(schedule_month_id, section_id, work_date, shift_code,
    reason, job_role, requires_approval, rn_floor_critical, call_in_change_id)
  select new.schedule_month_id, null, new.work_date, upper(trim(new.old_shift_code)),
    case when new.new_shift_code = 'C/I' then 'call_in' else 'sick_leave' end,
    case when v_pool = 'nurses' and n <= v_floor_count then 'rn'::public.job_role
      when v_pool = 'nurses' then 'lpn'::public.job_role
      else v_role end,
    n <= v_floor_count, n <= v_floor_count,
    case when new.new_shift_code = 'C/I' then new.id else null end
  from generate_series(1, v_count) as series(n);
  return new;
end;
$$;
revoke all on function public.auto_post_absence_gap() from public;
create trigger auto_post_absence_gap after insert on public.schedule_changes
for each row execute function public.auto_post_absence_gap();
