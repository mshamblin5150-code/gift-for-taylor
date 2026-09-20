-- #203: existing values remain untouched. A NOT VALID check applies to every
-- new insert/update, but does not reject historical rows during deployment.
-- Managers can review these counts and edit legacy values deliberately.
do $$
declare
  v_section_count integer;
  v_staff_count integer;
  v_cell_count integer;
  v_code_count integer;
  v_meaning_count integer;
begin
  select count(*) into v_section_count from public.sections where char_length(name) > 32;
  select count(*) into v_staff_count from public.staff_members where char_length(display_name) > 30;
  select count(*) into v_cell_count from public.schedule_cells where char_length(shift_code) > 5;
  select count(*) into v_code_count from public.shift_codes where char_length(code) > 5;
  select count(*) into v_meaning_count from public.shift_codes where char_length(meaning) > 40;
  raise notice 'Legacy over-cap rows retained: sections %, staff %, cells %, codes %, meanings %',
    v_section_count, v_staff_count, v_cell_count, v_code_count, v_meaning_count;
end;
$$;

alter table public.sections
  add constraint sections_print_name_limit check (char_length(name) <= 32) not valid;
alter table public.staff_members
  add constraint staff_print_name_limit check (char_length(display_name) <= 30) not valid;
alter table public.schedule_cells
  add constraint schedule_cells_print_code_limit check (char_length(shift_code) <= 5) not valid;
alter table public.shift_codes
  add constraint shift_codes_print_code_limit check (char_length(code) <= 5) not valid,
  add constraint shift_codes_print_meaning_limit check (char_length(meaning) <= 40) not valid;

