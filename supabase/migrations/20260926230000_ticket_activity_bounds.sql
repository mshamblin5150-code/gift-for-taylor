-- Ticket activity reaches the Maintainer once per unread burst, while duplicate
-- submissions and bounded sender activity keep retries from becoming a loop.
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
    'maintainer_repair', 'ticket_closed', 'ticket_question',
    'ticket_activity'
  )
);

alter table public.staff_notices
  add column ticket_activity_count integer,
  add constraint staff_notice_ticket_activity_count check (
    (kind = 'ticket_activity') = (ticket_activity_count is not null)
    and (ticket_activity_count is null or ticket_activity_count > 0)
  );

create unique index one_unread_ticket_activity_notice
  on public.staff_notices(staff_member_id)
  where kind = 'ticket_activity' and read_at is null;

create function private.notice_maintainer_ticket_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_maintainer_id uuid;
begin
  select account.staff_member_id into v_maintainer_id
  from private.maintainer_identity identity
  join public.staff_accounts account
    on account.auth_user_id = identity.auth_user_id
    and account.accepted_invite_at is not null
    and account.revoked_at is null
  join public.staff_members member
    on member.id = account.staff_member_id and member.active;

  if v_maintainer_id is null then
    return new;
  end if;

  insert into public.staff_notices(
    staff_member_id, kind, title, body, ticket_activity_count
  ) values (
    v_maintainer_id, 'ticket_activity', '1 new Ticket',
    'Run /ticket-sweep to read it.', 1
  )
  on conflict (staff_member_id)
    where kind = 'ticket_activity' and read_at is null
  do update set
    ticket_activity_count = public.staff_notices.ticket_activity_count + 1,
    title = (public.staff_notices.ticket_activity_count + 1)::text
      || ' new Tickets',
    body = 'Run /ticket-sweep to read them.';
  return new;
end;
$$;
revoke all on function private.notice_maintainer_ticket_activity() from public;

create trigger notice_new_ticket_activity
after insert on public.tickets
for each row execute function private.notice_maintainer_ticket_activity();

create trigger notice_changed_ticket_activity
after update of reopened_at, latest_reply_at on public.tickets
for each row
when (
  new.reopened_at is distinct from old.reopened_at
  or new.latest_reply_at is distinct from old.latest_reply_at
)
execute function private.notice_maintainer_ticket_activity();

create or replace function public.put_in_ticket(
  p_kind public.ticket_kind,
  p_text text,
  p_screen_context text,
  p_schedule_month date,
  p_release_id text,
  p_device_context text,
  p_context_captured_at timestamptz,
  p_recent_actions text[],
  p_refusal_code text
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_sender_id uuid := public.current_staff_member_id();
  v_sender_name text;
  v_ticket_id uuid;
  v_now timestamptz := clock_timestamp();
begin
  if v_sender_id is null then
    raise exception using errcode = 'P2831',
      message = 'A current Staff account is required';
  end if;
  if p_text is null or char_length(trim(p_text)) not between 1 and 2000 then
    raise exception using errcode = 'P2832',
      message = 'Ticket text must be between 1 and 2000 characters';
  end if;
  if p_screen_context is null
      or char_length(trim(p_screen_context)) not between 1 and 100
      or p_release_id is null
      or char_length(trim(p_release_id)) not between 1 and 120
      or p_device_context is null
      or char_length(trim(p_device_context)) not between 1 and 500
      or p_context_captured_at is null
      or p_recent_actions is null
      or cardinality(p_recent_actions) not between 1 and 8
      or array_position(p_recent_actions, null) is not null
      or char_length(p_recent_actions::text) > 1600
      or (p_refusal_code is not null
        and p_refusal_code !~ '^P[0-9]{4}$')
      or (p_schedule_month is not null
        and p_schedule_month <> date_trunc('month', p_schedule_month)::date) then
    raise exception using errcode = 'P2833',
      message = 'Ticket context is incomplete';
  end if;

  -- Lock one stable row per sender so duplicate detection and both bounds hold
  -- even when two retries arrive together.
  select display_name into strict v_sender_name
  from public.staff_members where id = v_sender_id
  for update;

  select id into v_ticket_id
  from public.tickets
  where sender_id = v_sender_id
    and kind = p_kind
    and text = trim(p_text)
    and created_at >= v_now - interval '5 minutes'
  order by created_at desc, id desc
  limit 1;
  if found then
    return v_ticket_id;
  end if;

  if (select count(*) from public.tickets
      where sender_id = v_sender_id
        and created_at >= v_now - interval '1 hour') >= 5
    or (select count(*) from public.tickets
      where sender_id = v_sender_id
        and created_at >= v_now - interval '24 hours') >= 20 then
    raise exception using errcode = 'P2845',
      message = 'You have sent a lot today; the designer will see them all';
  end if;

  insert into public.tickets(
    sender_id, sender_display_name, kind, text, screen_context,
    schedule_month, release_id, device_context, context_captured_at,
    recent_actions, refusal_code
  ) values (
    v_sender_id, v_sender_name, p_kind, trim(p_text),
    trim(p_screen_context), p_schedule_month, trim(p_release_id),
    trim(p_device_context), p_context_captured_at,
    p_recent_actions, p_refusal_code
  ) returning id into v_ticket_id;
  return v_ticket_id;
end;
$$;
