alter table public.staff_accounts
add column personal_email text;

update public.staff_accounts account
set personal_email = auth_user.email
from auth.users auth_user
where auth_user.id = account.auth_user_id;

alter table public.staff_accounts
alter column personal_email set not null;

create table public.staff_section_assignments (
  id uuid primary key default gen_random_uuid(),
  staff_member_id uuid not null references public.staff_members(id),
  section_id uuid not null references public.sections(id),
  display_order integer not null check (display_order >= 0),
  effective_from date not null,
  effective_through date,
  created_at timestamptz not null default now(),
  check (effective_through is null or effective_through >= effective_from)
);

create unique index one_current_section_per_staff_member
on public.staff_section_assignments (staff_member_id)
where effective_through is null;

create unique index one_current_position_per_section
on public.staff_section_assignments (section_id, display_order)
where effective_through is null;

create table public.invites (
  id uuid primary key default gen_random_uuid(),
  staff_member_id uuid not null references public.staff_members(id),
  token_hash bytea not null unique,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  accepted_at timestamptz,
  revoked_at timestamptz,
  check (expires_at > created_at),
  check (accepted_at is null or revoked_at is null)
);

create unique index one_active_invite_per_staff_member
on public.invites (staff_member_id)
where accepted_at is null and revoked_at is null;

create function public.can_manage_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.current_staff_role() in ('manager', 'administrator')
$$;

revoke all on function public.can_manage_staff() from public;
grant execute on function public.can_manage_staff() to authenticated;

alter table public.staff_section_assignments enable row level security;
alter table public.invites enable row level security;

grant select on public.staff_section_assignments to authenticated;
grant select on public.staff_accounts to authenticated;

create policy "active staff can read current Section assignments"
on public.staff_section_assignments for select
using (public.is_active_staff_member());

create policy "staff can read their own account; managers read all accounts"
on public.staff_accounts for select
using (
  auth_user_id = auth.uid()
  or public.can_manage_staff()
);

create view public.staff_list_entries
with (security_invoker = true)
as
select
  member.id,
  member.display_name,
  member.cell_number,
  assignment.section_id,
  assignment.display_order,
  account.personal_email
from public.staff_members member
join public.staff_section_assignments assignment
  on assignment.staff_member_id = member.id
  and assignment.effective_through is null
left join public.staff_accounts account
  on account.staff_member_id = member.id
where member.active;

grant select on public.staff_list_entries to authenticated;

