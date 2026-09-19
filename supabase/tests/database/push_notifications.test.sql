begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000701', 'push-one@example.test'),
  ('00000000-0000-0000-0000-000000000702', 'push-two@example.test');
insert into public.sections (id, name, display_order) values
  ('00000000-0000-0000-0000-000000000711', 'Push test', 99);
insert into public.staff_members (id, display_name, active) values
  ('00000000-0000-0000-0000-000000000721', 'Push One', true),
  ('00000000-0000-0000-0000-000000000722', 'Push Two', true),
  ('00000000-0000-0000-0000-000000000723', 'Former Push', false);
insert into public.staff_accounts (staff_member_id, auth_user_id, personal_email, accepted_invite_at)
values
  ('00000000-0000-0000-0000-000000000721', '00000000-0000-0000-0000-000000000701', 'push-one@example.test', now()),
  ('00000000-0000-0000-0000-000000000722', '00000000-0000-0000-0000-000000000702', 'push-two@example.test', now());

insert into public.schedule_months (id, month_start) values
  ('00000000-0000-0000-0000-000000000731', '2028-03-01');
select is((select count(*)::integer from public.staff_notices), 0,
  'an unpublished month creates no notices');
insert into public.schedule_changes (
  schedule_month_id, staff_member_id, section_id, work_date,
  old_shift_code, new_shift_code, changed_by_staff_member_id
) values (
  '00000000-0000-0000-0000-000000000731',
  '00000000-0000-0000-0000-000000000721',
  '00000000-0000-0000-0000-000000000711',
  '2028-03-10', '', '7A', '00000000-0000-0000-0000-000000000721'
);
select is((select count(*)::integer from public.staff_notices), 0,
  'edits while building a month do not notify Staff');
update public.schedule_months set release_state = 'released',
  released_at = now(), released_by_staff_member_id = '00000000-0000-0000-0000-000000000721'
where id = '00000000-0000-0000-0000-000000000731';
select is((select count(*)::integer from public.staff_notices where kind = 'month_release'), 2,
  'Month release creates one notice for each active Staff member');
update public.schedule_months set released_at = now()
where id = '00000000-0000-0000-0000-000000000731';
select is((select count(*)::integer from public.staff_notices where kind = 'month_release'), 2,
  'a later month update does not repeat the release notice');
update public.schedule_changes set announced_at = now()
where work_date = '2028-03-10';
select is((select count(*)::integer from public.staff_notices where kind = 'schedule_change'), 0,
  'marking a draft edit announced after release does not send a change push');

insert into public.schedule_changes (
  schedule_month_id, staff_member_id, section_id, work_date,
  old_shift_code, new_shift_code, changed_by_staff_member_id
) values (
  '00000000-0000-0000-0000-000000000731',
  '00000000-0000-0000-0000-000000000721',
  '00000000-0000-0000-0000-000000000711',
  '2028-03-12', '7A', 'X', '00000000-0000-0000-0000-000000000721'
), (
  '00000000-0000-0000-0000-000000000731',
  '00000000-0000-0000-0000-000000000721',
  '00000000-0000-0000-0000-000000000711',
  '2028-03-13', '7A', 'X', '00000000-0000-0000-0000-000000000721'
);
select is((select count(*)::integer from public.staff_notices where kind = 'schedule_change'), 0,
  'a saved change waits for the scheduler to send the text');
update public.schedule_changes set announced_at = now()
where work_date in ('2028-03-12', '2028-03-13');
select is((select count(*)::integer from public.staff_notices where kind = 'schedule_change'), 1,
  'announcing several released shifts creates one notice per affected person');
select is((select staff_member_id::text from public.staff_notices where kind = 'schedule_change'),
  '00000000-0000-0000-0000-000000000721', 'the changed Staff member is the recipient');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000701', true);
select is((select count(*)::integer from public.staff_notices), 2,
  'Staff can read only their own notices');
select throws_ok(
  $$insert into public.staff_notices (staff_member_id, kind, title, body)
    values ('00000000-0000-0000-0000-000000000721', 'test', 'fake', 'fake')$$,
  '42501', null, 'Staff cannot forge notices');
select lives_ok(
  $$select public.register_push_subscription('{"endpoint":"https://push.example.test/one","keys":{"p256dh":"key","auth":"secret"}}')$$,
  'Staff can allow notifications on their device');
select lives_ok($$select public.send_test_push()$$, 'Staff can send themselves a test push');
select is((select count(*)::integer from public.staff_notices where kind = 'test'), 1,
  'a test push creates only the caller’s notice');

select * from finish();
rollback;
