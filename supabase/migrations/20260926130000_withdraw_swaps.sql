-- A requester may take back a Swap until the Manager approves it.
drop function public.swap_colleague_cell_number(uuid);
drop index public.swaps_approval_queue;
alter table public.swaps drop constraint swaps_void_record;

alter table public.swaps alter column status drop default;
alter table public.swaps alter column status type text using status::text;
drop type public.swap_status;
create type public.swap_status as enum
  ('proposed', 'accepted', 'declined', 'approved', 'withdrawn', 'voided');
alter table public.swaps alter column status type public.swap_status
  using status::public.swap_status;
alter table public.swaps alter column status set default 'proposed';
alter table public.swaps add constraint swaps_void_record check (
  (status = 'voided') =
    (voided_staff_member_id is not null and voided_work_date is not null)
);
create index swaps_approval_queue on public.swaps (created_at)
  where status = 'accepted';

create function public.swap_colleague_cell_number(p_swap_id uuid)
returns text language sql stable security definer set search_path = '' as $$
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
grant execute on function public.swap_colleague_cell_number(uuid)
  to authenticated;

alter table public.swaps add column withdrawn_at timestamptz;

create function public.withdraw_swap(p_swap_id uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  update public.swaps set status = 'withdrawn',
    withdrawn_at = clock_timestamp()
  where id = p_swap_id
    and requester_id = public.current_staff_member_id()
    and status in ('proposed', 'accepted');
  if not found then raise exception 'This Swap cannot be withdrawn'; end if;
end;
$$;

alter table public.staff_notices drop constraint staff_notices_kind_check;
alter table public.staff_notices add constraint staff_notices_kind_check check (
  kind in (
    'month_release', 'schedule_change', 'open_shift_pickup',
    'open_shift_posted', 'request_submitted', 'request_decided',
    'swap_proposed', 'swap_accepted', 'swap_declined', 'swap_approved',
    'swap_withdrawn', 'swap_voided', 'giveaway_proposed',
    'giveaway_accepted', 'giveaway_declined', 'giveaway_approved',
    'giveaway_withdrawn', 'giveaway_voided', 'test',
    'floor_critical_call_in', 'call_in_filled', 'open_shift_batch',
    'maintainer_repair'
  )
);

create or replace function public.notice_swap()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := public.current_staff_member_id();
  v_kind text;
  v_title text;
  v_body text;
begin
  if tg_op = 'INSERT' then
    v_kind := 'swap_proposed';
    v_title := 'Swap proposed';
    v_body := 'A colleague proposed a Swap. Open Swaps to respond.';
  elsif new.status is distinct from old.status then
    v_kind := 'swap_' || new.status::text;
    v_title := 'Swap ' || new.status::text;
    v_body := 'Your Swap was ' || new.status::text ||
      '. Open Swaps for details.';
  else
    return new;
  end if;
  insert into public.staff_notices(staff_member_id, kind, title, body)
  select recipient.id, v_kind, v_title, v_body
  from public.staff_members recipient
  where recipient.active and (
    (recipient.id in (new.requester_id, new.colleague_id)
      and recipient.id is distinct from v_actor
      and (new.status <> 'withdrawn' or old.status = 'accepted'))
    or (new.status = 'accepted' and recipient.role = 'manager'
      and recipient.id is distinct from v_actor)
    or (new.status = 'voided' and recipient.role = 'manager'
      and recipient.id = v_actor)
  );
  return new;
end;
$$;

revoke all on function public.withdraw_swap(uuid) from public;
grant execute on function public.withdraw_swap(uuid) to authenticated;
