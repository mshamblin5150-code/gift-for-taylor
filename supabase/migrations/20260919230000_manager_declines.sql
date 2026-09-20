-- Manager decisions that do not change the Schedule still go through guarded RPCs.
alter table public.open_shift_pickups add column decision_reason text;

create function public.decline_swap(p_swap_id uuid, p_reason text default null)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the Manager can decline a Swap';
  end if;
  update public.swaps
  set status = 'declined', reason = nullif(trim(p_reason), '')
  where id = p_swap_id and status = 'accepted';
  if not found then raise exception 'This Swap is not awaiting Manager approval'; end if;
end;
$$;

create function public.decline_open_shift_pickup(p_pickup_id uuid, p_reason text default null)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  v_pickup public.open_shift_pickups%rowtype;
  v_short public.short_shifts%rowtype;
begin
  if public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the Manager can decline a pickup';
  end if;
  update public.open_shift_pickups
  set status = 'declined', decision_reason = nullif(trim(p_reason), '')
  where id = p_pickup_id and status = 'pending'
  returning * into v_pickup;
  if not found then raise exception 'Pickup is not awaiting approval'; end if;
  select * into v_short from public.short_shifts where id = v_pickup.short_shift_id;
  insert into public.staff_notices(staff_member_id, kind, title, body, month_start)
  values (v_pickup.staff_member_id, 'open_shift_pickup', 'Open shift pickup declined',
    'Your pickup of ' || v_short.shift_code || ' on ' || v_short.work_date::text ||
      ' was declined.' || case when v_pickup.decision_reason is null then ''
      else ' Reason: ' || v_pickup.decision_reason end,
    date_trunc('month', v_short.work_date)::date);
end;
$$;

revoke all on function public.decline_swap(uuid, text) from public;
revoke all on function public.decline_open_shift_pickup(uuid, text) from public;
grant execute on function public.decline_swap(uuid, text) to authenticated;
grant execute on function public.decline_open_shift_pickup(uuid, text) to authenticated;
