begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000003701', 'maintainer-370@example.test'),
  ('00000000-0000-0000-0000-000000003702', 'sender-370@example.test'),
  ('00000000-0000-0000-0000-000000003703', 'manager-370@example.test');

insert into public.staff_members(id, display_name, role) values
  ('10000000-0000-0000-0000-000000003701', 'Repair Maintainer Nurse', 'staff_member'),
  ('10000000-0000-0000-0000-000000003702', 'Private Sender Nurse', 'staff_member'),
  ('10000000-0000-0000-0000-000000003703', 'Repair Manager', 'manager');

insert into public.staff_accounts(
  staff_member_id, auth_user_id, personal_email, accepted_invite_at
) values
  ('10000000-0000-0000-0000-000000003701', '00000000-0000-0000-0000-000000003701', 'maintainer-370@example.test', now()),
  ('10000000-0000-0000-0000-000000003702', '00000000-0000-0000-0000-000000003702', 'sender-370@example.test', now()),
  ('10000000-0000-0000-0000-000000003703', '00000000-0000-0000-0000-000000003703', 'manager-370@example.test', now());

insert into private.maintainer_identity(auth_user_id)
values ('00000000-0000-0000-0000-000000003701');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003702","role":"authenticated"}',
  true);
select public.put_in_ticket(
  'problem', 'Dana and the patient are named in this private Ticket.',
  'Schedule', '2026-09-01', 'abc1234', 'Chrome on Windows',
  '2026-09-26 14:30:00+00');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003701","role":"authenticated"}',
  true);
select throws_ok($$select public.open_maintainer_repair(
  'investigation', 'Trace a missing Ticket',
  'ffffffff-ffff-ffff-ffff-ffffffffffff')$$,
  'P2834', 'Ticket not found',
  'a missing Ticket uses the shared Ticket-not-found Refusal');
select lives_ok($$select public.open_maintainer_repair(
  'investigation', 'Correct the Schedule failure',
  (select id from public.tickets limit 1))$$,
  'the Maintainer can name a Ticket when breaking the glass');
select is((select repair_ticket_id from public.current_access()),
  (select id from public.tickets limit 1),
  'the active Repair retains its Ticket cause');

set local role postgres;
select is((select body from public.staff_notices
  where kind = 'maintainer_repair'),
  E'Correct the Schedule failure\n\nThis Repair was opened because of a Ticket from a Staff member.',
  'the Manager Notice says only that a Staff Ticket prompted the Repair');
select ok(position('Private Sender Nurse' in (select body from public.staff_notices
  where kind = 'maintainer_repair')) = 0,
  'the Manager Notice omits the Ticket sender');
select ok(position('Dana' in (select body from public.staff_notices
  where kind = 'maintainer_repair')) = 0,
  'the Manager Notice omits the Ticket text');
select hasnt_column('public', 'maintainer_repair_audit', 'ticket_id',
  'Repair history has no path to the Ticket id');
select hasnt_column('public', 'maintainer_repair_audit', 'ticket_sender_id',
  'Repair history has no path to the Ticket sender');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003703","role":"authenticated"}',
  true);
select is((select count(*)::integer from public.tickets), 0,
  'the Manager cannot read the linked Ticket row');
select ok((select repair_ticket_id is null from public.current_access()),
  'the Manager current-access view does not expose the Ticket id');
select throws_ok($$select ticket_id from public.maintainer_repairs$$,
  '42501', null, 'the Manager cannot follow the Repair foreign key');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003701","role":"authenticated"}',
  true);
select lives_ok($$select public.close_maintainer_repair()$$,
  'the linked Repair can be closed');
select lives_ok($$select public.open_maintainer_repair(
  'unit_settings', 'Correct the print wording', null)$$,
  'a Repair can still be opened without a Ticket');
select is((select repair_ticket_id from public.current_access()), null::uuid,
  'a Repair without a Ticket retains no cause');

set local role postgres;
select is((select body from public.staff_notices
  where kind = 'maintainer_repair' and title = 'Repair: Unit settings'),
  'Correct the print wording',
  'a Repair without a Ticket keeps the ordinary Notice wording');

select * from finish();
rollback;
