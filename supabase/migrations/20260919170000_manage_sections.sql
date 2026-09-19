-- Section management is a Manager action, not a general Staff-list edit.
create function public.can_manage_sections()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.current_staff_role() = 'manager'
$$;

revoke all on function public.can_manage_sections() from public;
grant execute on function public.can_manage_sections() to authenticated;

create function public.add_section(p_name text)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not public.can_manage_sections() then
    raise exception 'Only the Manager can manage Sections';
  end if;
  if length(trim(coalesce(p_name, ''))) = 0 then
    raise exception 'Section name is required';
  end if;

  perform pg_advisory_xact_lock(hashtext('public.sections.order'));
  insert into public.sections (name, display_order)
  select trim(p_name), coalesce(max(display_order) + 1, 0)
  from public.sections
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.add_section(text) from public;
grant execute on function public.add_section(text) to authenticated;

create function public.rename_section(p_section_id uuid, p_name text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not public.can_manage_sections() then
    raise exception 'Only the Manager can manage Sections';
  end if;
  if length(trim(coalesce(p_name, ''))) = 0 then
    raise exception 'Section name is required';
  end if;
  update public.sections set name = trim(p_name) where id = p_section_id;
  if not found then
    raise exception 'Section not found';
  end if;
end;
$$;

revoke all on function public.rename_section(uuid, text) from public;
grant execute on function public.rename_section(uuid, text) to authenticated;

create function public.reorder_sections(p_section_ids uuid[])
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not public.can_manage_sections() then
    raise exception 'Only the Manager can manage Sections';
  end if;
  perform pg_advisory_xact_lock(hashtext('public.sections.order'));
  select count(*) into v_count from public.sections;
  if cardinality(p_section_ids) is distinct from v_count
    or (select count(distinct id) from unnest(p_section_ids) as requested(id)) <> v_count
    or exists (
      select 1 from unnest(p_section_ids) as requested(id)
      where not exists (select 1 from public.sections where id = requested.id)
    )
  then
    raise exception 'The reorder must include every Section exactly once';
  end if;

  update public.sections section
  set display_order = requested.position - 1
  from unnest(p_section_ids) with ordinality as requested(id, position)
  where section.id = requested.id;
end;
$$;

revoke all on function public.reorder_sections(uuid[]) from public;
grant execute on function public.reorder_sections(uuid[]) to authenticated;

create function public.delete_empty_section(p_section_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not public.can_manage_sections() then
    raise exception 'Only the Manager can manage Sections';
  end if;
  -- Historical assignments count too: deleting their Section would erase
  -- the meaning of an older Schedule even after its Staff members move on.
  if exists (
    select 1 from public.staff_section_assignments where section_id = p_section_id
  ) then
    raise exception 'A Section with Staff members cannot be deleted';
  end if;
  delete from public.sections where id = p_section_id;
  if not found then
    raise exception 'Section not found';
  end if;
  -- Other historical references (cells, short shifts, etc.) remain protected
  -- by their foreign keys even if there was never an assignment.
end;
$$;

revoke all on function public.delete_empty_section(uuid) from public;
grant execute on function public.delete_empty_section(uuid) to authenticated;
