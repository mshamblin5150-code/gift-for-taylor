-- Keep individual fetches long enough to measure Calendar subscription cadence.
-- The table is private: no client role may read request metadata or source IPs.
alter table public.calendar_feed_tokens
  add column measure_fetches_until timestamptz;
create table public.calendar_feed_fetches (
  id bigint generated always as identity primary key,
  subscription_id uuid not null references public.calendar_feed_tokens(id) on delete cascade,
  fetched_at timestamptz not null default clock_timestamp(),
  user_agent text,
  if_none_match boolean not null,
  if_modified_since boolean not null,
  forwarded_for text
);
create index calendar_feed_fetches_subscription_time_idx
  on public.calendar_feed_fetches (subscription_id, fetched_at);
alter table public.calendar_feed_fetches enable row level security;
revoke all on public.calendar_feed_fetches from public, anon, authenticated;
grant select, delete on public.calendar_feed_fetches to service_role;

-- Keep the two-argument RPC for the currently deployed function until the
-- new Edge Function is deployed after migrations.
create function public.record_calendar_feed_fetch(
  p_token text,
  p_user_agent text,
  p_if_none_match text,
  p_if_modified_since text,
  p_forwarded_for text
)
returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_subscription_id uuid;
  v_staff_member_id uuid;
  v_measure_fetches_until timestamptz;
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
  returning token.id, token.staff_member_id, token.measure_fetches_until
    into v_subscription_id, v_staff_member_id, v_measure_fetches_until;
  if v_measure_fetches_until > now() then
    insert into public.calendar_feed_fetches
      (subscription_id, user_agent, if_none_match, if_modified_since, forwarded_for)
    values (v_subscription_id, left(nullif(trim(p_user_agent), ''), 512),
      p_if_none_match is not null, p_if_modified_since is not null,
      left(nullif(trim(p_forwarded_for), ''), 512));
  end if;
  return v_staff_member_id;
end;
$$;
revoke all on function public.record_calendar_feed_fetch(text, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.record_calendar_feed_fetch(text, text, text, text, text)
  to service_role;
