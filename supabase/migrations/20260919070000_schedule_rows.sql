-- The Staff list rows on one month's Schedule, in Section and row order. Each
-- person appears once, in the last Section they held during that month, so the
-- printed page matches a move. A deactivated person appears only in a month
-- where they still have cells. Reads go through row-level security.
create function public.schedule_rows(p_month_start date)
returns table (staff_member_id uuid, display_name text, section_id uuid)
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
  select member.id, member.display_name, held.section_id
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
