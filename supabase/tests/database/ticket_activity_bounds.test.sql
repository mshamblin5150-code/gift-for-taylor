begin;
create extension if not exists pgtap with schema extensions;
select plan(27);

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000003671', 'maintainer-367@example.test'),
  ('00000000-0000-0000-0000-000000003672', 'sender-367@example.test'),
  ('00000000-0000-0000-0000-000000003673', 'hourly-367@example.test'),
  ('00000000-0000-0000-0000-000000003674', 'daily-367@example.test'),
  ('00000000-0000-0000-0000-000000003675', 'no-notice-367@example.test');

insert into public.staff_members(id, display_name, role) values
  ('10000000-0000-0000-0000-000000003671', 'Maintainer Nurse', 'staff_member'),
  ('10000000-0000-0000-0000-000000003672', 'Sender Nurse', 'staff_member'),
  ('10000000-0000-0000-0000-000000003673', 'Hourly Nurse', 'staff_member'),
  ('10000000-0000-0000-0000-000000003674', 'Daily Nurse', 'staff_member'),
  ('10000000-0000-0000-0000-000000003675', 'No-notice Nurse', 'staff_member');

insert into public.staff_accounts(
  staff_member_id, auth_user_id, personal_email, accepted_invite_at
) values
  ('10000000-0000-0000-0000-000000003671', '00000000-0000-0000-0000-000000003671', 'maintainer-367@example.test', now()),
  ('10000000-0000-0000-0000-000000003672', '00000000-0000-0000-0000-000000003672', 'sender-367@example.test', now()),
  ('10000000-0000-0000-0000-000000003673', '00000000-0000-0000-0000-000000003673', 'hourly-367@example.test', now()),
  ('10000000-0000-0000-0000-000000003674', '00000000-0000-0000-0000-000000003674', 'daily-367@example.test', now()),
  ('10000000-0000-0000-0000-000000003675', '00000000-0000-0000-0000-000000003675', 'no-notice-367@example.test', now());

insert into private.maintainer_identity(auth_user_id)
values ('00000000-0000-0000-0000-000000003671');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003672","role":"authenticated"}',
  true);

select lives_ok($$select public.put_in_ticket(
  'problem', 'The Save button did not work.', 'Schedule', '2026-09-01',
  'abc1234', 'Chrome on Windows', now())$$,
  'a new Ticket is accepted');

set local role postgres;
select is((select count(*)::integer from public.staff_notices
  where kind = 'ticket_activity'), 1,
  'a new Ticket raises one Maintainer notice');
select is((select title from public.staff_notices
  where kind = 'ticket_activity'), '1 new Ticket',
  'the first activity notice names one Ticket');
select ok((select push_eligible from public.staff_notices
  where kind = 'ticket_activity'),
  'the first activity notice is eligible for push');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003672","role":"authenticated"}',
  true);
select is(
  public.put_in_ticket(
    'problem', '  The Save button did not work.  ', 'Schedule', '2026-09-01',
    'abc1234', 'Chrome on Windows', now()),
  (select id from public.tickets),
  'a duplicate within five minutes returns the existing Ticket');

set local role postgres;
select is((select count(*)::integer from public.tickets
  where sender_id = '10000000-0000-0000-0000-000000003672'), 1,
  'a duplicate does not insert another Ticket');
select is((select count(*)::integer from public.staff_notices
  where kind = 'ticket_activity'), 1,
  'a duplicate does not add Ticket activity');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003672","role":"authenticated"}',
  true);
select lives_ok($$select public.put_in_ticket(
  'idea', 'Please add a week view.', 'Schedule', '2026-09-01',
  'abc1234', 'Chrome on Windows', now())$$,
  'different Ticket activity is accepted');

set local role postgres;
select is((select count(*)::integer from public.staff_notices
  where kind = 'ticket_activity'), 1,
  'unread Ticket activity updates the existing notice');
select is((select title from public.staff_notices
  where kind = 'ticket_activity'), '2 new Tickets',
  'the combined notice reports the burst count');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003671","role":"authenticated"}',
  true);
select lives_ok($$select public.mark_staff_notice_read(
  (select id from public.staff_notices where kind = 'ticket_activity'))$$,
  'the Maintainer can read the combined activity notice');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003672","role":"authenticated"}',
  true);
select lives_ok($$select public.put_in_ticket(
  'question', 'Where is next month?', 'Schedule', '2026-09-01',
  'abc1234', 'Chrome on Windows', now())$$,
  'new activity after reading is accepted');

set local role postgres;
select is((select count(*)::integer from public.staff_notices
  where kind = 'ticket_activity'), 2,
  'activity after reading inserts a new notice for another push');
