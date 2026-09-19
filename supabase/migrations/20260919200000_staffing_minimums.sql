-- Staffing targets are weekly defaults with optional one-day overrides.
create table public.section_weekday_minimums (
  section_id uuid not null references public.sections(id) on delete cascade,
  weekday integer not null check (weekday between 0 and 6),
  minimum integer not null check (minimum between 0 and 100),
  primary key (section_id, weekday)
);
create table public.section_date_minimums (
  section_id uuid not null references public.sections(id) on delete cascade,
  work_date date not null,
  minimum integer not null check (minimum between 0 and 100),
  primary key (section_id, work_date)
);
alter table public.section_weekday_minimums enable row level security;
alter table public.section_date_minimums enable row level security;
grant select on public.section_weekday_minimums, public.section_date_minimums to authenticated;
create policy "staff read weekday minimums" on public.section_weekday_minimums
  for select using (public.is_active_staff_member());
create policy "staff read date minimums" on public.section_date_minimums
  for select using (public.is_active_staff_member());

create function public.set_section_weekday_minimum(p_section_id uuid, p_weekday integer, p_minimum integer)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the Manager can set staffing minimums';
  end if;
  if p_weekday not between 0 and 6 or p_minimum not between 0 and 100 then
    raise exception 'Invalid staffing minimum';
  end if;
  insert into public.section_weekday_minimums(section_id, weekday, minimum)
  values (p_section_id, p_weekday, p_minimum)
  on conflict (section_id, weekday) do update set minimum = excluded.minimum;
end;
$$;
create function public.set_section_date_minimum(p_section_id uuid, p_date date, p_minimum integer)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the Manager can set staffing minimums';
  end if;
  if p_date is null or (p_minimum is not null and p_minimum not between 0 and 100) then
    raise exception 'Invalid staffing minimum';
  end if;
  if p_minimum is null then
    delete from public.section_date_minimums where section_id = p_section_id and work_date = p_date;
  else
    insert into public.section_date_minimums(section_id, work_date, minimum)
    values (p_section_id, p_date, p_minimum)
    on conflict (section_id, work_date) do update set minimum = excluded.minimum;
  end if;
end;
$$;

-- A manually posted shift belongs to a pickup pool even without an original owner.
alter table public.short_shifts alter column staff_member_id drop not null;
alter table public.short_shifts add column job_role public.job_role;
alter table public.short_shifts drop constraint short_shifts_reason_check;
alter table public.short_shifts add constraint short_shifts_reason_check
  check (reason in ('last_day', 'request_off', 'manual'));
alter table public.short_shifts add constraint short_shifts_manual_role_check
  check ((reason = 'manual') = (job_role is not null and staff_member_id is null));

create function public.section_staffing_for_month(p_month date)
returns table(section_id uuid, work_date date, minimum integer, working_count integer, open_count integer,
  weekday_minimum integer, date_minimum integer)
language sql stable security definer set search_path = '' as $$
  select section.id, day.work_date::date,
    coalesce(date_rule.minimum, week_rule.minimum, 0),
    (select count(*)::integer from public.schedule_cells cell
      join public.schedule_months month on month.id = cell.schedule_month_id
      where cell.section_id = section.id and cell.work_date = day.work_date
        and month.release_state in ('unpublished', 'released')
        and public.is_working_shift(cell.shift_code)
        and not exists (select 1 from public.open_shift_pickups pickup
          join public.short_shifts opened on opened.id = pickup.short_shift_id
          where pickup.staff_member_id = cell.staff_member_id
            and pickup.status = 'approved' and opened.reason = 'manual'
            and opened.work_date = cell.work_date))
      + (select count(*)::integer from public.open_shift_pickups pickup
        join public.short_shifts opened on opened.id = pickup.short_shift_id
        join public.schedule_cells cell on cell.staff_member_id = pickup.staff_member_id
          and cell.work_date = opened.work_date
        where pickup.status = 'approved' and opened.reason = 'manual'
          and opened.section_id = section.id and opened.work_date = day.work_date
          and public.is_working_shift(cell.shift_code)),
    (select count(*)::integer from public.short_shifts shift
      where shift.section_id = section.id and shift.work_date = day.work_date
        and shift.filled_at is null and public.is_working_shift(shift.shift_code)),
    week_rule.minimum, date_rule.minimum
  from public.sections section
  cross join lateral generate_series(date_trunc('month', p_month)::date,
    (date_trunc('month', p_month) + interval '1 month - 1 day')::date,
    interval '1 day') as day(work_date)
  left join public.section_weekday_minimums week_rule
    on week_rule.section_id = section.id and week_rule.weekday = extract(dow from day.work_date)::integer
  left join public.section_date_minimums date_rule
    on date_rule.section_id = section.id and date_rule.work_date = day.work_date
  where public.is_active_staff_member();
