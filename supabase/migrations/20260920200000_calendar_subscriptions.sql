-- Preserve existing feed URLs while giving each subscription its own identity.
alter table public.calendar_feed_tokens
  add column id uuid not null default gen_random_uuid(),
  add column name text,
  add column last_fetched_at timestamptz,
  add column fetching_user_agent text;
update public.calendar_feed_tokens set name = 'Existing calendar';
alter table public.calendar_feed_tokens alter column name set not null;
alter table public.calendar_feed_tokens rename column rotated_at to created_at;
alter table public.calendar_feed_tokens drop constraint calendar_feed_tokens_pkey;
alter table public.calendar_feed_tokens add primary key (id);
create index calendar_feed_tokens_staff_member_id_idx
  on public.calendar_feed_tokens (staff_member_id);

drop function public.has_calendar_feed();
drop function public.reset_calendar_feed();

create function public.list_calendar_subscriptions()
returns table (id uuid, name text, created_at timestamptz,
  last_fetched_at timestamptz, fetching_user_agent text)
language sql stable security definer set search_path = '' as $$
  select token.id, token.name, token.created_at,
    token.last_fetched_at, token.fetching_user_agent
  from public.calendar_feed_tokens token
  join public.staff_accounts account on account.staff_member_id = token.staff_member_id
  join public.staff_members member on member.id = token.staff_member_id
  where account.auth_user_id = auth.uid()
    and account.revoked_at is null and member.active
    and token.revoked_at is null
  order by token.created_at, token.id
$$;
revoke all on function public.list_calendar_subscriptions() from public;
grant execute on function public.list_calendar_subscriptions() to authenticated;

create function public.create_calendar_subscription(p_name text)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_staff_member_id uuid := public.current_staff_member_id();
  v_token text := encode(extensions.gen_random_bytes(32), 'hex');
  v_id uuid;
begin
  if v_staff_member_id is null or not exists (
    select 1 from public.staff_accounts account
    join public.staff_members member on member.id = account.staff_member_id
    where account.staff_member_id = v_staff_member_id
      and account.auth_user_id = auth.uid()
      and account.revoked_at is null and member.active
  ) then
    raise exception 'Only active Staff members can create a Calendar subscription';
  end if;
  if p_name is null or length(trim(p_name)) not between 1 and 80 then
    raise exception 'Calendar subscription name must be 1 to 80 characters';
  end if;
  insert into public.calendar_feed_tokens (staff_member_id, name, token_hash)
  values (v_staff_member_id, trim(p_name),
    encode(sha256(decode(v_token, 'hex')), 'hex'))
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'token', v_token);
end;
$$;
revoke all on function public.create_calendar_subscription(text) from public;
grant execute on function public.create_calendar_subscription(text) to authenticated;

create function public.revoke_calendar_subscription(p_id uuid)
returns void
language plpgsql volatile security definer set search_path = '' as $$
begin
  update public.calendar_feed_tokens token set revoked_at = now()
  where token.id = p_id and token.revoked_at is null
    and token.staff_member_id = public.current_staff_member_id()
    and exists (
      select 1 from public.staff_accounts account
      where account.staff_member_id = token.staff_member_id
        and account.auth_user_id = auth.uid()
        and account.revoked_at is null
    );
  if not found then
    raise exception 'Calendar subscription not found';
  end if;
end;
$$;
revoke all on function public.revoke_calendar_subscription(uuid) from public;
grant execute on function public.revoke_calendar_subscription(uuid) to authenticated;

-- The Edge Function calls this for every valid GET, before loading events.
create function public.record_calendar_feed_fetch(p_token text, p_user_agent text)
returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_staff_member_id uuid;
begin
  if p_token !~ '^[0-9a-f]{64}$' then return null; end if;
  update public.calendar_feed_tokens token
  set last_fetched_at = now(),
      fetching_user_agent = left(nullif(trim(p_user_agent), ''), 512)
  where token.token_hash = encode(sha256(decode(p_token, 'hex')), 'hex')
    and token.revoked_at is null
    and exists (
      select 1 from public.staff_members member
      where member.id = token.staff_member_id and member.active
    )
  returning token.staff_member_id into v_staff_member_id;
  return v_staff_member_id;
end;
$$;
revoke all on function public.record_calendar_feed_fetch(text, text)
  from public, anon, authenticated;
grant execute on function public.record_calendar_feed_fetch(text, text)
  to service_role;
