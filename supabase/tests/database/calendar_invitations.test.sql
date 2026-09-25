begin;
set local timezone = 'America/New_York';
create extension if not exists pgtap with schema extensions;
select plan(51);

-- The account lifecycle and channel switches are the public seam for the date
-- bound. Yesterday is deliberately dynamic so this exercises the exact edge.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000971', 'bounded@example.test');
insert into public.sections (id, name, display_order) values
  ('00000000-0000-0000-0000-000000000972', 'Bounded Calendar Section', 98);
insert into public.staff_members (id, display_name) values
  ('00000000-0000-0000-0000-000000000973', 'Bounded Calendar Staff');
insert into public.schedule_months
  (id, month_start, release_state, released_at,
   released_by_staff_member_id)
values
  ('00000000-0000-0000-0000-000000000974',
   (date_trunc('month', current_date) - interval '1 month')::date,
   'released', now(), '00000000-0000-0000-0000-000000000973'),
  ('00000000-0000-0000-0000-000000000975',
   date_trunc('month', current_date)::date,
   'released', now(), '00000000-0000-0000-0000-000000000973'),
  ('00000000-0000-0000-0000-000000000976',
   (date_trunc('month', current_date) + interval '1 month')::date,
   'released', now(), '00000000-0000-0000-0000-000000000973');
insert into public.schedule_cells
  (schedule_month_id, staff_member_id, section_id, work_date, shift_code)
values
  ('00000000-0000-0000-0000-000000000974',
   '00000000-0000-0000-0000-000000000973',
   '00000000-0000-0000-0000-000000000972',
   (date_trunc('month', current_date) - interval '1 month' + interval '1 day')::date,
   '7A'),
  ('00000000-0000-0000-0000-000000000975',
   '00000000-0000-0000-0000-000000000973',
   '00000000-0000-0000-0000-000000000972', current_date, '7A'),
  ('00000000-0000-0000-0000-000000000976',
   '00000000-0000-0000-0000-000000000973',
   '00000000-0000-0000-0000-000000000972',
   (date_trunc('month', current_date) + interval '1 month' + interval '1 day')::date,
   '7A');
insert into public.staff_accounts
  (staff_member_id, auth_user_id, personal_email, accepted_invite_at)
values ('00000000-0000-0000-0000-000000000973',
  '00000000-0000-0000-0000-000000000971', 'bounded@example.test', now());
select is((select count(*)::int from public.calendar_invitation_outbox
  where staff_member_id = '00000000-0000-0000-0000-000000000973'
    and method = 'REQUEST'), 2,
  'account completion requests only work today and later');
select is((select count(*)::int from public.calendar_invitation_outbox
  where staff_member_id = '00000000-0000-0000-0000-000000000973'
    and work_date < current_date), 0,
  'account completion never requests work already performed');
select is((select count(*)::int from public.calendar_invitation_outbox
  where staff_member_id = '00000000-0000-0000-0000-000000000973'
    and work_date = current_date), 1,
  'the REQUEST bound includes work today');
update public.schedule_cells set shift_code = '7P'
where staff_member_id = '00000000-0000-0000-0000-000000000973'
  and work_date < current_date;
select is((select count(*)::int from public.calendar_invitation_outbox
  where staff_member_id = '00000000-0000-0000-0000-000000000973'
    and work_date < current_date), 0,
  'editing a released historical cell cannot bypass the REQUEST bound');

-- Model a past invitation that really was published before the bound existed.
insert into public.calendar_invitation_outbox
  (staff_member_id, work_date, recipient, method, shift_code, starts_at,
   ends_at, sequence, sent_at, sender)
values ('00000000-0000-0000-0000-000000000973',
  (date_trunc('month', current_date) - interval '1 month' + interval '1 day')::date,
  'bounded@example.test', 'REQUEST', '7A',
  ((date_trunc('month', current_date) - interval '1 month' + interval '1 day')::date
    + time '07:00') at time zone 'America/New_York',
  ((date_trunc('month', current_date) - interval '1 month' + interval '1 day')::date
    + time '19:00') at time zone 'America/New_York',
  0, now(), 'no-reply@calendar.axion.healthcare');
create temp table bounded_calendar_token (token text);
grant select, insert on bounded_calendar_token to authenticated;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000971","role":"authenticated"}', true);
insert into bounded_calendar_token
  select public.create_calendar_subscription('Bound test')->>'token';
