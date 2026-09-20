begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

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

create temp table feed_secrets (old_token text, new_token text);
grant select, insert, update on feed_secrets to authenticated, service_role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000501","role":"authenticated"}', true);
select is(public.has_calendar_feed(), false, 'new Staff member has no feed yet');
insert into feed_secrets (old_token) select public.reset_calendar_feed();
select is(public.has_calendar_feed(), true, 'Staff member creates a feed');
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

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000501","role":"authenticated"}', true);
update feed_secrets set new_token = public.reset_calendar_feed();
set local role service_role;
select is((select public.calendar_feed_owner(old_token) from feed_secrets), null::uuid,
  'reset revokes old token');
select is((select count(*)::integer from feed_secrets,
  lateral public.calendar_feed_events(new_token)), 3,
  'new token serves current shifts');
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
