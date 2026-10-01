-- Replace the Dashboard-only webhook with a versioned trigger. Keep the
-- shared secret in Vault; migration history must not contain its value.
create schema if not exists push_hooks;

create or replace function push_hooks.send_push()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_secret text;
begin
  select decrypted_secret into v_secret from vault.decrypted_secrets
  where name = 'push_webhook_secret';

  -- Local projects can apply migrations before push is configured. The Notice
  -- remains in the app even when delivery is unavailable.
  if v_secret is null then
    raise warning 'push_webhook_secret is missing; push was not queued';
    return new;
  end if;

  perform net.http_post(
    url := 'https://ngtvpuslvrxtrdberhqy.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-push-secret', v_secret),
    -- send-push re-reads the Notice with its service role key. The webhook
    -- only needs to identify the newly inserted row.
    body := jsonb_build_object('type', 'INSERT', 'schema', 'public',
      'table', 'staff_notices', 'record', jsonb_build_object('id', new.id),
      'old_record', null),
    timeout_milliseconds := 10000
  );
  return new;
end;
$$;

revoke all on function push_hooks.send_push() from public, anon, authenticated;

drop trigger if exists send_push_on_notice on public.staff_notices;
create trigger send_push_on_notice after insert on public.staff_notices
for each row execute function push_hooks.send_push();
