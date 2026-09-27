begin;
create extension if not exists pgtap with schema extensions;
select plan(29);

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000003641', 'maintainer-364@example.test'),
  ('00000000-0000-0000-0000-000000003642', 'manager-364@example.test'),
  ('00000000-0000-0000-0000-000000003643', 'administrator-364@example.test'),
  ('00000000-0000-0000-0000-000000003644', 'night-364@example.test'),
  ('00000000-0000-0000-0000-000000003645', 'sender-364@example.test'),
  ('00000000-0000-0000-0000-000000003646', 'other-364@example.test'),
  ('00000000-0000-0000-0000-000000003647', 'not-staff-364@example.test');

insert into public.staff_members(id, display_name, role) values
  ('10000000-0000-0000-0000-000000003641', 'Maintainer Nurse', 'staff_member'),
  ('10000000-0000-0000-0000-000000003642', 'Manager Nurse', 'manager'),
  ('10000000-0000-0000-0000-000000003643', 'Administrator Nurse', 'administrator'),
  ('10000000-0000-0000-0000-000000003644', 'Night Nurse', 'night_scheduler'),
  ('10000000-0000-0000-0000-000000003645', 'Sender Nurse', 'staff_member'),
  ('10000000-0000-0000-0000-000000003646', 'Other Nurse', 'staff_member');

insert into public.staff_accounts(
  staff_member_id, auth_user_id, personal_email, accepted_invite_at
) values
  ('10000000-0000-0000-0000-000000003641', '00000000-0000-0000-0000-000000003641', 'maintainer-364@example.test', now()),
  ('10000000-0000-0000-0000-000000003642', '00000000-0000-0000-0000-000000003642', 'manager-364@example.test', now()),
  ('10000000-0000-0000-0000-000000003643', '00000000-0000-0000-0000-000000003643', 'administrator-364@example.test', now()),
  ('10000000-0000-0000-0000-000000003644', '00000000-0000-0000-0000-000000003644', 'night-364@example.test', now()),
  ('10000000-0000-0000-0000-000000003645', '00000000-0000-0000-0000-000000003645', 'sender-364@example.test', now()),
  ('10000000-0000-0000-0000-000000003646', '00000000-0000-0000-0000-000000003646', 'other-364@example.test', now());

insert into private.maintainer_identity(auth_user_id)
values ('00000000-0000-0000-0000-000000003641');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003645","role":"authenticated"}',
  true);

select lives_ok($$select public.put_in_ticket(
  'problem', 'The Save button did not work.', 'Schedule', '2026-09-01',
  'abc1234', 'Chrome on Windows', '2026-09-26 14:30:00+00',
  array['Screen: Schedule', 'RPC: propose_swap', 'Refusal: P2814'],
  'P2814')$$,
  'a Staff member can put in a problem Ticket');
select lives_ok($$select public.put_in_ticket(
  'idea', 'Please add a week view.', 'Schedule', '2026-09-01',
  'abc1234', 'Chrome on Windows', '2026-09-26 14:31:00+00',
  array['Screen: Schedule'], null)$$,
  'a Staff member can put in an idea Ticket');
select lives_ok($$select public.put_in_ticket(
  'question', 'Where do I find next month?', 'Schedule', '2026-09-01',
  'abc1234', 'Chrome on Windows', '2026-09-26 14:32:00+00',
  array['Screen: Schedule'], null)$$,
  'a Staff member can put in a question Ticket');
select is((select count(*)::integer from public.tickets), 3,
  'the sender reads all of their own Tickets');
select is((select min(state::text) from public.tickets), 'sent',
  'a new Ticket is Sent');
select is((select sender_display_name from public.tickets
  order by created_at limit 1), 'Sender Nurse',
  'the Ticket records the sending Staff member');
select is((select release_id from public.tickets order by created_at limit 1),
  'abc1234', 'the release context is retained');
select is((select device_context from public.tickets order by created_at limit 1),
  'Chrome on Windows', 'the device and browser context is retained');
select is((select schedule_month::text from public.tickets order by created_at limit 1),
  '2026-09-01', 'the viewed Month is retained');
select is((select recent_actions from public.tickets order by created_at limit 1),
  array['Screen: Schedule', 'RPC: propose_swap', 'Refusal: P2814'],
  'recent actions are retained');
