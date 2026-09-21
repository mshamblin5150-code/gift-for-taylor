-- Give the Invite refusal worded by the app a stable SQLSTATE.
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
    raise exception 'This Invite is invalid, expired, or has already been used';
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
    raise exception 'This Staff member already has an Invite awaiting confirmation';
  end if;
  if exists (select 1 from public.staff_accounts account
      where account.staff_member_id = v_invite.staff_member_id
        and account.revoked_at is null) then
    raise exception 'This Staff member has already accepted an Invite';
  end if;
  if exists (select 1 from public.staff_accounts account
      where account.auth_user_id = auth.uid()
        and account.staff_member_id <> v_invite.staff_member_id) then
    raise exception using errcode = 'P2793', message = 'This email is already signed in as another Staff member.';
  end if;
  if exists (select 1 from public.pending_invite_acceptances pending
      where pending.auth_user_id = auth.uid()) then
    raise exception 'This email already has an Invite awaiting confirmation';
  end if;
  select email into v_email from auth.users where id = auth.uid();
  if v_email is null then
    raise exception 'The signed-in account does not have an email address';
  end if;
  insert into public.pending_invite_acceptances
    (invite_id, staff_member_id, auth_user_id, personal_email)
  values (v_invite.id, v_invite.staff_member_id, auth.uid(), v_email);
  update public.invites set accepted_at = now() where id = v_invite.id;
  return 'accepted';
end;
$$;

