begin;
create extension if not exists pgtap with schema extensions;
select plan(27);

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000003651', 'maintainer-365@example.test'),
  ('00000000-0000-0000-0000-000000003652', 'sender-365@example.test'),
  ('00000000-0000-0000-0000-000000003653', 'other-365@example.test');

insert into public.staff_members(id, display_name, role) values
  ('10000000-0000-0000-0000-000000003651', 'Outcome Maintainer Nurse', 'staff_member'),
  ('10000000-0000-0000-0000-000000003652', 'Outcome Sender Nurse', 'staff_member'),
  ('10000000-0000-0000-0000-000000003653', 'Outcome Other Nurse', 'staff_member');

insert into public.staff_accounts(
  staff_member_id, auth_user_id, personal_email, accepted_invite_at
) values
  ('10000000-0000-0000-0000-000000003651', '00000000-0000-0000-0000-000000003651', 'maintainer-365@example.test', now()),
  ('10000000-0000-0000-0000-000000003652', '00000000-0000-0000-0000-000000003652', 'sender-365@example.test', now()),
  ('10000000-0000-0000-0000-000000003653', '00000000-0000-0000-0000-000000003653', 'other-365@example.test', now());

insert into private.maintainer_identity(auth_user_id)
values ('00000000-0000-0000-0000-000000003651');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003652","role":"authenticated"}',
  true);
select public.put_in_ticket(
  'problem', 'The Save button did not work.', 'Schedule', '2026-09-01',
  'abc1234', 'Chrome on Windows', '2026-09-26 14:30:00+00');
select public.put_in_ticket(
  'idea', 'Please add a week view.', 'Schedule', '2026-09-01',
  'abc1234', 'Chrome on Windows', '2026-09-26 14:31:00+00');

select throws_ok($$select public.link_ticket_to_github(
  (select id from public.tickets limit 1), 365,
  'https://github.com/mshamblin5150-code/gift-for-taylor/issues/365')$$,
  '42501', 'Only the Maintainer can link Tickets to GitHub',
  'the sender cannot link a Ticket to GitHub');
select throws_ok($$select public.close_ticket(
  (select id from public.tickets limit 1), 'done', 'This is live now.')$$,
  '42501', 'Only the Maintainer can close Tickets',
  'the sender cannot close a Ticket');
select throws_ok($$select github_issue_url from public.tickets$$,
  '42501', null, 'the sender cannot select the GitHub issue link');
select ok(not has_column_privilege(
  'authenticated', 'public.tickets', 'github_issue_url', 'select'),
  'the authenticated role has no direct GitHub issue URL access');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003651","role":"authenticated"}',
  true);
select lives_ok($$select public.open_ticket_for_maintainer(
  (select id from public.tickets where kind = 'problem'))$$,
  'the Maintainer opens the Ticket before deciding it');
select lives_ok($$select public.link_ticket_to_github(
  (select id from public.tickets where kind = 'problem'), 365,
  'https://github.com/mshamblin5150-code/gift-for-taylor/issues/365')$$,
  'the Maintainer records the GitHub issue');
set local role postgres;
select is((select github_issue_number from public.tickets where kind = 'problem'),
  365::bigint, 'the GitHub issue number is retained');
select is((select github_issue_url from public.tickets where kind = 'problem'),
  'https://github.com/mshamblin5150-code/gift-for-taylor/issues/365',
  'the GitHub issue URL is retained');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003651","role":"authenticated"}',
  true);
select throws_ok($$select public.close_ticket(
  (select id from public.tickets where kind = 'problem'), 'done', '   ')$$,
  'P2836', 'A closing reason is required',
  'closing requires a reason for the sender');
select lives_ok($$select public.close_ticket(
  (select id from public.tickets where kind = 'problem'), 'done',
  'The fix is live in release 1.2.3.')$$,
  'the Maintainer closes a Ticket as Done');
select is((select state::text from public.tickets where kind = 'problem'),
  'done', 'the Ticket records the Done outcome');
select is((select close_reason from public.tickets where kind = 'problem'),
  'The fix is live in release 1.2.3.',
  'the sender-facing closing reason is retained');
set local role postgres;
select is((select count(*)::integer from public.staff_notices
    where staff_member_id = '10000000-0000-0000-0000-000000003652'
      and kind = 'ticket_closed'), 1,
  'closing raises one ordinary Staff Notice for the sender');
select is((select title from public.staff_notices where kind = 'ticket_closed'),
  'Ticket done', 'the Notice names the outcome');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003651","role":"authenticated"}',
  true);

select lives_ok($$select public.open_ticket_for_maintainer(
  (select id from public.tickets where kind = 'idea'))$$,
  'the Maintainer opens the second Ticket');
select lives_ok($$select public.close_ticket(
  (select id from public.tickets where kind = 'idea'), 'wont_do',
  'This would make the Schedule harder to read.')$$,
  $$the Maintainer closes a Ticket as Won't do$$);
select is((select state::text from public.tickets where kind = 'idea'),
  'wont_do', $$the Ticket records the Won't do outcome$$);

set local role postgres;
update public.tickets set closed_at = clock_timestamp() - interval '14 days'
  + interval '1 minute' where kind = 'problem';
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003652","role":"authenticated"}',
  true);
select ok((public.open_ticket_for_sender(
    (select id from public.tickets where kind = 'problem'))->>'can_reopen')::boolean,
  'SQL tells the sender the Ticket can still be reopened');
select ok(not (public.open_ticket_for_sender(
    (select id from public.tickets where kind = 'problem'))
    ? 'github_issue_url'),
  'the sender detail RPC omits the GitHub issue link');
select throws_ok($$select public.reopen_ticket(
  (select id from public.tickets where kind = 'problem'), '   ')$$,
  'P2838', 'A reopening note is required',
  'reopening requires a short note');
select ok(not (public.reopen_ticket(
    (select id from public.tickets where kind = 'problem'),
    'The same Save failure happened again.') ? 'github_issue_url'),
  'the sender can reopen without receiving the GitHub issue link');
select is((select state::text from public.tickets where kind = 'problem'),
  'seen', 'a reopened Ticket returns to Seen');
select ok((select reopened_at is not null from public.tickets where kind = 'problem'),
  'the reopened Ticket is marked as a regression');
select is((select reopen_note from public.tickets where kind = 'problem'),
  'The same Save failure happened again.', 'the reopening note is retained');

set local role postgres;
update public.tickets set closed_at = clock_timestamp() - interval '14 days'
  - interval '1 minute' where kind = 'idea';
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003652","role":"authenticated"}',
  true);
select throws_ok($$select public.reopen_ticket(
  (select id from public.tickets where kind = 'idea'),
  'I still need a week view.')$$,
  'P2840', 'This Ticket can no longer be reopened',
  'the sender cannot reopen just outside 14 days');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003653","role":"authenticated"}',
  true);
select throws_ok($$select public.reopen_ticket(
  (select id from public.tickets where kind = 'idea'), 'Not my Ticket')$$,
  'P2839', 'This Ticket cannot be reopened',
  'another Staff member cannot reopen the sender''s Ticket');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003651","role":"authenticated"}',
  true);
select public.ask_ticket_question(
  (select id from public.tickets where kind = 'problem'),
  'Did the same Save failure happen again?', 'Yes');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003652","role":"authenticated"}',
  true);
select ok(not (public.answer_ticket_question(
    (select id from public.tickets where kind = 'problem'),
    (select id from public.ticket_thread_entries
      where author = 'maintainer' order by created_at desc limit 1),
    null, true) ? 'github_issue_url'),
  'answering a private question does not reveal the GitHub issue link');

select * from finish();
rollback;
