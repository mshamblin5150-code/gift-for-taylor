begin;
create extension if not exists pgtap with schema extensions;
select plan(20);

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000003661', 'maintainer-366@example.test'),
  ('00000000-0000-0000-0000-000000003662', 'manager-366@example.test'),
  ('00000000-0000-0000-0000-000000003665', 'sender-366@example.test'),
  ('00000000-0000-0000-0000-000000003666', 'other-366@example.test');

insert into public.staff_members(id, display_name, role) values
  ('10000000-0000-0000-0000-000000003661', 'Maintainer 366', 'staff_member'),
  ('10000000-0000-0000-0000-000000003662', 'Manager 366', 'manager'),
  ('10000000-0000-0000-0000-000000003665', 'Sender 366', 'staff_member'),
  ('10000000-0000-0000-0000-000000003666', 'Other 366', 'staff_member');

insert into public.staff_accounts(
  staff_member_id, auth_user_id, personal_email, accepted_invite_at
) values
  ('10000000-0000-0000-0000-000000003661', '00000000-0000-0000-0000-000000003661', 'maintainer-366@example.test', now()),
  ('10000000-0000-0000-0000-000000003662', '00000000-0000-0000-0000-000000003662', 'manager-366@example.test', now()),
  ('10000000-0000-0000-0000-000000003665', '00000000-0000-0000-0000-000000003665', 'sender-366@example.test', now()),
  ('10000000-0000-0000-0000-000000003666', '00000000-0000-0000-0000-000000003666', 'other-366@example.test', now());

insert into private.maintainer_identity(auth_user_id)
values ('00000000-0000-0000-0000-000000003661');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003665","role":"authenticated"}',
  true);
select public.put_in_ticket(
  'problem', 'The swap looked wrong.', 'Schedule', '2026-09-01',
  'abc366', 'Chrome on Windows', '2026-09-26 14:30:00+00');

set local role postgres;
create temporary table ticket_366 as
select id from public.tickets where sender_id =
  '10000000-0000-0000-0000-000000003665';
grant select on ticket_366 to authenticated;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003661","role":"authenticated"}',
  true);
select public.open_ticket_for_maintainer((select id from ticket_366));
select lives_ok(format(
  'select public.ask_ticket_question(%L, %L, %L)',
  (select id from ticket_366),
  'Was it the swap with the 14th in it?',
  'It was the swap with the 14th in it.'
), 'the Maintainer can ask with a suggested answer');
select is((select state::text from public.tickets
  where id = (select id from ticket_366)), 'waiting_on_sender',
  'asking moves the Ticket to Waiting on you');
select is((select question_count from public.tickets
  where id = (select id from ticket_366)), 1,
  'asking increments the visible question count');
select is((select count(*)::integer from public.ticket_thread_entries), 1,
  'the Maintainer reads the private question');

set local role postgres;
select is((select count(*)::integer from public.staff_notices
  where staff_member_id = '10000000-0000-0000-0000-000000003665'
    and kind = 'ticket_question'), 1,
  'asking creates one Notice for the sender');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003665","role":"authenticated"}',
  true);
select is((select count(*)::integer from public.ticket_thread_entries), 1,
  'the sender reads the question');
select throws_ok(format(
  'insert into public.ticket_thread_entries(ticket_id, author, text) values (%L, %L, %L)',
  (select id from ticket_366), 'sender', 'Bypass the RPC'
), '42501', null, 'direct thread writes are denied');
select lives_ok(format(
  'select public.answer_ticket_question(%L, %L, null, true)',
  (select id from ticket_366),
  (select id from public.ticket_thread_entries where author = 'maintainer')
), 'the sender confirms the suggested answer with one call');
select is((select state::text from public.tickets
  where id = (select id from ticket_366)), 'seen',
  'answering returns the Ticket to Seen');
select is((select text from public.ticket_thread_entries
  where author = 'sender'), 'It was the swap with the 14th in it.',
  'a one-tap Yes records the suggested answer');
select ok((select latest_reply_at is not null and reply_seen_at is null
  from public.tickets where id = (select id from ticket_366)),
  'the Maintainer list can show a new reply');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003666","role":"authenticated"}',
  true);
select is((select count(*)::integer from public.ticket_thread_entries), 0,
  'another Staff member cannot read the thread');
select throws_ok(format(
  'select public.ask_ticket_question(%L, %L, null)',
  (select id from ticket_366), 'Other Staff question'
), '42501', 'Only the Maintainer can ask Ticket questions',
  'another Staff member cannot ask');
select throws_ok(format(
  'select public.answer_ticket_question(%L, %L, %L, false)',
  (select id from ticket_366),
  (select id from public.ticket_thread_entries where author = 'maintainer'),
  'Other Staff answer'
), '42501', 'Only the sender can answer this Ticket',
  'another Staff member cannot answer');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003662","role":"authenticated"}',
  true);
select is((select count(*)::integer from public.ticket_thread_entries), 0,
  'the Manager cannot read the thread');
select throws_ok(format(
  'select public.ask_ticket_question(%L, %L, null)',
  (select id from ticket_366), 'Manager question'
), '42501', 'Only the Maintainer can ask Ticket questions',
  'the Manager cannot ask');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003661","role":"authenticated"}',
  true);
select is((select count(*)::integer from public.ticket_thread_entries), 2,
  'the Maintainer reads both sides of the thread');
select lives_ok(format('select public.open_ticket_for_maintainer(%L)',
  (select id from ticket_366)), 'the Maintainer opens the replied Ticket');
select ok((select reply_seen_at is not null from public.tickets
  where id = (select id from ticket_366)),
  'opening clears the new reply marker');
select throws_ok(format(
  'select public.answer_ticket_question(%L, %L, %L, false)',
  (select id from ticket_366),
  (select id from public.ticket_thread_entries where author = 'maintainer'),
  'Maintainer answer'
), '42501', 'Only the sender can answer this Ticket',
  'the Maintainer cannot answer for the sender');

select * from finish();
rollback;