set local role postgres;
select is((select count(*)::int from (
    select distinct on (work_date) method
    from public.calendar_invitation_outbox
    where staff_member_id = '00000000-0000-0000-0000-000000000973'
    order by work_date, sequence desc
  ) latest where method = 'CANCEL'), 3,
  'switching to the Calendar feed withdraws every published date, including history');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000971","role":"authenticated"}', true);
select public.use_calendar_invitations();
set local role postgres;
select is((select count(*)::int from (
    select distinct on (work_date) work_date, method
    from public.calendar_invitation_outbox
    where staff_member_id = '00000000-0000-0000-0000-000000000973'
    order by work_date, sequence desc
  ) latest where work_date >= current_date and method = 'REQUEST'), 2,
  'switching back requests only work today and later');
select is((select method from public.calendar_invitation_outbox
  where staff_member_id = '00000000-0000-0000-0000-000000000973'
    and work_date < current_date order by sequence desc limit 1), 'CANCEL',
  'switching back leaves published history withdrawn');

update public.staff_members set active = false
where id = '00000000-0000-0000-0000-000000000973';
select is((select count(*)::int from (
    select distinct on (work_date) method
    from public.calendar_invitation_outbox
    where staff_member_id = '00000000-0000-0000-0000-000000000973'
    order by work_date, sequence desc
  ) latest where method = 'CANCEL'), 3,
  'deactivation withdraws every invitation still published');
delete from public.calendar_invitation_outbox
where staff_member_id = '00000000-0000-0000-0000-000000000973';

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

set local role postgres;
insert into public.calendar_invitation_outbox
  (id, staff_member_id, work_date, recipient, method, shift_code, sequence)
values
  ('00000000-0000-0000-0000-000000000986',
   '00000000-0000-0000-0000-000000000983', '2027-06-01',
   'calendar@example.test', 'REQUEST', '7A', 0),
  ('00000000-0000-0000-0000-000000000987',
   '00000000-0000-0000-0000-000000000983', '2027-06-02',
   'calendar@example.test', 'REQUEST', '7A', 0);
create temp table claimed_delivery (id uuid, delivery_claim uuid);
grant select, insert, delete on claimed_delivery to service_role;
set local role service_role;
insert into claimed_delivery
  select id, delivery_claim from public.calendar_invitation_claim(
    '00000000-0000-0000-0000-000000000986');
select is((select count(*)::int from claimed_delivery), 1,
  'delivery claims the requested invitation');
select is((select delivery_attempts from public.calendar_invitation_outbox
  where id = '00000000-0000-0000-0000-000000000986'), 1,
  'claim records one bounded delivery attempt');
select is((select count(*)::int from public.calendar_invitation_claim(
  '00000000-0000-0000-0000-000000000986')), 0,
  'a claimed invitation cannot be claimed concurrently');
select public.calendar_invitation_failed(
  '00000000-0000-0000-0000-000000000986', gen_random_uuid());
select ok((select delivery_claim is not null
  from public.calendar_invitation_outbox
  where id = '00000000-0000-0000-0000-000000000986'),
  'a different worker cannot release the claim');
select public.calendar_invitation_failed(
  '00000000-0000-0000-0000-000000000986',
  (select delivery_claim from claimed_delivery));
delete from claimed_delivery;
insert into claimed_delivery
  select id, delivery_claim from public.calendar_invitation_claim(
    '00000000-0000-0000-0000-000000000986');
select is((select delivery_attempts from public.calendar_invitation_outbox
  where id = '00000000-0000-0000-0000-000000000986'), 2,
  'a released failed invitation can be claimed again');
select public.calendar_invitation_sending(
  '00000000-0000-0000-0000-000000000986',
  (select delivery_claim from claimed_delivery));
select public.calendar_invitation_sent(
  '00000000-0000-0000-0000-000000000986',
  (select delivery_claim from claimed_delivery));
select ok((select sent_at is not null and delivery_claim is null
  from public.calendar_invitation_outbox
  where id = '00000000-0000-0000-0000-000000000986'),
  'only the claiming worker marks the invitation sent');

delete from claimed_delivery;
insert into claimed_delivery select id, delivery_claim
  from public.calendar_invitation_claim('00000000-0000-0000-0000-000000000987');
