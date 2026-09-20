begin;
create extension if not exists pgtap with schema extensions;
select plan(36);

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000000531', 'minimum-manager@example.test'),
  ('00000000-0000-0000-0000-000000000532', 'minimum-rn@example.test'),
  ('00000000-0000-0000-0000-000000000533', 'minimum-lpn@example.test'),
  ('00000000-0000-0000-0000-000000000534', 'minimum-cna@example.test');
insert into public.sections(id, name, display_order) values
  ('00000000-0000-0000-0000-000000000535', 'Minimum nursing', 153),
  ('00000000-0000-0000-0000-00000000053b', 'Night nursing', 154);
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
  ('00000000-0000-0000-0000-000000000538', '00000000-0000-0000-0000-00000000053b', 1, '2027-03-01'),
  ('00000000-0000-0000-0000-000000000539', '00000000-0000-0000-0000-000000000535', 2, '2027-03-01');
insert into public.staff_job_roles(staff_member_id, job_role, effective_from) values
  ('00000000-0000-0000-0000-000000000537', 'rn', '2027-03-01'),
  ('00000000-0000-0000-0000-000000000538', 'lpn', '2027-03-01'),
  ('00000000-0000-0000-0000-000000000539', 'cna', '2027-03-01');
insert into public.schedule_months(id, month_start, release_state)
values ('00000000-0000-0000-0000-00000000053a', '2027-03-01', 'unpublished');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000532","role":"authenticated"}', true);
select throws_ok($$select public.set_pool_weekday_minimum('cna', 'day', 1, 2)$$,
  'Only the Manager can set staffing minimums', 'Staff cannot set minimum');
select throws_ok($$select public.post_open_shifts('2027-03-01', '7A', 'nurses', 1, false, true)$$,
  'Only the Manager can post Open shifts', 'Staff cannot post');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000531","role":"authenticated"}', true);
select is((select minimum from public.section_staffing_for_month('2027-03-01')
  where pool = 'nurses' and coverage_window = 'day' and work_date = '2027-03-01'), 3,
  'nursing day minimum is seeded');
select is((select rn_floor from public.section_staffing_for_month('2027-03-01')
  where pool = 'nurses' and coverage_window = 'night' and work_date = '2027-03-01'), 1,
  'nursing night RN floor is seeded');
select ok((select minimum is null from public.section_staffing_for_month('2027-03-01')
  where pool = 'cna' and coverage_window = 'day' and work_date = '2027-03-01'),
  'unset CNA minimum is not zero');
select lives_ok($$select public.set_pool_weekday_minimum('cna', 'day', 1, 1)$$,
  'Manager sets CNA minimum');
select lives_ok($$select public.set_pool_date_minimum('nurses', 'day', '2027-03-01', 2, 1)$$,
  'Manager overrides one date');
select is((select minimum from public.section_staffing_for_month('2027-03-01')
  where pool = 'nurses' and coverage_window = 'day' and work_date = '2027-03-01'), 2,
  'date override wins');
select lives_ok($$select public.set_pool_date_minimum('nurses', 'day', '2027-03-01', null)$$,
  'Manager removes date override');
select is((select minimum from public.section_staffing_for_month('2027-03-01')
  where pool = 'nurses' and coverage_window = 'day' and work_date = '2027-03-01'), 3,
  'weekday minimum returns');
select throws_ok($$select public.set_pool_weekday_minimum('cna', 'day', 1, 1, 1)$$,
  'Invalid staffing minimum', 'non-nursing pool cannot have RN floor');

set local role postgres;
insert into public.schedule_cells(schedule_month_id, staff_member_id, section_id, work_date, shift_code)
values
  ('00000000-0000-0000-0000-00000000053a', '00000000-0000-0000-0000-000000000537', '00000000-0000-0000-0000-000000000535', '2027-03-01', '7A'),
  ('00000000-0000-0000-0000-00000000053a', '00000000-0000-0000-0000-000000000538', '00000000-0000-0000-0000-00000000053b', '2027-03-01', '7A'),
  ('00000000-0000-0000-0000-00000000053a', '00000000-0000-0000-0000-000000000539', '00000000-0000-0000-0000-000000000535', '2027-03-01', '7A');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000531","role":"authenticated"}', true);
select is((select working_count from public.section_staffing_for_month('2027-03-01')
  where pool = 'nurses' and coverage_window = 'day' and work_date = '2027-03-01'), 2,
  'nurses count across Sections on unpublished month');
select is((select shortfall from public.section_staffing_for_month('2027-03-01')
  where pool = 'cna' and coverage_window = 'day' and work_date = '2027-03-01'), 0,
  'CNA minimum is met separately');
select is((select shortfall from public.section_staffing_for_month('2027-03-01')
  where pool = 'nurses' and coverage_window = 'day' and work_date = '2027-03-01'), 1,
  'nursing pool is short one');
select is((select shortfall from public.section_staffing_for_month('2027-03-01')
  where pool = 'nurses' and coverage_window = 'night' and work_date = '2027-03-01'), 3,
  'day Shift codes do not cover Nights');
select is(public.post_open_shifts('2027-03-01', '7A', 'nurses', 3, true, false), 1,
  'posts only uncovered pool gap');
select is(public.post_open_shifts('2027-03-01', '7A', 'nurses', 3, true, false), 0,
  'posted Open shift prevents duplicate gap');
select is((select requires_approval from public.short_shifts where reason = 'manual' limit 1), false,
  'ordinary pool gap respects approval choice');