create function public.issue_staff_invite(p_staff_member_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_token text := encode(extensions.gen_random_bytes(32), 'hex');
begin
  insert into public.invites (staff_member_id, token_hash)
  values (
    p_staff_member_id,
    extensions.digest(convert_to(v_token, 'UTF8'), 'sha256')
  );
  return v_token;
end;
$$;

revoke all on function public.issue_staff_invite(uuid) from public;

create function public.create_staff_member_with_invite(
  p_display_name text,
  p_cell_number text,
  p_section_id uuid
)
returns table (staff_member_id uuid, cell_number text, token text)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_staff_member_id uuid;
  v_display_order integer;
  v_token text;
begin
  if not public.can_manage_staff() then
    raise exception 'Only the Manager or administrator can manage the Staff list';
  end if;
  if length(trim(p_display_name)) = 0 or length(trim(p_cell_number)) = 0 then
    raise exception 'Name and cell number are required';
  end if;
  if not exists (select 1 from public.sections where id = p_section_id) then
    raise exception 'Section not found';
  end if;

  perform pg_advisory_xact_lock(hashtext(p_section_id::text));
  select coalesce(max(assignment.display_order) + 1, 0)
  into v_display_order
  from public.staff_section_assignments assignment
  where assignment.section_id = p_section_id
    and assignment.effective_through is null;

  insert into public.staff_members (display_name, cell_number)
  values (trim(p_display_name), trim(p_cell_number))
  returning id into v_staff_member_id;

  insert into public.staff_section_assignments (
    staff_member_id,
    section_id,
    display_order,
    effective_from
  ) values (
    v_staff_member_id,
    p_section_id,
    v_display_order,
    current_date
  );

  v_token := public.issue_staff_invite(v_staff_member_id);
  return query select v_staff_member_id, trim(p_cell_number), v_token;
end;
$$;

revoke all on function public.create_staff_member_with_invite(text, text, uuid) from public;
grant execute on function public.create_staff_member_with_invite(text, text, uuid)
to authenticated;

create function public.resend_staff_invite(p_staff_member_id uuid)
returns table (staff_member_id uuid, cell_number text, token text)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_cell_number text;
  v_token text;
begin
  if not public.can_manage_staff() then
    raise exception 'Only the Manager or administrator can manage the Staff list';
  end if;

  select member.cell_number
  into v_cell_number
  from public.staff_members member
  where member.id = p_staff_member_id
    and member.active;
  if not found then
    raise exception 'Staff member not found';
  end if;
  if exists (
    select 1
    from public.staff_accounts account
    where account.staff_member_id = p_staff_member_id
  ) then
    raise exception 'This Staff member has already accepted an Invite';
  end if;

  update public.invites
  set revoked_at = now()
  where invites.staff_member_id = p_staff_member_id
    and accepted_at is null
    and revoked_at is null;

  v_token := public.issue_staff_invite(p_staff_member_id);
  return query select p_staff_member_id, v_cell_number, v_token;
end;
$$;

revoke all on function public.resend_staff_invite(uuid) from public;
grant execute on function public.resend_staff_invite(uuid) to authenticated;

create function public.reorder_staff_section(
  p_section_id uuid,
  p_staff_member_ids uuid[]
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_expected_count integer;
begin
  if not public.can_manage_staff() then
    raise exception 'Only the Manager or administrator can manage the Staff list';
  end if;

  select count(*)::integer
  into v_expected_count
  from public.staff_section_assignments assignment
  where assignment.section_id = p_section_id
    and assignment.effective_through is null;

  if cardinality(p_staff_member_ids) <> v_expected_count
    or (
      select count(distinct requested_member.staff_member_id)
      from unnest(p_staff_member_ids) as requested_member(staff_member_id)
    ) <> v_expected_count
    or exists (
      select 1
      from unnest(p_staff_member_ids) as requested_member(staff_member_id)
      where not exists (
        select 1
        from public.staff_section_assignments assignment
        where assignment.staff_member_id = requested_member.staff_member_id
          and assignment.section_id = p_section_id
          and assignment.effective_through is null
      )
    )
  then
    raise exception 'The reorder must include every current Staff member in the Section once';
  end if;

  -- Offset first so the unique position index cannot collide during the update.
  update public.staff_section_assignments
  set display_order = display_order + v_expected_count
  where section_id = p_section_id
    and effective_through is null;

  update public.staff_section_assignments assignment
  set display_order = requested.display_order
  from (
    select
      ordered.staff_member_id,
      (ordered.ordinal_position - 1)::integer as display_order
    from unnest(p_staff_member_ids) with ordinality
      as ordered(staff_member_id, ordinal_position)
  ) requested
  where assignment.staff_member_id = requested.staff_member_id
    and assignment.section_id = p_section_id
    and assignment.effective_through is null;
end;
$$;

revoke all on function public.reorder_staff_section(uuid, uuid[]) from public;
grant execute on function public.reorder_staff_section(uuid, uuid[]) to authenticated;

create function public.accept_invite(p_token text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_invite public.invites%rowtype;
  v_email text;
begin
  if auth.uid() is null then
    raise exception 'Sign in before accepting an Invite';
  end if;

  select invite.*
  into v_invite
  from public.invites invite
  where invite.token_hash = extensions.digest(convert_to(p_token, 'UTF8'), 'sha256')
    and invite.accepted_at is null
    and invite.revoked_at is null
    and invite.expires_at > now()
  for update;

  if not found then
    raise exception 'This Invite is invalid, expired, or has already been used';
  end if;

  select auth_user.email
  into v_email
  from auth.users auth_user
  where auth_user.id = auth.uid();
  if v_email is null then
    raise exception 'The signed-in account does not have an email address';
  end if;

  insert into public.staff_accounts (
    staff_member_id,
    auth_user_id,
    personal_email,
    accepted_invite_at
  ) values (
    v_invite.staff_member_id,
    auth.uid(),
    v_email,
    now()
  );

  update public.invites
  set accepted_at = now()
  where id = v_invite.id;
end;
$$;

revoke all on function public.accept_invite(text) from public;
grant execute on function public.accept_invite(text) to authenticated;
