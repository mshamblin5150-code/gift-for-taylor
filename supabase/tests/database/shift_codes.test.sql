begin;
create extension if not exists pgtap with schema extensions;
select plan(28);

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000000571', 'codes-manager@example.test'),
  ('00000000-0000-0000-0000-000000000572', 'codes-staff@example.test');
insert into public.staff_members(id, display_name, role) values
  ('00000000-0000-0000-0000-000000000573', 'Codes Manager', 'manager'),
  ('00000000-0000-0000-0000-000000000574', 'Codes Staff', 'staff_member');
insert into public.staff_accounts(staff_member_id, auth_user_id, personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000000573', '00000000-0000-0000-0000-000000000571', 'codes-manager@example.test', now()),
  ('00000000-0000-0000-0000-000000000574', '00000000-0000-0000-0000-000000000572', 'codes-staff@example.test', now());
insert into public.sections(id, name, display_order) values
  ('00000000-0000-0000-0000-000000000575', 'Codes Section', 999);
insert into public.schedule_months(id, month_start, release_state, released_at, released_by_staff_member_id)
values ('00000000-0000-0000-0000-000000000576', '2027-03-01', 'released', now(),
  '00000000-0000-0000-0000-000000000573');
insert into public.schedule_cells(schedule_month_id, staff_member_id, section_id, work_date, shift_code)
values ('00000000-0000-0000-0000-000000000576', '00000000-0000-0000-0000-000000000574',
  '00000000-0000-0000-0000-000000000575', '2027-03-04', '7A');
create temp table code_cell_before as
select updated_at from public.schedule_cells where work_date = '2027-03-04';
grant select on code_cell_before to authenticated;

select is((select count(*)::int from public.shift_codes where active), 14,
  'the active catalog excludes the three obsolete codes and includes C/I');
select is((select count(*)::int from public.shift_codes
  where code in ('4P', '9-7', '7-5') and active), 0,
  'obsolete untimed codes are not active');
select is((select meaning from public.shift_codes where code = 'C/I'), 'Called in',
  'C/I has its default meaning');
select is(public.is_working_shift('C/I'), false, 'C/I is not worked');
select is((select count(*)::int from public.shift_codes
  where code in ('16D', '7A', 'D', 'MM', '11A') and coverage_window = 'day'), 5,
  'all five timed Day codes have Day coverage');
select is((select count(*)::int from public.shift_codes
  where code in ('3P', '7P', 'ME', 'N') and coverage_window = 'night'), 4,
  'all four timed Night codes have Night coverage, including midnight wraps');
select is((select count(*)::int from public.shift_codes
  where start_time is null and coverage_window is not null), 0,
  'hourless codes have no coverage window');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000572","role":"authenticated"}', true);
select throws_ok($$select public.save_shift_code('NEW', null, null, null, true, null)$$,
  'Only the Manager can edit Shift codes', 'Staff cannot edit the catalog');
select is((select count(*)::int from public.shift_codes where active), 14,
  'Staff can read the catalog');

create temp table code_feed(token text);
grant select, insert on code_feed to authenticated, service_role;
insert into code_feed
select public.create_calendar_subscription('Shift code test')->>'token';

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000571","role":"authenticated"}', true);
select lives_ok($$select public.save_shift_code('7A', 'Day coverage', '08:00', '20:00', true, 'night', '7A')$$,
  'Manager edits an existing code');
select is((select coverage_window from public.shift_codes where code = '7A'), 'night',
  'Manager can override the inferred window');
select lives_ok($$select public.save_shift_code('7A', 'Revised meaning', '08:00', '20:00', true, 'night', '7A')$$,
  'Manager makes an unrelated edit');
select is((select coverage_window from public.shift_codes where code = '7A'), 'night',
  'the explicit window survives the unrelated edit');
select is((select shift_code from public.schedule_cells where work_date = '2027-03-04'), '7A',
  'editing hours leaves the historical cell unchanged');
select ok((select cell.updated_at > previous.updated_at
  from public.schedule_cells cell cross join code_cell_before previous
  where cell.work_date = '2027-03-04'),
  'editing hours advances the calendar event modification time');
select throws_ok($$select public.delete_shift_code('7A')$$,
  'A Shift code in use cannot be deleted', 'used code cannot be deleted');
select lives_ok($$select public.save_shift_code('TRAIN', 'Training', null, null, false, null)$$,
  'Manager adds a code with a meaning and no hours');
select is((select coverage_window from public.shift_codes where code = 'TRAIN'), null,
  'new hourless codes have no window');
select is(public.is_working_shift('TRAIN'), false,
  'working-shift checks use the catalog');
select lives_ok($$select public.save_shift_code('TRAIN', 'Coverage', null, null, true, null, 'TRAIN')$$,
  'Manager can change whether a code is worked');
select is(public.is_working_shift('TRAIN'), true,
  'changed working flag takes effect immediately');
select lives_ok($$select public.delete_shift_code('TRAIN')$$,
  'unused code can be deleted');
select lives_ok($$select public.save_shift_code('DAY', 'New code', '09:00', '21:00', true, 'day', '7A')$$,
  'used Shift code can be renamed without changing old cells');
select is((select shift_code from public.schedule_cells where work_date = '2027-03-04'), '7A',
  'old Schedule cell retains the historical code after rename');
select is((select active from public.shift_codes where code = '7A'), false,
  'historical code is hidden from the active legend');
select is((select count(*)::int from public.shift_codes where code = 'DAY' and active), 1,
  'new code is available in the active legend');

reset role;
insert into public.schedule_cells(schedule_month_id, staff_member_id, section_id, work_date, shift_code)
values ('00000000-0000-0000-0000-000000000576', '00000000-0000-0000-0000-000000000574',
  '00000000-0000-0000-0000-000000000575', '2027-03-05', 'ADHOC');
select is((select coverage_window from public.shift_codes where code = 'ADHOC'), null,
  'free-hand codes are registered without hours or a window');
set local role service_role;
select is((select starts_at from code_feed,
  lateral public.calendar_feed_events(token) where work_date = '2027-03-04'),
  '2027-03-04 13:00:00+00'::timestamptz,
  'Calendar feed reinterprets the saved cell using the edited hours');

select * from finish();
rollback;