$$;

create function public.post_open_shifts(p_section_id uuid, p_date date, p_shift_code text,
  p_job_role public.job_role, p_count integer, p_fill_gap boolean default false)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_month uuid;
  v_count integer := p_count;
  v_target integer;
  v_working integer;
  v_open integer;
begin
  if public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the Manager can post Open shifts';
  end if;
  if p_date is null or p_section_id is null or not public.is_working_shift(coalesce(p_shift_code, ''))
    or p_job_role is null or p_count not between 1 and 100 then
    raise exception 'A Section, date, working Shift code, role and count are required';
  end if;
  perform pg_advisory_xact_lock(hashtext(p_section_id::text || ':' || p_date::text));
  select id into v_month from public.schedule_months
    where month_start = date_trunc('month', p_date)::date;
  if v_month is null then raise exception 'Start this Schedule month first'; end if;
  if not exists (select 1 from public.sections where id = p_section_id) then
    raise exception 'Section not found';
  end if;
  if p_fill_gap then
    select minimum, working_count, open_count into v_target, v_working, v_open
      from public.section_staffing_for_month(p_date)
      where section_id = p_section_id and work_date = p_date;
    v_count := least(p_count, greatest(v_target - v_working - v_open, 0));
  end if;
  if v_count > 0 then
    insert into public.shift_codes(code, is_working, display_order)
    values (upper(trim(p_shift_code)), true, 1000)
    on conflict (code) do nothing;
  end if;
  insert into public.short_shifts(schedule_month_id, section_id, work_date, shift_code, reason, job_role)
  select v_month, p_section_id, p_date, upper(trim(p_shift_code)), 'manual', p_job_role
    from generate_series(1, v_count);
  return v_count;
end;
$$;

revoke all on function public.set_section_weekday_minimum(uuid, integer, integer),
  public.set_section_date_minimum(uuid, date, integer), public.section_staffing_for_month(date),
  public.post_open_shifts(uuid, date, text, public.job_role, integer, boolean) from public;
grant execute on function public.set_section_weekday_minimum(uuid, integer, integer),
  public.set_section_date_minimum(uuid, date, integer), public.section_staffing_for_month(date),
  public.post_open_shifts(uuid, date, text, public.job_role, integer, boolean) to authenticated;

