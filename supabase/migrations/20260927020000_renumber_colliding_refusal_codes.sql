-- A Refusal code names one meaning everywhere. These definitions move the
-- colliding meanings to their permanent codes without rewriting history.

create or replace function public.validate_swap_shift_eligibility()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_swap public.swaps%rowtype;
  v_from uuid;
  v_to uuid;
begin
  select * into v_swap from public.swaps where id = new.swap_id;
  v_from := case new.side
    when 'requester' then v_swap.requester_id else v_swap.colleague_id end;
  v_to := case new.side
    when 'requester' then v_swap.colleague_id else v_swap.requester_id end;
  if not public.can_take_shift(v_from, v_to, new.work_date) then
    raise exception using errcode = 'P2846',
      message = format(
        'A Staff member cannot work the offered shift on %s', new.work_date
      );
  end if;
  return new;
end;
$$;

create or replace function public.recheck_swap_eligibility_before_approval()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'approved' and old.status = 'accepted' and exists (
    select 1 from public.swap_shifts shift
    where shift.swap_id = new.id
      and not public.can_take_shift(
        case shift.side when 'requester' then new.requester_id
          else new.colleague_id end,
        case shift.side when 'requester' then new.colleague_id
          else new.requester_id end,
        shift.work_date
      )
  ) then
    raise exception using errcode = 'P2846',
      message = 'A Staff member can no longer work one of the offered shifts';
  end if;
  return new;
end;
$$;

create or replace function public.redact_ticket_thread_entry(p_entry_id uuid)
returns public.ticket_thread_entries
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare v_entry public.ticket_thread_entries%rowtype;
begin
  if not public.is_maintainer() then
    raise exception using errcode = '42501',
      message = 'Only the Maintainer can redact Ticket thread text';
  end if;

  update public.ticket_thread_entries
  set text = 'Text removed by the Maintainer',
    suggested_answer = null,
    text_removal = 'maintainer'
  where id = p_entry_id
  returning * into v_entry;
  if not found then
    raise exception using errcode = 'P2847',
      message = 'Ticket thread message not found';
  end if;
  return v_entry;
end;
$$;

create or replace function public.open_maintainer_repair(
  p_reason_category public.maintainer_repair_reason_category,
  p_detail text default null,
  p_ticket_id uuid default null
)
returns setof public.maintainer_repairs
language plpgsql volatile security definer set search_path = '' as $$
declare v_detail text := nullif(trim(p_detail), '');
begin
  if not public.is_maintainer() then
    raise exception 'Only the Maintainer can open a Repair';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('maintainer-repair:' || auth.uid()::text, 0));
  if v_detail is not null and length(v_detail) not between 3 and 240 then
    raise exception 'Repair detail must be 3-240 characters';
  end if;
  if p_reason_category = 'something_else' and v_detail is null then
    raise exception 'Something else requires repair detail (3-240 characters)';
  end if;
  if p_ticket_id is not null
      and not exists (select 1 from public.tickets where id = p_ticket_id) then
    raise exception using errcode = 'P2834', message = 'Ticket not found';
  end if;

  update public.maintainer_repairs
  set closed_at = expires_at
  where auth_user_id = auth.uid() and closed_at is null
    and expires_at <= clock_timestamp();
  if private.active_maintainer_repair_id() is not null then
    raise exception 'Close the current Repair before opening another';
  end if;

  return query insert into public.maintainer_repairs(
      auth_user_id, reason_category, detail, ticket_id)
    values (auth.uid(), p_reason_category, v_detail, p_ticket_id)
    returning *;
end;
$$;

create or replace function public.withdraw_call_in(
  p_staff_member_id uuid,
  p_work_date date
)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  v_section uuid;
  v_code text;
  v_change public.schedule_changes%rowtype;
begin
  if p_staff_member_id is null or p_work_date is null then
    raise exception 'A Staff member and date are required';
  end if;
  perform pg_advisory_xact_lock(
    hashtext(p_staff_member_id::text || ':' || p_work_date::text));
  select cell.section_id, cell.shift_code into v_section, v_code
  from public.schedule_cells cell
  where cell.staff_member_id = p_staff_member_id
    and cell.work_date = p_work_date
  for update;
  if not found or v_code <> 'C/I' then
    raise exception using errcode = 'P2848',
      message = 'There is no Call-in to withdraw';
  end if;
  if not public.can_record_call_in(v_section) then
    raise exception using errcode = 'P2811',
      message = 'You must be working when you withdraw a Call-in';
  end if;
  select * into v_change from public.schedule_changes change
  where change.staff_member_id = p_staff_member_id
    and change.work_date = p_work_date
  order by change.changed_at desc, change.id desc limit 1;
  if not found or v_change.new_shift_code <> 'C/I'
    or not public.is_working_shift(v_change.old_shift_code) then
    raise exception using errcode = 'P2848',
      message = 'There is no recorded Call-in to withdraw';
  end if;

  perform 1 from public.short_shifts short
  where short.call_in_change_id = v_change.id order by short.id for update;
  if exists (select 1 from public.short_shifts short
    where short.call_in_change_id = v_change.id
      and short.filled_at is not null) then
    raise exception using errcode = 'P2813',
      message = 'A Call-in is settled once an Open shift is filled';
  end if;
  with declined as (
    update public.open_shift_pickups pickup set status = 'declined'
    from public.short_shifts short
    where pickup.short_shift_id = short.id
      and short.call_in_change_id = v_change.id
      and pickup.status = 'pending'
    returning pickup.staff_member_id, short.shift_code, short.work_date
  )
  insert into public.staff_notices(
    staff_member_id, kind, title, body, month_start)
  select staff_member_id, 'open_shift_pickup', 'Open shift withdrawn',
    'The ' || shift_code || ' shift on ' || work_date::text
      || ' is no longer available.',
    date_trunc('month', work_date)::date from declined;

  delete from public.staff_notices notice using public.short_shifts short
  where notice.short_shift_id = short.id
    and short.call_in_change_id = v_change.id;
  delete from public.open_shift_pickups pickup using public.short_shifts short
  where pickup.short_shift_id = short.id
    and short.call_in_change_id = v_change.id;
  delete from public.short_shifts where call_in_change_id = v_change.id;
  perform public.write_schedule_cell(
    p_staff_member_id, v_section, p_work_date, v_change.old_shift_code);
end;
$$;

create or replace function public.delete_empty_section(p_section_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not public.can_manage_sections() then
    raise exception 'Only the Manager can manage Sections';
  end if;
  -- Historical assignments preserve the meaning of older Schedules.
  if exists (
    select 1 from public.staff_section_assignments
    where section_id = p_section_id
  ) then
    raise exception using errcode = 'P2795',
      message = 'A Section with Staff members cannot be deleted';
  end if;
  delete from public.sections where id = p_section_id;
  if not found then
    raise exception 'Section not found';
  end if;
exception when foreign_key_violation then
  raise exception using errcode = 'P2849',
    message = 'A Section with Schedule history cannot be deleted';
end;
$$;
