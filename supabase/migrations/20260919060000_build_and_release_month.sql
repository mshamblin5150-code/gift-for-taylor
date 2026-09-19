-- The Manager starts next month from the current one and releases it when it
-- is finished. The app works out the copied cells (lined up by weekday, with
-- R/O, H, S/L and A/L cleared); the database stores them in one step. Until
-- release the month is unpublished, which the existing read policies already
-- hide from Staff members.

create function public.start_month(p_month_start date, p_cells jsonb)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_month_id uuid;
  v_expected integer;
  v_inserted integer;
begin
  if not public.can_edit_schedule() then
    raise exception 'Only the Manager can start a month';
  end if;
  if date_trunc('month', p_month_start)::date <> p_month_start then
    raise exception 'The month must start on its first day';
  end if;
  if jsonb_typeof(p_cells) <> 'array' then
    raise exception 'The cells must be a list';
  end if;

  insert into public.schedule_months (month_start)
  values (p_month_start)
  on conflict (month_start) do nothing
  returning id into v_month_id;
  if v_month_id is null then
    raise exception 'That month has already been started';
  end if;

  v_expected := jsonb_array_length(p_cells);

  -- A cell is stored only for someone active on the Staff list in that
  -- Section; the date trigger keeps every cell inside the month.
  insert into public.schedule_cells (
    schedule_month_id,
    staff_member_id,
    section_id,
    work_date,
    shift_code
  )
  select
    v_month_id,
    cell.staff_member_id,
    cell.section_id,
    cell.work_date,
    trim(coalesce(cell.shift_code, ''))
  from jsonb_to_recordset(p_cells) as cell(
    staff_member_id uuid,
    section_id uuid,
    work_date date,
    shift_code text
  )
  join public.staff_members member
    on member.id = cell.staff_member_id
    and member.active
  join public.staff_section_assignments assignment
    on assignment.staff_member_id = cell.staff_member_id
    and assignment.section_id = cell.section_id
    and assignment.effective_through is null;

  get diagnostics v_inserted = row_count;
  if v_inserted <> v_expected then
    raise exception 'Every cell must be for someone on the Staff list in that Section';
  end if;
end;
$$;

revoke all on function public.start_month(date, jsonb) from public;
grant execute on function public.start_month(date, jsonb) to authenticated;

-- Release makes the month live in one step. Edits made while building it were
-- never seen by staff, so they need no Change announcement. A month loaded
-- from the printed page is released by confirming it instead.
create function public.release_month(p_month_start date)
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
    raise exception 'Only the Manager can release a month';
  end if;

  update public.schedule_months
  set
    release_state = 'released',
    released_at = now(),
    released_by_staff_member_id = v_actor_id
  where month_start = p_month_start
    and release_state = 'unpublished'
    and loaded_from_page_at is null;

  if not found then
    raise exception 'There is no unpublished month to release';
  end if;

  update public.schedule_changes change
  set announced_at = now()
  from public.schedule_months month
  where month.id = change.schedule_month_id
    and month.month_start = p_month_start
    and change.announced_at is null;
end;
$$;

revoke all on function public.release_month(date) from public;
grant execute on function public.release_month(date) to authenticated;
