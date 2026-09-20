begin;
create extension if not exists pgtap with schema extensions;
select plan(20);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000981', 'calendar@example.test');
insert into public.sections (id, name, display_order) values
  ('00000000-0000-0000-0000-000000000982', 'Calendar Section', 99);
insert into public.staff_members (id, display_name) values
  ('00000000-0000-0000-0000-000000000983', 'Calendar Staff');
insert into public.staff_accounts
  (staff_member_id, auth_user_id, personal_email, accepted_invite_at)
values ('00000000-0000-0000-0000-000000000983',
  '00000000-0000-0000-0000-000000000981', 'calendar@example.test', now());
insert into public.schedule_months
  (id, month_start, release_state, released_at, released_by_staff_member_id)
values ('00000000-0000-0000-0000-000000000984', '2027-04-01',
  'released', now(), '00000000-0000-0000-0000-000000000983');
insert into public.schedule_cells
  (schedule_month_id, staff_member_id, section_id, work_date, shift_code)
values
  ('00000000-0000-0000-0000-000000000984', '00000000-0000-0000-0000-000000000983',
   '00000000-0000-0000-0000-000000000982', '2027-04-04', '7A'),
  ('00000000-0000-0000-0000-000000000984', '00000000-0000-0000-0000-000000000983',
   '00000000-0000-0000-0000-000000000982', '2027-04-05', 'X');
select is((select count(*)::int from public.calendar_invitation_outbox), 1,
  'only the working released shift queues an invitation');
select is((select method from public.calendar_invitation_outbox), 'REQUEST',
  'first event requests the shift');
select is((select sequence from public.calendar_invitation_outbox), 0,
  'first event starts at sequence zero');

update public.schedule_cells set shift_code = '7P' where work_date = '2027-04-04';
select is((select sequence from public.calendar_invitation_outbox
  where superseded_at is null), 1, 'edit increments the sequence');
select ok((select newer.last_modified > older.last_modified
  from public.calendar_invitation_outbox newer
  join public.calendar_invitation_outbox older
    on older.staff_member_id = newer.staff_member_id
    and older.work_date = newer.work_date and older.sequence = 0
  where newer.sequence = 1),
  'edited invitation advances LAST-MODIFIED even within the same second');
select is((select starts_at from public.calendar_invitation_outbox
  where superseded_at is null), '2027-04-04 23:00:00+00'::timestamptz,
  'edited night shift uses current Shift code hours');
update public.schedule_cells set shift_code = 'X' where work_date = '2027-04-04';
select is((select method from public.calendar_invitation_outbox
  where superseded_at is null), 'CANCEL', 'removed shift is withdrawn');
select is((select sequence from public.calendar_invitation_outbox
  where superseded_at is null), 2, 'cancellation increments the sequence');

update public.schedule_cells set shift_code = '7A' where work_date = '2027-04-04';
create temp table calendar_token (token text);
grant select, insert on calendar_token to authenticated, service_role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000981","role":"authenticated"}', true);
insert into calendar_token select public.create_calendar_subscription('iPhone')->>'token';
select is(public.my_calendar_channel(), 'feed',
  'Staff can choose the feed channel');
set local role service_role;
select is((select count(*)::int from calendar_token token,
  lateral public.calendar_feed_events(token.token)), 1,
  'feed serves the current shift after switching');
select is((select method from public.calendar_invitation_outbox
  where superseded_at is null), 'CANCEL',
  'switching to feed withdraws invitations');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000981","role":"authenticated"}', true);
select public.use_calendar_invitations();
set local role service_role;
select is((select public.calendar_feed_owner(token) from calendar_token),
  null::uuid, 'switching back revokes the feed token');
select is((select method from public.calendar_invitation_outbox
  where superseded_at is null), 'REQUEST',
  'switching back requests current shifts');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000981","role":"authenticated"}', true);
select throws_ok('select * from public.calendar_invitation_outbox',
  '42501', null, 'Staff cannot read invitation delivery rows');
set local role postgres;

insert into public.schedule_months (id, month_start) values
  ('00000000-0000-0000-0000-000000000985', '2027-05-01');
insert into public.schedule_cells
  (schedule_month_id, staff_member_id, section_id, work_date, shift_code)
values ('00000000-0000-0000-0000-000000000985',
  '00000000-0000-0000-0000-000000000983',
  '00000000-0000-0000-0000-000000000982', '2027-05-04', '7A');
update public.schedule_months set release_state = 'released', released_at = now(),
  released_by_staff_member_id = '00000000-0000-0000-0000-000000000983'
where id = '00000000-0000-0000-0000-000000000985';
select is((select count(*)::int from public.calendar_invitation_outbox
  where work_date = '2027-05-04' and method = 'REQUEST'), 1,
  'Month release queues the unpublished working shift once');
update public.shift_codes set is_working = false where code = '7A';
select is((select method from public.calendar_invitation_outbox
  where work_date = '2027-05-04' and superseded_at is null), 'CANCEL',
  'making a Shift code nonworking withdraws released shifts');
insert into public.schedule_cells
  (schedule_month_id, staff_member_id, section_id, work_date, shift_code)
values ('00000000-0000-0000-0000-000000000985',
  '00000000-0000-0000-0000-000000000983',
  '00000000-0000-0000-0000-000000000982', '2027-05-05', 'D');
delete from public.schedule_cells where work_date = '2027-05-05';
select is((select method from public.calendar_invitation_outbox
  where work_date = '2027-05-05' and superseded_at is null), 'CANCEL',
  'deleting a released working cell withdraws its invitation');

create temp table named_subscriptions (id uuid);
grant select, insert on named_subscriptions to authenticated;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000981","role":"authenticated"}', true);
insert into named_subscriptions
  select (public.create_calendar_subscription('iPhone') ->> 'id')::uuid;
insert into named_subscriptions
  select (public.create_calendar_subscription('Google') ->> 'id')::uuid;
select is((select count(*)::int from public.list_calendar_subscriptions()), 2,
  'one Staff member may hold two named Calendar subscriptions');
select public.revoke_calendar_subscription((select id from named_subscriptions
  order by id limit 1));
select is(public.my_calendar_channel(), 'feed',
  'revoking one subscription leaves the other feed active');
select public.revoke_calendar_subscription((select id from named_subscriptions
  order by id desc limit 1));
select is(public.my_calendar_channel(), 'invitations',
  'revoking the last subscription restores invitations');

select * from finish();
rollback;
