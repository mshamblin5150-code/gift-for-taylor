begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

select vault.create_secret('test-calendar-secret', 'calendar_webhook_secret');

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000003391', 'code-manager@example.test'),
  ('00000000-0000-0000-0000-000000003392', 'code-one@example.test'),
  ('00000000-0000-0000-0000-000000003393', 'code-two@example.test'),
  ('00000000-0000-0000-0000-000000003396', 'code-three@example.test');
insert into public.staff_members(id, display_name, role) values
  ('00000000-0000-0000-0000-000000003391', 'Code Manager', 'manager'),
  ('00000000-0000-0000-0000-000000003392', 'Code One', 'staff_member'),
  ('00000000-0000-0000-0000-000000003393', 'Code Two', 'staff_member'),
  ('00000000-0000-0000-0000-000000003396', 'Code Three', 'staff_member');
insert into public.staff_accounts
  (staff_member_id, auth_user_id, personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000003391',
    '00000000-0000-0000-0000-000000003391', 'code-manager@example.test', now()),
  ('00000000-0000-0000-0000-000000003392',
    '00000000-0000-0000-0000-000000003392', 'code-one@example.test', now()),
  ('00000000-0000-0000-0000-000000003393',
    '00000000-0000-0000-0000-000000003393', 'code-two@example.test', now()),
  ('00000000-0000-0000-0000-000000003396',
    '00000000-0000-0000-0000-000000003396', 'code-three@example.test', now());
insert into public.sections(id, name, display_order) values
  ('00000000-0000-0000-0000-000000003394', 'Code batch section', 339);
create temporary table code_batch_dates as select
  date_trunc('month',
    (clock_timestamp() at time zone 'America/New_York')::date + interval '1 month'
  )::date as month_start,
  (clock_timestamp() at time zone 'America/New_York')::date as ny_today;
grant select on code_batch_dates to authenticated;
insert into public.schedule_months
  (id, month_start, release_state, released_at, released_by_staff_member_id)
select '00000000-0000-0000-0000-000000003395', month_start, 'released', now(),
  '00000000-0000-0000-0000-000000003391' from code_batch_dates;
insert into public.schedule_months
  (id, month_start, release_state, released_at, released_by_staff_member_id)
select '00000000-0000-0000-0000-000000003397',
  date_trunc('month', ny_today)::date, 'released', now(),
  '00000000-0000-0000-0000-000000003391' from code_batch_dates;
insert into public.schedule_months
  (id, month_start, release_state, released_at, released_by_staff_member_id)
select '00000000-0000-0000-0000-000000003398',
  date_trunc('month', ny_today) - interval '1 month', 'released', now(),
  '00000000-0000-0000-0000-000000003391' from code_batch_dates;
insert into public.schedule_cells
  (schedule_month_id, staff_member_id, section_id, work_date, shift_code)
select '00000000-0000-0000-0000-000000003395', staff_id,
  '00000000-0000-0000-0000-000000003394', month_start + day_offset, '7A'
from code_batch_dates cross join (values
  ('00000000-0000-0000-0000-000000003392'::uuid, 3),
  ('00000000-0000-0000-0000-000000003393'::uuid, 3),
  ('00000000-0000-0000-0000-000000003392'::uuid, 4)
) shifts(staff_id, day_offset);
insert into public.schedule_cells
  (schedule_month_id, staff_member_id, section_id, work_date, shift_code)
select '00000000-0000-0000-0000-000000003397',
  '00000000-0000-0000-0000-000000003392',
  '00000000-0000-0000-0000-000000003394', ny_today, '7A'
from code_batch_dates;
insert into public.schedule_cells
  (schedule_month_id, staff_member_id, section_id, work_date, shift_code)
select '00000000-0000-0000-0000-000000003398',
  '00000000-0000-0000-0000-000000003392',
  '00000000-0000-0000-0000-000000003394',
  (date_trunc('month', ny_today) - interval '1 day')::date, '7A'
from code_batch_dates;
delete from public.calendar_invitation_outbox;
delete from net.http_request_queue;

select set_config('TimeZone', case
  when (clock_timestamp() at time zone 'Pacific/Kiritimati')::date =
       (clock_timestamp() at time zone 'America/New_York')::date
    then 'Pacific/Honolulu'
  else 'Pacific/Kiritimati'
end, true);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003391","role":"authenticated"}', true);
create temporary table first_code_preview as
select public.preview_shift_code_change(
  '7A', 'Day', '08:00', '20:00', true, 'day', '7A') as plan;
