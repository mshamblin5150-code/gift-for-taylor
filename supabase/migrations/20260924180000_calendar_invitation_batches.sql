alter table public.calendar_invitation_outbox add column batch_id uuid;
create index calendar_invitation_outbox_batch
  on public.calendar_invitation_outbox (batch_id)
  where batch_id is not null and sent_at is null and superseded_at is null;

create function public.queue_calendar_invitation(
  p_staff_member_id uuid, p_work_date date, p_method text,
  p_shift_code text, p_starts_at timestamptz, p_ends_at timestamptz,
  p_batch_id uuid
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_recipient text;
  v_sequence integer;
  v_last_modified timestamptz;
begin
  perform pg_advisory_xact_lock(hashtext(p_staff_member_id::text || ':' || p_work_date::text));
  select account.personal_email into v_recipient
  from public.staff_accounts account
  where account.staff_member_id = p_staff_member_id
    and account.accepted_invite_at is not null and account.revoked_at is null;
  if v_recipient is null then return; end if;

  update public.calendar_invitation_outbox
    set superseded_at = clock_timestamp()
    where staff_member_id = p_staff_member_id and work_date = p_work_date
      and sent_at is null and superseded_at is null;
  select coalesce(max(sequence) + 1, 0),
    greatest(clock_timestamp(), coalesce(max(last_modified) + interval '1 second',
      clock_timestamp())) into v_sequence, v_last_modified
  from public.calendar_invitation_outbox
  where staff_member_id = p_staff_member_id and work_date = p_work_date;
  insert into public.calendar_invitation_outbox
    (staff_member_id, work_date, recipient, method, shift_code,
     starts_at, ends_at, sequence, last_modified, batch_id)
  values (p_staff_member_id, p_work_date, v_recipient, p_method,
    p_shift_code, p_starts_at, p_ends_at, v_sequence, v_last_modified,
    p_batch_id);
end;
$$;
revoke all on function public.queue_calendar_invitation(
  uuid,date,text,text,timestamptz,timestamptz,uuid)
  from public, anon, authenticated;

create or replace function public.queue_calendar_invitation(
  p_staff_member_id uuid, p_work_date date, p_method text,
  p_shift_code text, p_starts_at timestamptz, p_ends_at timestamptz
) returns void language sql security definer set search_path = '' as $$
  select public.queue_calendar_invitation(p_staff_member_id, p_work_date,
    p_method, p_shift_code, p_starts_at, p_ends_at, null)
$$;

create function public.queue_calendar_cell(
  p_staff_member_id uuid, p_work_date date, p_shift_code text,
  p_method text, p_batch_id uuid
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_start time;
  v_end time;
begin
  select code.start_time, code.end_time into v_start, v_end
  from public.shift_codes code where code.code = upper(trim(p_shift_code));
  perform public.queue_calendar_invitation(p_staff_member_id, p_work_date,
    p_method, p_shift_code,
    case when v_start is not null then
      (p_work_date + v_start) at time zone 'America/New_York' end,
    case when v_end is not null then
      (p_work_date + v_end + case when v_end <= v_start
        then interval '1 day' else interval '0 day' end)
        at time zone 'America/New_York' end,
    p_batch_id);
end;
$$;
revoke all on function public.queue_calendar_cell(uuid,date,text,text,uuid)
  from public, anon, authenticated;

-- A release owns one batch identity. Ordinary cell changes continue through
-- the four-argument queue function and therefore remain prompt single sends.
create or replace function public.calendar_month_released()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_cell record;
  v_batch_id uuid := gen_random_uuid();
begin
  if old.release_state = 'unpublished' and new.release_state = 'released' then
    for v_cell in
      select cell.staff_member_id, cell.work_date, cell.shift_code
      from public.schedule_cells cell
      join public.staff_members member on member.id = cell.staff_member_id
      where cell.schedule_month_id = new.id and member.active
        and member.calendar_channel = 'invitations'
        and public.is_working_shift(cell.shift_code)
    loop
      perform public.queue_calendar_cell(v_cell.staff_member_id,
        v_cell.work_date, v_cell.shift_code, 'REQUEST', v_batch_id);
    end loop;
    if exists (select 1 from public.calendar_invitation_outbox
        where batch_id = v_batch_id) then
      perform public.post_calendar_invitation_delivery(v_batch_id);
    end if;
  end if;
  return new;
end;
$$;

drop trigger send_calendar_invitation_on_queue
  on public.calendar_invitation_outbox;
create trigger send_calendar_invitation_on_queue
  after insert on public.calendar_invitation_outbox
  for each row when (new.batch_id is null)
  execute function public.calendar_invitation_webhook();

-- Claim every eligible row in one release together. Rows held after an
-- uncertain send stay claimed while untouched recipients can be retried. The
-- shared token makes each eligible set the concurrency boundary; later single
-- cell changes keep their own row id as the delivery identity.
create or replace function public.calendar_invitation_claim(p_id uuid)
returns setof public.calendar_invitation_outbox
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_claim uuid := gen_random_uuid();
begin
  if exists (select 1 from public.calendar_invitation_outbox event
      where event.batch_id = p_id and event.sent_at is null
        and event.superseded_at is null) then
    return query
      update public.calendar_invitation_outbox event
      set delivery_attempts = event.delivery_attempts + 1,
          delivery_claim = v_claim,
          delivery_claimed_at = clock_timestamp(),
          delivery_started_at = null
      where event.batch_id = p_id and event.sent_at is null
        and event.superseded_at is null
        and public.calendar_invitation_is_claimable(event)
      returning event.*;
    return;
  end if;

  return query
    update public.calendar_invitation_outbox event
    set delivery_attempts = event.delivery_attempts + 1,
        delivery_claim = v_claim,
        delivery_claimed_at = clock_timestamp(),
        delivery_started_at = null
    where event.id = p_id and event.batch_id is null
      and public.calendar_invitation_is_claimable(event)
    returning event.*;
end;
$$;

create function public.calendar_invitation_sending(
  p_id uuid, p_recipient text, p_method text, p_claim uuid
) returns setof uuid language sql volatile security definer set search_path = '' as $$
  update public.calendar_invitation_outbox event
  set delivery_started_at = clock_timestamp()
  where coalesce(event.batch_id, event.id) = p_id
    and event.recipient = p_recipient and event.method = p_method
    and event.delivery_claim = p_claim and event.sent_at is null
    and event.superseded_at is null and event.delivery_started_at is null
  returning event.id
$$;
revoke all on function public.calendar_invitation_sending(uuid,text,text,uuid)
  from public, anon, authenticated;
grant execute on function public.calendar_invitation_sending(uuid,text,text,uuid)
  to service_role;

create function public.calendar_invitation_failed(
  p_id uuid, p_recipient text, p_method text, p_claim uuid
) returns void language sql volatile security definer set search_path = '' as $$
  update public.calendar_invitation_outbox event
  set delivery_claim = null, delivery_claimed_at = null,
      delivery_started_at = null
  where coalesce(event.batch_id, event.id) = p_id
    and event.recipient = p_recipient and event.method = p_method
    and event.delivery_claim = p_claim and event.sent_at is null
$$;
revoke all on function public.calendar_invitation_failed(uuid,text,text,uuid)
  from public, anon, authenticated;
grant execute on function public.calendar_invitation_failed(uuid,text,text,uuid)
  to service_role;

create function public.calendar_invitation_sent(
  p_id uuid, p_recipient text, p_method text, p_claim uuid
) returns boolean language sql volatile security definer set search_path = '' as $$
  with completed as (
    update public.calendar_invitation_outbox event
    set sent_at = clock_timestamp(), delivery_claim = null,
        delivery_claimed_at = null, delivery_started_at = null
    where coalesce(event.batch_id, event.id) = p_id
      and event.recipient = p_recipient and event.method = p_method
      and event.delivery_claim = p_claim and event.sent_at is null
      and event.superseded_at is null and event.delivery_started_at is not null
    returning true
  )
  select exists(select 1 from completed)
$$;
revoke all on function public.calendar_invitation_sent(uuid,text,text,uuid)
  from public, anon, authenticated;
grant execute on function public.calendar_invitation_sent(uuid,text,text,uuid)
  to service_role;

create or replace function public.retry_calendar_invitation_deliveries()
returns integer language plpgsql volatile security definer set search_path = '' as $$
declare
  v_id uuid;
  v_posted integer := 0;
begin
  for v_id in
    select coalesce(event.batch_id, event.id)
    from public.calendar_invitation_outbox event
    where event.sent_at is null and event.superseded_at is null
      and public.calendar_invitation_is_claimable(event)
    group by coalesce(event.batch_id, event.id)
    order by min(event.last_modified)
    limit 50
  loop
    if public.post_calendar_invitation_delivery(v_id) then
      v_posted := v_posted + 1;
    end if;
  end loop;
  return v_posted;
end;
$$;