select is((select refusal_code from public.tickets order by created_at limit 1),
  'P2814', 'the refusal code is retained');

select throws_ok($$select public.put_in_ticket(
  'problem', '   ', 'Schedule', null, 'abc1234', 'Chrome', now(),
  array['Screen: Schedule'], null)$$,
  'P2832', 'Ticket text must be between 1 and 2000 characters',
  'blank Ticket text has a stable refusal code');
select throws_ok($$select public.put_in_ticket(
  'problem', 'A valid explanation', '', null, 'abc1234', 'Chrome', now(),
  array['Screen: Schedule'], null)$$,
  'P2833', 'Ticket context is incomplete',
  'missing attached context has a stable refusal code');
select throws_ok($$select public.put_in_ticket(
  'problem', 'A valid explanation', 'Schedule', null, 'abc1234', 'Chrome',
  now(), array[]::text[], null)$$,
  'P2833', 'Ticket context is incomplete',
  'a Ticket cannot omit recent actions');
select throws_ok($$insert into public.tickets(
  sender_id, sender_display_name, kind, text, screen_context,
  release_id, device_context, context_captured_at
) values (
  '10000000-0000-0000-0000-000000003645', 'Sender Nurse', 'problem',
  'Bypass the RPC', 'Schedule', 'abc1234', 'Chrome', now()
)$$, '42501', null, 'direct Ticket inserts are denied');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003646","role":"authenticated"}',
  true);
select is((select count(*)::integer from public.tickets), 0,
  'another Staff member cannot read the sender''s Tickets');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003642","role":"authenticated"}',
  true);
select is((select count(*)::integer from public.tickets), 0,
  'the Manager cannot read another person''s Tickets');
select lives_ok($$select public.put_in_ticket(
  'question', 'Manager question', 'Schedule', null,
  'abc1234', 'Safari on iPhone', now(), array['Screen: Schedule'], null)$$,
  'the Manager can put in their own Ticket');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003643","role":"authenticated"}',
  true);
select is((select count(*)::integer from public.tickets), 0,
  'an Administrator cannot read another person''s Tickets');
select lives_ok($$select public.put_in_ticket(
  'idea', 'Administrator idea', 'Schedule', null,
  'abc1234', 'Edge on Windows', now(), array['Screen: Schedule'], null)$$,
  'an Administrator can put in their own Ticket');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003644","role":"authenticated"}',
  true);
select is((select count(*)::integer from public.tickets), 0,
  'a Night scheduler cannot read another person''s Tickets');
select lives_ok($$select public.put_in_ticket(
  'problem', 'Night scheduler problem', 'Schedule', null,
  'abc1234', 'Chrome on Android', now(), array['Screen: Schedule'], null)$$,
  'a Night scheduler can put in their own Ticket');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003647","role":"authenticated"}',
  true);
select throws_ok($$select public.put_in_ticket(
  'problem', 'No Staff account', 'Schedule', null,
  'abc1234', 'Chrome', now(), array['Screen: Schedule'], null)$$,
  'P2831', 'A current Staff account is required',
  'an account not linked to Staff cannot put in a Ticket');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003641","role":"authenticated"}',
  true);
select is((select count(*)::integer from public.tickets), 6,
  'the Maintainer reads every Ticket without opening a Repair');
select is((select count(*)::integer from public.current_maintainer_repair()), 0,
  'reading Tickets does not open a Repair');
select lives_ok($$select public.open_ticket_for_maintainer(
  (select id from public.tickets where sender_display_name = 'Sender Nurse'
    order by created_at limit 1))$$,
  'the Maintainer can open a Ticket');
select is((select state::text from public.tickets
  where sender_display_name = 'Sender Nurse' order by created_at limit 1),
  'seen', 'opening a Sent Ticket marks it Seen');
set local role postgres;
select is((select seen_by_auth_user_id from public.tickets
  where sender_display_name = 'Sender Nurse' order by created_at limit 1),
  '00000000-0000-0000-0000-000000003641'::uuid,
  'opening records which Maintainer saw it');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003645","role":"authenticated"}',
  true);
select is((select state::text from public.tickets
  where text = 'The Save button did not work.'), 'seen',
  'the sender now reads the Ticket as Seen');

select * from finish();
rollback;
