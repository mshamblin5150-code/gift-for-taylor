-- A posted Open shift can be traced to the particular Call-in that opened it.
-- The posting path (#147) will populate this link; unrelated shifts stay null.
alter table public.short_shifts add column call_in_change_id uuid
  references public.schedule_changes(id);
create index short_shifts_call_in_change on public.short_shifts(call_in_change_id)
  where call_in_change_id is not null;

-- Posting notices can be removed on withdrawal without touching unrelated
-- notices to the same recipient for the same month.
alter table public.staff_notices add column short_shift_id uuid
  references public.short_shifts(id);
create index staff_notices_short_shift on public.staff_notices(short_shift_id)
  where short_shift_id is not null;

-- Attach the existing posting notice to its Open shift, so deleting a
-- withdrawn posting does not erase a different shift's notice.
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
  insert into public.staff_notices(staff_member_id, kind, title, body, month_start, short_shift_id)
  select distinct member.id, 'open_shift_posted', 'Open shift posted',
    p_short.shift_code || ' on ' || p_short.work_date::text || ' is open for pickup.',
    date_trunc('month', p_short.work_date)::date, p_short.id
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

-- The Schedule's work date is local to the department. After midnight, a
-- Staff member still on yesterday's overnight Shift is also on the floor.
create function public.can_record_call_in(p_section_id uuid)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare
  v_local timestamp := clock_timestamp() at time zone 'America/New_York';
begin
  return public.can_edit_section(p_section_id) or coalesce(
    public.current_staff_role() = 'staff_member' and exists (
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
revoke all on function public.can_record_call_in(uuid) from public;

create function public.record_call_in(p_staff_member_id uuid, p_work_date date)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  v_section uuid;
  v_code text;
begin
  if p_staff_member_id is null or p_work_date is null then
    raise exception 'A Staff member and date are required';
  end if;
  -- Serialize with another recorder or a withdrawal on this cell.
  perform pg_advisory_xact_lock(hashtext(p_staff_member_id::text || ':' || p_work_date::text));
  select cell.section_id, cell.shift_code into v_section, v_code
  from public.schedule_cells cell
  where cell.staff_member_id = p_staff_member_id and cell.work_date = p_work_date
  for update;
  if not found or not public.is_working_shift(v_code) then
    raise exception 'Target has no working Shift to call in from';
  end if;
  if not public.can_record_call_in(v_section) then
    raise exception 'You must be working when you record a Call-in';
  end if;
  perform public.write_schedule_cell(p_staff_member_id, v_section, p_work_date, 'C/I');
end;
$$;

create function public.withdraw_call_in(p_staff_member_id uuid, p_work_date date)
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
    raise exception 'There is no Call-in to withdraw';
  end if;
  if not public.can_record_call_in(v_section) then
    raise exception 'You must be working when you withdraw a Call-in';
  end if;
  select * into v_change from public.schedule_changes change
  where change.staff_member_id = p_staff_member_id and change.work_date = p_work_date
  order by change.changed_at desc, change.id desc limit 1;
  if not found or v_change.new_shift_code <> 'C/I'
    or not public.is_working_shift(v_change.old_shift_code) then
    raise exception 'There is no recorded Call-in to withdraw';
  end if;

  -- Lock linked shifts before deciding; a concurrent pickup locks the same
  -- row before it can stamp filled_at. All actions below are one transaction.
  perform 1 from public.short_shifts short
  where short.call_in_change_id = v_change.id order by short.id for update;
  if exists (select 1 from public.short_shifts short
    where short.call_in_change_id = v_change.id and short.filled_at is not null) then
    raise exception 'A Call-in is settled once an Open shift is filled';
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

revoke all on function public.record_call_in(uuid, date),
  public.withdraw_call_in(uuid, date) from public;
grant execute on function public.record_call_in(uuid, date),
  public.withdraw_call_in(uuid, date) to authenticated;
