begin;

create extension if not exists pgtap with schema extensions;
select plan(13);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000301', 'print-manager@example.test'),
  ('00000000-0000-0000-0000-000000000302', 'print-staff@example.test');
insert into public.staff_members (id, display_name, role) values
  ('00000000-0000-0000-0000-000000000303', 'Print Manager', 'manager'),
  ('00000000-0000-0000-0000-000000000304', 'Print Staff', 'staff_member');
insert into public.staff_accounts
  (staff_member_id, auth_user_id, personal_email, accepted_invite_at)
values
  ('00000000-0000-0000-0000-000000000303', '00000000-0000-0000-0000-000000000301', 'print-manager@example.test', now()),
  ('00000000-0000-0000-0000-000000000304', '00000000-0000-0000-0000-000000000302', 'print-staff@example.test', now());

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000302","role":"authenticated"}', true);
select is((select count(*)::integer from public.print_wording), 1, 'staff read the one unit setting');
select is((select title from public.print_wording),
  'Welch Community Hospital - Emergency Room Schedule', 'seeded title is backfilled');
select is((select tooltip from public.print_wording), 'Print the book page', 'seeded tooltip is backfilled');
select is((select notice from public.print_wording), 'Schedule subject to change', 'seeded notice is backfilled');
select throws_ok(
  $$select public.set_print_wording('Any tooltip', 'ER Schedule', '')$$,
  'Only the Manager can change print wording',
  'staff cannot change print wording'
);

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000301","role":"authenticated"}', true);
select lives_ok(
  $$select public.set_print_wording('Print <Schedule>', 'ER & Schedule', '')$$,
  'the Manager can save arbitrary wording'
);
select is((select title from public.print_wording), 'ER & Schedule', 'the unit title is saved');
select is((select notice from public.print_wording), '', 'empty notice is saved');
select throws_ok(
  $$select public.set_print_wording('', 'ER Schedule', '')$$,
  '23514',
  null,
  'empty tooltip is rejected by the database'
);
select throws_ok(
  $$select public.set_print_wording('Print', '   ', '')$$,
  '23514', null, 'blank title is rejected by the database'
);
select throws_ok(
  $$select public.set_print_wording('Print', repeat('x', 81), '')$$,
  '23514', null, 'long title is rejected by the database'
);
select throws_ok(
  $$select public.set_print_wording('Print', 'Title', repeat('x', 81))$$,
  '23514', null, 'long notice is rejected by the database'
);
select is((select count(*)::integer from public.print_wording), 1, 'there remains one unit setting');

select * from finish();
rollback;
