-- The client reads the caller-side availability once per month session. The
-- command still checks can_record_call_in at write time.
create function public.is_current_staff_member_on_floor()
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare
  v_local timestamp := clock_timestamp() at time zone 'America/New_York';
begin
  return coalesce(public.is_active_staff_member() and exists (
    select 1 from public.schedule_cells own
    left join public.shift_codes code on code.code = upper(trim(own.shift_code))
    where own.staff_member_id = public.current_staff_member_id()
      and public.is_working_shift(own.shift_code)
      and ((own.work_date = v_local::date
          and (code.start_time is null
            or (v_local::time >= code.start_time
              and (code.end_time > code.start_time
                and v_local::time < code.end_time
                or code.end_time <= code.start_time))))
        or (own.work_date = v_local::date - 1
          and code.end_time <= code.start_time
          and v_local::time < code.end_time))
  ), false);
end;
$$;

create or replace function public.can_record_call_in(p_section_id uuid)
returns boolean language sql volatile security definer set search_path = '' as $$
  select public.can_edit_section(p_section_id)
    or public.is_current_staff_member_on_floor();
$$;

-- A C/I with no linked posting is still withdrawable. It becomes settled as
-- soon as any Open shift created by that particular Call-in has been filled.
create function public.call_in_withdrawal_state(
  p_staff_member_id uuid,
  p_work_date date
)
returns text language plpgsql stable security definer set search_path = '' as $$
declare
  v_change_id uuid;
begin
  select change.id into v_change_id
  from public.schedule_changes change
  join public.schedule_cells cell
    on cell.staff_member_id = change.staff_member_id
    and cell.work_date = change.work_date
  where change.staff_member_id = p_staff_member_id
    and change.work_date = p_work_date
    and cell.shift_code = 'C/I'
    and change.new_shift_code = 'C/I'
    and public.is_working_shift(change.old_shift_code)
  order by change.changed_at desc, change.id desc
  limit 1;
  if not found then return 'not_recorded'; end if;
  if exists (
    select 1 from public.short_shifts short
    where short.call_in_change_id = v_change_id
      and short.filled_at is not null
  ) then
    return 'settled';
  end if;
  return 'withdrawable';
end;
$$;

drop function public.record_call_in(uuid, date);
create function public.record_call_in(p_staff_member_id uuid, p_work_date date)
returns integer language plpgsql volatile security definer set search_path = '' as $$
declare
  v_section uuid;
  v_code text;
  v_change_id uuid;
  v_posted integer;
begin
  if p_staff_member_id is null or p_work_date is null then
    raise exception 'A Staff member and date are required';
  end if;
  perform pg_advisory_xact_lock(hashtext(p_staff_member_id::text || ':' || p_work_date::text));
  select cell.section_id, cell.shift_code into v_section, v_code
  from public.schedule_cells cell
  where cell.staff_member_id = p_staff_member_id and cell.work_date = p_work_date
  for update;
  if not found or not public.is_working_shift(v_code) then
    raise exception using errcode = 'P2812',
      message = 'Target has no working Shift to call in from';
  end if;
  if not public.can_record_call_in(v_section) then
    raise exception using errcode = 'P2811',
      message = 'You must be working when you record a Call-in';
  end if;
  perform public.write_schedule_cell(p_staff_member_id, v_section, p_work_date, 'C/I');
  select change.id into v_change_id from public.schedule_changes change
  where change.staff_member_id = p_staff_member_id
    and change.work_date = p_work_date
    and change.new_shift_code = 'C/I'
  order by change.changed_at desc, change.id desc limit 1;
  select count(*)::integer into v_posted from public.short_shifts short
  where short.call_in_change_id = v_change_id;
  return v_posted;
end;
$$;

create or replace function public.withdraw_call_in(p_staff_member_id uuid, p_work_date date)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  v_section uuid;
  v_code text;
  v_change public.schedule_changes%rowtype;
begin
  if p_staff_member_id is null or p_work_date is null then
    raise exception 'A Staff member and date are required';
  end if;
  perform pg_advisory_xact_lock(hashtext(p_staff_member_id::text || ':' || p_work_date::text));
  select cell.section_id, cell.shift_code into v_section, v_code
  from public.schedule_cells cell
  where cell.staff_member_id = p_staff_member_id and cell.work_date = p_work_date
  for update;
  if not found or v_code <> 'C/I' then
    raise exception using errcode = 'P2812', message = 'There is no Call-in to withdraw';
  end if;
  if not public.can_record_call_in(v_section) then
    raise exception using errcode = 'P2811',
      message = 'You must be working when you withdraw a Call-in';
  end if;
  select * into v_change from public.schedule_changes change
  where change.staff_member_id = p_staff_member_id and change.work_date = p_work_date
  order by change.changed_at desc, change.id desc limit 1;
  if not found or v_change.new_shift_code <> 'C/I'
    or not public.is_working_shift(v_change.old_shift_code) then
    raise exception using errcode = 'P2812', message = 'There is no recorded Call-in to withdraw';
  end if;

  perform 1 from public.short_shifts short
  where short.call_in_change_id = v_change.id order by short.id for update;
  if exists (select 1 from public.short_shifts short
    where short.call_in_change_id = v_change.id and short.filled_at is not null) then
    raise exception using errcode = 'P2813',
      message = 'A Call-in is settled once an Open shift is filled';
  end if;
  with declined as (
    update public.open_shift_pickups pickup set status = 'declined'
    from public.short_shifts short
    where pickup.short_shift_id = short.id and short.call_in_change_id = v_change.id
      and pickup.status = 'pending'
    returning pickup.staff_member_id, short.shift_code, short.work_date
  )
  insert into public.staff_notices(staff_member_id, kind, title, body, month_start)
  select staff_member_id, 'open_shift_pickup', 'Open shift withdrawn',
    'The ' || shift_code || ' shift on ' || work_date::text || ' is no longer available.',
    date_trunc('month', work_date)::date from declined;

  delete from public.staff_notices notice using public.short_shifts short
  where notice.short_shift_id = short.id and short.call_in_change_id = v_change.id;
  delete from public.open_shift_pickups pickup using public.short_shifts short
  where pickup.short_shift_id = short.id and short.call_in_change_id = v_change.id;
  delete from public.short_shifts where call_in_change_id = v_change.id;
  perform public.write_schedule_cell(p_staff_member_id, v_section,
    p_work_date, v_change.old_shift_code);
end;
$$;

revoke all on function public.is_current_staff_member_on_floor(),
  public.call_in_withdrawal_state(uuid, date),
  public.record_call_in(uuid, date),
  public.withdraw_call_in(uuid, date) from public;
grant execute on function public.is_current_staff_member_on_floor(),
  public.call_in_withdrawal_state(uuid, date),
  public.record_call_in(uuid, date),
  public.withdraw_call_in(uuid, date) to authenticated;
