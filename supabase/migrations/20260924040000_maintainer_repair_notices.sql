-- Opening a Repair always leaves one quiet, durable Notice for the Manager.
alter table public.staff_notices drop constraint staff_notices_kind_check;
alter table public.staff_notices add constraint staff_notices_kind_check check (kind in (
  'month_release', 'schedule_change', 'open_shift_pickup', 'open_shift_posted',
  'request_submitted', 'request_decided', 'swap_proposed', 'swap_accepted',
  'swap_declined', 'swap_approved', 'test', 'floor_critical_call_in',
  'call_in_filled', 'open_shift_batch', 'maintainer_repair'
));

create function private.maintainer_repair_category_label(
  p_category public.maintainer_repair_reason_category
)
returns text language sql immutable set search_path = '' as $$
  select case p_category
    when 'manager_handover' then 'Manager handover'
    when 'schedule_or_month' then 'Schedule or Month'
    when 'unit_settings' then 'Unit settings'
    when 'staff_or_invite' then 'Staff record or Invite'
    when 'investigation' then 'Investigating a fault'
    when 'something_else' then 'Something else'
  end
$$;
revoke all on function private.maintainer_repair_category_label(
  public.maintainer_repair_reason_category) from public;

create or replace function private.maintainer_repair_summary(p_repair_id uuid)
returns text language sql stable security definer set search_path = '' as $$
  select private.maintainer_repair_category_label(repair.reason_category)
    || coalesce(' — ' || repair.detail, '')
  from public.maintainer_repairs repair
  where repair.id = p_repair_id
$$;

create function private.notice_maintainer_repair()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_manager_id uuid;
  v_actor_id uuid;
  v_category text;
begin
  select member.id into v_manager_id
  from public.staff_members member
  where member.active and member.role = 'manager';

  select account.staff_member_id into v_actor_id
  from public.staff_accounts account
  where account.auth_user_id = new.auth_user_id
    and account.accepted_invite_at is not null
    and account.revoked_at is null;

  if v_manager_id is null or v_manager_id is not distinct from v_actor_id then
    return new;
  end if;

  v_category := private.maintainer_repair_category_label(new.reason_category);

  insert into public.staff_notices(
    staff_member_id, kind, title, body, push_eligible)
  values (v_manager_id, 'maintainer_repair', 'Repair: ' || v_category,
    coalesce(new.detail, ''), false);
  return new;
end;
$$;
revoke all on function private.notice_maintainer_repair() from public;

create trigger notice_maintainer_repair
after insert on public.maintainer_repairs
for each row execute function private.notice_maintainer_repair();
