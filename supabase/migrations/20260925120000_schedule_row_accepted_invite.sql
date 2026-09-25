-- Swap proposals need the same account fact that propose_swap enforces. Expose
-- only the boolean; Staff members do not need another person's account details.
drop function public.schedule_rows(date);

create function public.schedule_rows(p_month_start date)
returns table (staff_member_id uuid, display_name text, section_id uuid,
  cell_number text, last_day date, has_push_subscription boolean,
  has_accepted_invite boolean)
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
    ) else false end,
    member.active and exists (
      select 1 from public.staff_accounts account
      where account.staff_member_id = member.id
        and account.accepted_invite_at is not null
        and account.revoked_at is null
    )
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

-- Cell numbers remain Staff-list data. A requester may read only the number for
-- the colleague on a Swap they already proposed, which is enough to open the
-- text draft without widening schedule_rows for every Staff member.
create function public.swap_colleague_cell_number(p_swap_id uuid)
returns text
language sql stable security definer set search_path = ''
as $$
  select member.cell_number
  from public.swaps swap
  join public.staff_members member on member.id = swap.colleague_id
  where swap.id = p_swap_id
    and swap.requester_id = public.current_staff_member_id()
    and swap.status = 'proposed'
    and member.active
    and exists (
      select 1 from public.staff_accounts account
      where account.staff_member_id = member.id
        and account.accepted_invite_at is not null
        and account.revoked_at is null
    )
$$;

revoke all on function public.swap_colleague_cell_number(uuid) from public;
grant execute on function public.swap_colleague_cell_number(uuid) to authenticated;
