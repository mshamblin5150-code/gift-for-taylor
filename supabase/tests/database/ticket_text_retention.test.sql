begin;
create extension if not exists pgtap with schema extensions;
select plan(25);

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000003691', 'maintainer-369@example.test'),
  ('00000000-0000-0000-0000-000000003692', 'sender-369@example.test'),
  ('00000000-0000-0000-0000-000000003693', 'other-369@example.test');

insert into public.staff_members(id, display_name, role) values
  ('10000000-0000-0000-0000-000000003691', 'Maintainer 369', 'staff_member'),
  ('10000000-0000-0000-0000-000000003692', 'Sender 369', 'staff_member'),
  ('10000000-0000-0000-0000-000000003693', 'Manager 369', 'manager');

insert into public.staff_accounts(
  staff_member_id, auth_user_id, personal_email, accepted_invite_at
) values
  ('10000000-0000-0000-0000-000000003691', '00000000-0000-0000-0000-000000003691', 'maintainer-369@example.test', now()),
  ('10000000-0000-0000-0000-000000003692', '00000000-0000-0000-0000-000000003692', 'sender-369@example.test', now()),
  ('10000000-0000-0000-0000-000000003693', '00000000-0000-0000-0000-000000003693', 'other-369@example.test', now());

insert into private.maintainer_identity(auth_user_id)
values ('00000000-0000-0000-0000-000000003691');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003692","role":"authenticated"}',
  true);
select public.put_in_ticket(
  'problem', 'Patient detail that must disappear.', 'Schedule', '2026-09-01',
  'abc369', 'Chrome on Windows', '2026-09-26 14:30:00+00');
select public.put_in_ticket(
  'idea', 'Redact this Ticket now.', 'My tickets', null,
  'abc369', 'Chrome on Windows', '2026-09-26 14:31:00+00');
select public.put_in_ticket(
  'question', 'Keep this after a recent reclose.', 'My tickets', null,
  'abc369', 'Chrome on Windows', '2026-09-26 14:32:00+00');

set local role postgres;
create temporary table tickets_369 as
select kind, id from public.tickets;
grant select on tickets_369 to authenticated;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003691","role":"authenticated"}',
  true);
select public.open_ticket_for_maintainer(
  (select id from tickets_369 where kind = 'problem'));
select public.link_ticket_to_github(
  (select id from tickets_369 where kind = 'problem'), 369,
  'https://github.com/mshamblin5150-code/gift-for-taylor/issues/369');
select public.ask_ticket_question(
  (select id from tickets_369 where kind = 'problem'),
  'Which screen contained the detail?', 'The Schedule screen');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003692","role":"authenticated"}',
  true);
select public.answer_ticket_question(
  (select id from tickets_369 where kind = 'problem'),
  (select id from public.ticket_thread_entries where author = 'maintainer'),
  'It named a patient on the Schedule.', false);
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003691","role":"authenticated"}',
  true);
select public.close_ticket(
  (select id from tickets_369 where kind = 'problem'), 'done',
  'The text retention rule is live.');
select public.open_ticket_for_maintainer(
  (select id from tickets_369 where kind = 'question'));
select public.close_ticket(
  (select id from tickets_369 where kind = 'question'), 'wont_do',
  'The sender reopened this before it closed again.');

set local role postgres;
update public.tickets set closed_at = clock_timestamp() - interval '91 days'
where id = (select id from tickets_369 where kind = 'problem');
update public.tickets set
  reopened_at = clock_timestamp() - interval '90 days',
  closed_at = clock_timestamp() - interval '89 days'
where id = (select id from tickets_369 where kind = 'question');
create temporary table ticket_metadata_369 as
select to_jsonb(ticket) - 'text' - 'text_removal' as metadata
from public.tickets ticket where kind = 'problem';
select is(public.erase_expired_ticket_text(), 1,
  'the scheduled operation erases one expired Ticket');
select is((select text from public.tickets
    where id = (select id from tickets_369 where kind = 'problem')),
  'Text erased 90 days after closing',
  'a Ticket closed 91 days ago no longer contains its free text');
select is((select text_removal::text from public.tickets
    where id = (select id from tickets_369 where kind = 'problem')),
  'retention', 'the Ticket records why its text is gone');
