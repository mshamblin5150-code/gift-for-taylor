-- Give every Manager-handover and Invite-acceptance refusal worded by the app
-- a stable SQLSTATE. Page wording remains in the client.
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
    raise exception using errcode = 'P2797',
      message = 'Only the Manager can transfer the Manager role';
  end if;
  select id into v_old_manager_id from public.staff_members
    where role = 'manager' and active for update;
  if not found then
    raise exception using errcode = 'P2798',
      message = 'Manager transfer cannot continue: no active Manager';
  end if;
  if p_new_manager_id = v_old_manager_id then
    raise exception using errcode = 'P2799',
      message = 'Choose another Staff member as Manager';
  end if;
  if exists (select 1 from unnest(coalesce(p_former_section_ids, '{}'::uuid[]))
      as requested(section_id) where not exists
      (select 1 from public.sections where id = requested.section_id)) then
    raise exception using errcode = 'P2800', message = 'Section not found';
  end if;
  select member.role into v_new_role
    from public.staff_members member
    where member.id = p_new_manager_id
    for update;
  v_eligibility := private.manager_handover_eligibility(p_new_manager_id);
  if v_eligibility is not null then
    case v_eligibility
      when 'no_staff_account' then
        raise exception using errcode = 'P2801',
          message = 'Manager successor is not eligible: no_staff_account';
      when 'invite_acceptance_pending' then
        raise exception using errcode = 'P2802',
          message = 'Manager successor is not eligible: invite_acceptance_pending';
      when 'account_revoked' then
        raise exception using errcode = 'P2803',
          message = 'Manager successor is not eligible: account_revoked';
      when 'inactive' then
        raise exception using errcode = 'P2804',
          message = 'Manager successor is not eligible: inactive';
      when 'already_manager' then
        raise exception using errcode = 'P2805',
          message = 'Manager successor is not eligible: already_manager';
      when 'no_current_section' then
        raise exception using errcode = 'P2806',
          message = 'Manager successor is not eligible: no_current_section';
    end case;
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

create or replace function public.accept_invite(p_token text, p_cell_number text)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare
  v_invite public.invites%rowtype;
  v_email text;
  v_cell text;
begin
  if auth.uid() is null then
    raise exception 'Sign in before accepting an Invite';
  end if;
  select invite.* into v_invite from public.invites invite
  where invite.token_hash = extensions.digest(convert_to(p_token, 'UTF8'), 'sha256')
    and invite.accepted_at is null and invite.revoked_at is null
    and invite.expires_at > now()
  for update;
  if not found then
    raise exception using errcode = 'P2794',
      message = 'This Invite is invalid, expired, or has already been used';
  end if;
  begin
    v_cell := public.normalize_cell_number(p_cell_number);
  exception when others then
    v_cell := null;
  end;
  if v_cell is distinct from (
    select member.cell_number from public.staff_members member
    where member.id = v_invite.staff_member_id and member.active
  ) or v_cell is null then
    if (select count(*) from public.invite_cell_mismatches mismatch
        where mismatch.invite_id = v_invite.id
          and mismatch.attempted_at > now() - interval '10 minutes') >= 3 then
      return 'throttled';
    end if;
    insert into public.invite_cell_mismatches (invite_id, staff_member_id)
    values (v_invite.id, v_invite.staff_member_id);
    return 'cell_mismatch';
  end if;
  if exists (select 1 from public.pending_invite_acceptances pending
      where pending.staff_member_id = v_invite.staff_member_id) then
    raise exception using errcode = 'P2807',
      message = 'This Staff member already has an Invite awaiting confirmation';
  end if;
  if exists (select 1 from public.staff_accounts account
      where account.staff_member_id = v_invite.staff_member_id
        and account.revoked_at is null) then
    raise exception using errcode = 'P2808',
      message = 'This Staff member has already accepted an Invite';
  end if;
  if exists (select 1 from public.staff_accounts account
      where account.auth_user_id = auth.uid()
        and account.staff_member_id <> v_invite.staff_member_id) then
    raise exception using errcode = 'P2793',
      message = 'This email is already signed in as another Staff member.';
  end if;
  if exists (select 1 from public.pending_invite_acceptances pending
      where pending.auth_user_id = auth.uid()) then
    raise exception using errcode = 'P2809',
      message = 'This email already has an Invite awaiting confirmation';
  end if;
  select email into v_email from auth.users where id = auth.uid();
  if v_email is null then
    raise exception using errcode = 'P2810',
      message = 'The signed-in account does not have an email address';
  end if;
  insert into public.pending_invite_acceptances
    (invite_id, staff_member_id, auth_user_id, personal_email)
  values (v_invite.id, v_invite.staff_member_id, auth.uid(), v_email);
  update public.invites set accepted_at = now() where id = v_invite.id;
  return 'accepted';
end;
$$;
