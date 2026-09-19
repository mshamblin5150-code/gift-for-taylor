-- The scheduler texts the affected Staff members from their own phone, then
-- marks exactly the changes those texts covered announced. Changes saved after
-- the tray was read stay unannounced, so nothing is marked that wasn't sent.
create function public.mark_changes_announced(p_change_ids uuid[])
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not public.can_edit_schedule() then
    raise exception 'Only the Manager can announce changes';
  end if;

  update public.schedule_changes
  set announced_at = now()
  where id = any(coalesce(p_change_ids, '{}'))
    and announced_at is null;
end;
$$;

revoke all on function public.mark_changes_announced(uuid[]) from public;
grant execute on function public.mark_changes_announced(uuid[]) to authenticated;