select is((select count(*)::integer from public.ticket_thread_entries
    where ticket_id = (select id from tickets_369 where kind = 'problem')
      and text = 'Text erased 90 days after closing'), 2,
  'all thread text is erased with the Ticket text');
select is((select count(*)::integer from public.ticket_thread_entries
    where ticket_id = (select id from tickets_369 where kind = 'problem')
      and text_removal = 'retention'), 2,
  'each erased thread message records the retention removal');
select is((select count(*)::integer from public.ticket_thread_entries
    where ticket_id = (select id from tickets_369 where kind = 'problem')
      and suggested_answer is not null), 0,
  'suggested thread text is erased too');
select is((select kind::text from public.tickets
    where id = (select id from tickets_369 where kind = 'problem')),
  'problem', 'the Ticket kind remains');
select is((select schedule_month from public.tickets
    where id = (select id from tickets_369 where kind = 'problem')),
  '2026-09-01'::date, 'the attached Month remains');
select is((select github_issue_url from public.tickets
    where id = (select id from tickets_369 where kind = 'problem')),
  'https://github.com/mshamblin5150-code/gift-for-taylor/issues/369',
  'the issue link remains');
select is((select metadata from ticket_metadata_369),
  (select to_jsonb(ticket) - 'text' - 'text_removal'
    from public.tickets ticket
    where id = (select id from tickets_369 where kind = 'problem')),
  'erasure preserves all Ticket metadata');
select ok(exists(select 1 from cron.job
    where jobname = 'erase-expired-ticket-text'),
  'pg_cron schedules Ticket text erasure');
select is((select text from public.tickets
    where id = (select id from tickets_369 where kind = 'question')),
  'Keep this after a recent reclose.',
  'closing again restarts the 90-day clock');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003692","role":"authenticated"}',
  true);
select throws_ok(format('select public.redact_ticket_text(%L)',
  (select id from tickets_369 where kind = 'idea')),
  '42501', 'Only the Maintainer can redact Ticket text',
  'the sender cannot redact Ticket text');
select throws_ok(format('select public.redact_ticket_thread_entry(%L)',
  (select id from public.ticket_thread_entries limit 1)),
  '42501', 'Only the Maintainer can redact Ticket thread text',
  'the sender cannot redact thread text');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003693","role":"authenticated"}',
  true);
select throws_ok(format('select public.redact_ticket_text(%L)',
  (select id from tickets_369 where kind = 'idea')),
  '42501', 'Only the Maintainer can redact Ticket text',
  'the Manager cannot redact Ticket text');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003691","role":"authenticated"}',
  true);
select lives_ok(format('select public.redact_ticket_text(%L)',
  (select id from tickets_369 where kind = 'idea')),
  'the Maintainer can redact Ticket text at once');
select lives_ok(format('select public.redact_ticket_thread_entry(%L)',
  (select id from public.ticket_thread_entries limit 1)),
  'the Maintainer can redact one thread message at once');
select throws_ok($$select public.redact_ticket_text(
    'ffffffff-ffff-ffff-ffff-ffffffffffff')$$,
  'P2834', 'Ticket not found',
  'redacting requires an existing Ticket');
select throws_ok($$select public.redact_ticket_thread_entry(
    'ffffffff-ffff-ffff-ffff-ffffffffffff')$$,
  'P2845', 'Ticket thread message not found',
  'redacting requires an existing thread message');
select is((select text from public.tickets
    where id = (select id from tickets_369 where kind = 'idea')),
  'Text removed by the Maintainer',
  'redacted Ticket text has the required wording');
select is((select text_removal::text from public.tickets
    where id = (select id from tickets_369 where kind = 'idea')),
  'maintainer', 'redacted Ticket text records the Maintainer removal');
select is((select text from public.ticket_thread_entries
    order by created_at, id limit 1),
  'Text removed by the Maintainer',
  'one redacted thread message has the required wording');
select is((select text_removal::text from public.ticket_thread_entries
    order by created_at, id limit 1),
  'maintainer', 'the redacted message records the Maintainer removal');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003692","role":"authenticated"}',
  true);
select is((select text from public.tickets
    where id = (select id from tickets_369 where kind = 'idea')),
  'Text removed by the Maintainer',
  'the sender sees the Ticket replacement wording');
select is((select text from public.ticket_thread_entries
    order by created_at, id limit 1),
  'Text removed by the Maintainer',
  'the sender sees the thread replacement wording');

select * from finish();
rollback;
