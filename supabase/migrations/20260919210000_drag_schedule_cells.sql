-- A drag (and its Undo) is one transaction. Expected values prevent a stale
-- grid from silently overwriting another scheduler's edit.
create function public.save_schedule_cell_pair(
  p_first_staff_member_id uuid,
  p_first_section_id uuid,
  p_first_work_date date,
  p_first_expected_code text,
  p_first_new_code text,
  p_second_staff_member_id uuid,
  p_second_section_id uuid,
  p_second_work_date date,
  p_second_expected_code text,
  p_second_new_code text
)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  v_first_code text;
  v_second_code text;
  v_first_key text := p_first_staff_member_id::text || ':' || p_first_work_date::text;
  v_second_key text := p_second_staff_member_id::text || ':' || p_second_work_date::text;
begin
  if p_first_work_date is null or p_second_work_date is null
    or date_trunc('month', p_first_work_date) <> date_trunc('month', p_second_work_date)
    or v_first_key = v_second_key then
    raise exception 'Choose two different Schedule cells in the same month';
  end if;
  if not public.can_edit_section(p_first_section_id)
     or not public.can_edit_section(p_second_section_id) then
    raise exception 'You cannot edit both Sections';
  end if;

  -- Acquire both locks in the same order for concurrent opposing drags.
  perform pg_advisory_xact_lock(hashtext(least(v_first_key, v_second_key)));
  perform pg_advisory_xact_lock(hashtext(greatest(v_first_key, v_second_key)));

  select cell.shift_code into v_first_code
  from public.schedule_cells cell
  join public.schedule_months month on month.id = cell.schedule_month_id
  where month.month_start = date_trunc('month', p_first_work_date)::date
    and cell.staff_member_id = p_first_staff_member_id
    and cell.work_date = p_first_work_date;
  select cell.shift_code into v_second_code
  from public.schedule_cells cell
  join public.schedule_months month on month.id = cell.schedule_month_id
  where month.month_start = date_trunc('month', p_second_work_date)::date
    and cell.staff_member_id = p_second_staff_member_id
    and cell.work_date = p_second_work_date;
  if coalesce(v_first_code, '') <> trim(coalesce(p_first_expected_code, ''))
     or coalesce(v_second_code, '') <> trim(coalesce(p_second_expected_code, '')) then
    raise exception 'The Schedule changed. Reload and try again.';
  end if;

  -- Each save validates Section placement and Last day and appends a Schedule
  -- change. An error in either save rolls back both saves and log entries.
  perform public.save_schedule_cell(p_first_staff_member_id, p_first_section_id,
    p_first_work_date, p_first_new_code);
  perform public.save_schedule_cell(p_second_staff_member_id, p_second_section_id,
    p_second_work_date, p_second_new_code);
end;
$$;
revoke all on function public.save_schedule_cell_pair(uuid, uuid, date, text, text, uuid, uuid, date, text, text) from public;
grant execute on function public.save_schedule_cell_pair(uuid, uuid, date, text, text, uuid, uuid, date, text, text) to authenticated;
