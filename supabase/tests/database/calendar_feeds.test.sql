begin;
create extension if not exists pgtap with schema extensions;
select plan(33);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000501', 'feed-one@example.test'),
  ('00000000-0000-0000-0000-000000000502', 'feed-two@example.test');
insert into public.sections (id, name, display_order) values
  ('00000000-0000-0000-0000-000000000503', 'Feed test Section', 99);
insert into public.staff_members (id, display_name) values
  ('00000000-0000-0000-0000-000000000504', 'First Staff member'),
  ('00000000-0000-0000-0000-000000000505', 'Second Staff member');
insert into public.staff_accounts
  (staff_member_id, auth_user_id, personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000000504', '00000000-0000-0000-0000-000000000501', 'feed-one@example.test', now()),
  ('00000000-0000-0000-0000-000000000505', '00000000-0000-0000-0000-000000000502', 'feed-two@example.test', now());
insert into public.schedule_months
  (id, month_start, release_state, released_at, released_by_staff_member_id)
values
  ('00000000-0000-0000-0000-000000000506', '2027-01-01', 'released', now(), '00000000-0000-0000-0000-000000000504'),
  ('00000000-0000-0000-0000-000000000507', '2027-02-01', 'unpublished', null, null);
insert into public.schedule_cells
  (schedule_month_id, staff_member_id, section_id, work_date, shift_code) values
  ('00000000-0000-0000-0000-000000000506', '00000000-0000-0000-0000-000000000504', '00000000-0000-0000-0000-000000000503', '2027-01-04', '7A'),
  ('00000000-0000-0000-0000-000000000506', '00000000-0000-0000-0000-000000000504', '00000000-0000-0000-0000-000000000503', '2027-01-05', '7P'),
  ('00000000-0000-0000-0000-000000000506', '00000000-0000-0000-0000-000000000504', '00000000-0000-0000-0000-000000000503', '2027-01-06', 'X'),
  ('00000000-0000-0000-0000-000000000506', '00000000-0000-0000-0000-000000000504', '00000000-0000-0000-0000-000000000503', '2027-01-07', 'R/O'),
  ('00000000-0000-0000-0000-000000000506', '00000000-0000-0000-0000-000000000504', '00000000-0000-0000-0000-000000000503', '2027-01-08', '4P-8A'),
  ('00000000-0000-0000-0000-000000000506', '00000000-0000-0000-0000-000000000505', '00000000-0000-0000-0000-000000000503', '2027-01-04', 'D'),
  ('00000000-0000-0000-0000-000000000507', '00000000-0000-0000-0000-000000000504', '00000000-0000-0000-0000-000000000503', '2027-02-01', 'D');

create temp table feed_secrets (old_token text, new_token text, old_id uuid);
grant select, insert, update on feed_secrets to authenticated, service_role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000501","role":"authenticated"}', true);
select is((select count(*)::integer from public.list_calendar_subscriptions()), 0,
  'new Staff member has no subscriptions');
insert into feed_secrets (old_token, old_id)
select result->>'token', (result->>'id')::uuid
from (select public.create_calendar_subscription('iPhone') result) created;
select is((select name from public.list_calendar_subscriptions()), 'iPhone',
  'Staff member names a subscription');
select throws_ok(
  $$select public.calendar_feed_events('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')$$,
  '42501', null, 'Staff cannot call the privileged feed query');

set local role service_role;
select is((select public.calendar_feed_owner(old_token) from feed_secrets),
  '00000000-0000-0000-0000-000000000504'::uuid,
  'token resolves only to its owner');
select is((select count(*)::integer from feed_secrets,
  lateral public.calendar_feed_events(old_token)), 3,
  'working shifts appear, off days and R/O and unpublished month do not');
select is((select count(distinct event.staff_member_id)::integer from feed_secrets,
  lateral public.calendar_feed_events(old_token) event), 1,
  'feed token does not serve another Staff member');
select is((select starts_at from feed_secrets,
  lateral public.calendar_feed_events(old_token) where work_date = '2027-01-04'),
  '2027-01-04 12:00:00+00'::timestamptz,
  'day shift uses legend hours in Eastern time');
select is((select ends_at from feed_secrets,
  lateral public.calendar_feed_events(old_token) where work_date = '2027-01-05'),
  '2027-01-06 12:00:00+00'::timestamptz,
  'night shift ends the next day');
select is((select starts_at is null and ends_at is null from feed_secrets,
  lateral public.calendar_feed_events(old_token) where work_date = '2027-01-08'),
  true, 'off-legend code is all day');
select is((select sequence from feed_secrets,
  lateral public.calendar_feed_events(old_token) where work_date = '2027-01-04'),
  0::bigint, 'initial event sequence is zero');
select is((select updated_at from feed_secrets,
  lateral public.calendar_feed_events(old_token) where work_date = '2027-01-04'),
  (select updated_at from public.schedule_cells where staff_member_id =
    '00000000-0000-0000-0000-000000000504' and work_date = '2027-01-04'),
  'event carries its cell modification timestamp');
delete from public.schedule_cells
where staff_member_id = '00000000-0000-0000-0000-000000000505';
insert into public.calendar_feed_tokens (staff_member_id, name, token_hash)
values ('00000000-0000-0000-0000-000000000505', 'Empty feed',
  encode(sha256(decode(repeat('b', 64), 'hex')), 'hex'));
select is(public.calendar_feed_last_modified(repeat('b', 64)),
  (select created_at from public.calendar_feed_tokens where staff_member_id =
    '00000000-0000-0000-0000-000000000505'),
  'empty feed uses its stable token creation time');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000501","role":"authenticated"}', true);
update feed_secrets set new_token =
  (public.create_calendar_subscription('Google')->>'token');
select is((select count(*)::integer from public.list_calendar_subscriptions()), 2,
  'Staff member can have two subscriptions');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000502","role":"authenticated"}', true);
select is((select string_agg(name, ',') from public.list_calendar_subscriptions()),
  'Empty feed', 'another Staff member sees only their own subscription');
select throws_ok(
  $$select public.revoke_calendar_subscription((select old_id from feed_secrets))$$,
  'Calendar subscription not found',
  'another Staff member cannot revoke this subscription');
set local role service_role;
select is((select public.calendar_feed_owner(old_token) from feed_secrets),
  '00000000-0000-0000-0000-000000000504'::uuid,
  'creating another subscription leaves the first active');
select is((select count(*)::integer from feed_secrets,
  lateral public.calendar_feed_events(new_token)), 3,
  'new token serves current shifts');
update public.calendar_feed_tokens
set measure_fetches_until = now() + interval '8 days'
where id = (select old_id from feed_secrets);
select is((select public.record_calendar_feed_fetch(old_token, 'Test Calendar/1.0',
  '"etag"', null, '192.0.2.10')
  from feed_secrets), '00000000-0000-0000-0000-000000000504'::uuid,
  'valid fetch records its owner');
select is((select count(*)::integer from public.calendar_feed_fetches
  where subscription_id = (select old_id from feed_secrets)), 1,
  'each valid fetch has a history row');
select is((select if_none_match from public.calendar_feed_fetches
  where subscription_id = (select old_id from feed_secrets)), true,
  'ETag request is recorded');
select is((select forwarded_for from public.calendar_feed_fetches
  where subscription_id = (select old_id from feed_secrets)), '192.0.2.10',
  'forwarded source address is recorded');
select is((select public.record_calendar_feed_fetch(repeat('a', 64), null,
  null, null, null)), null::uuid, 'unknown tokens are not recorded');
select ok((select last_fetched_at is not null from public.calendar_feed_tokens
  where id = (select old_id from feed_secrets)),
  'fetch time is recorded on the fetched subscription');
select is((select fetching_user_agent from public.calendar_feed_tokens
  where id = (select old_id from feed_secrets)), 'Test Calendar/1.0',
  'fetching user-agent is recorded on the fetched subscription');
select is((select last_fetched_at from public.calendar_feed_tokens
  where token_hash = encode(sha256(decode((select new_token from feed_secrets), 'hex')), 'hex')),
  null::timestamptz, 'other subscription remains unchecked');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000501","role":"authenticated"}', true);
select public.revoke_calendar_subscription((select old_id from feed_secrets));
select is((select count(*)::integer from public.list_calendar_subscriptions()), 1,
  'revoking one subscription leaves the other listed');
set local role service_role;
select is((select public.calendar_feed_owner(old_token) from feed_secrets), null::uuid,
  'revoked subscription stops serving its feed');
select is((select public.calendar_feed_owner(new_token) from feed_secrets),
  '00000000-0000-0000-0000-000000000504'::uuid,
  'other subscription keeps serving its feed');
reset role;
update public.schedule_cells set shift_code = 'D'
where staff_member_id = '00000000-0000-0000-0000-000000000504'
  and work_date = '2027-01-04';
insert into public.schedule_changes (schedule_month_id, staff_member_id, section_id,
  work_date, old_shift_code, new_shift_code, changed_by_staff_member_id)
values ('00000000-0000-0000-0000-000000000506',
  '00000000-0000-0000-0000-000000000504',
  '00000000-0000-0000-0000-000000000503', '2027-01-04', '7A', 'D',
  '00000000-0000-0000-0000-000000000504');
set local role service_role;
select is((select ends_at from feed_secrets,
  lateral public.calendar_feed_events(new_token) where work_date = '2027-01-04'),
  '2027-01-04 20:00:00+00'::timestamptz,
  'feed reflects a saved Schedule change');
select is((select sequence from feed_secrets,
  lateral public.calendar_feed_events(new_token) where work_date = '2027-01-04'),
  1::bigint, 'event sequence counts Schedule changes');

reset role;
update public.schedule_cells
set shift_code = 'X', updated_at = '2028-01-01 00:00:00+00'
where staff_member_id = '00000000-0000-0000-0000-000000000504'
  and work_date in ('2027-01-04', '2027-01-05', '2027-01-08');
set local role service_role;
select is((select count(*)::integer from feed_secrets,
  lateral public.calendar_feed_events(new_token)), 0,
  'clearing the final working shifts leaves an empty feed');
select is((select public.calendar_feed_last_modified(new_token) from feed_secrets),
  '2028-01-01 00:00:00+00'::timestamptz,
  'cleared shifts advance the feed timestamp even when no event remains');

reset role;
update public.staff_members set active = false
where id = '00000000-0000-0000-0000-000000000504';
set local role service_role;
select is((select public.calendar_feed_owner(new_token) from feed_secrets), null::uuid,
  'deactivation revokes the feed immediately');

select * from finish();
rollback;
