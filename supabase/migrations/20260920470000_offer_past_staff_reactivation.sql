-- The Manager must explicitly decline a past Cell-number match before using
-- that number for a new person. Keep the three-argument RPC as the safe path
-- for existing callers; the four-argument RPC records that explicit choice.
create function public.create_staff_member_with_invite(
  p_display_name text, p_cell_number text, p_section_id uuid,
  p_allow_recycled_cell boolean
)
returns table (staff_member_id uuid, cell_number text, token text)
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_staff_member_id uuid;
  v_display_order integer;
  v_token text;
  v_cell_number text;
begin
  if not public.can_manage_staff() then
    raise exception 'Only the Manager or administrator can manage the Staff list';
  end if;
  if nullif(trim(p_display_name), '') is null then
    raise exception 'Name and cell number are required';
  end if;
  if nullif(trim(p_cell_number), '') is null then
    raise exception 'Add a cell number before sending an Invite';
  end if;
  if not exists (select 1 from public.sections where id = p_section_id) then
    raise exception 'Section not found';
  end if;
  v_cell_number := public.normalize_cell_number(p_cell_number);
  perform pg_advisory_xact_lock(hashtext(v_cell_number));
  if not coalesce(p_allow_recycled_cell, false) and exists (
    select 1 from public.staff_members member
    where member.cell_number = v_cell_number and not member.active
  ) then
    raise exception 'A past Staff member has this cell number. Offer reactivation first.';
  end if;

  perform pg_advisory_xact_lock(hashtext(p_section_id::text));
  select coalesce(max(assignment.display_order) + 1, 0)
  into v_display_order
  from public.staff_section_assignments assignment
  where assignment.section_id = p_section_id
    and assignment.effective_through is null;

  insert into public.staff_members (display_name, cell_number)
  values (trim(p_display_name), v_cell_number)
  returning id, public.staff_members.cell_number into v_staff_member_id, v_cell_number;

  insert into public.staff_section_assignments (
    staff_member_id, section_id, display_order, effective_from
  ) values (v_staff_member_id, p_section_id, v_display_order, current_date);

  v_token := public.issue_staff_invite(v_staff_member_id);
  return query select v_staff_member_id, v_cell_number, v_token;
end;
$$;

revoke all on function public.create_staff_member_with_invite(text, text, uuid, boolean)
from public;
grant execute on function public.create_staff_member_with_invite(text, text, uuid, boolean)
to authenticated;

create or replace function public.create_staff_member_with_invite(
  p_display_name text, p_cell_number text, p_section_id uuid
)
returns table (staff_member_id uuid, cell_number text, token text)
language sql volatile security definer set search_path = '' as $$
  select * from public.create_staff_member_with_invite(
    p_display_name, p_cell_number, p_section_id, false
  );
$$;

-- A duplicate auth account may still arise through an import or another
-- path. Never expose the staff_accounts unique-index error to an invitee.
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

  select invite.* into v_invite
  from public.invites invite
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
  -- Preserve the mismatch record and backoff from #135. A correct retry is
  -- always allowed, even during the backoff.
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

  select auth_user.email into v_email
  from auth.users auth_user where auth_user.id = auth.uid();
  if v_email is null then
    raise exception 'The signed-in account does not have an email address';
  end if;

  begin
    -- A returning Staff member's revoked link is replaced by the new one.
    insert into public.staff_accounts (
      staff_member_id, auth_user_id, personal_email, accepted_invite_at
    ) values (v_invite.staff_member_id, auth.uid(), v_email, now())
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

  update public.invites set accepted_at = now() where id = v_invite.id;
  return 'accepted';
end;
$$;