select public.calendar_invitation_failed(
  '00000000-0000-0000-0000-000000000987',
  (select delivery_claim from claimed_delivery));
delete from claimed_delivery;
insert into claimed_delivery select id, delivery_claim
  from public.calendar_invitation_claim('00000000-0000-0000-0000-000000000987');
select public.calendar_invitation_failed(
  '00000000-0000-0000-0000-000000000987',
  (select delivery_claim from claimed_delivery));
delete from claimed_delivery;
insert into claimed_delivery select id, delivery_claim
  from public.calendar_invitation_claim('00000000-0000-0000-0000-000000000987');
select public.calendar_invitation_failed(
  '00000000-0000-0000-0000-000000000987',
  (select delivery_claim from claimed_delivery));
select is((select count(*)::int from public.calendar_invitation_claim(
  '00000000-0000-0000-0000-000000000987')), 0,
  'a failed invitation stops after three delivery attempts');

set local role postgres;
select vault.create_secret('test-calendar-secret', 'calendar_webhook_secret');
delete from net.http_request_queue;
update public.calendar_invitation_outbox set superseded_at = clock_timestamp()
where sent_at is null and superseded_at is null;
insert into public.calendar_invitation_outbox
  (id, staff_member_id, work_date, recipient, method, shift_code, sequence)
values
  ('00000000-0000-0000-0000-000000000988',
   '00000000-0000-0000-0000-000000000983', '2027-06-03',
   'calendar@example.test', 'REQUEST', '7A', 0),
  ('00000000-0000-0000-0000-000000000989',
   '00000000-0000-0000-0000-000000000983', '2027-06-04',
   'calendar@example.test', 'REQUEST', '7A', 0),
  ('00000000-0000-0000-0000-000000000990',
   '00000000-0000-0000-0000-000000000983', '2027-06-05',
   'calendar@example.test', 'REQUEST', '7A', 0);
select is((select count(*)::int from net.http_request_queue), 3,
  'three invitations queued together post three webhook requests');
select is((select count(distinct convert_from(body, 'UTF8')::jsonb ->> 'id')::int
  from net.http_request_queue), 3,
  'each burst webhook names one different invitation');

update public.calendar_invitation_outbox set superseded_at = clock_timestamp()
where id in ('00000000-0000-0000-0000-000000000988',
  '00000000-0000-0000-0000-000000000989',
  '00000000-0000-0000-0000-000000000990');
insert into public.calendar_invitation_outbox
  (id, staff_member_id, work_date, recipient, method, shift_code, sequence)
values ('00000000-0000-0000-0000-000000000991',
  '00000000-0000-0000-0000-000000000983', '2027-06-06',
  'calendar@example.test', 'REQUEST', '7A', 0);
delete from claimed_delivery;
set local role service_role;
insert into claimed_delivery select id, delivery_claim
  from public.calendar_invitation_claim('00000000-0000-0000-0000-000000000991');
select public.calendar_invitation_failed(
  '00000000-0000-0000-0000-000000000991',
  (select delivery_claim from claimed_delivery));
set local role postgres;
delete from net.http_request_queue;
select is(public.retry_calendar_invitation_deliveries(), 1,
  'the retry sweep posts one failed invitation');
select is((select count(*)::int from net.http_request_queue
  where convert_from(body, 'UTF8')::jsonb ->> 'id' =
    '00000000-0000-0000-0000-000000000991'), 1,
  'the retry sweep posts only that invitation id');

update public.calendar_invitation_outbox set superseded_at = clock_timestamp()
where id = '00000000-0000-0000-0000-000000000991';
insert into public.calendar_invitation_outbox
  (id, staff_member_id, work_date, recipient, method, shift_code, sequence)
values ('00000000-0000-0000-0000-000000000992',
  '00000000-0000-0000-0000-000000000983', '2027-06-07',
  'calendar@example.test', 'REQUEST', '7A', 0);
delete from claimed_delivery;
set local role service_role;
insert into claimed_delivery select id, delivery_claim
  from public.calendar_invitation_claim('00000000-0000-0000-0000-000000000992');
set local role postgres;
update public.calendar_invitation_outbox
  set delivery_claimed_at = clock_timestamp() - interval '6 minutes'
where id = '00000000-0000-0000-0000-000000000992';
delete from net.http_request_queue;
select is(public.retry_calendar_invitation_deliveries(), 1,
  'the retry sweep recovers one stale claim');