create or replace function public.add_section(p_name text)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if char_length(trim(coalesce(p_name, ''))) > 32 then
    raise exception 'Section name must be 32 characters or fewer';
  end if;
  if not public.can_manage_sections() then
    raise exception 'Only the Manager can manage Sections';
  end if;
  if length(trim(coalesce(p_name, ''))) = 0 then
    raise exception 'Section name is required';
  end if;

  perform pg_advisory_xact_lock(hashtext('public.sections.order'));
  insert into public.sections (name, display_order)
  select trim(p_name), coalesce(max(display_order) + 1, 0)
  from public.sections
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.rename_section(p_section_id uuid, p_name text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if char_length(trim(coalesce(p_name, ''))) > 32 then
    raise exception 'Section name must be 32 characters or fewer';
  end if;
  if not public.can_manage_sections() then
    raise exception 'Only the Manager can manage Sections';
  end if;
  if length(trim(coalesce(p_name, ''))) = 0 then
    raise exception 'Section name is required';
  end if;
  update public.sections set name = trim(p_name) where id = p_section_id;
  if not found then
    raise exception 'Section not found';
  end if;
end;
$$;

create or replace function public.create_staff_member_with_invite(
  p_display_name text, p_cell_number text, p_section_id uuid,
  p_allow_recycled_cell boolean
)
returns table (staff_member_id uuid, cell_number text, token text)
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_staff_member_id uuid;
  v_display_order integer;
  v_token text;
  v_cell_number text;
begin
  if char_length(trim(coalesce(p_display_name, ''))) > 30 then
    raise exception 'Staff name must be 30 characters or fewer';
  end if;
  if not public.can_manage_staff() then
    raise exception 'Only the Manager or administrator can manage the Staff list';
  end if;
  if nullif(trim(p_display_name), '') is null then
    raise exception 'Name and cell number are required';
  end if;
  if nullif(trim(p_cell_number), '') is null then
    raise exception 'Add a cell number before sending an Invite';
  end if;
  if not exists (select 1 from public.sections where id = p_section_id) then
    raise exception 'Section not found';
  end if;
  v_cell_number := public.normalize_cell_number(p_cell_number);
  perform pg_advisory_xact_lock(hashtext(v_cell_number));
  if not coalesce(p_allow_recycled_cell, false) and exists (
    select 1 from public.staff_members member
    where member.cell_number = v_cell_number and not member.active
  ) then
    raise exception 'A past Staff member has this cell number. Offer reactivation first.';
  end if;

  perform pg_advisory_xact_lock(hashtext(p_section_id::text));
  select coalesce(max(assignment.display_order) + 1, 0)
  into v_display_order
  from public.staff_section_assignments assignment
  where assignment.section_id = p_section_id
    and assignment.effective_through is null;

  insert into public.staff_members (display_name, cell_number)
  values (trim(p_display_name), v_cell_number)
  returning id, public.staff_members.cell_number into v_staff_member_id, v_cell_number;

  insert into public.staff_section_assignments (
    staff_member_id, section_id, display_order, effective_from
  ) values (v_staff_member_id, p_section_id, v_display_order, current_date);

  v_token := public.issue_staff_invite(v_staff_member_id);
  return query select v_staff_member_id, v_cell_number, v_token;
end;
$$;

create or replace function public.update_staff_contact(p_staff_member_id uuid,
  p_display_name text, p_cell_number text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_old public.staff_members%rowtype;
  v_name text := nullif(trim(p_display_name), '');
  v_cell text := nullif(trim(p_cell_number), '');
begin
  if char_length(v_name) > 30 then
    raise exception 'Staff name must be 30 characters or fewer';
  end if;
  if not public.can_manage_staff() then
    raise exception 'Only the Manager or administrator can manage the Staff list';
  end if;
  if v_name is null then raise exception 'Name is required'; end if;
  select * into v_old from public.staff_members member
  where member.id = p_staff_member_id for update;
  if not found then raise exception 'That person is not on the Staff list'; end if;
  if v_cell is not null then v_cell := public.normalize_cell_number(v_cell); end if;
  update public.staff_members set display_name = v_name, cell_number = v_cell
  where id = p_staff_member_id;
  if v_old.display_name is distinct from v_name then
    perform public.log_staff_change(p_staff_member_id, 'name',
      v_old.display_name, v_name, current_date);
  end if;
  if v_old.cell_number is distinct from v_cell then
    perform public.log_staff_change(p_staff_member_id, 'cell_number',
      v_old.cell_number, v_cell, current_date);
  end if;
end;
$$;

create or replace function public.write_schedule_cell(
  p_staff_member_id uuid, p_section_id uuid, p_work_date date, p_shift_code text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  v_month_start date := date_trunc('month', p_work_date)::date;
  v_month_id uuid;
  v_new_code text := trim(coalesce(p_shift_code, ''));
  v_old_code text;
  v_row public.staff_section_assignments%rowtype;
begin
  if char_length(v_new_code) > 5 then
    raise exception 'Shift code must be 5 characters or fewer';
  end if;
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

create or replace function public.save_shift_code(
  p_code text, p_meaning text, p_start_time time, p_end_time time,
  p_is_working boolean, p_coverage_window text, p_original_code text default null
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_code text := upper(trim(p_code));
  v_order integer;
begin
  if char_length(v_code) > 5 then
    raise exception 'Shift code must be 5 characters or fewer';
  end if;
  if char_length(trim(coalesce(p_meaning, ''))) > 40 then
    raise exception 'Shift meaning must be 40 characters or fewer';
  end if;
  if public.current_staff_role() <> 'manager' then
    raise exception 'Only the Manager can edit Shift codes';
  end if;
  if v_code is null or length(v_code) = 0
    or (p_start_time is null) <> (p_end_time is null)
    or (p_coverage_window is not null and p_coverage_window not in ('day', 'night'))
    or (p_start_time is null and p_coverage_window is not null) then
    raise exception 'Invalid Shift code, hours or Coverage window';
  end if;
  if p_original_code is not null and v_code <> p_original_code then
    select display_order into v_order from public.shift_codes where code = p_original_code;
    if v_order is null then raise exception 'Shift code not found'; end if;
    if exists (select 1 from public.shift_codes where code = v_code) then
      raise exception 'That Shift code already exists';
    end if;
    if public.shift_code_in_use(p_original_code) then
      update public.shift_codes set active = false where code = p_original_code;
    else
      delete from public.shift_codes where code = p_original_code;
    end if;
  end if;
  insert into public.shift_codes(
    code, meaning, start_time, end_time, is_working, coverage_window, display_order)
  values (v_code, nullif(trim(p_meaning), ''), p_start_time, p_end_time,
    p_is_working,
    coalesce(p_coverage_window, public.coverage_window_for_hours(p_start_time, p_end_time)),
    coalesce(v_order, (select display_order from public.shift_codes where code = p_original_code),
      (select coalesce(max(display_order), 0) + 1 from public.shift_codes)))
  on conflict (code) do update set meaning = excluded.meaning,
    start_time = excluded.start_time, end_time = excluded.end_time,
    is_working = excluded.is_working, coverage_window = excluded.coverage_window,
    active = true;
end;
$$;

