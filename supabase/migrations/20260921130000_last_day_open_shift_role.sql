-- Last-day Open shifts retain the departing person's Job role on their Last day.
-- Owner-backed shifts may carry a stamped role; ownerless shifts still require one.
alter table public.short_shifts drop constraint short_shifts_manual_role_check;
alter table public.short_shifts add constraint short_shifts_manual_role_check
  check (
    (reason in ('manual', 'call_in', 'sick_leave', 'rule_change')
      and staff_member_id is null and job_role is not null)
    or (reason = 'last_day' and staff_member_id is not null)
    or (reason = 'request_off' and staff_member_id is not null
      and job_role is null)
  );

-- Existing unfilled shifts need the same stable role as newly opened shifts.
update public.short_shifts short
set job_role = (
  select role.job_role from public.staff_job_roles role
  join public.staff_members member on member.id = role.staff_member_id
  where role.staff_member_id = short.staff_member_id
    and role.effective_from <= member.last_day
    and (role.effective_through is null or role.effective_through >= member.last_day)
  order by role.effective_from desc limit 1
)
where short.reason = 'last_day' and short.filled_at is null and short.job_role is null;
create or replace function public.set_staff_last_day(
  p_staff_member_id uuid,
  p_last_day date
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_cell record;
  v_job_role public.job_role;
begin
  if not public.can_manage_staff() then
    raise exception 'Only the Manager or administrator can manage the Staff list';
  end if;
  if p_last_day is null then
    raise exception 'A Last day is required';
  end if;
  if p_staff_member_id = public.current_staff_member_id() then
    raise exception 'You can''t set your own Last day';
  end if;

  update public.staff_members
  set active = false,
      last_day = p_last_day
  where id = p_staff_member_id
    and active;
  if not found then
    raise exception 'That person is not on the Staff list';
  end if;

  select role.job_role into v_job_role
  from public.staff_job_roles role
  where role.staff_member_id = p_staff_member_id
    and role.effective_from <= p_last_day
    and (role.effective_through is null or role.effective_through >= p_last_day)
  order by role.effective_from desc limit 1;

  -- Placements planned to start after the Last day never happened, so they
  -- are plans to drop rather than history to keep.
  delete from public.staff_section_assignments
  where staff_member_id = p_staff_member_id
    and effective_from > p_last_day;
  update public.staff_section_assignments
  set effective_through = p_last_day
  where staff_member_id = p_staff_member_id
    and (effective_through is null or effective_through > p_last_day);

  delete from public.staff_job_roles
  where staff_member_id = p_staff_member_id
    and effective_from > p_last_day;
  update public.staff_job_roles
  set effective_through = p_last_day
  where staff_member_id = p_staff_member_id
    and (effective_through is null or effective_through > p_last_day);

  -- A departing Night scheduler loses the role, as remove_night_scheduler
  -- does.
  update public.staff_members
  set role = 'staff_member'
  where id = p_staff_member_id
    and role = 'night_scheduler';
  delete from public.night_scheduler_sections
  where staff_member_id = p_staff_member_id;

  -- Sign-in stops at once; an unused Invite can no longer be accepted.
  update public.staff_accounts
  set revoked_at = now()
  where staff_member_id = p_staff_member_id
    and revoked_at is null;
  update public.invites
  set revoked_at = now()
  where staff_member_id = p_staff_member_id
    and accepted_at is null
    and revoked_at is null;

  for v_cell in
    select cell.id, cell.schedule_month_id, cell.section_id, cell.work_date, cell.shift_code
    from public.schedule_cells cell
    where cell.staff_member_id = p_staff_member_id
      and cell.work_date > p_last_day
      and cell.shift_code <> ''
    order by cell.work_date
    for update
  loop
    update public.schedule_cells
    set shift_code = '',
        updated_at = now()
    where id = v_cell.id;

    insert into public.schedule_changes (
      schedule_month_id,
      staff_member_id,
      section_id,
      work_date,
      old_shift_code,
      new_shift_code,
      changed_by_staff_member_id
    ) values (
      v_cell.schedule_month_id,
      p_staff_member_id,
      v_cell.section_id,
      v_cell.work_date,
      v_cell.shift_code,
      '',
      public.current_staff_member_id()
    );

    if public.is_working_shift(v_cell.shift_code) then
      if v_job_role is null then
        raise exception 'That Staff member has no Job role on their Last day';
      end if;
      insert into public.short_shifts (
        schedule_month_id,
        section_id,
        work_date,
        shift_code,
        staff_member_id,
        job_role,
        reason
      ) values (
        v_cell.schedule_month_id,
        v_cell.section_id,
        v_cell.work_date,
        v_cell.shift_code,
        p_staff_member_id,
        v_job_role,
        'last_day'
      );
    end if;
  end loop;

  perform public.log_staff_change(
    p_staff_member_id, 'last_day', null, p_last_day::text, p_last_day
  );
end;
$$;
