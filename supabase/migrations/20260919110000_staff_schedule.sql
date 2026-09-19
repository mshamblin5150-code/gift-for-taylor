-- Staff members can see their own changes after a month is released, so
-- their changed shifts can be highlighted without exposing the scheduler log.
grant execute on function public.current_staff_member_id() to authenticated;

create policy "staff can read their changes in released months"
on public.schedule_changes for select
using (
  public.current_staff_role() = 'staff_member'
  and staff_member_id = public.current_staff_member_id()
  and exists (
    select 1
    from public.schedule_months month
    where month.id = schedule_month_id
      and month.release_state = 'released'
      and changed_at > month.released_at
  )
);
