-- Keep the source-month check in the same transaction as starting the month.
-- The client supplies a source only when copying the preceding Schedule.
drop function public.start_month(date, jsonb);

create function public.start_month(
  p_month_start date,
  p_cells jsonb,
  p_source_month_start date default null
)
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
    raise exception using errcode = '42501',
      message = 'Only the Manager can start a month';
  end if;
  if date_trunc('month', p_month_start)::date <> p_month_start then
    raise exception 'The month must start on its first day';
  end if;
  if jsonb_typeof(p_cells) <> 'array' then
    raise exception 'The cells must be a list';
  end if;

  -- Check the target first so a second start always has one verdict.
  if exists (
    select 1 from public.schedule_months
    where month_start = p_month_start
  ) then
    raise exception using errcode = 'P2791',
      message = 'That month has already been started';
  end if;
  if p_source_month_start is not null and not exists (
    select 1 from public.schedule_months
    where month_start = p_source_month_start
  ) then
    raise exception using errcode = 'P2792',
      message = 'There is no Schedule to start from';
  end if;

  insert into public.schedule_months (month_start)
  values (p_month_start)
  on conflict (month_start) do nothing
  returning id into v_month_id;
  if v_month_id is null then
    raise exception using errcode = 'P2791',
      message = 'That month has already been started';
  end if;

  v_expected := jsonb_array_length(p_cells);
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

revoke all on function public.start_month(date, jsonb, date) from public;
grant execute on function public.start_month(date, jsonb, date) to authenticated;