-- The existing Open shift trigger also handles manual shifts and month release.
create or replace function public.notice_open_shift(p_short public.short_shifts, p_actor uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_role public.job_role;
begin
  select coalesce(p_short.job_role, (select role.job_role from public.staff_job_roles role
    where role.staff_member_id = p_short.staff_member_id
      and role.effective_from <= p_short.work_date
    order by role.effective_from desc limit 1)) into v_role;
  if v_role is null then return; end if;
  insert into public.staff_notices(staff_member_id, kind, title, body, month_start)
  select distinct member.id, 'open_shift_posted', 'Open shift posted',
    p_short.shift_code || ' on ' || p_short.work_date::text || ' is open for pickup.',
    date_trunc('month', p_short.work_date)::date
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
end;
$$;

-- Preserve the existing pickup path while using the explicit role of manual shifts.
create or replace function public.visible_open_shifts()
returns table (id uuid, section_id uuid, work_date date, shift_code text,
  original_staff_member_id uuid, job_role public.job_role, pickup_id uuid,
  pickup_staff_member_id uuid, pickup_status text)
language sql stable security definer set search_path = ''
as $$
  select short.id, short.section_id, short.work_date, short.shift_code,
    short.staff_member_id, coalesce(short.job_role, original_role.job_role),
    pickup.id, pickup.staff_member_id, pickup.status
  from public.short_shifts short
  join public.schedule_months month on month.id = short.schedule_month_id
  left join lateral (
    select role.job_role from public.staff_job_roles role
    where role.staff_member_id = short.staff_member_id
      and role.effective_from <= short.work_date
    order by role.effective_from desc limit 1
  ) original_role on true
  left join public.open_shift_pickups pickup
    on pickup.short_shift_id = short.id
    and (public.current_staff_role() = 'manager'
      or pickup.staff_member_id = public.current_staff_member_id())
  where month.release_state = 'released' and short.filled_at is null
    and public.is_working_shift(short.shift_code)
    and (public.current_staff_role() = 'manager' or exists (
      select 1 from public.staff_job_roles mine
      where mine.staff_member_id = public.current_staff_member_id()
        and mine.effective_from <= short.work_date
        and (mine.effective_through is null or mine.effective_through >= short.work_date)
        and (mine.job_role = coalesce(short.job_role, original_role.job_role)
          or (mine.job_role in ('rn', 'lpn') and coalesce(short.job_role, original_role.job_role) in ('rn', 'lpn')))
    ));
$$;

create or replace function public.request_open_shift_pickup(p_short_shift_id uuid)
returns public.open_shift_pickups
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_staff uuid := public.current_staff_member_id();
  v_short public.short_shifts%rowtype;
  v_role public.job_role;
  v_pickup public.open_shift_pickups%rowtype;
  v_cell text;
begin
  if v_staff is null or public.current_staff_role() = 'manager' then
    raise exception 'Only Staff members can request a pickup';
  end if;
  select * into v_short from public.short_shifts where id = p_short_shift_id for update;
  if not found or v_short.filled_at is not null or not exists (
    select 1 from public.schedule_months where id = v_short.schedule_month_id and release_state = 'released'
  ) then raise exception 'Open shift is unavailable'; end if;
  select coalesce(v_short.job_role, (
    select job_role from public.staff_job_roles
    where staff_member_id = v_short.staff_member_id
      and effective_from <= v_short.work_date
    order by effective_from desc limit 1
  )) into v_role;
  if not exists (
    select 1 from public.staff_job_roles mine
    where mine.staff_member_id = v_staff and mine.effective_from <= v_short.work_date
      and (mine.effective_through is null or mine.effective_through >= v_short.work_date)
      and (mine.job_role = v_role or (mine.job_role in ('rn', 'lpn') and v_role in ('rn', 'lpn')))
  ) then raise exception 'This Open shift is outside your role'; end if;
  if not exists (
    select 1 from public.staff_section_assignments assignment
    where assignment.staff_member_id = v_staff and assignment.effective_from <= v_short.work_date
      and (assignment.effective_through is null or assignment.effective_through >= v_short.work_date)
  ) then raise exception 'Staff member is not on the Schedule for that day'; end if;
  perform pg_advisory_xact_lock(hashtext(v_staff::text || ':' || v_short.work_date::text));
  select shift_code into v_cell from public.schedule_cells
  where staff_member_id = v_staff and work_date = v_short.work_date for update;
  if v_cell is not null and v_cell not in ('', 'X') then
    raise exception 'You already have a shift that day';
  end if;
  insert into public.open_shift_pickups(short_shift_id, staff_member_id)
  values (p_short_shift_id, v_staff) returning * into v_pickup;
  insert into public.staff_notices(staff_member_id, kind, title, body, month_start)
  select manager.id, 'open_shift_pickup', 'Open shift pickup requested',
    'A Staff member requested the ' || v_short.shift_code || ' shift on ' ||
      v_short.work_date::text || '.', date_trunc('month', v_short.work_date)::date
  from public.staff_members manager where manager.role = 'manager' and manager.active;
  return v_pickup;
end;
$$;

create or replace function public.approve_open_shift_pickup(p_pickup_id uuid)
returns void language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_pickup public.open_shift_pickups%rowtype;
  v_short public.short_shifts%rowtype;
  v_role public.job_role;
  v_section uuid;
  v_cell text;
begin
  if public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the Manager can approve a pickup';
  end if;
  select * into v_pickup from public.open_shift_pickups where id = p_pickup_id for update;
  if not found or v_pickup.status <> 'pending' then
    raise exception 'Pickup is not awaiting approval'; end if;
  select * into v_short from public.short_shifts where id = v_pickup.short_shift_id for update;
  if not found or v_short.filled_at is not null then raise exception 'Open shift has been filled'; end if;
  perform pg_advisory_xact_lock(hashtext(v_pickup.staff_member_id::text || ':' || v_short.work_date::text));
  select coalesce(v_short.job_role, (
    select job_role from public.staff_job_roles
    where staff_member_id = v_short.staff_member_id
      and effective_from <= v_short.work_date
    order by effective_from desc limit 1
  )) into v_role;
  if not exists (
    select 1 from public.staff_members member
    join public.staff_job_roles mine on mine.staff_member_id = member.id
    where member.id = v_pickup.staff_member_id and member.active
      and mine.effective_from <= v_short.work_date
      and (mine.effective_through is null or mine.effective_through >= v_short.work_date)
      and (mine.job_role = v_role or (mine.job_role in ('rn', 'lpn') and v_role in ('rn', 'lpn')))
  ) then raise exception 'Staff member is no longer eligible'; end if;
  select section_id into v_section from public.staff_section_assignments
  where staff_member_id = v_pickup.staff_member_id
    and effective_from <= v_short.work_date
    and (effective_through is null or effective_through >= v_short.work_date)
  order by effective_from desc limit 1;
  if v_section is null then raise exception 'Staff member is not on the Schedule'; end if;
  select shift_code into v_cell from public.schedule_cells
  where staff_member_id = v_pickup.staff_member_id and work_date = v_short.work_date for update;
  if v_cell is not null and v_cell not in ('', 'X') then
    raise exception 'Staff member already has a shift that day'; end if;
  perform public.save_schedule_cell(v_pickup.staff_member_id, v_section,
    v_short.work_date, v_short.shift_code);
  update public.open_shift_pickups set status = 'approved',
    approved_at = clock_timestamp(), approved_by = public.current_staff_member_id()
  where id = p_pickup_id;
  update public.open_shift_pickups set status = 'declined'
  where short_shift_id = v_short.id and id <> p_pickup_id and status = 'pending';
  insert into public.staff_notices(staff_member_id, kind, title, body, month_start)
  values (v_pickup.staff_member_id, 'open_shift_pickup', 'Open shift pickup approved',
    'Your ' || v_short.shift_code || ' shift on ' || v_short.work_date::text ||
      ' is on your Schedule.', date_trunc('month', v_short.work_date)::date);
  insert into public.staff_notices(staff_member_id, kind, title, body, month_start)
  select other.staff_member_id, 'open_shift_pickup', 'Open shift filled',
    'The ' || v_short.shift_code || ' shift on ' || v_short.work_date::text ||
      ' was picked up by another Staff member.',
    date_trunc('month', v_short.work_date)::date
  from public.open_shift_pickups other
  where other.short_shift_id = v_short.id and other.status = 'declined';
  update public.short_shifts set filled_at = clock_timestamp() where id = v_short.id;
end;
$$;
