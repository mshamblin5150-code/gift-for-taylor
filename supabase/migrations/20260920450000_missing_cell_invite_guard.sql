create or replace function public.create_staff_member_with_invite(
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
  ) values (
    v_staff_member_id, p_section_id, v_display_order, current_date
  );

  v_token := public.issue_staff_invite(v_staff_member_id);
  return query select v_staff_member_id, v_cell_number, v_token;
end;
$$;

create or replace function public.resend_staff_invite(p_staff_member_id uuid)
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
  if nullif(trim(v_cell_number), '') is null then
    raise exception 'Add a cell number before sending an Invite';
  end if;
  if exists (
    select 1
    from public.staff_accounts account
    where account.staff_member_id = p_staff_member_id
      and account.revoked_at is null
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