select throws_ok($$select public.post_open_shifts('2027-03-01', 'X', 'nurses', 1, false, true)$$,
  'A date, working Shift code with a Coverage window, pool and count are required',
  'non-working code cannot post');

set local role postgres;
update public.schedule_cells set shift_code = 'X'
where staff_member_id = '00000000-0000-0000-0000-000000000537' and work_date = '2027-03-01';
set local role authenticated;
select is((select shortfall from public.section_staffing_for_month('2027-03-01')
  where pool = 'nurses' and coverage_window = 'day' and work_date = '2027-03-01'), 2,
  'nurse absence increases gap');
select is((select rn_shortfall from public.section_staffing_for_month('2027-03-01')
  where pool = 'nurses' and coverage_window = 'day' and work_date = '2027-03-01'), 1,
  'RN floor is reported separately');
select is(public.post_open_shifts('2027-03-02', '7A', 'nurses', 3, true, false), 3,
  'empty day posts three nurses');
select is((select count(*)::integer from public.short_shifts
  where work_date = '2027-03-02' and rn_floor_critical and job_role = 'rn' and requires_approval), 1,
  'one empty-day posting is floor critical and requires approval');
select is((select count(*)::integer from public.short_shifts
  where work_date = '2027-03-02' and not rn_floor_critical and not requires_approval), 2,
  'remaining empty-day postings are ordinary');

set local role postgres;
update public.staff_job_roles set effective_through = '2027-03-01'
where staff_member_id = '00000000-0000-0000-0000-000000000538';
insert into public.staff_job_roles(staff_member_id, job_role, effective_from)
values ('00000000-0000-0000-0000-000000000538', 'rn', '2027-03-02');
insert into public.schedule_cells(schedule_month_id, staff_member_id, section_id, work_date, shift_code)
values ('00000000-0000-0000-0000-00000000053a', '00000000-0000-0000-0000-000000000538',
  '00000000-0000-0000-0000-00000000053b', '2027-03-02', '7P');
set local role authenticated;
select is((select rn_count from public.section_staffing_for_month('2027-03-01')
  where pool = 'nurses' and coverage_window = 'day' and work_date = '2027-03-01'), 0,
  'role change does not rewrite earlier LPN count');
select is((select rn_count from public.section_staffing_for_month('2027-03-01')
  where pool = 'nurses' and coverage_window = 'night' and work_date = '2027-03-02'), 1,
  'new role counts on later date and code window');

select lives_ok($$select public.set_pool_date_minimum('nurses', 'day', '2027-03-01', 1, 0)$$,
  'Manager can lower nursing requirement for a date');
select is((select shortfall from public.section_staffing_for_month('2027-03-01')
  where pool = 'nurses' and coverage_window = 'day' and work_date = '2027-03-01'), 0,
  'nursing requirement can be met while another role is short');
select lives_ok($$select public.set_pool_date_minimum('cna', 'day', '2027-03-01', 2)$$,
  'Manager can raise CNA requirement independently');
select is((select shortfall from public.section_staffing_for_month('2027-03-01')
  where pool = 'cna' and coverage_window = 'day' and work_date = '2027-03-01'), 1,
  'CNA reads short even though nursing is covered');

set local role postgres;
insert into public.shift_codes(code, is_working, display_order)
values ('UNKNOWN', true, 1000);
insert into public.schedule_cells(schedule_month_id, staff_member_id, section_id, work_date, shift_code)
values ('00000000-0000-0000-0000-00000000053a', '00000000-0000-0000-0000-000000000537',
  '00000000-0000-0000-0000-000000000535', '2027-03-03', 'UNKNOWN');
set local role authenticated;
select is((select shortfall from public.section_staffing_for_month('2027-03-01')
  where pool = 'nurses' and coverage_window = 'day' and work_date = '2027-03-03'), 3,
  'hourless working code covers neither window');

set local role postgres;
update public.schedule_months set release_state = 'released', released_at = now(),
  released_by_staff_member_id = '00000000-0000-0000-0000-000000000536'
where id = '00000000-0000-0000-0000-00000000053a';
insert into public.short_shifts(schedule_month_id, section_id, work_date, shift_code,
  staff_member_id, reason)
values ('00000000-0000-0000-0000-00000000053a', '00000000-0000-0000-0000-000000000535',
  '2027-03-04', '7A', '00000000-0000-0000-0000-000000000537', 'request_off');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000533","role":"authenticated"}', true);
select is((select count(*)::integer from public.visible_open_shifts()
  where work_date = '2027-03-04'), 1,
  'nurse in Night Section sees Day Open shift');
select lives_ok($$select public.request_open_shift_pickup((select id from public.short_shifts
  where work_date = '2027-03-04'))$$, 'night nurse requests Day shift');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000531","role":"authenticated"}', true);
select lives_ok($$select public.approve_open_shift_pickup((select id from public.open_shift_pickups
  where short_shift_id = (select id from public.short_shifts where work_date = '2027-03-04')))$$,
  'Manager approves cross-window pickup');
select is((select section_id from public.schedule_cells
  where staff_member_id = '00000000-0000-0000-0000-000000000538' and work_date = '2027-03-04'),
  '00000000-0000-0000-0000-00000000053b'::uuid,
  'pickup cell remains in picker Section');
select is((select working_count from public.section_staffing_for_month('2027-03-01')
  where pool = 'nurses' and coverage_window = 'day' and work_date = '2027-03-04'), 1,
  'Day pickup counts on Days despite Night Section');

select * from finish();
rollback;
