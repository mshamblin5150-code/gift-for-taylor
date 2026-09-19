-- The first month is transcribed from the printed book page and loaded straight
-- into the production database. The Manager checks it in the app, correcting
-- cells through the ordinary edit path, and confirms it before it replaces her
-- Excel file.

alter table public.schedule_months
add column loaded_from_page_at timestamptz,
add column confirmed_at timestamptz,
add column confirmed_by_staff_member_id uuid references public.staff_members(id),
add check ((confirmed_at is null) = (confirmed_by_staff_member_id is null)),
add check (confirmed_at is null or loaded_from_page_at is not null);

create table public.schedule_changes (
  id uuid primary key default gen_random_uuid(),
  schedule_month_id uuid not null references public.schedule_months(id),
  staff_member_id uuid not null references public.staff_members(id),
  section_id uuid not null references public.sections(id),
  work_date date not null,
  old_shift_code text not null,
  new_shift_code text not null,
  changed_by_staff_member_id uuid not null references public.staff_members(id),
  changed_by_display_name text not null,
  changed_at timestamptz not null default now(),
  announced_at timestamptz,
  check (old_shift_code <> new_shift_code)
);

create index schedule_changes_by_month
on public.schedule_changes (schedule_month_id, changed_at);

alter table public.schedule_changes enable row level security;

grant select on public.schedule_changes to authenticated;

create policy "schedulers can read the change log"
on public.schedule_changes for select
using (
  public.current_staff_role() in ('manager', 'administrator', 'night_scheduler')
);

create function public.current_staff_member_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select member.id
  from public.staff_accounts account
  join public.staff_members member on member.id = account.staff_member_id
  where account.auth_user_id = auth.uid()
    and member.active
    and account.accepted_invite_at is not null
$$;

revoke all on function public.current_staff_member_id() from public;

create function public.save_schedule_cell(
  p_staff_member_id uuid,
  p_work_date date,
  p_shift_code text
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := public.current_staff_member_id();
  v_month_id uuid;
  v_section_id uuid;
  v_old_code text;
  v_new_code text := trim(coalesce(p_shift_code, ''));
begin
  if public.current_staff_role() is distinct from 'manager' then
    raise exception 'Only the Manager can edit the Schedule';
  end if;

  select month.id
  into v_month_id
  from public.schedule_months month
  where month.month_start = date_trunc('month', p_work_date)::date;
  if not found then
    raise exception 'That month has not been started';
  end if;

  select cell.section_id, cell.shift_code
  into v_section_id, v_old_code
  from public.schedule_cells cell
  where cell.schedule_month_id = v_month_id
    and cell.staff_member_id = p_staff_member_id
    and cell.work_date = p_work_date
  for update;

  if not found then
    select assignment.section_id
    into v_section_id
    from public.staff_section_assignments assignment
    join public.staff_members member on member.id = assignment.staff_member_id
    where assignment.staff_member_id = p_staff_member_id
      and assignment.effective_through is null
      and member.active;
    if not found then
      raise exception 'Staff member not found';
    end if;
    v_old_code := '';
  end if;

  if v_old_code = v_new_code then
    return;
  end if;

  insert into public.schedule_cells (
    schedule_month_id,
    staff_member_id,
    section_id,
    work_date,
    shift_code
  ) values (
    v_month_id,
    p_staff_member_id,
    v_section_id,
    p_work_date,
    v_new_code
  )
  on conflict (schedule_month_id, staff_member_id, work_date)
  do update set shift_code = excluded.shift_code, updated_at = now();

  insert into public.schedule_changes (
    schedule_month_id,
    staff_member_id,
    section_id,
    work_date,
    old_shift_code,
    new_shift_code,
    changed_by_staff_member_id,
    changed_by_display_name
  )
  select
    v_month_id,
    p_staff_member_id,
    v_section_id,
    p_work_date,
    v_old_code,
    v_new_code,
    actor.id,
    actor.display_name
  from public.staff_members actor
  where actor.id = v_actor_id;
end;
$$;

revoke all on function public.save_schedule_cell(uuid, date, text) from public;
grant execute on function public.save_schedule_cell(uuid, date, text) to authenticated;

-- Confirming the month loaded from the printed page is the moment it replaces
-- her Excel file, so it also releases that month.
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
  if public.current_staff_role() is distinct from 'manager' then
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
