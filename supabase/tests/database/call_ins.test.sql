begin;
set local time zone 'America/New_York';
create extension if not exists pgtap with schema extensions;
select plan(20);

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000000901', 'call-manager@example.test'),
  ('00000000-0000-0000-0000-000000000902', 'call-recorder@example.test'),
  ('00000000-0000-0000-0000-000000000903', 'call-other@example.test');
insert into public.sections(id, name, display_order) values
  ('00000000-0000-0000-0000-000000000904', 'Call-in RN', 901);
insert into public.staff_members(id, display_name, role) values
  ('00000000-0000-0000-0000-000000000905', 'Call Manager', 'manager'),
  ('00000000-0000-0000-0000-000000000906', 'Call Recorder', 'staff_member'),
  ('00000000-0000-0000-0000-000000000907', 'Call Target', 'staff_member');
insert into public.staff_accounts(staff_member_id, auth_user_id, personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000000905', '00000000-0000-0000-0000-000000000901', 'call-manager@example.test', now()),
  ('00000000-0000-0000-0000-000000000906', '00000000-0000-0000-0000-000000000902', 'call-recorder@example.test', now()),
  ('00000000-0000-0000-0000-000000000907', '00000000-0000-0000-0000-000000000903', 'call-other@example.test', now());
insert into public.staff_section_assignments(staff_member_id, section_id, display_order, effective_from) values
  ('00000000-0000-0000-0000-000000000906', '00000000-0000-0000-0000-000000000904', 0, current_date - 1),
  ('00000000-0000-0000-0000-000000000907', '00000000-0000-0000-0000-000000000904', 1, current_date - 1);
insert into public.schedule_months(id, month_start) values
  ('00000000-0000-0000-0000-000000000908', date_trunc('month', current_date)::date)
  on conflict (month_start) do nothing;
insert into public.schedule_months(id, month_start) values
  ('00000000-0000-0000-0000-000000000909', '2027-10-01');
insert into public.schedule_cells(schedule_month_id, staff_member_id, section_id, work_date, shift_code)
select month.id, '00000000-0000-0000-0000-000000000906',
  '00000000-0000-0000-0000-000000000904', current_date, 'ADHOC'
from public.schedule_months month where month.month_start = date_trunc('month', current_date)::date;
insert into public.schedule_cells(schedule_month_id, staff_member_id, section_id, work_date, shift_code) values
  ('00000000-0000-0000-0000-000000000909', '00000000-0000-0000-0000-000000000907',
   '00000000-0000-0000-0000-000000000904', '2027-10-14', '7A'),
  ('00000000-0000-0000-0000-000000000909', '00000000-0000-0000-0000-000000000907',
   '00000000-0000-0000-0000-000000000904', '2027-10-15', '7P');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000902","role":"authenticated"}', true);
select lives_ok($$select public.record_call_in('00000000-0000-0000-0000-000000000907', '2027-10-14')$$,
  'working Staff member records a colleague on another day');
reset role;
select is((select shift_code from public.schedule_cells where staff_member_id =
  '00000000-0000-0000-0000-000000000907' and work_date = '2027-10-14'), 'C/I',
  'Call-in writes the target cell');
set local role authenticated;
select throws_ok($$select public.record_call_in('00000000-0000-0000-0000-000000000907', '2027-10-14')$$,
  'Target has no working Shift to call in from', 'cannot record the same Call-in twice');
select throws_ok($$select public.save_schedule_cell('00000000-0000-0000-0000-000000000907',
  '00000000-0000-0000-0000-000000000904', '2027-10-15', 'X')$$,
  'Only the Manager can edit the Schedule', 'general Schedule edit remains forbidden');
select lives_ok($$select public.withdraw_call_in('00000000-0000-0000-0000-000000000907', '2027-10-14')$$,
  'recorder can withdraw an unfilled Call-in');
reset role;
select is((select shift_code from public.schedule_cells where staff_member_id =
  '00000000-0000-0000-0000-000000000907' and work_date = '2027-10-14'), '7A',
  'withdrawal restores the exact previous Shift code');
set local role authenticated;
select throws_ok($$select public.withdraw_call_in('00000000-0000-0000-0000-000000000907', '2027-10-14')$$,
  'There is no Call-in to withdraw', 'withdrawal cannot be repeated');

reset role;
insert into public.schedule_cells(schedule_month_id, staff_member_id, section_id, work_date, shift_code)
select month.id, '00000000-0000-0000-0000-000000000907',
  '00000000-0000-0000-0000-000000000904', current_date, '7A'
from public.schedule_months month where month.month_start = date_trunc('month', current_date)::date;
set local role authenticated;
select lives_ok($$select public.record_call_in('00000000-0000-0000-0000-000000000907', current_date)$$,
  'working Staff member can record a colleague on the same day');
select lives_ok($$select public.withdraw_call_in('00000000-0000-0000-0000-000000000907', current_date)$$,
  'same-day Call-in is withdrawable');
reset role;
update public.schedule_cells set shift_code = case
  when (clock_timestamp() at time zone 'America/New_York')::time < time '07:00'
    or (clock_timestamp() at time zone 'America/New_York')::time >= time '19:00'
    then '7A' else '7P' end
where staff_member_id = '00000000-0000-0000-0000-000000000906' and work_date = current_date;
set local role authenticated;
select throws_ok($$select public.record_call_in('00000000-0000-0000-0000-000000000907', '2027-10-15')$$,
  'You must be working when you record a Call-in',
  'Staff member scheduled later or already off duty cannot record');
reset role;
delete from public.schedule_cells where staff_member_id = '00000000-0000-0000-0000-000000000906' and work_date = current_date;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000902","role":"authenticated"}', true);
select throws_ok($$select public.record_call_in('00000000-0000-0000-0000-000000000907', '2027-10-15')$$,
  'You must be working when you record a Call-in', 'off-duty Staff member is refused with a reason');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000901","role":"authenticated"}', true);
select lives_ok($$select public.record_call_in('00000000-0000-0000-0000-000000000907', '2027-10-15')$$,
  'Manager can record while off-duty');
reset role;

insert into public.short_shifts(schedule_month_id, work_date, shift_code, reason, job_role,
  call_in_change_id, requires_approval) values
  ('00000000-0000-0000-0000-000000000909', '2027-10-15', '7P', 'manual', 'rn',
   (select id from public.schedule_changes where staff_member_id = '00000000-0000-0000-0000-000000000907'
     and work_date = '2027-10-15' and new_shift_code = 'C/I'), true);
insert into public.open_shift_pickups(short_shift_id, staff_member_id)
select id, '00000000-0000-0000-0000-000000000906' from public.short_shifts
where call_in_change_id is not null;
insert into public.staff_notices(staff_member_id, kind, title, body, month_start, short_shift_id)
select '00000000-0000-0000-0000-000000000906', 'open_shift_posted', 'Open shift posted',
  'Test posting', '2027-10-01', id from public.short_shifts where call_in_change_id is not null;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000901","role":"authenticated"}', true);
select lives_ok($$select public.withdraw_call_in('00000000-0000-0000-0000-000000000907', '2027-10-15')$$,
  'withdrawal revokes its Open shift and pending pickup');
reset role;
select is((select count(*)::integer from public.short_shifts where call_in_change_id is not null), 0,
  'no Call-in Open shift remains');
select is((select count(*)::integer from public.open_shift_pickups), 0,
  'no orphan pickup remains');
select is((select count(*)::integer from public.staff_notices where title = 'Open shift posted'
  and body = 'Test posting'), 0, 'posting notice is withdrawn');
select is((select count(*)::integer from public.staff_notices where title = 'Open shift withdrawn'), 1,
  'pending picker is told the shift went away');
select is((select shift_code from public.schedule_cells where staff_member_id =
  '00000000-0000-0000-0000-000000000907' and work_date = '2027-10-15'), '7P',
  'restoration also works after a pending pickup');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000901","role":"authenticated"}', true);
select public.record_call_in('00000000-0000-0000-0000-000000000907', '2027-10-15');
reset role;
insert into public.short_shifts(schedule_month_id, work_date, shift_code, reason, job_role,
  call_in_change_id, filled_at) values
  ('00000000-0000-0000-0000-000000000909', '2027-10-15', '7P', 'manual', 'rn',
   (select id from public.schedule_changes where staff_member_id = '00000000-0000-0000-0000-000000000907'
     and work_date = '2027-10-15' and new_shift_code = 'C/I' order by changed_at desc limit 1), now());
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000901","role":"authenticated"}', true);
select throws_ok($$select public.withdraw_call_in('00000000-0000-0000-0000-000000000907', '2027-10-15')$$,
  'A Call-in is settled once an Open shift is filled', 'filled shift prevents withdrawal');
select is((select shift_code from public.schedule_cells where staff_member_id =
  '00000000-0000-0000-0000-000000000907' and work_date = '2027-10-15'), 'C/I',
  'failed withdrawal leaves the caller on Call-in');
select * from finish();
rollback;
