-- The announce sheet needs to know which affected Staff members already have
-- a live notification subscription. Keep that contact detail scheduler-only.
drop function public.schedule_rows(date);

create function public.schedule_rows(p_month_start date)
returns table (staff_member_id uuid, display_name text, section_id uuid,
  cell_number text, last_day date, has_push_subscription boolean)
language sql stable security definer set search_path = ''
as $$
  with bounds as (
    select date_trunc('month', p_month_start)::date as month_start,
      (date_trunc('month', p_month_start) + interval '1 month - 1 day')::date as month_end
  ), held as (
    select distinct on (assignment.staff_member_id) assignment.staff_member_id,
      assignment.section_id, assignment.display_order, assignment.effective_through
    from public.staff_section_assignments assignment cross join bounds
    where assignment.effective_from <= bounds.month_end
      and (assignment.effective_through is null
        or assignment.effective_through >= bounds.month_start)
    order by assignment.staff_member_id, assignment.effective_from desc
  )
  select member.id, member.display_name, held.section_id,
    case when public.can_manage_staff() and member.active then member.cell_number end,
    held.effective_through,
    case when public.can_edit_section(held.section_id) then exists (
      select 1 from public.push_subscriptions subscription
      where subscription.staff_member_id = member.id
    ) else false end
  from held
  join public.staff_members member on member.id = held.staff_member_id
  join public.sections section on section.id = held.section_id
  cross join bounds
  where public.is_active_staff_member()
    and (public.current_staff_role() <> 'staff_member' or exists (
      select 1 from public.schedule_months month
      where month.month_start = bounds.month_start and month.release_state = 'released'
    ))
    and (member.active or exists (
      select 1 from public.schedule_cells cell
      where cell.staff_member_id = member.id
        and cell.work_date between bounds.month_start and bounds.month_end
    ))
  order by section.display_order, held.display_order, member.display_name
$$;

revoke all on function public.schedule_rows(date) from public;
grant execute on function public.schedule_rows(date) to authenticated;
