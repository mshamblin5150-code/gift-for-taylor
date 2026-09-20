begin;
create extension if not exists pgtap with schema extensions;
select plan(27);

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000000271', 'open-manager@example.test'),
  ('00000000-0000-0000-0000-000000000272', 'open-rn@example.test'),
  ('00000000-0000-0000-0000-000000000273', 'open-lpn@example.test'),
  ('00000000-0000-0000-0000-000000000274', 'open-cna@example.test');
insert into public.sections(id, name, display_order) values
  ('00000000-0000-0000-0000-000000000275', 'Open nursing', 120),
  ('00000000-0000-0000-0000-000000000276', 'Open CNA', 121);
insert into public.staff_members(id, display_name, role) values
  ('00000000-0000-0000-0000-000000000277', 'Open Manager', 'manager'),
  ('00000000-0000-0000-0000-000000000278', 'Open RN', 'staff_member'),
  ('00000000-0000-0000-0000-000000000279', 'Open LPN', 'staff_member'),
  ('00000000-0000-0000-0000-00000000027a', 'Open CNA', 'staff_member');
insert into public.staff_accounts(staff_member_id, auth_user_id, personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000000277', '00000000-0000-0000-0000-000000000271', 'open-manager@example.test', now()),
  ('00000000-0000-0000-0000-000000000278', '00000000-0000-0000-0000-000000000272', 'open-rn@example.test', now()),
  ('00000000-0000-0000-0000-000000000279', '00000000-0000-0000-0000-000000000273', 'open-lpn@example.test', now()),
  ('00000000-0000-0000-0000-00000000027a', '00000000-0000-0000-0000-000000000274', 'open-cna@example.test', now());
insert into public.staff_section_assignments(staff_member_id, section_id, display_order, effective_from) values
  ('00000000-0000-0000-0000-000000000278', '00000000-0000-0000-0000-000000000275', 0, '2027-02-01'),
  ('00000000-0000-0000-0000-000000000279', '00000000-0000-0000-0000-000000000275', 1, '2027-02-01'),
  ('00000000-0000-0000-0000-00000000027a', '00000000-0000-0000-0000-000000000276', 0, '2027-02-01');
insert into public.staff_job_roles(staff_member_id, job_role, effective_from) values
  ('00000000-0000-0000-0000-000000000278', 'rn', '2027-02-01'),
  ('00000000-0000-0000-0000-000000000279', 'lpn', '2027-02-01'),
  ('00000000-0000-0000-0000-00000000027a', 'cna', '2027-02-01');
insert into public.schedule_months(id, month_start, release_state, released_at, released_by_staff_member_id)
values ('00000000-0000-0000-0000-00000000027b', '2027-02-01', 'released', now(), '00000000-0000-0000-0000-000000000277');
insert into public.schedule_cells(schedule_month_id, staff_member_id, section_id, work_date, shift_code)
values ('00000000-0000-0000-0000-00000000027b', '00000000-0000-0000-0000-000000000278',
  '00000000-0000-0000-0000-000000000275', '2027-02-10', '7A');
insert into public.schedule_cells(schedule_month_id, staff_member_id, section_id, work_date, shift_code)
values ('00000000-0000-0000-0000-00000000027b', '00000000-0000-0000-0000-000000000278',
  '00000000-0000-0000-0000-000000000275', '2027-02-11', '7P');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000272","role":"authenticated"}', true);
select lives_ok($$select public.submit_request_off(array['2027-02-10']::date[], null)$$, 'RN requests off');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000271","role":"authenticated"}', true);
select lives_ok($$select public.decide_request_off((select id from public.requests_off limit 1), 'approved', null)$$, 'Manager approves Request off');
reset role;
select is((select count(*)::int from public.staff_notices where kind = 'open_shift_posted' and staff_member_id = '00000000-0000-0000-0000-000000000279'), 1,
  'eligible LPN receives Open shift post');
select is((select count(*)::int from public.staff_notices where kind = 'open_shift_posted' and staff_member_id = '00000000-0000-0000-0000-00000000027a'), 0,
  'ineligible CNA receives no Open shift post');
set local role authenticated;
select is((select count(*)::int from public.visible_open_shifts()), 1, 'Manager sees Open shift');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000274","role":"authenticated"}', true);
select is((select count(*)::int from public.visible_open_shifts()), 0, 'CNA cannot see nursing shift');
select throws_ok($$select public.request_open_shift_pickup((select id from public.short_shifts limit 1))$$,
  'This Open shift is outside your role', 'CNA cannot request nursing shift');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000273","role":"authenticated"}', true);
select is((select count(*)::int from public.visible_open_shifts()), 1, 'LPN sees RN shift');
select lives_ok($$select public.request_open_shift_pickup((select id from public.short_shifts limit 1))$$, 'LPN requests pickup');
select is((select count(*)::int from public.open_shift_pickups where status = 'pending'), 1, 'pickup waits for Manager');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000271","role":"authenticated"}', true);
select is((select count(*)::int from public.staff_notices where kind = 'open_shift_pickup'), 1,
  'Manager receives pickup request notice');
select lives_ok($$select public.approve_open_shift_pickup((select id from public.open_shift_pickups limit 1))$$, 'Manager approves pickup');
select is((select shift_code from public.schedule_cells where staff_member_id = '00000000-0000-0000-0000-000000000279' and work_date = '2027-02-10'), '7A', 'LPN gets shift');
select is((select count(*)::int from public.short_shifts where filled_at is null), 0, 'short mark clears');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000273","role":"authenticated"}', true);
select is((select count(*)::int from public.staff_notices where title = 'Open shift pickup approved'),
  1, 'LPN receives approval notice');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000271","role":"authenticated"}', true);
select public.save_schedule_cell('00000000-0000-0000-0000-000000000279'::uuid,
  '00000000-0000-0000-0000-000000000275'::uuid, '2027-02-11'::date, '7P');
select lives_ok($$select public.set_staff_last_day('00000000-0000-0000-0000-000000000278'::uuid, '2027-02-10'::date)$$,
  'Manager sets Last day');
reset role;
select is((select count(*)::int from public.staff_notices where kind = 'open_shift_posted' and staff_member_id = '00000000-0000-0000-0000-000000000279'), 1,
  'busy LPN is not notified about a shift they cannot pick up');
set local role authenticated;
select public.save_schedule_cell('00000000-0000-0000-0000-000000000279'::uuid,
  '00000000-0000-0000-0000-000000000275'::uuid, '2027-02-11'::date, 'X');
select is((select count(*)::int from public.visible_open_shifts() where work_date = '2027-02-11'),
  1, 'later RN shift remains open after original role ends');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000273","role":"authenticated"}', true);
select is((select count(*)::int from public.visible_open_shifts() where work_date = '2027-02-11'),
  0, 'LPN cannot see shift after original RN Last day ends role');

reset role;
update public.staff_job_roles set effective_through = '2027-02-13'
where staff_member_id = '00000000-0000-0000-0000-000000000278';
insert into public.short_shifts(schedule_month_id, section_id, work_date,
  shift_code, staff_member_id, reason)
values ('00000000-0000-0000-0000-00000000027b',
  '00000000-0000-0000-0000-000000000275', '2027-02-13', '7A',
  '00000000-0000-0000-0000-000000000278', 'last_day');
set local role authenticated;
select is((select count(*)::int from public.visible_open_shifts() where work_date = '2027-02-13'),
  1, 'LPN sees shift while original RN role is active');

select lives_ok($$select public.request_open_shift_pickup(
  (select id from public.short_shifts where work_date = '2027-02-13'))$$,
  'LPN requests shift while original RN role is active');
reset role;
update public.staff_job_roles set effective_through = '2027-02-10'
where staff_member_id = '00000000-0000-0000-0000-000000000278';
insert into public.staff_job_roles(staff_member_id, job_role, effective_from)
values ('00000000-0000-0000-0000-000000000278', 'cna', '2027-02-12');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000271","role":"authenticated"}', true);
insert into public.short_shifts(schedule_month_id, section_id, work_date,
  shift_code, staff_member_id, reason)
values ('00000000-0000-0000-0000-00000000027b',
  '00000000-0000-0000-0000-000000000275', '2027-02-11', '7A',
  '00000000-0000-0000-0000-000000000278', 'last_day');
select is((select count(*)::int from public.staff_notices
  where kind = 'open_shift_posted' and staff_member_id = '00000000-0000-0000-0000-000000000279'
    and body like '%2027-02-11%'), 0,
  'LPN is not notified about a shift after original RN role ends');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000273","role":"authenticated"}', true);
select is((select count(*)::int from public.visible_open_shifts() where work_date = '2027-02-11'),
  0, 'LPN cannot see shift after original RN role ends');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000271","role":"authenticated"}', true);
select throws_ok($$select public.approve_open_shift_pickup(
  (select id from public.open_shift_pickups where short_shift_id =
    (select id from public.short_shifts where work_date = '2027-02-13')))$$,
  'Staff member is no longer eligible', 'Manager cannot approve pickup after original RN role ends');
reset role;
delete from public.open_shift_pickups where short_shift_id =
  (select id from public.short_shifts where work_date = '2027-02-13');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000273","role":"authenticated"}', true);
select throws_ok($$select public.request_open_shift_pickup(
  (select id from public.short_shifts where work_date = '2027-02-13'))$$,
  'This Open shift is outside your role', 'LPN cannot request shift after original RN role ends');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000274","role":"authenticated"}', true);
select is((select count(*)::int from public.visible_open_shifts() where work_date = '2027-02-13'),
  1, 'CNA sees shift after original Staff member changes to CNA');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000273","role":"authenticated"}', true);
select is((select count(*)::int from public.visible_open_shifts() where work_date = '2027-02-13'),
  0, 'LPN does not see shift after original Staff member changes to CNA');

select * from finish();
rollback;
