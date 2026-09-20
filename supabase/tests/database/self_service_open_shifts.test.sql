begin;
create extension if not exists pgtap with schema extensions;
select plan(23);

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000000601', 'self-manager@example.test'),
  ('00000000-0000-0000-0000-000000000602', 'self-rn@example.test'),
  ('00000000-0000-0000-0000-000000000603', 'self-lpn@example.test');
insert into public.sections(id, name, display_order) values
  ('00000000-0000-0000-0000-000000000604', 'Self RN', 601),
  ('00000000-0000-0000-0000-000000000605', 'Self LPN', 602);
insert into public.staff_members(id, display_name, role) values
  ('00000000-0000-0000-0000-000000000606', 'Self Manager', 'manager'),
  ('00000000-0000-0000-0000-000000000607', 'Self RN', 'staff_member'),
  ('00000000-0000-0000-0000-000000000608', 'Self LPN', 'staff_member');
insert into public.staff_accounts(staff_member_id, auth_user_id, personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000000606', '00000000-0000-0000-0000-000000000601', 'self-manager@example.test', now()),
  ('00000000-0000-0000-0000-000000000607', '00000000-0000-0000-0000-000000000602', 'self-rn@example.test', now()),
  ('00000000-0000-0000-0000-000000000608', '00000000-0000-0000-0000-000000000603', 'self-lpn@example.test', now());
insert into public.staff_section_assignments(staff_member_id, section_id, display_order, effective_from) values
  ('00000000-0000-0000-0000-000000000607', '00000000-0000-0000-0000-000000000604', 0, '2027-03-01'),
  ('00000000-0000-0000-0000-000000000608', '00000000-0000-0000-0000-000000000605', 0, '2027-03-01');
insert into public.staff_job_roles(staff_member_id, job_role, effective_from) values
  ('00000000-0000-0000-0000-000000000607', 'rn', '2027-03-01'),
  ('00000000-0000-0000-0000-000000000608', 'lpn', '2027-03-01');
insert into public.schedule_months(id, month_start, release_state, released_at, released_by_staff_member_id)
values ('00000000-0000-0000-0000-000000000609', '2027-03-01', 'released', now(),
  '00000000-0000-0000-0000-000000000606');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000601","role":"authenticated"}', true);
select is(public.open_shift_approval_default(), true, 'approval starts on');
select lives_ok($$select public.set_open_shift_approval_default(false)$$, 'Manager turns approval off');
select is(public.open_shift_approval_default(), false, 'setting persists');
select is(public.post_open_shifts('2027-03-12', '7A', 'nurses', 3, true), 3,
  'Manager posts nursing gap with setting off');
select is((select count(*)::integer from public.short_shifts
  where work_date = '2027-03-12' and rn_floor_critical and requires_approval), 1,
  'RN floor gap still requires approval');
select is((select count(*)::integer from public.short_shifts
  where work_date = '2027-03-12' and not rn_floor_critical and not requires_approval), 2,
  'ordinary gap shifts use Manager setting');
reset role;
insert into public.short_shifts(schedule_month_id, work_date, shift_code, reason, job_role)
values ('00000000-0000-0000-0000-000000000609', '2027-03-10', '7A', 'manual', 'rn');
select is((select requires_approval from public.short_shifts where work_date = '2027-03-10'),
  false, 'ordinary shift follows Manager default');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000603","role":"authenticated"}', true);
select lives_ok($$select public.request_open_shift_pickup((select id from public.short_shifts
  where work_date = '2027-03-10'))$$, 'LPN takes nursing shift immediately');
select is((select shift_code from public.schedule_cells where staff_member_id =
  '00000000-0000-0000-0000-000000000608' and work_date = '2027-03-10'), '7A',
  'shift appears on pickers Schedule');
select is((select status from public.open_shift_pickups where staff_member_id =
  '00000000-0000-0000-0000-000000000608'), 'approved', 'pickup is approved');
select ok((select filled_at is not null from public.short_shifts where work_date = '2027-03-10'),
  'Open shift is filled');
select is((select count(*)::integer from public.staff_notices where staff_member_id =
  '00000000-0000-0000-0000-000000000608' and title = 'Open shift pickup approved'), 1,
  'picker receives confirmation');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000602","role":"authenticated"}', true);
select throws_ok($$select public.request_open_shift_pickup((select id from public.short_shifts
  where work_date = '2027-03-10'))$$, 'Open shift is unavailable', 'second picker cannot take filled shift');
reset role;
insert into public.short_shifts(schedule_month_id, work_date, shift_code, reason, job_role,
  rn_floor_critical, requires_approval)
values ('00000000-0000-0000-0000-000000000609', '2027-03-11', '7A', 'manual', 'rn', true, true);
select is((select requires_approval from public.short_shifts where work_date = '2027-03-11'),
  true, 'floor critical shift requires approval with setting off');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000603","role":"authenticated"}', true);
select lives_ok($$select public.request_open_shift_pickup((select id from public.short_shifts
  where work_date = '2027-03-11'))$$, 'floor pickup waits for Manager');
select is((select status from public.open_shift_pickups where short_shift_id =
  (select id from public.short_shifts where work_date = '2027-03-11')), 'pending',
  'floor pickup remains pending');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000601","role":"authenticated"}', true);
select lives_ok($$select public.set_open_shift_approval((select id from public.short_shifts
  where work_date = '2027-03-11'), false)$$, 'Manager can override floor shift');
select is((select requires_approval from public.short_shifts where work_date = '2027-03-11'),
  false, 'per shift override persists');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000602","role":"authenticated"}', true);
select lives_ok($$select public.request_open_shift_pickup((select id from public.short_shifts
  where work_date = '2027-03-11'))$$, 'RN immediately takes overridden shift');
reset role;
select is((select status from public.open_shift_pickups where staff_member_id =
  '00000000-0000-0000-0000-000000000608' and short_shift_id =
  (select id from public.short_shifts where work_date = '2027-03-11')), 'declined',
  'earlier pending pickup is declined');
select is((select shift_code from public.schedule_cells where staff_member_id =
  '00000000-0000-0000-0000-000000000607' and work_date = '2027-03-11'), '7A',
  'winner gets the shift');
select is((select count(*)::integer from public.staff_notices where staff_member_id =
  '00000000-0000-0000-0000-000000000608' and title = 'Open shift filled'), 1,
  'declined picker receives filled notice');
select ok((select filled_at is not null from public.short_shifts where work_date = '2027-03-11'),
  'overridden shift records filled time');
select * from finish();
rollback;
