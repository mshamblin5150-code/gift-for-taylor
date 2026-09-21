begin;
create extension if not exists pgtap with schema extensions;
select plan(4);

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000002181', 'coverage-admin@example.test'),
  ('00000000-0000-0000-0000-000000002182', 'coverage-staff@example.test');
insert into public.staff_members(id, display_name, role) values
  ('00000000-0000-0000-0000-000000002181', 'Coverage Admin', 'administrator'),
  ('00000000-0000-0000-0000-000000002182', 'Coverage Staff', 'staff_member');
insert into public.staff_accounts(staff_member_id, auth_user_id,
  personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000002181',
   '00000000-0000-0000-0000-000000002181', 'coverage-admin@example.test', now()),
  ('00000000-0000-0000-0000-000000002182',
   '00000000-0000-0000-0000-000000002182', 'coverage-staff@example.test', now());

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000002182","role":"authenticated"}', true);
select throws_ok($$
  select public.preview_coverage_weekday_rule('cna', 'day', 0,
    current_date, 1, null, 0)
$$, 'Only a Manager or Administrator can set Staffing minimums',
  'Staff member cannot preview a Unit rule change');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000002181","role":"authenticated"}', true);
select is(public.preview_coverage_weekday_rule('cna', 'day', 0,
  current_date, 1, null, 0), '[]'::jsonb,
  'Administrator can preview a Unit rule change');
select lives_ok($$
  select public.commit_coverage_weekday_rule('cna', 'day', 0,
    current_date, 1, null, 0, '[]'::jsonb, '[]'::jsonb)
$$, 'Administrator can save a Unit rule change');
select is((select actor from public.coverage_rule_audit
  where action = 'weekday_minimum' order by changed_at desc limit 1),
  '00000000-0000-0000-0000-000000002181'::uuid,
  'Unit audit records the Administrator');

select * from finish();
rollback;
