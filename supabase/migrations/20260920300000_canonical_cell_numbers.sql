-- Match the client's loose input rule, then store only E.164. A blank is
-- incomplete Staff data (not a valid number) and remains nullable for imports.
create function public.normalize_cell_number(p_value text)
returns text language plpgsql immutable strict set search_path = '' as $$
declare
  v_value text := btrim(p_value);
  v_digits text := regexp_replace(p_value, '[^0-9]', '', 'g');
begin
  if length(v_digits) in (7, 10) then return '+1' || v_digits; end if;
  if length(v_digits) in (8, 11) and left(v_digits, 1) = '1' then
    return '+' || v_digits;
  end if;
  if left(v_value, 1) = '+' and length(v_digits) between 7 and 15
    and left(v_digits, 1) <> '0' then
    return '+' || v_digits;
  end if;
  raise exception 'Enter a cell number with its area code.';
end;
$$;

-- Legacy junk is cleared, not guessed: these people need a Cell number added
-- before an Invite can be used. Warn with the row ID for follow-up. If two
-- active rows collapse to the same number, keep the first UUID and mark the
-- later one incomplete rather than arbitrarily choosing an identity for it.
do $$
declare
  v_row record;
  v_cell text;
begin
  for v_row in select id, cell_number, active from public.staff_members
    where cell_number is not null order by id
  loop
    begin
      v_cell := public.normalize_cell_number(v_row.cell_number);
    exception when raise_exception then
      raise warning 'Staff member % has an unrecognizable Cell number; cleared for correction', v_row.id;
      v_cell := null;
    end;
    if v_cell is not null and v_row.active and exists (
      select 1 from public.staff_members other
      where other.id <> v_row.id and other.id < v_row.id
        and other.active and other.cell_number = v_cell
    ) then
      raise warning 'Staff member % has a duplicate active Cell number; cleared for correction', v_row.id;
      v_cell := null;
    end if;
    update public.staff_members set cell_number = v_cell where id = v_row.id;
  end loop;
end;
$$;

alter table public.staff_members add constraint staff_members_cell_number_e164
  check (cell_number is null or cell_number ~ '^\+[1-9][0-9]{6,14}$');
create unique index staff_members_active_cell_number_unique
  on public.staff_members (cell_number)
  where active and cell_number is not null;

-- This single boundary covers Add Staff, contact edits, first-month imports,
-- and direct maintenance writes. Lock by number before the friendly duplicate
-- check, so concurrent inserts cannot leak a raw unique-index error.
create function public.canonicalize_staff_cell_number()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.cell_number is not null and btrim(new.cell_number) <> '' then
    new.cell_number := public.normalize_cell_number(new.cell_number);
  else
    new.cell_number := null;
  end if;
  if new.active and new.cell_number is not null then
    perform pg_advisory_xact_lock(hashtext(new.cell_number));
    if exists (select 1 from public.staff_members member
      where member.cell_number = new.cell_number and member.active
        and member.id <> new.id) then
      raise exception 'An active Staff member already has this cell number';
    end if;
  end if;
  return new;
end;
$$;
create trigger canonicalize_staff_cell_number
before insert or update of cell_number, active on public.staff_members
for each row execute function public.canonicalize_staff_cell_number();

-- Add Staff returns the stored representation to its SMS caller too.
create or replace function public.create_staff_member_with_invite(
  p_display_name text, p_cell_number text, p_section_id uuid
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
  if length(trim(p_display_name)) = 0 or length(trim(p_cell_number)) = 0 then
    raise exception 'Name and cell number are required';
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
  ) values (v_staff_member_id, p_section_id, v_display_order, current_date);

  v_token := public.issue_staff_invite(v_staff_member_id);
  return query select v_staff_member_id, v_cell_number, v_token;
end;
$$;

-- Normalize before logging so the change history describes the stored value.
create or replace function public.update_staff_contact(p_staff_member_id uuid,
  p_display_name text, p_cell_number text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_old public.staff_members%rowtype;
  v_name text := nullif(trim(p_display_name), '');
  v_cell text := nullif(trim(p_cell_number), '');
begin
  if not public.can_manage_staff() then
    raise exception 'Only the Manager or administrator can manage the Staff list';
  end if;
  if v_name is null then raise exception 'Name is required'; end if;
  select * into v_old from public.staff_members member
  where member.id = p_staff_member_id for update;
  if not found then raise exception 'That person is not on the Staff list'; end if;
  if v_cell is not null then v_cell := public.normalize_cell_number(v_cell); end if;
  update public.staff_members set display_name = v_name, cell_number = v_cell
  where id = p_staff_member_id;
  if v_old.display_name is distinct from v_name then
    perform public.log_staff_change(p_staff_member_id, 'name',
      v_old.display_name, v_name, current_date);
  end if;
  if v_old.cell_number is distinct from v_cell then
    perform public.log_staff_change(p_staff_member_id, 'cell_number',
      v_old.cell_number, v_cell, current_date);
  end if;
end;
$$;
