begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000000531', 'minimum-manager@example.test'),
  ('00000000-0000-0000-0000-000000000532', 'minimum-rn@example.test'),
  ('00000000-0000-0000-0000-000000000533', 'minimum-lpn@example.test'),
  ('00000000-0000-0000-0000-000000000534', 'minimum-cna@example.test');
insert into public.sections(id, name, display_order)
  values ('00000000-0000-0000-0000-000000000535', 'Minimum nursing', 153);
insert into public.staff_members(id, display_name, role) values
  ('00000000-0000-0000-0000-000000000536', 'Minimum Manager', 'manager'),
  ('00000000-0000-0000-0000-000000000537', 'Minimum RN', 'staff_member'),
  ('00000000-0000-0000-0000-000000000538', 'Minimum LPN', 'staff_member'),
  ('00000000-0000-0000-0000-000000000539', 'Minimum CNA', 'staff_member');
insert into public.staff_accounts(staff_member_id, auth_user_id, personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000000536', '00000000-0000-0000-0000-000000000531', 'minimum-manager@example.test', now()),
  ('00000000-0000-0000-0000-000000000537', '00000000-0000-0000-0000-000000000532', 'minimum-rn@example.test', now()),
  ('00000000-0000-0000-0000-000000000538', '00000000-0000-0000-0000-000000000533', 'minimum-lpn@example.test', now()),
  ('00000000-0000-0000-0000-000000000539', '00000000-0000-0000-0000-000000000534', 'minimum-cna@example.test', now());
insert into public.staff_section_assignments(staff_member_id, section_id, display_order, effective_from) values
  ('00000000-0000-0000-0000-000000000537', '00000000-0000-0000-0000-000000000535', 0, '2027-03-01'),
  ('00000000-0000-0000-0000-000000000538', '00000000-0000-0000-0000-000000000535', 1, '2027-03-01'),
  ('00000000-0000-0000-0000-000000000539', '00000000-0000-0000-0000-000000000535', 2, '2027-03-01');
insert into public.staff_job_roles(staff_member_id, job_role, effective_from) values
  ('00000000-0000-0000-0000-000000000537', 'rn', '2027-03-01'),
  ('00000000-0000-0000-0000-000000000538', 'lpn', '2027-03-01'),
  ('00000000-0000-0000-0000-000000000539', 'cna', '2027-03-01');
insert into public.schedule_months(id, month_start, release_state, released_at, released_by_staff_member_id)
  values ('00000000-0000-0000-0000-00000000053a', '2027-03-01', 'released', now(),
    '00000000-0000-0000-0000-000000000536');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000532","role":"authenticated"}', true);
select throws_ok($$select public.set_section_weekday_minimum('00000000-0000-0000-0000-000000000535', 1, 2)$$,
  'Only the Manager can set staffing minimums', 'Staff cannot set weekday minimum');
select throws_ok($$select public.post_open_shifts('00000000-0000-0000-0000-000000000535',
  '2027-03-01', '7A', 'rn', 1, false)$$,
  'Only the Manager can post Open shifts', 'Staff cannot post');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000531","role":"authenticated"}', true);
select lives_ok($$select public.set_section_weekday_minimum('00000000-0000-0000-0000-000000000535', 1, 2)$$,
  'Manager sets Monday minimum');
select lives_ok($$select public.set_section_date_minimum('00000000-0000-0000-0000-000000000535', '2027-03-01', 3)$$,
  'Manager overrides one date');
select is((select minimum from public.section_staffing_for_month('2027-03-01')
  where section_id = '00000000-0000-0000-0000-000000000535' and work_date = '2027-03-01'), 3,
  'date override wins');
select is((select minimum from public.section_staffing_for_month('2027-03-01')
  where section_id = '00000000-0000-0000-0000-000000000535' and work_date = '2027-03-08'), 2,
  'weekday minimum applies next week');
select lives_ok($$select public.set_section_date_minimum('00000000-0000-0000-0000-000000000535', '2027-03-01', null)$$,
  'Manager removes date override');
select is((select minimum from public.section_staffing_for_month('2027-03-01')
  where section_id = '00000000-0000-0000-0000-000000000535' and work_date = '2027-03-01'), 2,
  'date returns to weekday default');
select is(public.post_open_shifts('00000000-0000-0000-0000-000000000535',
  '2027-03-01', '7A', 'rn', 2, true), 2, 'posts full gap in one step');
select is(public.post_open_shifts('00000000-0000-0000-0000-000000000535',
  '2027-03-01', '7A', 'rn', 2, true), 0, 'does not duplicate already posted gap');
select is((select count(*)::integer from public.visible_open_shifts()
  where section_id = '00000000-0000-0000-0000-000000000535'), 2,
  'Manager sees both manual Open shifts');
set local role postgres;
select is((select count(*)::integer from public.staff_notices where kind = 'open_shift_posted'), 2,
  'eligible nurses receive one notice each');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000534","role":"authenticated"}', true);
select is((select count(*)::integer from public.visible_open_shifts()
  where section_id = '00000000-0000-0000-0000-000000000535'), 0,
  'CNA cannot see nursing Open shifts');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000533","role":"authenticated"}', true);
select is((select count(*)::integer from public.visible_open_shifts()
  where section_id = '00000000-0000-0000-0000-000000000535'), 2,
  'LPN sees RN pool');
select lives_ok($$select public.request_open_shift_pickup((select id from public.short_shifts
  where section_id = '00000000-0000-0000-0000-000000000535' limit 1))$$,
  'LPN requests manual Open shift');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000531","role":"authenticated"}', true);
select lives_ok($$select public.approve_open_shift_pickup((select id from public.open_shift_pickups
  where staff_member_id = '00000000-0000-0000-0000-000000000538' limit 1))$$,
  'Manager approves manual pickup');
select is((select working_count from public.section_staffing_for_month('2027-03-01')
  where section_id = '00000000-0000-0000-0000-000000000535' and work_date = '2027-03-01'), 1,
  'approved pickup counts as working');
select is((select open_count from public.section_staffing_for_month('2027-03-01')
  where section_id = '00000000-0000-0000-0000-000000000535' and work_date = '2027-03-01'), 1,
  'other Open shift remains');

select * from finish();
rollback;
