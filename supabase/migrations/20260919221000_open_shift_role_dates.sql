-- Match the original Staff member's role to the Open shift date.
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
      and (role.effective_through is null or role.effective_through >= short.work_date)
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
      and (effective_through is null or effective_through >= v_short.work_date)
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
      and (effective_through is null or effective_through >= v_short.work_date)
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
