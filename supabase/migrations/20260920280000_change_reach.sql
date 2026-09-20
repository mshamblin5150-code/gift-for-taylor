-- Reach describes the evidence available when a Change announcement is made.
-- Moot changes are terminal without causing the announced_at notice trigger.
alter table public.schedule_changes
  add column moot_at timestamptz,
  add column reach text check (reach in ('notified', 'draft_opened', 'nobody')),
  add constraint schedule_changes_one_outcome
    check (announced_at is null or moot_at is null),
  add constraint schedule_changes_reach_only_when_announced
    check (reach is null or announced_at is not null);

drop function public.mark_changes_announced(uuid[]);

-- IDs bound the tray snapshot being settled. The database alone decides which
-- of its cells still differ from the earliest pending baseline and who held a
-- push subscription when the button was tapped.
create function public.mark_changes_announced(
  p_change_ids uuid[],
  p_draft_opened_staff_member_ids uuid[]
)
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

  with selected as (
    select change.id, change.schedule_month_id, change.staff_member_id,
      change.work_date
    from public.schedule_changes change
    where change.id = any(coalesce(p_change_ids, '{}'::uuid[]))
      and change.announced_at is null and change.moot_at is null
      and public.can_edit_section(change.section_id)
      and not exists (
        select 1 from public.schedule_changes newer
        where newer.schedule_month_id = change.schedule_month_id
          and newer.staff_member_id = change.staff_member_id
          and newer.work_date = change.work_date
          and newer.announced_at is null and newer.moot_at is null
          and newer.id <> all(coalesce(p_change_ids, '{}'::uuid[]))
      )
  ),
  baseline as (
    select distinct on (pending.schedule_month_id, pending.staff_member_id,
                        pending.work_date)
      pending.schedule_month_id, pending.staff_member_id, pending.work_date,
      pending.old_shift_code
    from public.schedule_changes pending
    join selected on selected.schedule_month_id = pending.schedule_month_id
      and selected.staff_member_id = pending.staff_member_id
      and selected.work_date = pending.work_date
    where pending.announced_at is null and pending.moot_at is null
    order by pending.schedule_month_id, pending.staff_member_id,
      pending.work_date, pending.changed_at, pending.id
  ),
  outcome as (
    select selected.id, selected.staff_member_id,
      coalesce(cell.shift_code, '') is distinct from baseline.old_shift_code
        as moved
    from selected
    join baseline on baseline.schedule_month_id = selected.schedule_month_id
      and baseline.staff_member_id = selected.staff_member_id
      and baseline.work_date = selected.work_date
    left join public.schedule_cells cell
      on cell.schedule_month_id = selected.schedule_month_id
      and cell.staff_member_id = selected.staff_member_id
      and cell.work_date = selected.work_date
  )
  update public.schedule_changes change
  set announced_at = case when outcome.moved then now() end,
      moot_at = case when outcome.moved then null else now() end,
      reach = case
        when not outcome.moved then null
        when exists (
          select 1 from public.push_subscriptions subscription
          where subscription.staff_member_id = outcome.staff_member_id
        ) then 'notified'
        when outcome.staff_member_id = any(
          coalesce(p_draft_opened_staff_member_ids, '{}'::uuid[])
        ) then 'draft_opened'
        else 'nobody'
      end
  from outcome
  where change.id = outcome.id;
end;
$$;

revoke all on function public.mark_changes_announced(uuid[], uuid[]) from public;
grant execute on function public.mark_changes_announced(uuid[], uuid[])
  to authenticated;
