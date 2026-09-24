create type public.manager_handover_eligibility_code as enum (
  'no_staff_account',
  'invite_acceptance_pending',
  'account_revoked',
  'inactive',
  'already_manager',
  'no_current_section'
);

-- One expression answers readiness everywhere. Pending acceptance deliberately
-- precedes the missing-account answer because confirmation creates the account.
create function private.manager_handover_eligibility(p_staff_member_id uuid)
returns public.manager_handover_eligibility_code
language sql stable security definer set search_path = '' as $$
  select case
    when exists (
      select 1 from public.pending_invite_acceptances pending
      where pending.staff_member_id = p_staff_member_id
    ) then 'invite_acceptance_pending'::public.manager_handover_eligibility_code
    when exists (
      select 1 from public.staff_accounts account
      where account.staff_member_id = p_staff_member_id
        and account.revoked_at is not null
    ) then 'account_revoked'::public.manager_handover_eligibility_code
    when not exists (
      select 1 from public.staff_accounts account
      where account.staff_member_id = p_staff_member_id
    ) then 'no_staff_account'::public.manager_handover_eligibility_code
    when not coalesce((
      select member.active from public.staff_members member
      where member.id = p_staff_member_id
    ), false) then 'inactive'::public.manager_handover_eligibility_code
    when exists (
      select 1 from public.staff_members member
      where member.id = p_staff_member_id and member.role = 'manager'
    ) then 'already_manager'::public.manager_handover_eligibility_code
    when not exists (
      select 1 from public.staff_section_assignments assignment
      where assignment.staff_member_id = p_staff_member_id
        and assignment.effective_through is null
    ) then 'no_current_section'::public.manager_handover_eligibility_code
  end
$$;
revoke all on function private.manager_handover_eligibility(uuid) from public;

create function public.manager_handover_candidates()
returns table (
  staff_member_id uuid,
  display_name text,
  eligibility_code public.manager_handover_eligibility_code
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.can_manage_staff() then
    raise exception 'Only the Manager or Administrator can view Manager handover readiness';
  end if;
  return query
    select member.id, member.display_name,
      private.manager_handover_eligibility(member.id)
    from public.staff_members member
    order by member.display_name, member.id;
end;
$$;
revoke all on function public.manager_handover_candidates() from public;
grant execute on function public.manager_handover_candidates() to authenticated;

-- A Staff member can exist without a live assignment after an interrupted
-- import or repair. Let the ordinary Staff-details command repair that state
-- instead of requiring a second database-only path.
create or replace function public.change_staff_section(
  p_staff_member_id uuid,
  p_section_id uuid,
  p_from date
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_current public.staff_section_assignments%rowtype;
  v_display_order integer;
  v_old_name text;
  v_new_name text;
begin
  if not public.can_manage_staff() then
    raise exception 'Only the Manager or administrator can manage the Staff list';
  end if;

  perform 1
  from public.staff_members member
  where member.id = p_staff_member_id and member.active
  for update;
  if not found then
    raise exception 'That person is not on the Staff list';
  end if;

  select section.name into v_new_name
  from public.sections section
  where section.id = p_section_id;
  if not found then
    raise exception 'Section not found';
  end if;
  if p_from is null then
    raise exception 'Choose when the Section assignment starts';
  end if;

  select assignment.* into v_current
  from public.staff_section_assignments assignment
  where assignment.staff_member_id = p_staff_member_id
    and assignment.effective_through is null
  for update;

  if v_current.id is not null then
    if v_current.section_id = p_section_id then
      raise exception 'They are already in that Section';
    end if;
    if p_from < v_current.effective_from then
      raise exception 'The move must start on or after their current Section did';
    end if;
    select section.name into v_old_name
    from public.sections section
    where section.id = v_current.section_id;
    if p_from = v_current.effective_from then
      delete from public.staff_section_assignments where id = v_current.id;
    else
      update public.staff_section_assignments
      set effective_through = p_from - 1
      where id = v_current.id;
    end if;
  end if;

  perform pg_advisory_xact_lock(hashtext(p_section_id::text));
  select coalesce(max(assignment.display_order) + 1, 0)
  into v_display_order
  from public.staff_section_assignments assignment
  where assignment.section_id = p_section_id
    and assignment.effective_through is null;

  insert into public.staff_section_assignments(
    staff_member_id, section_id, display_order, effective_from)
  values (p_staff_member_id, p_section_id, v_display_order, p_from);
  perform public.log_staff_change(
    p_staff_member_id, 'section', v_old_name, v_new_name, p_from);
end;
$$;

-- Carry forward the incumbent lookup introduced by 20260921030000 while
-- making both the picker and the transfer consume the same readiness rule.
create or replace function public.transfer_manager_with_access(
  p_new_manager_id uuid, p_former_administrator boolean,
  p_former_section_ids uuid[]
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_old_manager_id uuid;
  v_old_access text;
  v_new_role public.staff_role;
  v_new_sections uuid[];
  v_former_role public.staff_role;
  v_eligibility public.manager_handover_eligibility_code;
begin
  perform pg_advisory_xact_lock(810081);
  if public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the Manager can transfer the Manager role';
  end if;
  select id into v_old_manager_id from public.staff_members
    where role = 'manager' and active for update;
  if not found then
    raise exception 'Manager transfer cannot continue: no active Manager';
  end if;
  if p_new_manager_id = v_old_manager_id then
    raise exception 'Choose another Staff member as Manager';
  end if;
  if exists (select 1 from unnest(coalesce(p_former_section_ids, '{}'::uuid[]))
      as requested(section_id) where not exists
      (select 1 from public.sections where id = requested.section_id)) then
    raise exception 'Section not found';
  end if;
  select member.role into v_new_role
    from public.staff_members member
    where member.id = p_new_manager_id
    for update;
  v_eligibility := private.manager_handover_eligibility(p_new_manager_id);
  if v_eligibility is not null then
    raise exception 'Manager successor is not eligible: %', v_eligibility;
  end if;
  select coalesce(array_agg(section_id order by section_id), '{}'::uuid[])
    into v_new_sections from public.night_scheduler_sections
    where staff_member_id = p_new_manager_id;
  v_old_access := public.staff_access_label(v_new_role, v_new_sections);
  delete from public.night_scheduler_sections where staff_member_id = p_new_manager_id;
  update public.staff_members set role = 'manager' where id = p_new_manager_id;
  v_former_role := public.staff_role_for_grants(
    p_former_administrator, p_former_section_ids);
  update public.staff_members set role = v_former_role where id = v_old_manager_id;
  delete from public.night_scheduler_sections where staff_member_id = v_old_manager_id;
  insert into public.night_scheduler_sections(staff_member_id, section_id)
    select distinct v_old_manager_id, requested.section_id
    from unnest(coalesce(p_former_section_ids, '{}'::uuid[])) as requested(section_id);
  perform public.log_staff_change(p_new_manager_id, 'access_role',
    v_old_access, 'manager', current_date);
  perform public.log_staff_change(v_old_manager_id, 'access_role',
    'manager', public.staff_access_label(v_former_role, p_former_section_ids),
    current_date);
end;
$$;
