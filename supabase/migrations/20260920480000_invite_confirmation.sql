-- An Invite acceptance is a proposal until the Manager confirms the person.
-- No staff account exists while it is pending, so every existing access policy
-- and account-triggered calendar delivery remains behind confirmation.
create table public.pending_invite_acceptances (
  invite_id uuid primary key references public.invites(id) on delete cascade,
  staff_member_id uuid not null unique references public.staff_members(id),
  auth_user_id uuid not null unique references auth.users(id) on delete cascade,
  personal_email text not null,
  accepted_at timestamptz not null default now()
);

alter table public.pending_invite_acceptances enable row level security;
grant select on public.pending_invite_acceptances to authenticated;
create policy "Manager reads pending Invite acceptances"
on public.pending_invite_acceptances for select
using (public.current_staff_role() = 'manager');

create or replace function public.issue_staff_invite(p_staff_member_id uuid)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare
  v_token text := encode(extensions.gen_random_bytes(32), 'hex');
begin
  if exists (select 1 from public.pending_invite_acceptances
      where staff_member_id = p_staff_member_id) then
    raise exception 'This Staff member has an Invite awaiting confirmation';
  end if;
  insert into public.invites (staff_member_id, token_hash)
  values (p_staff_member_id,
    extensions.digest(convert_to(v_token, 'UTF8'), 'sha256'));
  return v_token;
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
    raise exception 'This email is already signed in as another Staff member.';
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

create function public.confirm_invite_acceptance(p_invite_id uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  v_pending public.pending_invite_acceptances%rowtype;
begin
  if public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the Manager can confirm an Invite';
  end if;
  select * into v_pending from public.pending_invite_acceptances
  where invite_id = p_invite_id for update;
  if not found then raise exception 'Invite acceptance is no longer pending'; end if;
  if not exists (select 1 from public.staff_members
      where id = v_pending.staff_member_id and active) then
    raise exception 'Staff member is no longer active';
  end if;
  begin
    insert into public.staff_accounts
      (staff_member_id, auth_user_id, personal_email, accepted_invite_at)
    values (v_pending.staff_member_id, v_pending.auth_user_id,
      v_pending.personal_email, v_pending.accepted_at)
    on conflict (staff_member_id) do update
    set auth_user_id = excluded.auth_user_id,
        personal_email = excluded.personal_email,
        accepted_invite_at = excluded.accepted_invite_at,
        revoked_at = null
    where public.staff_accounts.revoked_at is not null;
  exception when unique_violation then
    raise exception 'This email is already signed in as another Staff member.';
  end;
  if not found then
    raise exception 'This Staff member has already accepted an Invite';
  end if;
  delete from public.pending_invite_acceptances where invite_id = p_invite_id;
end;
$$;

create function public.reject_invite_acceptance(p_invite_id uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  v_pending public.pending_invite_acceptances%rowtype;
begin
  if public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the Manager can reject an Invite';
  end if;
  select * into v_pending from public.pending_invite_acceptances
  where invite_id = p_invite_id for update;
  if not found then raise exception 'Invite acceptance is no longer pending'; end if;
  -- Keep the consumed link unusable. Resend issues a fresh one after correction.
  delete from public.pending_invite_acceptances where invite_id = p_invite_id;
end;
$$;

revoke all on function public.confirm_invite_acceptance(uuid) from public;
revoke all on function public.reject_invite_acceptance(uuid) from public;
grant execute on function public.confirm_invite_acceptance(uuid) to authenticated;
grant execute on function public.reject_invite_acceptance(uuid) to authenticated;

create function public.my_invite_acceptance_pending()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.pending_invite_acceptances
    where auth_user_id = auth.uid())
$$;
revoke all on function public.my_invite_acceptance_pending() from public;
grant execute on function public.my_invite_acceptance_pending() to authenticated;
