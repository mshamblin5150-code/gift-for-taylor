alter table public.calendar_invitation_outbox
  add column delivery_attempts integer not null default 0,
  add column delivery_claim uuid,
  add column delivery_claimed_at timestamptz,
  add constraint calendar_invitation_delivery_attempts_bounded
    check (delivery_attempts between 0 and 3),
  add constraint calendar_invitation_delivery_claim_complete
    check ((delivery_claim is null) = (delivery_claimed_at is null));

drop function public.calendar_invitation_to_send(uuid);
drop function public.calendar_invitation_sent(uuid);

-- Claiming is the concurrency boundary: PostgreSQL rechecks the update
-- predicate after a concurrent updater releases the row lock, so only one
-- invocation receives a row for any delivery attempt.
create function public.calendar_invitation_claim(p_id uuid)
returns setof public.calendar_invitation_outbox
language sql volatile security definer set search_path = '' as $$
  update public.calendar_invitation_outbox event
  set delivery_attempts = event.delivery_attempts + 1,
      delivery_claim = gen_random_uuid(),
      delivery_claimed_at = clock_timestamp()
  where event.id = p_id
    and event.sent_at is null
    and event.superseded_at is null
    and event.delivery_claim is null
    and event.delivery_attempts < 3
  returning event.*
$$;
revoke all on function public.calendar_invitation_claim(uuid)
  from public, anon, authenticated;
grant execute on function public.calendar_invitation_claim(uuid) to service_role;

create function public.calendar_invitation_failed(p_id uuid, p_claim uuid)
returns void language sql volatile security definer set search_path = '' as $$
  update public.calendar_invitation_outbox
  set delivery_claim = null, delivery_claimed_at = null
  where id = p_id and delivery_claim = p_claim and sent_at is null
$$;
revoke all on function public.calendar_invitation_failed(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.calendar_invitation_failed(uuid, uuid)
  to service_role;

create function public.calendar_invitation_sent(p_id uuid, p_claim uuid)
returns void language sql volatile security definer set search_path = '' as $$
  update public.calendar_invitation_outbox
  set sent_at = clock_timestamp(), delivery_claim = null,
      delivery_claimed_at = null
  where id = p_id and delivery_claim = p_claim and sent_at is null
$$;
revoke all on function public.calendar_invitation_sent(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.calendar_invitation_sent(uuid, uuid)
  to service_role;
