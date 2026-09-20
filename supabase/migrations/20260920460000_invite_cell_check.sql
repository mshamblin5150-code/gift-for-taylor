-- Keep failed checks outside the Invite row so resending does not erase the
-- Manager's evidence. The typed number itself is never stored.
create table public.invite_cell_mismatches (
  id uuid primary key default gen_random_uuid(),
  invite_id uuid not null references public.invites(id),
  staff_member_id uuid not null references public.staff_members(id),
  attempted_at timestamptz not null default now()
);
create index invite_cell_mismatches_recent
  on public.invite_cell_mismatches (invite_id, attempted_at desc);
create index invite_cell_mismatches_by_staff
  on public.invite_cell_mismatches (staff_member_id, attempted_at desc);
alter table public.invite_cell_mismatches enable row level security;
create policy "managers can read Invite Cell mismatches"
  on public.invite_cell_mismatches for select
  using (public.can_manage_staff());
grant select on public.invite_cell_mismatches to authenticated;

-- A mismatch returns a status instead of raising: PostgreSQL would roll back
-- its failed-attempt record if the RPC raised an exception.
drop function public.accept_invite(text);
create function public.accept_invite(p_token text, p_cell_number text)
returns text
language plpgsql volatile security definer set search_path = '' as $$
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

  -- A legitimate person can always recover, even after someone else caused
  -- the short backoff. Only incorrect attempts are throttled.
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

  select auth_user.email into v_email from auth.users auth_user
  where auth_user.id = auth.uid();
  if v_email is null then
    raise exception 'The signed-in account does not have an email address';
  end if;

  insert into public.staff_accounts (
    staff_member_id, auth_user_id, personal_email, accepted_invite_at
  ) values (v_invite.staff_member_id, auth.uid(), v_email, now())
  on conflict (staff_member_id) do update
  set auth_user_id = excluded.auth_user_id,
      personal_email = excluded.personal_email,
      accepted_invite_at = excluded.accepted_invite_at,
      revoked_at = null
  where public.staff_accounts.revoked_at is not null;
  if not found then
    raise exception 'This Staff member has already accepted an Invite';
  end if;

  update public.invites set accepted_at = now() where id = v_invite.id;
  return 'accepted';
end;
$$;
revoke all on function public.accept_invite(text, text) from public;
grant execute on function public.accept_invite(text, text) to authenticated;

create or replace view public.staff_list_entries
with (security_invoker = false) as
select
  member.id, member.display_name,
  case when public.can_manage_staff() then member.cell_number end as cell_number,
  assignment.section_id, assignment.display_order,
  case when public.can_manage_staff() then account.personal_email end as personal_email,
  assignment.effective_from as section_from, job_role.job_role,
  case when public.can_manage_staff() then (
    select max(mismatch.attempted_at)
    from public.invite_cell_mismatches mismatch
    where mismatch.staff_member_id = member.id
  ) end as invite_cell_mismatch_at
from public.staff_members member
join public.staff_section_assignments assignment
  on assignment.staff_member_id = member.id and assignment.effective_through is null
left join public.staff_accounts account
  on account.staff_member_id = member.id and account.revoked_at is null
left join public.staff_job_roles job_role
  on job_role.staff_member_id = member.id and job_role.effective_through is null
where member.active and public.is_active_staff_member();
