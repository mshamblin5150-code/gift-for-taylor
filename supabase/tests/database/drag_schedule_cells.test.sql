begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000581', 'drag-manager@example.test'),
  ('00000000-0000-0000-0000-000000000582', 'drag-staff@example.test'),
  ('00000000-0000-0000-0000-000000000587', 'drag-scheduler@example.test');
insert into public.sections (id, name, display_order) values
  ('00000000-0000-0000-0000-000000000583', 'Drag test Section', 99),
  ('00000000-0000-0000-0000-000000000588', 'Other drag Section', 100);
insert into public.staff_members (id, display_name, role) values
  ('00000000-0000-0000-0000-000000000584', 'Drag Manager', 'manager'),
  ('00000000-0000-0000-0000-000000000585', 'First RN', 'staff_member'),
  ('00000000-0000-0000-0000-000000000586', 'Second RN', 'staff_member'),
  ('00000000-0000-0000-0000-000000000589', 'Night scheduler', 'night_scheduler');
insert into public.staff_accounts
  (staff_member_id, auth_user_id, personal_email, accepted_invite_at)
values
  ('00000000-0000-0000-0000-000000000584',
   '00000000-0000-0000-0000-000000000581', 'drag-manager@example.test', now()),
  ('00000000-0000-0000-0000-000000000585',
   '00000000-0000-0000-0000-000000000582', 'drag-staff@example.test', now()),
  ('00000000-0000-0000-0000-000000000589',
   '00000000-0000-0000-0000-000000000587', 'drag-scheduler@example.test', now());
insert into public.staff_section_assignments
  (staff_member_id, section_id, display_order, effective_from)
values
  ('00000000-0000-0000-0000-000000000585', '00000000-0000-0000-0000-000000000583', 1, '2027-03-01'),
  ('00000000-0000-0000-0000-000000000586', '00000000-0000-0000-0000-000000000588', 2, '2027-03-01');
insert into public.night_scheduler_sections (staff_member_id, section_id) values
  ('00000000-0000-0000-0000-000000000589', '00000000-0000-0000-0000-000000000583');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000581","role":"authenticated"}', true);
select public.save_schedule_cell('00000000-0000-0000-0000-000000000585',
  '00000000-0000-0000-0000-000000000583', '2027-03-18', '7A');
select public.save_schedule_cell('00000000-0000-0000-0000-000000000586',
  '00000000-0000-0000-0000-000000000588', '2027-03-18', 'X');

select lives_ok($$
  select public.save_schedule_cell_pair(
    '00000000-0000-0000-0000-000000000585', '00000000-0000-0000-0000-000000000583', '2027-03-18', '7A', 'X',
    '00000000-0000-0000-0000-000000000586', '00000000-0000-0000-0000-000000000588', '2027-03-18', 'X', '7A')
$$, 'both cells save in one call');
select is((select shift_code from public.schedule_cells
  where staff_member_id = '00000000-0000-0000-0000-000000000585' and work_date = '2027-03-18'),
  'X', 'source now has the target code');
select is((select shift_code from public.schedule_cells
  where staff_member_id = '00000000-0000-0000-0000-000000000586' and work_date = '2027-03-18'),
  '7A', 'target now has the source code');
select throws_ok($$
  select public.save_schedule_cell_pair(
    '00000000-0000-0000-0000-000000000585', '00000000-0000-0000-0000-000000000583', '2027-03-18', '7A', 'N',
    '00000000-0000-0000-0000-000000000586', '00000000-0000-0000-0000-000000000588', '2027-03-18', '7A', 'X')
$$, 'The Schedule changed. Reload and try again.', 'a stale source is refused');
select is((select count(*)::integer from public.schedule_changes
  where work_date = '2027-03-18' and staff_member_id in
    ('00000000-0000-0000-0000-000000000585', '00000000-0000-0000-0000-000000000586')),
  4, 'a refused drop writes no Schedule change');

select public.save_schedule_cell('00000000-0000-0000-0000-000000000585',
  '00000000-0000-0000-0000-000000000583', '2027-03-18', '7A');
select lives_ok($$
  select public.save_schedule_cell_pair(
    '00000000-0000-0000-0000-000000000585', '00000000-0000-0000-0000-000000000583', '2027-03-18', '7A', '7A',
    '00000000-0000-0000-0000-000000000585', '00000000-0000-0000-0000-000000000583', '2027-03-19', '', '7A')
$$, 'copying a code across days succeeds');
select is((select shift_code from public.schedule_cells
  where staff_member_id = '00000000-0000-0000-0000-000000000585' and work_date = '2027-03-18'),
  '7A', 'copying leaves the source in place');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000587","role":"authenticated"}', true);
select throws_ok($$
  select public.save_schedule_cell_pair(
    '00000000-0000-0000-0000-000000000585', '00000000-0000-0000-0000-000000000583', '2027-03-18', '7A', 'X',
    '00000000-0000-0000-0000-000000000586', '00000000-0000-0000-0000-000000000588', '2027-03-18', '7A', 'X')
$$, 'You cannot edit both Sections', 'Night scheduler cannot drop into another Section');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000582","role":"authenticated"}', true);
select throws_ok($$
  select public.save_schedule_cell_pair(
    '00000000-0000-0000-0000-000000000585', '00000000-0000-0000-0000-000000000583', '2027-03-18', '7A', 'X',
    '00000000-0000-0000-0000-000000000586', '00000000-0000-0000-0000-000000000588', '2027-03-18', '7A', 'X')
$$, 'You cannot edit both Sections', 'Staff member cannot drag either cell');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000581","role":"authenticated"}', true);
select is((select count(*)::integer from public.schedule_changes
  where work_date = '2027-03-18' and staff_member_id in
    ('00000000-0000-0000-0000-000000000585', '00000000-0000-0000-0000-000000000586')),
  5, 'refused drags leave both cells unchanged');

select * from finish();
rollback;
