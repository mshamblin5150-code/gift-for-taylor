-- The first month is transcribed from the printed book page and loaded straight
-- into the production database. The Manager checks it in the app, correcting
-- cells through save_schedule_cell like any other edit, and confirms it before
-- it replaces her Excel file.

alter table public.schedule_months
add column loaded_from_page_at timestamptz,
add column confirmed_at timestamptz,
add column confirmed_by_staff_member_id uuid references public.staff_members(id),
add check ((confirmed_at is null) = (confirmed_by_staff_member_id is null)),
add check (confirmed_at is null or loaded_from_page_at is not null);

-- Confirming the month loaded from the printed page is the moment it replaces
-- her Excel file, so it also releases that month. Corrections made while she
-- checked it were never seen by staff, so they need no Change announcement.
create function public.confirm_loaded_month(p_month_start date)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := public.current_staff_member_id();
begin
  if not public.can_edit_schedule() then
    raise exception 'Only the Manager can confirm the month';
  end if;

  update public.schedule_months
  set
    confirmed_at = now(),
    confirmed_by_staff_member_id = v_actor_id,
    release_state = 'released',
    released_at = coalesce(released_at, now()),
    released_by_staff_member_id = coalesce(released_by_staff_member_id, v_actor_id)
  where month_start = p_month_start
    and loaded_from_page_at is not null
    and confirmed_at is null;

  if not found then
    raise exception 'There is no loaded month waiting to be confirmed';
  end if;

  update public.schedule_changes change
  set announced_at = now()
  from public.schedule_months month
  where month.id = change.schedule_month_id
    and month.month_start = p_month_start
    and change.announced_at is null;
end;
$$;

revoke all on function public.confirm_loaded_month(date) from public;
grant execute on function public.confirm_loaded_month(date) to authenticated;

-- Run once from the Supabase SQL editor (as postgres) with the transcription of
-- the printed page. It is never callable through the API. p_rows is a JSON
-- array in page order:
--   [{"section": "...", "name": "...", "cell": "...", "codes": ["7A", ...]}]
-- with one code per day of the month ("" for a blank cell) and an optional
-- cell number for the person's Invite. Staff members already on the Staff list
-- are matched by exact name; everyone else is added at the bottom of their
-- Section. No Invites are sent.
create function public.load_first_month(p_month_start date, p_rows jsonb)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_month_id uuid;
  v_days integer;
  v_row jsonb;
  v_row_number integer := 0;
  v_name text;
  v_cell_number text;
  v_section_id uuid;
  v_staff_member_id uuid;
  v_current_section_id uuid;
  v_display_order integer;
  v_day integer;
begin
  if date_trunc('month', p_month_start)::date <> p_month_start then
    raise exception 'The month must start on its first day';
  end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then
    raise exception 'The transcription has no rows';
  end if;
  if exists (
    select 1 from public.schedule_months where month_start = p_month_start
  ) then
    raise exception 'That month is already in the database';
  end if;

  v_days := extract(day from p_month_start + interval '1 month' - interval '1 day');

  insert into public.schedule_months (month_start, loaded_from_page_at)
  values (p_month_start, now())
  returning id into v_month_id;

  for v_row in select value from jsonb_array_elements(p_rows)
  loop
    v_row_number := v_row_number + 1;
    v_name := trim(coalesce(v_row ->> 'name', ''));
    if length(v_name) = 0 then
      raise exception 'Row % has no name', v_row_number;
    end if;
    v_cell_number := nullif(trim(coalesce(v_row ->> 'cell', '')), '');

    select section.id
    into v_section_id
    from public.sections section
    where section.name = trim(coalesce(v_row ->> 'section', ''));
    if not found then
      raise exception 'Row % has an unknown Section', v_row_number;
    end if;

    if jsonb_typeof(v_row -> 'codes') is distinct from 'array'
      or jsonb_array_length(v_row -> 'codes') <> v_days
    then
      raise exception 'Row % must have % day cells', v_row_number, v_days;
    end if;

    select member.id
    into v_staff_member_id
    from public.staff_members member
    where member.display_name = v_name
      and member.active;

    if found then
      if exists (
        select 1
        from public.schedule_cells cell
        where cell.schedule_month_id = v_month_id
          and cell.staff_member_id = v_staff_member_id
      ) then
        raise exception 'Row % repeats a name', v_row_number;
      end if;

      select assignment.section_id
      into v_current_section_id
      from public.staff_section_assignments assignment
      where assignment.staff_member_id = v_staff_member_id
        and assignment.effective_through is null;
      if found and v_current_section_id <> v_section_id then
        raise exception 'Row % is in a different Section on the Staff list',
          v_row_number;
      end if;

      update public.staff_members
      set cell_number = v_cell_number
      where id = v_staff_member_id
        and cell_number is null;
    else
      if exists (
        select 1
        from public.staff_members member
        where member.display_name = v_name
          and not member.active
      ) then
        raise exception 'Row % names a deactivated Staff member', v_row_number;
      end if;

      insert into public.staff_members (display_name, cell_number)
      values (v_name, v_cell_number)
      returning id into v_staff_member_id;
      v_current_section_id := null;
    end if;

    if v_current_section_id is null then
      select coalesce(max(assignment.display_order) + 1, 0)
      into v_display_order
      from public.staff_section_assignments assignment
      where assignment.section_id = v_section_id
        and assignment.effective_through is null;

      insert into public.staff_section_assignments (
        staff_member_id,
        section_id,
        display_order,
        effective_from
      ) values (
        v_staff_member_id,
        v_section_id,
        v_display_order,
        p_month_start
      );
    end if;

    for v_day in 1..v_days
    loop
      insert into public.schedule_cells (
        schedule_month_id,
        staff_member_id,
        section_id,
        work_date,
        shift_code
      ) values (
        v_month_id,
        v_staff_member_id,
        v_section_id,
        p_month_start + (v_day - 1),
        trim(coalesce(v_row -> 'codes' ->> (v_day - 1), ''))
      );
    end loop;
  end loop;
end;
$$;

revoke all on function public.load_first_month(date, jsonb) from public, anon, authenticated;
