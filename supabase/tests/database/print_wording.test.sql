begin;

create extension if not exists pgtap with schema extensions;
select plan(6);

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
select throws_ok(
  $$select public.set_print_wording('schedule', 'er', 'none')$$,
  'Only the Manager can change print wording',
  'staff cannot change print wording'
);

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000301","role":"authenticated"}', true);
select lives_ok(
  $$select public.set_print_wording('schedule', 'er', 'none')$$,
  'the Manager can choose approved wording'
);
select is((select title_style from public.print_wording), 'er', 'the unit title is saved');
select throws_ok(
  $$select public.set_print_wording('a patient name', 'er', 'none')$$,
  '23514',
  null,
  'unapproved personal wording is rejected by the database'
);
select is((select count(*)::integer from public.print_wording), 1, 'there remains one unit setting');

select * from finish();
rollback;
