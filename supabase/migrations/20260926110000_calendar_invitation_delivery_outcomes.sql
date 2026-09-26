create table public.calendar_invitation_delivery_outcomes (
  invitation_id uuid not null
    references public.calendar_invitation_outbox(id),
  attempt_number integer not null check (attempt_number between 1 and 3),
  happened_at timestamptz not null default clock_timestamp(),
  outcome text not null check (outcome in ('sent', 'refused', 'uncertain')),
  error_code text,
  status_code text,
  error_message text,
  primary key (invitation_id, attempt_number),
  constraint calendar_invitation_outcome_error_code_length
    check (error_code is null or char_length(error_code) <= 120),
  constraint calendar_invitation_outcome_status_code_length
    check (status_code is null or char_length(status_code) <= 16),
  constraint calendar_invitation_outcome_error_message_length
    check (error_message is null or char_length(error_message) between 1 and 1000),
  constraint calendar_invitation_outcome_error_complete
    check ((outcome = 'sent' and error_message is null) or
      (outcome <> 'sent' and error_message is not null))
);
alter table public.calendar_invitation_delivery_outcomes enable row level security;
revoke all on public.calendar_invitation_delivery_outcomes
  from public, anon, authenticated;

create function public.record_calendar_invitation_failure(
  p_id uuid,
  p_recipient text,
  p_method text,
  p_claim uuid,
  p_outcome text,
  p_error_code text,
  p_status_code text,
  p_error_message text
) returns boolean
language sql
volatile
security definer
set search_path = ''
as $$
  with eligible as (
    select event.id, event.delivery_attempts
    from public.calendar_invitation_outbox event
    where coalesce(event.batch_id, event.id) = p_id
      and event.recipient = p_recipient
      and event.method = p_method
      and event.delivery_claim = p_claim
      and event.sent_at is null
      and event.superseded_at is null
      and p_outcome in ('refused', 'uncertain')
  ), recorded as (
    insert into public.calendar_invitation_delivery_outcomes(
      invitation_id, attempt_number, outcome, error_code, status_code,
      error_message
    )
    select eligible.id, eligible.delivery_attempts, p_outcome,
      nullif(left(btrim(p_error_code), 120), ''),
      nullif(left(btrim(p_status_code), 16), ''),
      coalesce(nullif(left(btrim(p_error_message), 1000), ''),
        'Unknown provider failure')
    from eligible
    on conflict (invitation_id, attempt_number) do nothing
    returning invitation_id, attempt_number
  ), released as (
    update public.calendar_invitation_outbox event
    set delivery_claim = null, delivery_claimed_at = null,
        delivery_started_at = null
    from eligible
    where p_outcome = 'refused'
      and event.id = eligible.id
      and event.delivery_claim = p_claim
      and (exists (
          select 1 from recorded
          where recorded.invitation_id = eligible.id
            and recorded.attempt_number = eligible.delivery_attempts
        ) or exists (
          select 1 from public.calendar_invitation_delivery_outcomes delivery
          where delivery.invitation_id = eligible.id
            and delivery.attempt_number = eligible.delivery_attempts
        ))
  )
  select exists(select 1 from eligible)
    and not exists (
      select 1 from eligible
      where not (exists (
          select 1 from recorded
          where recorded.invitation_id = eligible.id
            and recorded.attempt_number = eligible.delivery_attempts
        ) or exists (
          select 1 from public.calendar_invitation_delivery_outcomes delivery
          where delivery.invitation_id = eligible.id
            and delivery.attempt_number = eligible.delivery_attempts
        ))
    )
$$;
revoke all on function public.record_calendar_invitation_failure(
  uuid, text, text, uuid, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.record_calendar_invitation_failure(
  uuid, text, text, uuid, text, text, text, text
) to service_role;

create or replace function public.calendar_invitation_sent(
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
    returning event.id, event.delivery_attempts
  ), recorded as (
    insert into public.calendar_invitation_delivery_outcomes(
      invitation_id, attempt_number, outcome
    )
    select completed.id, completed.delivery_attempts, 'sent'
    from completed
    on conflict (invitation_id, attempt_number) do nothing
  )
  select exists(select 1 from completed)
$$;

create function public.read_undelivered_calendar_invitations()
returns table (
  staff_display_name text,
  work_date date,
  recipient text,
  method text,
  shift_code text,
  delivery_attempts integer,
  delivery_failed_at timestamptz,
  delivery_error_code text,
  delivery_status_code text,
  delivery_error_message text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if private.active_maintainer_repair_id() is null then
    raise exception 'An active Maintainer Repair is required to read Undelivered invitations'
      using errcode = '42501';
  end if;

  return query
  select member.display_name, event.work_date, event.recipient, event.method,
    event.shift_code, event.delivery_attempts,
    coalesce(failure.happened_at, event.delivery_started_at),
    failure.error_code, failure.status_code,
    coalesce(failure.error_message, 'Delivery outcome could not be recorded')
  from public.calendar_invitation_outbox event
  join public.staff_members member on member.id = event.staff_member_id
  left join lateral (
    select delivery.happened_at, delivery.error_code,
      delivery.status_code, delivery.error_message
    from public.calendar_invitation_delivery_outcomes delivery
    where delivery.invitation_id = event.id
      and delivery.outcome in ('refused', 'uncertain')
    order by delivery.attempt_number desc
    limit 1
  ) failure on true
  where event.sent_at is null
    and event.superseded_at is null
    and (failure.happened_at is not null or event.delivery_started_at is not null)
  order by failure.happened_at desc, event.work_date, member.display_name;
end;
$$;
revoke all on function public.read_undelivered_calendar_invitations()
  from public;
grant execute on function public.read_undelivered_calendar_invitations()
  to authenticated;
