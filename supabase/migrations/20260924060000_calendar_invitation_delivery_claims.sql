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
    and (event.delivery_claim is null
      or event.delivery_claimed_at < clock_timestamp() - interval '5 minutes')
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

-- Both the insert trigger and the bounded retry sweep post one row id. The
-- Edge Function must still claim that row before it sends mail.
create function public.post_calendar_invitation_delivery(p_id uuid)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare v_secret text;
begin
  select decrypted_secret into v_secret from vault.decrypted_secrets
  where name = 'calendar_webhook_secret';
  if v_secret is null then return false; end if;
  perform net.http_post(
    url := 'https://ngtvpuslvrxtrdberhqy.supabase.co/functions/v1/send-calendar-invitation',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-calendar-secret', v_secret),
    body := jsonb_build_object('id', p_id),
    timeout_milliseconds := 10000
  );
  return true;
end;
$$;
revoke all on function public.post_calendar_invitation_delivery(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.calendar_invitation_webhook()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform public.post_calendar_invitation_delivery(new.id);
  return new;
end;
$$;

create function public.retry_calendar_invitation_deliveries()
returns integer language plpgsql volatile security definer set search_path = '' as $$
declare
  v_id uuid;
  v_posted integer := 0;
begin
  for v_id in
    select event.id from public.calendar_invitation_outbox event
    where event.sent_at is null and event.superseded_at is null
      and event.delivery_attempts < 3
      and (event.delivery_claim is null
        or event.delivery_claimed_at < clock_timestamp() - interval '5 minutes')
    order by event.last_modified
    limit 50
  loop
    if public.post_calendar_invitation_delivery(v_id) then
      v_posted := v_posted + 1;
    end if;
  end loop;
  return v_posted;
end;
$$;
revoke all on function public.retry_calendar_invitation_deliveries()
  from public, anon, authenticated, service_role;

create extension if not exists pg_cron;
select cron.schedule(
  'retry-calendar-invitation-deliveries',
  '*/5 * * * *',
  'select public.retry_calendar_invitation_deliveries()'
);
