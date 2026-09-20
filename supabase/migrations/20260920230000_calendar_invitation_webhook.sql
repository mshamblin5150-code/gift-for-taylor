-- Invoke the delivery function after an outbox row commits. The shared secret
-- lives in Vault, not in the trigger definition or migration history.
create or replace function public.calendar_invitation_webhook()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_secret text;
begin
  select decrypted_secret into v_secret from vault.decrypted_secrets
    where name = 'calendar_webhook_secret';
  -- Local/test projects can apply this migration before delivery is configured.
  if v_secret is null then return new; end if;
  perform net.http_post(
    url := 'https://ngtvpuslvrxtrdberhqy.supabase.co/functions/v1/send-calendar-invitation',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-calendar-secret', v_secret),
    body := jsonb_build_object('id', new.id),
    timeout_milliseconds := 10000
  );
  return new;
end;
$$;
revoke all on function public.calendar_invitation_webhook()
  from public, anon, authenticated;

drop trigger if exists send_calendar_invitation_on_queue
  on public.calendar_invitation_outbox;
create trigger send_calendar_invitation_on_queue
  after insert on public.calendar_invitation_outbox
  for each row execute function public.calendar_invitation_webhook();
