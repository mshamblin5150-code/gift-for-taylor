-- The organizer is part of an iMIP event's authority. Keep it on each immutable
-- outbox row so the transition can withdraw old events after the Edge Function
-- has learned the new default sender.
alter table public.calendar_invitation_outbox add column sender text;
update public.calendar_invitation_outbox
set sender = 'no-reply@axion.healthcare';
alter table public.calendar_invitation_outbox
  alter column sender set default 'no-reply@calendar.axion.healthcare',
  alter column sender set not null;

create or replace function public.queue_calendar_invitation(
  p_staff_member_id uuid, p_work_date date, p_method text,
  p_shift_code text, p_starts_at timestamptz, p_ends_at timestamptz,
  p_batch_id uuid
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_recipient text;
  v_sender constant text := 'no-reply@calendar.axion.healthcare';
  v_sequence integer;
  v_last_modified timestamptz;
begin
  -- Enforce the invariant at the common boundary so Month releases, cell
  -- edits, Shift code changes and lifecycle backfills cannot bypass it.
  if p_method = 'REQUEST' and p_work_date <
      (clock_timestamp() at time zone 'America/New_York')::date then
    return;
  end if;
  perform pg_advisory_xact_lock(hashtext(p_staff_member_id::text || ':' || p_work_date::text));
  select account.personal_email into v_recipient
  from public.staff_accounts account
  where account.staff_member_id = p_staff_member_id
    and account.accepted_invite_at is not null and account.revoked_at is null;
  if v_recipient is null then return; end if;

  -- A pending message from this organizer can be replaced. A migration
  -- withdrawal from the old organizer is a different authority and must live
  -- long enough to be delivered alongside the new request.
  update public.calendar_invitation_outbox
    set superseded_at = clock_timestamp()
    where staff_member_id = p_staff_member_id and work_date = p_work_date
      and sender = v_sender and sent_at is null and superseded_at is null;
  select coalesce(max(sequence) + 1, 0),
    greatest(clock_timestamp(), coalesce(max(last_modified) + interval '1 second',
      clock_timestamp())) into v_sequence, v_last_modified
  from public.calendar_invitation_outbox
  where staff_member_id = p_staff_member_id and work_date = p_work_date;
  insert into public.calendar_invitation_outbox
    (staff_member_id, work_date, recipient, method, shift_code,
     starts_at, ends_at, sequence, last_modified, batch_id, sender)
  values (p_staff_member_id, p_work_date, v_recipient, p_method,
    p_shift_code, p_starts_at, p_ends_at, v_sequence, v_last_modified,
    p_batch_id, v_sender);
end;
$$;

-- A REQUEST covers today and work still to come. A CANCEL remains unbounded,
-- but only follows a REQUEST that was actually published; newly bounded
-- accounts therefore do not spend mail withdrawing history they never received.
create or replace function public.queue_current_calendar_shifts(
  p_staff_member_id uuid, p_method text
) returns void language plpgsql security definer set search_path = '' as $$
declare v_cell record;
begin
  for v_cell in
    select cell.work_date, cell.shift_code from public.schedule_cells cell
    join public.schedule_months month on month.id = cell.schedule_month_id
    where cell.staff_member_id = p_staff_member_id
      and month.release_state = 'released'
      and public.is_working_shift(cell.shift_code)
      and (
        (p_method = 'REQUEST' and cell.work_date >=
          (clock_timestamp() at time zone 'America/New_York')::date)
        or (p_method = 'CANCEL' and (
          select event.method from public.calendar_invitation_outbox event
          where event.staff_member_id = p_staff_member_id
            and event.work_date = cell.work_date
          order by event.sequence desc limit 1
        ) = 'REQUEST')
      )
  loop
    perform public.queue_calendar_cell(p_staff_member_id, v_cell.work_date,
      v_cell.shift_code, p_method);
  end loop;
end;
$$;

-- Anything not yet sent from the old organizer is replaced below or no longer
-- current. Do not let it escape after this transaction commits.
update public.calendar_invitation_outbox
set superseded_at = clock_timestamp()
where sender = 'no-reply@axion.healthcare'
  and sent_at is null and superseded_at is null;

-- Withdraw every old-organizer REQUEST that may have reached SMTP unless a
-- later CANCEL is definitively sent. A started-but-unconfirmed CANCEL is not
-- proof of withdrawal; superseding it below must therefore queue a replacement.
-- Historic recipient and event details are intentionally retained: a departed
-- Staff member may no longer have a live account, but the old event in that
-- personal calendar still needs its matching cancellation.
do $$
declare
  v_event record;
  v_sequence integer;
  v_last_modified timestamptz;
begin
  for v_event in
    select distinct on (
      event.staff_member_id, event.work_date, event.recipient
    ) event.*
    from public.calendar_invitation_outbox event
    where event.sender = 'no-reply@axion.healthcare'
      and event.method = 'REQUEST'
      -- Once SMTP delivery starts, an interrupted completion is deliberately
      -- held because the message may be in the recipient's calendar already.
      and (event.sent_at is not null or event.delivery_started_at is not null)
      and not exists (
        select 1 from public.calendar_invitation_outbox cancellation
        where cancellation.staff_member_id = event.staff_member_id
          and cancellation.work_date = event.work_date
          and cancellation.recipient = event.recipient
          and cancellation.sender = 'no-reply@axion.healthcare'
          and cancellation.method = 'CANCEL'
          and cancellation.sequence > event.sequence
          and cancellation.sent_at is not null
      )
    order by event.staff_member_id, event.work_date, event.recipient,
      event.sequence desc
  loop
    select coalesce(max(event.sequence) + 1, 0),
      greatest(clock_timestamp(),
        coalesce(max(event.last_modified) + interval '1 second',
          clock_timestamp()))
    into v_sequence, v_last_modified
    from public.calendar_invitation_outbox event
    where event.staff_member_id = v_event.staff_member_id
      and event.work_date = v_event.work_date;

    insert into public.calendar_invitation_outbox
      (staff_member_id, work_date, recipient, method, shift_code,
       starts_at, ends_at, sequence, last_modified, sender)
    values (v_event.staff_member_id, v_event.work_date, v_event.recipient,
      'CANCEL', v_event.shift_code, v_event.starts_at, v_event.ends_at,
      v_sequence, v_last_modified, 'no-reply@axion.healthcare');
  end loop;
end;
$$;

-- Publish only current and future work from the new organizer. Old-organizer
-- cancellations remain independently pending because queueing supersedes rows
-- only within the same organizer authority.
do $$
declare v_member record;
begin
  for v_member in
    select member.id from public.staff_members member
    join public.staff_accounts account on account.staff_member_id = member.id
    where member.active and member.calendar_channel = 'invitations'
      and account.accepted_invite_at is not null and account.revoked_at is null
  loop
    perform public.queue_current_calendar_shifts(v_member.id, 'REQUEST');
  end loop;
end;
$$;
