-- Disconnected subscriptions remain visible while their calendar banner lives.
create function public.list_disconnected_calendar_subscriptions()
returns table (id uuid, name text, revoked_at timestamptz,
  last_fetched_at timestamptz, fetching_user_agent text)
language sql stable security definer set search_path = '' as $$
  select token.id, token.name, token.revoked_at,
    token.last_fetched_at, token.fetching_user_agent
  from public.calendar_feed_tokens token
  join public.staff_accounts account on account.staff_member_id = token.staff_member_id
  join public.staff_members member on member.id = token.staff_member_id
  where account.auth_user_id = auth.uid()
    and account.revoked_at is null and member.active
    and token.revoked_at is not null
    and token.revoked_at > now() - interval '1 year'
  order by token.revoked_at desc
$$;
revoke all on function public.list_disconnected_calendar_subscriptions() from public;
grant execute on function public.list_disconnected_calendar_subscriptions() to authenticated;
