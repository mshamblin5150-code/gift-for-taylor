-- Page-worded refusals for deleting a Section or Shift code in use.
create or replace function public.delete_empty_section(p_section_id uuid)
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
  -- Historical assignments preserve the meaning of older Schedules.
  if exists (
    select 1 from public.staff_section_assignments where section_id = p_section_id
  ) then
    raise exception using errcode = 'P2795',
      message = 'A Section with Staff members cannot be deleted';
  end if;
  delete from public.sections where id = p_section_id;
  if not found then
    raise exception 'Section not found';
  end if;
exception when foreign_key_violation then
  raise exception using errcode = 'P2795',
    message = 'A Section with Schedule history cannot be deleted';
end;
$$;

create or replace function public.delete_shift_code(p_code text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if public.current_staff_role() <> 'manager' then
    raise exception 'Only the Manager can delete Shift codes';
  end if;
  if public.shift_code_in_use(p_code) then
    raise exception using errcode = 'P2796',
      message = 'A Shift code in use cannot be deleted';
  end if;
  delete from public.shift_codes where code = p_code;
end;
$$;