select is((select count(*)::int from net.http_request_queue
  where convert_from(body, 'UTF8')::jsonb ->> 'id' =
    '00000000-0000-0000-0000-000000000992'), 1,
  'the stale claim retry posts only that invitation id');
set local role service_role;
select is((select count(*)::int from public.calendar_invitation_claim(
  '00000000-0000-0000-0000-000000000992')), 1,
  'a stale claim can be reclaimed after the delivery timeout');

set local role postgres;
insert into public.calendar_invitation_outbox
  (id, staff_member_id, work_date, recipient, method, shift_code, sequence)
values ('00000000-0000-0000-0000-000000000993',
  '00000000-0000-0000-0000-000000000983', '2027-06-08',
  'calendar@example.test', 'REQUEST', '7A', 0);
delete from claimed_delivery;
set local role service_role;
insert into claimed_delivery select id, delivery_claim
  from public.calendar_invitation_claim('00000000-0000-0000-0000-000000000993');
select public.calendar_invitation_sending(
  '00000000-0000-0000-0000-000000000993',
  (select delivery_claim from claimed_delivery));
set local role postgres;
update public.calendar_invitation_outbox
  set delivery_claimed_at = clock_timestamp() - interval '6 minutes'
where id = '00000000-0000-0000-0000-000000000993';
delete from net.http_request_queue;
select is(public.retry_calendar_invitation_deliveries(), 0,
  'the retry sweep does not replay an uncertain send');
set local role service_role;
select is((select count(*)::int from public.calendar_invitation_claim(
  '00000000-0000-0000-0000-000000000993')), 0,
  'an uncertain send cannot be reclaimed automatically');

set local role postgres;
insert into public.schedule_months (id, month_start) values
  ('00000000-0000-0000-0000-000000000994', '2027-07-01');
insert into public.schedule_cells
  (schedule_month_id, staff_member_id, section_id, work_date, shift_code)
values
  ('00000000-0000-0000-0000-000000000994',
   '00000000-0000-0000-0000-000000000983',
   '00000000-0000-0000-0000-000000000982', '2027-07-04', 'D'),
  ('00000000-0000-0000-0000-000000000994',
   '00000000-0000-0000-0000-000000000983',
   '00000000-0000-0000-0000-000000000982', '2027-07-05', 'D');
delete from net.http_request_queue;
update public.schedule_months set release_state = 'released', released_at = now(),
  released_by_staff_member_id = '00000000-0000-0000-0000-000000000983'
where id = '00000000-0000-0000-0000-000000000994';
select is((select count(distinct batch_id)::int
  from public.calendar_invitation_outbox
  where work_date in ('2027-07-04', '2027-07-05')), 1,
  'a Month release stamps one batch across its invitation rows');
select is((select count(distinct (batch_id, recipient, method))::int
  from public.calendar_invitation_outbox
  where work_date in ('2027-07-04', '2027-07-05')), 1,
  'two released shifts for one Staff member produce one message');
select is((select count(*)::int from net.http_request_queue), 1,
  'a Month release posts one webhook for its batch');
delete from claimed_delivery;
set local role service_role;
insert into claimed_delivery select id, delivery_claim
from public.calendar_invitation_claim((select batch_id
  from public.calendar_invitation_outbox where work_date = '2027-07-04'));
select is((select count(*)::int from claimed_delivery), 2,
  'claiming a release batch claims every current shift in it');
select is((select count(distinct delivery_claim)::int from claimed_delivery), 1,
  'one claim token owns the release batch');
set local role postgres;
update public.schedule_cells set shift_code = '7A'
where work_date = '2027-07-04';
select ok((select batch_id is null and sequence = 1
  from public.calendar_invitation_outbox
  where work_date = '2027-07-04' and superseded_at is null),
  'a later single-shift REQUEST leaves the batch and advances its sequence');
set local role service_role;
select is((select count(*)::int
  from public.calendar_invitation_sending(
    (select batch_id from public.calendar_invitation_outbox
      where work_date = '2027-07-05'),
    'calendar@example.test', 'REQUEST',
    (select claimed.delivery_claim from claimed_delivery claimed
      join public.calendar_invitation_outbox event on event.id = claimed.id
      where event.work_date = '2027-07-05'))), 1,
  'send start returns only the still-current event from a claimed message');

select * from finish();
rollback;
