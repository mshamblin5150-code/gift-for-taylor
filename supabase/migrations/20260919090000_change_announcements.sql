-- The scheduler texts the affected Staff members from their own phone, then
-- marks exactly the changes those texts covered announced. Changes saved after
-- the tray was read stay unannounced, so nothing is marked that wasn't sent.
-- A Night scheduler announces changes only in the Sections they may edit.
create function public.mark_changes_announced(p_change_ids uuid[])
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.editable_section_ids()) then
    raise exception 'Only a scheduler can announce changes';
  end if;

  update public.schedule_changes change
  set announced_at = now()
  where change.id = any(coalesce(p_change_ids, '{}'))
    and change.announced_at is null
    and public.can_edit_section(change.section_id);
end;
$$;

revoke all on function public.mark_changes_announced(uuid[]) from public;
grant execute on function public.mark_changes_announced(uuid[]) to authenticated;

-- Schedule rows now carry each active person's cell number, where their Change
-- announcements are texted. The body is unchanged apart from that column.
drop function public.schedule_rows(date);

create function public.schedule_rows(p_month_start date)
returns table (
  staff_member_id uuid,
  display_name text,
  section_id uuid,
  cell_number text
)
language sql
stable
security invoker
set search_path = ''
as $$
  with bounds as (
    select
      date_trunc('month', p_month_start)::date as month_start,
      (date_trunc('month', p_month_start) + interval '1 month - 1 day')::date
        as month_end
  ),
  held as (
    select distinct on (assignment.staff_member_id)
      assignment.staff_member_id,
      assignment.section_id,
      assignment.display_order
    from public.staff_section_assignments assignment
    cross join bounds
    where assignment.effective_from <= bounds.month_end
      and (
        assignment.effective_through is null
        or assignment.effective_through >= bounds.month_start
      )
    order by assignment.staff_member_id, assignment.effective_from desc
  )
  select
    member.id,
    member.display_name,
    held.section_id,
    case when member.active then member.cell_number end
  from held
  join public.staff_members member on member.id = held.staff_member_id
  join public.sections section on section.id = held.section_id
  cross join bounds
  where member.active
    or exists (
      select 1
      from public.schedule_cells cell
      where cell.staff_member_id = member.id
        and cell.work_date between bounds.month_start and bounds.month_end
    )
  order by section.display_order, held.display_order, member.display_name
$$;

revoke all on function public.schedule_rows(date) from public;
grant execute on function public.schedule_rows(date) to authenticated;
