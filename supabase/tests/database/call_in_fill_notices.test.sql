begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000001491', 'fill-manager@example.test'),
  ('00000000-0000-0000-0000-000000001492', 'fill-recorder@example.test'),
  ('00000000-0000-0000-0000-000000001493', 'fill-taker@example.test');
insert into public.sections(id, name, display_order) values
  ('00000000-0000-0000-0000-000000001494', 'Fill nurses', 149);
insert into public.staff_members(id, display_name, role) values
  ('00000000-0000-0000-0000-000000001491', 'Fill Manager', 'manager'),
  ('00000000-0000-0000-0000-000000001492', 'Fill Recorder', 'staff_member'),
  ('00000000-0000-0000-0000-000000001493', 'Fill Taker', 'staff_member'),
  ('00000000-0000-0000-0000-000000001495', 'Fill Caller', 'staff_member'),
  ('00000000-0000-0000-0000-000000001496', 'Fill Colleague', 'staff_member');
insert into public.staff_accounts(staff_member_id, auth_user_id, personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000001491', '00000000-0000-0000-0000-000000001491', 'fill-manager@example.test', now()),
  ('00000000-0000-0000-0000-000000001492', '00000000-0000-0000-0000-000000001492', 'fill-recorder@example.test', now()),
  ('00000000-0000-0000-0000-000000001493', '00000000-0000-0000-0000-000000001493', 'fill-taker@example.test', now());
insert into public.staff_section_assignments(staff_member_id, section_id, display_order, effective_from)
select id, '00000000-0000-0000-0000-000000001494', row_number() over (order by id)::integer, current_date - 1
from public.staff_members where id in (
  '00000000-0000-0000-0000-000000001492', '00000000-0000-0000-0000-000000001493',
  '00000000-0000-0000-0000-000000001495', '00000000-0000-0000-0000-000000001496');
insert into public.staff_job_roles(staff_member_id, job_role, effective_from)
select id, case when id = '00000000-0000-0000-0000-000000001492'
  then 'rn'::public.job_role else 'lpn'::public.job_role end, current_date - 1
from public.staff_members where id in (
  '00000000-0000-0000-0000-000000001492', '00000000-0000-0000-0000-000000001493',
  '00000000-0000-0000-0000-000000001495', '00000000-0000-0000-0000-000000001496');
insert into public.schedule_months(id, month_start, release_state, released_at, released_by_staff_member_id)
values ('00000000-0000-0000-0000-000000001497', '2027-04-01', 'released', now(),
  '00000000-0000-0000-0000-000000001491');
insert into public.schedule_months(month_start) values (date_trunc('month', current_date)::date)
on conflict (month_start) do nothing;
insert into public.schedule_cells(schedule_month_id, staff_member_id, section_id, work_date, shift_code)
select month.id, '00000000-0000-0000-0000-000000001492',
  '00000000-0000-0000-0000-000000001494', current_date, 'ADHOC'
from public.schedule_months month where month.month_start = date_trunc('month', current_date)::date;
insert into public.schedule_cells(schedule_month_id, staff_member_id, section_id, work_date, shift_code)
select '00000000-0000-0000-0000-000000001497', member.id,
  '00000000-0000-0000-0000-000000001494', day.work_date, '7A'
from (values ('2027-04-14'::date), ('2027-04-15'::date), ('2027-04-16'::date)) day(work_date)
cross join public.staff_members member
where member.id in ('00000000-0000-0000-0000-000000001492',
  '00000000-0000-0000-0000-000000001495', '00000000-0000-0000-0000-000000001496');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000001492","role":"authenticated"}', true);
select public.record_call_in('00000000-0000-0000-0000-000000001495', '2027-04-14');
reset role;
select is((select count(*)::integer from public.staff_notices where kind = 'call_in_filled'
  and month_start = '2027-04-01'), 0, 'posting does not send fill notices');
select is((select count(*)::integer from public.staff_notices where kind = 'open_shift_posted'
  and short_shift_id = (select id from public.short_shifts where work_date = '2027-04-14')
  and staff_member_id in ('00000000-0000-0000-0000-000000001492',
    '00000000-0000-0000-0000-000000001495')),
  0, 'caller and recorder remain excluded from posting');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000001493","role":"authenticated"}', true);
select is((select status from public.request_open_shift_pickup(
  (select id from public.short_shifts where work_date = '2027-04-14'))), 'approved',
  'self-service fills the Call-in Open shift');
reset role;
select is((select count(*)::integer from public.staff_notices where kind = 'call_in_filled'
  and short_shift_id = (select id from public.short_shifts where work_date = '2027-04-14')
  and staff_member_id = '00000000-0000-0000-0000-000000001495' and push_eligible), 1,
  'caller gets a push-eligible notice without an account');
select is((select count(*)::integer from public.staff_notices where kind = 'call_in_filled'
  and short_shift_id = (select id from public.short_shifts where work_date = '2027-04-14')
  and staff_member_id = '00000000-0000-0000-0000-000000001492' and push_eligible), 1,
  'recorder gets a push-eligible notice');
select is((select count(*)::integer from public.staff_notices where kind = 'call_in_filled'
  and short_shift_id = (select id from public.short_shifts where work_date = '2027-04-14')
  and staff_member_id = '00000000-0000-0000-0000-000000001491' and not push_eligible), 1,
  'Manager gets one quiet notice');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000001491","role":"authenticated"}', true);
select public.save_schedule_cell('00000000-0000-0000-0000-000000001495',
  '00000000-0000-0000-0000-000000001494', '2027-04-15', 'C/I');
select public.set_open_shift_approval((select id from public.short_shifts where work_date = '2027-04-15'), true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000001493","role":"authenticated"}', true);
select is((select status from public.request_open_shift_pickup(
  (select id from public.short_shifts where work_date = '2027-04-15'))), 'pending',
  'approval-required Call-in waits for Manager');
select is((select count(*)::integer from public.staff_notices where kind = 'call_in_filled'
  and short_shift_id = (select id from public.short_shifts where work_date = '2027-04-15')), 0,
  'pending pickup sends no fill notice');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000001491","role":"authenticated"}', true);
select public.approve_open_shift_pickup((select id from public.open_shift_pickups where short_shift_id =
  (select id from public.short_shifts where work_date = '2027-04-15')));
reset role;
select is((select count(*)::integer from public.staff_notices where kind = 'call_in_filled'
  and short_shift_id = (select id from public.short_shifts where work_date = '2027-04-15')
  and staff_member_id = '00000000-0000-0000-0000-000000001495' and push_eligible), 1,
  'approval also tells caller');
select is((select count(*)::integer from public.staff_notices where kind = 'call_in_filled'
  and short_shift_id = (select id from public.short_shifts where work_date = '2027-04-15')
  and staff_member_id = '00000000-0000-0000-0000-000000001491' and not push_eligible), 1,
  'Manager as recorder gets one quiet notice after approval');
select is((select count(*)::integer from public.staff_notices where kind = 'call_in_filled'
  and short_shift_id = (select id from public.short_shifts where work_date = '2027-04-15')), 2,
  'Manager recorder is not double-notified');

insert into public.short_shifts(schedule_month_id, work_date, shift_code, reason, job_role)
values ('00000000-0000-0000-0000-000000001497', '2027-04-16', '7A', 'manual', 'lpn');
update public.short_shifts set filled_at = now() where reason = 'manual' and work_date = '2027-04-16';
select is((select count(*)::integer from public.staff_notices where kind = 'call_in_filled'
  and short_shift_id = (select id from public.short_shifts where reason = 'manual'
    and work_date = '2027-04-16')), 0, 'unrelated Open shift sends no Call-in notice');
select * from finish();
rollback;
