begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000001760', 'settings-manager@example.test'),
  ('00000000-0000-0000-0000-000000001761', 'settings-admin@example.test'),
  ('00000000-0000-0000-0000-000000001762', 'settings-staff@example.test');
insert into public.staff_members(id, display_name, role) values
  ('00000000-0000-0000-0000-000000001763', 'Settings Manager', 'manager'),
  ('00000000-0000-0000-0000-000000001764', 'Settings Administrator', 'administrator'),
  ('00000000-0000-0000-0000-000000001765', 'Settings Staff', 'staff_member');
insert into public.staff_accounts(staff_member_id, auth_user_id, personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000001763', '00000000-0000-0000-0000-000000001760', 'settings-manager@example.test', now()),
  ('00000000-0000-0000-0000-000000001764', '00000000-0000-0000-0000-000000001761', 'settings-admin@example.test', now()),
  ('00000000-0000-0000-0000-000000001765', '00000000-0000-0000-0000-000000001762', 'settings-staff@example.test', now());
insert into public.schedule_months(month_start) values ('2031-01-01');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000001760","role":"authenticated"}', true);
select lives_ok($$select public.set_print_wording('Print page', 'Released title', 'Released notice')$$,
  'Manager sets the Unit print default');
select lives_ok($$select public.release_month_checked('2031-01-01', true)$$,
  'Manager releases the month');
select is((select print_title from public.schedule_months where month_start = '2031-01-01'),
  'Released title', 'release captures the title');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000001761","role":"authenticated"}', true);
select lives_ok($$select public.set_print_wording('Print page', 'Future title', 'Future notice')$$,
  'Administrator changes the Unit print default');
select is((select title from public.print_wording where id), 'Future title',
  'the default changes');
select is((select print_title from public.schedule_months where month_start = '2031-01-01'),
  'Released title', 'released wording stays frozen');
select lives_ok($$select public.correct_month_print_wording(
  '2031-01-01', 'Print page', 'Corrected title', 'Corrected notice')$$,
  'Administrator corrects one released month');
select is((select print_title from public.schedule_months where month_start = '2031-01-01'),
  'Corrected title', 'the correction changes that month');
select is((select title from public.print_wording where id), 'Future title',
  'the correction does not change the default');
select is((select count(*)::integer from public.unit_setting_audit
  where kind = 'Released month print wording'
    and actor_name = 'Settings Administrator'
    and before_value->>'title' = 'Released title'
    and after_value->>'title' = 'Corrected title'), 1,
  'month correction has an actor and before/after values');
select lives_ok($$select public.set_open_shift_approval_default(false)$$,
  'Administrator sets the approval default');
select is(public.open_shift_approval_default(), false,
  'new Open shifts use the changed default');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000001762","role":"authenticated"}', true);
select throws_ok($$select public.set_open_shift_approval_default(true)$$,
  'Only the Manager can set Open shift approval',
  'Staff cannot change the Unit approval default');
select throws_ok($$select public.correct_month_print_wording(
  '2031-01-01', 'Print page', 'Wrong title', 'Wrong notice')$$,
  'Only Unit managers can correct print wording',
  'Staff cannot correct released wording');
select is((select count(*)::integer from public.unit_setting_audit), 0,
  'Staff cannot read Unit audit history');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000001761","role":"authenticated"}', true);
select lives_ok($$select public.set_staff_access_role(
  '00000000-0000-0000-0000-000000001765', 'administrator')$$,
  'Administrator grants Administrator access');
select is((select role::text from public.staff_members
  where id = '00000000-0000-0000-0000-000000001765'), 'administrator',
  'permission assignment persists');
select throws_ok($$select public.set_staff_access_role(
  '00000000-0000-0000-0000-000000001765', 'manager')$$,
  'Only the Manager can transfer the Manager role',
  'Administrator cannot transfer the Manager role');

select * from finish();
rollback;
