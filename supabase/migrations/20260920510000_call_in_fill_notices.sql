alter table public.staff_notices drop constraint staff_notices_kind_check;
alter table public.staff_notices add constraint staff_notices_kind_check check (kind in (
  'month_release', 'schedule_change', 'open_shift_pickup', 'open_shift_posted',
  'request_submitted', 'request_decided', 'swap_proposed', 'swap_accepted',
  'swap_declined', 'swap_approved', 'test', 'floor_critical_call_in',
  'call_in_filled'
));

-- Both self-service and Manager approval stamp filled_at. Notify once at that
-- shared transition, after the pickup has actually placed someone on the Schedule.
create function public.notice_filled_call_in()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.staff_notices(staff_member_id, kind, title, body,
    month_start, short_shift_id, push_eligible)
  select member.id, 'call_in_filled', 'Call-in shift filled',
    'The ' || new.shift_code || ' Open shift on ' || new.work_date::text ||
      ' has been picked up.',
    date_trunc('month', new.work_date)::date, new.id,
    member.role <> 'manager'
  from public.schedule_changes change
  join public.staff_members member on member.id in (
    change.staff_member_id, change.changed_by_staff_member_id)
    or (member.role = 'manager' and member.active)
  where change.id = new.call_in_change_id and change.new_shift_code = 'C/I';
  return new;
end;
$$;
revoke all on function public.notice_filled_call_in() from public;
create trigger notice_filled_call_in after update of filled_at on public.short_shifts
for each row when (old.filled_at is null and new.filled_at is not null
  and new.call_in_change_id is not null)
execute function public.notice_filled_call_in();