select is(jsonb_array_length((select plan from first_code_preview)), 3,
  'preview lists each affected date');
select is((select sum((item->>'count')::integer)::integer
  from first_code_preview, jsonb_array_elements(plan) item), 4,
  'preview counts every affected Calendar invitation');
select is((select start_time from public.shift_codes where code = '7A'),
  '07:00'::time, 'preview rolls back the Shift code edit');
set local role postgres;
select is((select count(*)::integer from public.calendar_invitation_outbox), 0,
  'preview rolls back queued invitations');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003391","role":"authenticated"}', true);
select throws_ok($$select public.save_shift_code(
  '7A', 'Day', '08:00', '20:00', true, 'day', '7A')$$,
  'Review the Calendar invitation batch in Unit settings first',
  'compatibility save refuses a released-Schedule batch');

set local role postgres;
delete from public.schedule_cells where schedule_month_id =
  '00000000-0000-0000-0000-000000003395'
  and staff_member_id = '00000000-0000-0000-0000-000000003392'
  and work_date = (select month_start + 3 from code_batch_dates);
insert into public.schedule_cells
  (schedule_month_id, staff_member_id, section_id, work_date, shift_code)
select '00000000-0000-0000-0000-000000003395',
  '00000000-0000-0000-0000-000000003396',
  '00000000-0000-0000-0000-000000003394', month_start + 3, '7A'
from code_batch_dates;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003391","role":"authenticated"}', true);
select throws_ok($$select public.commit_shift_code_change(
  '7A', 'Day', '08:00', '20:00', true, 'day', '7A',
  (select plan from first_code_preview))$$,
  'The Schedule changed since preview; review the batch again',
  'save rejects a plan changed after preview');
select is((select start_time from public.shift_codes where code = '7A'),
  '07:00'::time, 'rejected save rolls back the Shift code edit');

set local role postgres;
delete from public.calendar_invitation_outbox;
delete from net.http_request_queue;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003391","role":"authenticated"}', true);
create temporary table confirmed_code_preview as
select public.preview_shift_code_change(
  '7A', 'Day', '08:00', '20:00', true, 'day', '7A') as plan;
select lives_ok($$select public.commit_shift_code_change(
  '7A', 'Day', '08:00', '20:00', true, 'day', '7A',
  (select plan from confirmed_code_preview))$$,
  'confirmed Shift code edit saves its reviewed batch');
set local role postgres;
select is((select start_time from public.shift_codes where code = '7A'),
  '08:00'::time, 'confirmed edit changes the Shift code');
select is((select count(*)::integer from public.calendar_invitation_outbox
  where superseded_at is null and method = 'REQUEST'), 4,
  'confirmed edit queues one invitation row per affected shift');
select is((select count(distinct (batch_id, recipient, method))::integer
  from public.calendar_invitation_outbox where superseded_at is null), 3,
  'each affected Staff member receives one REQUEST message');
select is((select count(*)::integer from net.http_request_queue), 1,
  'confirmed REQUEST batch posts one delivery webhook');

delete from net.http_request_queue;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003391","role":"authenticated"}', true);
create temporary table cancellation_preview as
select public.preview_shift_code_change(
  '7A', 'Off', null, null, false, null, '7A') as plan;
select lives_ok($$select public.commit_shift_code_change(
  '7A', 'Off', null, null, false, null, '7A',
  (select plan from cancellation_preview))$$,
  'confirmed nonworking edit saves its cancellation batch');
set local role postgres;
select is((select count(*)::integer from public.calendar_invitation_outbox
  where superseded_at is null and method = 'CANCEL'), 4,
  'stopping work queues one cancellation per affected shift');
select is((select min(starts_at at time zone 'America/New_York')::time
  from public.calendar_invitation_outbox
  where superseded_at is null and method = 'CANCEL'), '08:00'::time,
  'cancellations use the old Shift code times');
select is((select count(*)::integer from (
  select batch_id from public.calendar_invitation_outbox
  where superseded_at is null group by batch_id having count(distinct method) > 1
) mixed), 0, 'one batch never mixes REQUEST and CANCEL methods');
select is((select count(*)::integer from net.http_request_queue), 1,
  'confirmed CANCEL batch posts one delivery webhook');

select * from finish();
rollback;
