-- The Manager sets the default once; each Open shift retains its own choice.
create table public.open_shift_approval_settings (
  singleton boolean primary key default true check (singleton),
  requires_approval boolean not null default true
);
insert into public.open_shift_approval_settings(singleton) values (true);
alter table public.open_shift_approval_settings enable row level security;
revoke all on public.open_shift_approval_settings from public, anon, authenticated;

create function public.open_shift_approval_default()
returns boolean language sql stable security definer set search_path = '' as $$
  select requires_approval from public.open_shift_approval_settings where singleton;
$$;
create function public.set_open_shift_approval_default(p_requires_approval boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the Manager can set Open shift approval';
  end if;
  if p_requires_approval is null then
    raise exception 'Approval choice is required';
  end if;
  update public.open_shift_approval_settings
  set requires_approval = p_requires_approval where singleton;
end;
$$;
revoke all on function public.open_shift_approval_default(),
  public.set_open_shift_approval_default(boolean) from public;
grant execute on function public.open_shift_approval_default() to authenticated;
grant execute on function public.set_open_shift_approval_default(boolean) to authenticated;

alter table public.short_shifts alter column requires_approval
  set default public.open_shift_approval_default();

-- Omitting the final argument uses the Manager setting. An explicit choice
-- wins for ordinary shifts; an RN-floor gap starts with approval on.
create or replace function public.post_open_shifts(p_date date, p_shift_code text, p_pool text,
  p_count integer, p_fill_gap boolean, p_requires_approval boolean default null)
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
    case when n <= v_floor_count then true
      else coalesce(p_requires_approval, public.open_shift_approval_default()) end,
    n <= v_floor_count
  from generate_series(1, v_count) as series(n);
  return v_count;
end;
$$;

create function public.set_open_shift_approval(p_short_shift_id uuid, p_requires_approval boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the Manager can set Open shift approval';
  end if;
  if p_requires_approval is null then raise exception 'Approval choice is required'; end if;
  update public.short_shifts set requires_approval = p_requires_approval
  where id = p_short_shift_id and filled_at is null;
  if not found then raise exception 'Open shift is unavailable'; end if;
end;
$$;
revoke all on function public.set_open_shift_approval(uuid, boolean) from public;
grant execute on function public.set_open_shift_approval(uuid, boolean) to authenticated;

drop function public.visible_open_shifts();
create function public.visible_open_shifts()
returns table (id uuid, section_id uuid, work_date date, shift_code text,
  original_staff_member_id uuid, job_role public.job_role, pickup_id uuid,
  pickup_staff_member_id uuid, pickup_status text, requires_approval boolean)
language sql stable security definer set search_path = '' as $$
  select short.id, short.section_id, short.work_date, short.shift_code,
    short.staff_member_id, coalesce(short.job_role, original_role.job_role),
    pickup.id, pickup.staff_member_id, pickup.status, short.requires_approval
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
revoke all on function public.visible_open_shifts() from public;
grant execute on function public.visible_open_shifts() to authenticated;

-- Both Manager saves and self-service pickups use the same placement checks,
-- row lock, cell write, and Schedule change log. Only the guarded entry points
-- may call this function.
create function public.write_schedule_cell(
  p_staff_member_id uuid, p_section_id uuid, p_work_date date, p_shift_code text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  v_month_start date := date_trunc('month', p_work_date)::date;
  v_month_id uuid;
  v_new_code text := trim(coalesce(p_shift_code, ''));
  v_old_code text;
  v_row public.staff_section_assignments%rowtype;
begin
  perform 1 from public.staff_members member
  where member.id = p_staff_member_id for share;
  select assignment.* into v_row
  from public.staff_section_assignments assignment
  where assignment.staff_member_id = p_staff_member_id
    and assignment.effective_from < (v_month_start + interval '1 month')::date
    and (assignment.effective_through is null or assignment.effective_through >= v_month_start)
  order by assignment.effective_from desc limit 1;
  if not found or v_row.section_id <> p_section_id then
    raise exception 'That Staff member is not on the Staff list in this Section';
  end if;
  if p_work_date > v_row.effective_through then
    raise exception 'That day is after their Last day';
  end if;
  insert into public.schedule_months(month_start) values (v_month_start)
  on conflict (month_start) do nothing;
  select month.id into v_month_id from public.schedule_months month
  where month.month_start = v_month_start;
  perform pg_advisory_xact_lock(hashtext(p_staff_member_id::text || ':' || p_work_date::text));
  select cell.shift_code into v_old_code from public.schedule_cells cell
  where cell.schedule_month_id = v_month_id
    and cell.staff_member_id = p_staff_member_id and cell.work_date = p_work_date;
  v_old_code := coalesce(v_old_code, '');
  if v_old_code = v_new_code then return; end if;
  insert into public.schedule_cells(schedule_month_id, staff_member_id, section_id,
    work_date, shift_code)
  values (v_month_id, p_staff_member_id, p_section_id, p_work_date, v_new_code)
  on conflict (schedule_month_id, staff_member_id, work_date) do update
  set shift_code = excluded.shift_code, section_id = excluded.section_id,
    updated_at = now();
  insert into public.schedule_changes(schedule_month_id, staff_member_id,
    section_id, work_date, old_shift_code, new_shift_code, changed_by_staff_member_id)
  values (v_month_id, p_staff_member_id, p_section_id, p_work_date,
    v_old_code, v_new_code, public.current_staff_member_id());
end;
$$;
revoke all on function public.write_schedule_cell(uuid, uuid, date, text) from public;

create or replace function public.save_schedule_cell(
  p_staff_member_id uuid, p_section_id uuid, p_work_date date, p_shift_code text)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if not public.can_edit_section(p_section_id) then
    if public.current_staff_role() = 'night_scheduler' then
      raise exception 'Only the Manager can edit that Section';
    end if;
    raise exception 'Only the Manager can edit the Schedule';
  end if;
  perform public.write_schedule_cell(p_staff_member_id, p_section_id,
    p_work_date, p_shift_code);
end;
$$;

-- Preserve the dated eligibility and the row and advisory locks from the
-- existing pickup RPC. Self-service completion happens in this transaction.
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
  v_section uuid;
begin
  if v_staff is null or public.current_staff_role() = 'manager' then
    raise exception 'Only Staff members can request a pickup';
  end if;
  select * into v_short from public.short_shifts where id = p_short_shift_id for update;
  if not found or not exists (
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
  select section_id into v_section from public.staff_section_assignments assignment
  where assignment.staff_member_id = v_staff and assignment.effective_from <= v_short.work_date
    and (assignment.effective_through is null or assignment.effective_through >= v_short.work_date)
  order by effective_from desc limit 1;
  if v_section is null then raise exception 'Staff member is not on the Schedule for that day'; end if;
  perform pg_advisory_xact_lock(hashtext(v_staff::text || ':' || v_short.work_date::text));
  select shift_code into v_cell from public.schedule_cells
  where staff_member_id = v_staff and work_date = v_short.work_date for update;
  if v_cell is not null and v_cell not in ('', 'X') then
    raise exception 'You already have a shift that day';
  end if;
  if v_short.filled_at is not null then
    insert into public.open_shift_pickups(short_shift_id, staff_member_id, status)
    values (p_short_shift_id, v_staff, 'declined')
    on conflict (short_shift_id, staff_member_id) do nothing
    returning * into v_pickup;
    if found then
      insert into public.staff_notices(staff_member_id, kind, title, body, month_start)
      values (v_staff, 'open_shift_pickup', 'Open shift filled',
        'The ' || v_short.shift_code || ' shift on ' || v_short.work_date::text ||
          ' was picked up by another Staff member.',
        date_trunc('month', v_short.work_date)::date);
    else
      select * into v_pickup from public.open_shift_pickups
      where short_shift_id = p_short_shift_id and staff_member_id = v_staff;
    end if;
    return v_pickup;
  end if;
  insert into public.open_shift_pickups(short_shift_id, staff_member_id)
  values (p_short_shift_id, v_staff) returning * into v_pickup;
  if v_short.requires_approval then
    insert into public.staff_notices(staff_member_id, kind, title, body, month_start)
    select manager.id, 'open_shift_pickup', 'Open shift pickup requested',
      'A Staff member requested the ' || v_short.shift_code || ' shift on ' ||
        v_short.work_date::text || '.', date_trunc('month', v_short.work_date)::date
    from public.staff_members manager where manager.role = 'manager' and manager.active;
  else
    perform public.write_schedule_cell(v_staff, v_section,
      v_short.work_date, v_short.shift_code);
    update public.open_shift_pickups set status = 'approved',
      approved_at = clock_timestamp(), approved_by = null
    where id = v_pickup.id returning * into v_pickup;
    with declined as (
      update public.open_shift_pickups set status = 'declined'
      where short_shift_id = v_short.id and id <> v_pickup.id and status = 'pending'
      returning staff_member_id
    )
    insert into public.staff_notices(staff_member_id, kind, title, body, month_start)
    select staff_member_id, 'open_shift_pickup', 'Open shift filled',
      'The ' || v_short.shift_code || ' shift on ' || v_short.work_date::text ||
        ' was picked up by another Staff member.',
      date_trunc('month', v_short.work_date)::date from declined;
    insert into public.staff_notices(staff_member_id, kind, title, body, month_start)
    values (v_staff, 'open_shift_pickup', 'Open shift pickup approved',
      'Your ' || v_short.shift_code || ' shift on ' || v_short.work_date::text ||
        ' is on your Schedule.', date_trunc('month', v_short.work_date)::date);
    update public.short_shifts set filled_at = clock_timestamp() where id = v_short.id;
  end if;
  return v_pickup;
end;
$$;