select is((select title from public.staff_notices
  where kind = 'ticket_activity' and read_at is null), '1 new Ticket',
  'the new unread notice starts a fresh burst');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003673","role":"authenticated"}',
  true);
select is((select count(public.put_in_ticket(
  'problem', 'Hourly Ticket ' || n::text, 'Schedule', null,
  'abc1234', 'Chrome on Windows', now()))::integer
  from generate_series(1, 5) n), 5,
  'five Tickets in an hour are accepted');
select throws_ok($$select public.put_in_ticket(
  'problem', 'Hourly Ticket 6', 'Schedule', null,
  'abc1234', 'Chrome on Windows', now())$$,
  'P2845', 'You have sent a lot today; the designer will see them all',
  'the sixth Ticket in an hour has a stable friendly refusal');

set local role postgres;
insert into public.tickets(
  sender_id, sender_display_name, kind, text, screen_context,
  release_id, device_context, context_captured_at, created_at,
  recent_actions
)
select '10000000-0000-0000-0000-000000003674', 'Daily Nurse', 'problem',
  'Daily Ticket ' || n::text, 'Schedule', 'abc1234',
  'Chrome on Windows', now(), clock_timestamp() - n * interval '70 minutes',
  array['Screen: Schedule']
from generate_series(1, 20) n;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003674","role":"authenticated"}',
  true);
select throws_ok($$select public.put_in_ticket(
  'idea', 'Daily Ticket 21', 'Schedule', null,
  'abc1234', 'Chrome on Windows', now())$$,
  'P2845', 'You have sent a lot today; the designer will see them all',
  'the twenty-first Ticket in twenty-four hours has the same refusal');

set local role postgres;
update public.staff_notices set read_at = clock_timestamp()
where kind = 'ticket_activity' and read_at is null;
update public.tickets set
  state = 'done',
  seen_at = clock_timestamp(),
  seen_by_auth_user_id = '00000000-0000-0000-0000-000000003671',
  close_reason = 'The fix is live.',
  closed_at = clock_timestamp(),
  closed_by_auth_user_id = '00000000-0000-0000-0000-000000003671'
where sender_id = '10000000-0000-0000-0000-000000003672'
  and text = 'The Save button did not work.';

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003672","role":"authenticated"}',
  true);
select lives_ok($$select public.reopen_ticket(
  (select id from public.tickets where text = 'The Save button did not work.'),
  'The same problem happened again.')$$,
  'a sender can reopen a Ticket');

set local role postgres;
select is((select count(*)::integer from public.staff_notices
  where kind = 'ticket_activity' and read_at is null), 1,
  'reopening raises Ticket activity');
select is((select title from public.staff_notices
  where kind = 'ticket_activity' and read_at is null), '1 new Ticket',
  'reopening starts a one-Ticket burst');
update public.staff_notices set read_at = clock_timestamp()
where kind = 'ticket_activity' and read_at is null;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003671","role":"authenticated"}',
  true);
select lives_ok($$select public.open_ticket_for_maintainer(
  (select id from public.tickets where text = 'Please add a week view.'))$$,
  'the Maintainer can open the Ticket used for a reply');
select lives_ok($$select public.ask_ticket_question(
  (select id from public.tickets where text = 'Please add a week view.'),
  'Would a seven-day strip work?', null)$$,
  'the Maintainer can ask its sender a question');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003672","role":"authenticated"}',
  true);
select lives_ok($$select public.answer_ticket_question(
  (select id from public.tickets where text = 'Please add a week view.'),
  (select id from public.ticket_thread_entries
    where text = 'Would a seven-day strip work?'),
  'Yes, that would work.', false)$$,
  'the sender can reply to the Maintainer');

set local role postgres;
select is((select count(*)::integer from public.staff_notices
  where kind = 'ticket_activity' and read_at is null), 1,
  'a sender reply raises Ticket activity');
update public.staff_notices set read_at = clock_timestamp()
where kind = 'ticket_activity' and read_at is null;
delete from public.staff_accounts
where staff_member_id = '10000000-0000-0000-0000-000000003671';

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003675","role":"authenticated"}',
  true);
select lives_ok($$select public.put_in_ticket(
  'problem', 'This Ticket has nobody to push to.', 'Schedule', null,
  'abc1234', 'Chrome on Windows', now())$$,
  'a Ticket still stands when the Maintainer has no Staff account');

set local role postgres;
select is((select count(*)::integer from public.tickets
  where sender_id = '10000000-0000-0000-0000-000000003675'), 1,
  'the Ticket is retained without a Maintainer Staff row');
select is((select count(*)::integer from public.staff_notices
  where kind = 'ticket_activity' and read_at is null), 0,
  'no activity notice is created when there is nobody to push to');

select * from finish();
rollback;
