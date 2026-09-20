-- Fetch metadata, subscription state, events, and validator share one statement
-- snapshot. Keep the older RPCs for the Edge Function deployed before this one.
create function public.calendar_feed_state(
  p_token text,
  p_user_agent text,
  p_if_none_match text,
  p_if_modified_since text,
  p_forwarded_for text
) returns jsonb
language sql volatile security definer set search_path = '' as $$
  with fetched as (
    update public.calendar_feed_tokens token
    set last_fetched_at = now(),
        fetching_user_agent = left(nullif(trim(p_user_agent), ''), 512)
    where token.token_hash = case when p_token ~ '^[0-9a-f]{64}$'
      then encode(sha256(decode(p_token, 'hex')), 'hex') end
    returning token.id, token.staff_member_id, token.revoked_at,
      token.created_at, token.measure_fetches_until
  ), measured as (
    insert into public.calendar_feed_fetches
      (subscription_id, user_agent, if_none_match, if_modified_since, forwarded_for)
    select id, left(nullif(trim(p_user_agent), ''), 512),
      p_if_none_match is not null, p_if_modified_since is not null,
      left(nullif(trim(p_forwarded_for), ''), 512)
    from fetched where measure_fetches_until > now()
  ), subscription as (
    select fetched.*, member.active, member.calendar_channel,
      case when fetched.revoked_at is null and member.active then 'live'
        when not member.active then 'ended'
        when member.calendar_channel = 'invitations' then 'invitations'
        else 'feed' end as state
    from fetched
    join public.staff_members member on member.id = fetched.staff_member_id
  )
  select jsonb_build_object(
    'state', subscription.state,
    'subscription_id', subscription.id,
    'staff_member_id', subscription.staff_member_id,
    'revoked_at', subscription.revoked_at,
    'last_modified', case when subscription.state = 'live'
      then coalesce(modified.latest, subscription.created_at)
      else subscription.revoked_at end,
    'events', coalesce(events.items, '[]'::jsonb)
  )
  from subscription
  cross join lateral (
    select max(greatest(cell.updated_at, month.released_at)) as latest
    from public.schedule_cells cell
    join public.schedule_months month on month.id = cell.schedule_month_id
    where cell.staff_member_id = subscription.staff_member_id
      and month.release_state = 'released'
  ) modified
  cross join lateral (
    select jsonb_agg(jsonb_build_object(
      'staff_member_id', subscription.staff_member_id,
      'work_date', cell.work_date,
      'shift_code', cell.shift_code,
      'starts_at', case when code.start_time is not null then
        (cell.work_date + code.start_time) at time zone 'America/New_York' end,
      'ends_at', case when code.end_time is not null then
        (cell.work_date + code.end_time +
          case when code.end_time <= code.start_time
            then interval '1 day' else interval '0 day' end)
          at time zone 'America/New_York' end,
      'updated_at', cell.updated_at,
      'sequence', (select count(*) from public.schedule_changes change
        where change.staff_member_id = subscription.staff_member_id
          and change.work_date = cell.work_date)
    ) order by cell.work_date) as items
    from public.schedule_cells cell
    join public.schedule_months month on month.id = cell.schedule_month_id
    left join public.shift_codes code on code.code = upper(trim(cell.shift_code))
    where cell.staff_member_id = subscription.staff_member_id
      and month.release_state = 'released'
      and public.is_working_shift(cell.shift_code)
      and (subscription.state = 'live' or cell.work_date <=
        (subscription.revoked_at at time zone 'America/New_York')::date)
  ) events;
$$;
revoke all on function public.calendar_feed_state(text,text,text,text,text)
  from public, anon, authenticated;
grant execute on function public.calendar_feed_state(text,text,text,text,text)
  to service_role;
