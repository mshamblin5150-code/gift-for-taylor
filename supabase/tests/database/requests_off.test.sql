begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000000261', 'request-manager@example.test'),
  ('00000000-0000-0000-0000-000000000262', 'request-staff@example.test');
insert into public.sections(id, name, display_order)
values ('00000000-0000-0000-0000-000000000263', 'Request test Section', 110);
insert into public.staff_members(id, display_name, role) values
  ('00000000-0000-0000-0000-000000000264', 'Request Manager', 'manager'),
  ('00000000-0000-0000-0000-000000000265', 'Request Staff', 'staff_member');
insert into public.staff_accounts(staff_member_id, auth_user_id, personal_email, accepted_invite_at)
values
  ('00000000-0000-0000-0000-000000000264', '00000000-0000-0000-0000-000000000261', 'request-manager@example.test', now()),
  ('00000000-0000-0000-0000-000000000265', '00000000-0000-0000-0000-000000000262', 'request-staff@example.test', now());
insert into public.staff_section_assignments(staff_member_id, section_id, display_order, effective_from)
values ('00000000-0000-0000-0000-000000000265', '00000000-0000-0000-0000-000000000263', 0, '2027-02-01');
insert into public.schedule_months(id, month_start, release_state, released_at, released_by_staff_member_id)
values ('00000000-0000-0000-0000-000000000266', '2027-02-01', 'released', now(), '00000000-0000-0000-0000-000000000264');
insert into public.schedule_cells(schedule_month_id, staff_member_id, section_id, work_date, shift_code)
values ('00000000-0000-0000-0000-000000000266', '00000000-0000-0000-0000-000000000265', '00000000-0000-0000-0000-000000000263', '2027-02-10', '7A');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000262","role":"authenticated"}', true);
select lives_ok($$select public.submit_request_off(array['2027-02-10','2027-02-11']::date[], 'Family')$$, 'Staff submits Request off');
select is((select count(*)::int from public.requests_off), 1, 'Staff sees own Request off');
select is((select count(*)::int from public.request_off_dates), 2, 'both requested days kept');
select throws_ok($$select public.decide_request_off((select id from public.requests_off limit 1), 'approved', null)$$, 'Only the Manager can decide Requests off', 'Staff cannot approve');
select lives_ok($$select public.confirm_request_off_email((select id from public.requests_off limit 1))$$, 'requester confirms email copy');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000261","role":"authenticated"}', true);
select is((select count(*)::int from public.staff_notices where kind = 'request_submitted'), 1,
  'Manager receives the submitted Request off in the shared feed');
select is((select count(*)::int from public.requests_off where decision = 'pending'), 1, 'Manager sees approval queue');
select lives_ok($$select public.decide_request_off((select id from public.requests_off limit 1), 'approved', 'Okay')$$, 'Manager approves');
select is((select shift_code from public.schedule_cells where work_date = '2027-02-10' and staff_member_id = '00000000-0000-0000-0000-000000000265'), 'R/O', 'approval writes R/O');
select is((select shift_code from public.short_shifts where work_date = '2027-02-10' and staff_member_id = '00000000-0000-0000-0000-000000000265'), '7A', 'scheduled day becomes short');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000262","role":"authenticated"}', true);
select is((select count(*)::int from public.staff_notices where kind = 'request_decided' and staff_member_id = '00000000-0000-0000-0000-000000000265'), 1, 'decision notice recorded in shared feed');
select lives_ok($$select public.acknowledge_request_off_notices()$$, 'Staff opens notices');
select is((select count(*)::int from public.staff_notices where kind = 'request_decided' and read_at is null), 0, 'decision notice marked read');

select * from finish();
rollback;
