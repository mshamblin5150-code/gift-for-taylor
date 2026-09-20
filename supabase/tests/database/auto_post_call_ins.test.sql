begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000001471', 'auto-manager@example.test'),
  ('00000000-0000-0000-0000-000000001472', 'auto-picker@example.test');
insert into public.sections(id, name, display_order) values
  ('00000000-0000-0000-0000-000000001473', 'Auto-post nurses', 147);
insert into public.staff_members(id, display_name, role) values
  ('00000000-0000-0000-0000-000000001471', 'Auto Manager', 'manager'),
  ('00000000-0000-0000-0000-000000001472', 'Auto Picker', 'staff_member'),
  ('00000000-0000-0000-0000-000000001474', 'Auto RN', 'staff_member'),
  ('00000000-0000-0000-0000-000000001475', 'Auto LPN one', 'staff_member'),
  ('00000000-0000-0000-0000-000000001476', 'Auto LPN two', 'staff_member'),
  ('00000000-0000-0000-0000-000000001477', 'Auto LPN three', 'staff_member');
insert into public.staff_accounts(staff_member_id, auth_user_id, personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000001471', '00000000-0000-0000-0000-000000001471', 'auto-manager@example.test', now()),
  ('00000000-0000-0000-0000-000000001472', '00000000-0000-0000-0000-000000001472', 'auto-picker@example.test', now());
insert into public.staff_section_assignments(staff_member_id, section_id, display_order, effective_from)
select id, '00000000-0000-0000-0000-000000001473', row_number() over (order by id)::integer, '2027-04-01'
from public.staff_members where id in (
  '00000000-0000-0000-0000-000000001472', '00000000-0000-0000-0000-000000001474',
  '00000000-0000-0000-0000-000000001475', '00000000-0000-0000-0000-000000001476',
  '00000000-0000-0000-0000-000000001477');
insert into public.staff_job_roles(staff_member_id, job_role, effective_from) values
  ('00000000-0000-0000-0000-000000001472', 'lpn', '2027-04-01'),
  ('00000000-0000-0000-0000-000000001474', 'rn', '2027-04-01'),
  ('00000000-0000-0000-0000-000000001475', 'lpn', '2027-04-01'),
  ('00000000-0000-0000-0000-000000001476', 'lpn', '2027-04-01'),
  ('00000000-0000-0000-0000-000000001477', 'lpn', '2027-04-01');
insert into public.schedule_months(id, month_start, release_state, released_at, released_by_staff_member_id) values
  ('00000000-0000-0000-0000-000000001478', '2027-04-01', 'released', now(),
   '00000000-0000-0000-0000-000000001471'),
  ('00000000-0000-0000-0000-000000001479', '2027-05-01', 'unpublished', null, null);
insert into public.schedule_cells(schedule_month_id, staff_member_id, section_id, work_date, shift_code)
select case when d.work_date < '2027-05-01' then '00000000-0000-0000-0000-000000001478'::uuid
    else '00000000-0000-0000-0000-000000001479'::uuid end,
  member.id, '00000000-0000-0000-0000-000000001473', d.work_date, '7A'
from (values ('2027-04-14'::date), ('2027-04-15'), ('2027-04-16'),
  ('2027-04-17'), ('2027-05-14')) d(work_date)
cross join public.staff_members member
where member.id in ('00000000-0000-0000-0000-000000001474',
  '00000000-0000-0000-0000-000000001475', '00000000-0000-0000-0000-000000001476')
  or d.work_date = '2027-04-15' and member.id = '00000000-0000-0000-0000-000000001477';

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000001471","role":"authenticated"}', true);
select public.set_open_shift_approval_default(false);
select public.save_schedule_cell('00000000-0000-0000-0000-000000001475',
  '00000000-0000-0000-0000-000000001473', '2027-04-14', 'C/I');
select is((select count(*)::integer from public.short_shifts where work_date = '2027-04-14'), 1,
  'three on against three: one Call-in posts one Open shift');
select is((select count(*)::integer from public.short_shifts where work_date = '2027-04-14'
  and reason = 'call_in' and call_in_change_id is not null and not requires_approval), 1,
  'ordinary Call-in is self-service despite Manager default');
select public.save_schedule_cell('00000000-0000-0000-0000-000000001475',
  '00000000-0000-0000-0000-000000001473', '2027-04-15', 'C/I');
select is((select count(*)::integer from public.short_shifts where work_date = '2027-04-15'), 0,
  'four on against three: one Call-in posts nothing');
select public.save_schedule_cell('00000000-0000-0000-0000-000000001474',
  '00000000-0000-0000-0000-000000001473', '2027-04-16', 'C/I');
select is((select count(*)::integer from public.short_shifts where work_date = '2027-04-16'
  and rn_floor_critical and requires_approval), 1, 'sole RN Call-in posts approved floor shift');
select is((select count(*)::integer from public.staff_notices where kind = 'floor_critical_call_in'
  and staff_member_id = '00000000-0000-0000-0000-000000001471'
  and month_start = '2027-04-01'), 1, 'Manager is pushed for released floor-critical shift');
select public.save_schedule_cell('00000000-0000-0000-0000-000000001475',
  '00000000-0000-0000-0000-000000001473', '2027-04-14', 'S/L');
select is((select count(*)::integer from public.short_shifts where work_date = '2027-04-14'), 1,
  'Call-in classified as Sick leave posts no second shift');
select public.save_schedule_cell('00000000-0000-0000-0000-000000001475',
  '00000000-0000-0000-0000-000000001473', '2027-04-17', 'S/L');
select is((select count(*)::integer from public.short_shifts where work_date = '2027-04-17'
  and reason = 'sick_leave' and not requires_approval), 1, 'Manager Sick leave posts the same gap');
select public.save_schedule_cell('00000000-0000-0000-0000-000000001474',
  '00000000-0000-0000-0000-000000001473', '2027-05-14', 'C/I');
select is((select count(*)::integer from public.staff_notices where kind = 'floor_critical_call_in'
  and month_start = '2027-05-01'), 0, 'unpublished Call-in does not push');
reset role;
update public.schedule_months set release_state = 'released', released_at = now(),
  released_by_staff_member_id = '00000000-0000-0000-0000-000000001471'
where month_start = '2027-05-01';
select is((select count(*)::integer from public.staff_notices where kind = 'floor_critical_call_in'
  and month_start = '2027-05-01'), 1, 'month release replays floor-critical notice');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000001471","role":"authenticated"}', true);
select public.withdraw_call_in('00000000-0000-0000-0000-000000001474', '2027-05-14');
select is((select count(*)::integer from public.short_shifts where work_date = '2027-05-14'), 0,
  'withdrawal removes its auto-posted Open shift');
select is((select count(*)::integer from public.staff_notices where kind = 'floor_critical_call_in'
  and month_start = '2027-05-01'), 0, 'withdrawal removes the Manager posting notice');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000001472","role":"authenticated"}', true);
select throws_ok($$select public.post_open_shifts('2027-04-18', '7A', 'nurses', 1, true)$$,
  'Only the Manager can post Open shifts', 'Staff cannot hand-post');
select throws_ok($$select public.save_schedule_cell('00000000-0000-0000-0000-000000001476',
  '00000000-0000-0000-0000-000000001473', '2027-04-14', 'S/L')$$,
  'Only the Manager can edit the Schedule', 'floor nurse cannot classify Sick leave');
select is((select status from public.request_open_shift_pickup(
  (select id from public.short_shifts where work_date = '2027-04-14'))), 'approved',
  'ordinary Call-in shift is immediately pickup-able');
select is((select filled_at is not null from public.short_shifts where work_date = '2027-04-14'), true,
  'self-service pickup fills the Open shift');
select is((select count(*)::integer from public.short_shifts where work_date = '2027-04-16'
  and requires_approval), 1, 'floor-critical shift remains approval-gated');
select is((select count(*)::integer from public.short_shifts where work_date = '2027-04-15'), 0,
  'overstaffed day remains without a posting');
select * from finish();
rollback;
