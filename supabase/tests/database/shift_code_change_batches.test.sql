begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000003391', 'code-batch-manager@example.test'),
  ('00000000-0000-0000-0000-000000003392', 'code-batch-one@example.test'),
  ('00000000-0000-0000-0000-000000003393', 'code-batch-two@example.test');
insert into public.staff_members(id, display_name, role) values
  ('00000000-0000-0000-0000-000000003391', 'Code Batch Manager', 'manager'),
  ('00000000-0000-0000-0000-000000003392', 'Code Batch One', 'staff_member'),
  ('00000000-0000-0000-0000-000000003393', 'Code Batch Two', 'staff_member');
insert into public.staff_accounts(staff_member_id, auth_user_id,
  personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000003391',
    '00000000-0000-0000-0000-000000003391',
    'code-batch-manager@example.test', now()),
  ('00000000-0000-0000-0000-000000003392',
    '00000000-0000-0000-0000-000000003392',
    'code-batch-one@example.test', now()),
  ('00000000-0000-0000-0000-000000003393',
    '00000000-0000-0000-0000-000000003393',
    'code-batch-two@example.test', now());
insert into public.sections(id, name, display_order) values
  ('00000000-0000-0000-0000-000000003394', 'Code Batch Section', 339);

create temporary table code_batch_dates as select
  date_trunc('month', current_date + interval '1 month')::date as month_start;
grant select on code_batch_dates to authenticated;
insert into public.schedule_months(id, month_start, release_state, released_at,
  released_by_staff_member_id)
select '00000000-0000-0000-0000-000000003395', month_start, 'released',
  now(), '00000000-0000-0000-0000-000000003391' from code_batch_dates;
insert into public.schedule_months(id, month_start, release_state, released_at,
  released_by_staff_member_id)
values ('00000000-0000-0000-0000-000000003396',
  date_trunc('month', current_date - interval '1 month')::date, 'released',
  now(), '00000000-0000-0000-0000-000000003391');
insert into public.schedule_cells(schedule_month_id, staff_member_id,
  section_id, work_date, shift_code)
select '00000000-0000-0000-0000-000000003395', staff_member_id,
  '00000000-0000-0000-0000-000000003394', work_date, '7A'
from (values
  ('00000000-0000-0000-0000-000000003392'::uuid,
    (select month_start + 3 from code_batch_dates)),
  ('00000000-0000-0000-0000-000000003393'::uuid,
    (select month_start + 3 from code_batch_dates)),
  ('00000000-0000-0000-0000-000000003392'::uuid,
    (select month_start + 4 from code_batch_dates))
) cells(staff_member_id, work_date);
insert into public.schedule_cells(schedule_month_id, staff_member_id,
  section_id, work_date, shift_code)
values ('00000000-0000-0000-0000-000000003396',
  '00000000-0000-0000-0000-000000003392',
  '00000000-0000-0000-0000-000000003394',
  date_trunc('month', current_date - interval '1 month')::date + 3, '7A');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003391","role":"authenticated"}', true);

create temporary table request_preview as
select public.preview_shift_code_change('7A', 'Day', '08:00', '20:00',
  true, 'day', '7A') as plan;
select is((select jsonb_array_length(plan) from request_preview), 2,
  'preview lists each affected date');
select is((select (plan->0->>'count')::integer
  from request_preview), 2, 'preview counts Staff affected on the first date');
select is((select plan->0->>'method' from request_preview),
  'REQUEST', 'a working-time change previews replacement requests');
select is((select start_time from public.shift_codes where code = '7A'),
  '07:00'::time, 'preview rolls the proposed Shift code edit back');
set local role postgres;
select is((select count(*)::integer from public.calendar_invitation_outbox), 4,
  'preview queues no Calendar invitations');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003391","role":"authenticated"}', true);
select lives_ok($$
  select public.commit_shift_code_change('7A', 'Day', '08:00', '20:00',
    true, 'day', '7A', (select plan from request_preview))
$$, 'confirmed Shift code edit saves its reviewed batch');
select is((select start_time from public.shift_codes where code = '7A'),
  '08:00'::time, 'confirmed edit changes the Shift code');
set local role postgres;
select is((select count(distinct batch_id)::integer
  from public.calendar_invitation_outbox
  where superseded_at is null and work_date in
    (select month_start + value from code_batch_dates,
      unnest(array[3, 4]) value)), 1,
  'every replacement invitation shares one batch');
select is((select count(distinct (batch_id, recipient, method))::integer
  from public.calendar_invitation_outbox
  where superseded_at is null and work_date in
    (select month_start + value from code_batch_dates,
      unnest(array[3, 4]) value)), 2,
  'each affected Staff member receives one REQUEST message');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003391","role":"authenticated"}', true);
create temporary table stale_preview as
select public.preview_shift_code_change('7A', 'Day', '09:00', '21:00',
  true, 'day', '7A') as plan;
set local role postgres;
update public.schedule_cells set shift_code = '7P'
where staff_member_id = '00000000-0000-0000-0000-000000003393'
  and work_date = (select month_start + 3 from code_batch_dates);
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003391","role":"authenticated"}', true);
select throws_ok($$
  select public.commit_shift_code_change('7A', 'Day', '09:00', '21:00',
    true, 'day', '7A', (select plan from stale_preview))
$$, 'The Schedule changed since preview; review the batch again',
  'a concurrent Schedule change refuses the stale confirmation');
select is((select start_time from public.shift_codes where code = '7A'),
  '08:00'::time, 'a refused confirmation rolls its Shift code edit back');

create temporary table cancel_preview as
select public.preview_shift_code_change('7A', 'Day off', '08:00', '20:00',
  false, 'day', '7A') as plan;
select is((select bool_and(item->>'method' = 'CANCEL')
  from cancel_preview, jsonb_array_elements(plan) item), true,
  'stopping work previews cancellations only');
select lives_ok($$
  select public.commit_shift_code_change('7A', 'Day off', '08:00', '20:00',
    false, 'day', '7A', (select plan from cancel_preview))
$$, 'confirmed nonworking edit withdraws the reviewed shifts');
set local role postgres;
select is((select count(distinct (batch_id, recipient, method))::integer
  from public.calendar_invitation_outbox where superseded_at is null
    and method = 'CANCEL' and shift_code = '7A'), 1,
  'one Staff member receives one CANCEL message for both remaining shifts');
select is((select min(starts_at)::time from public.calendar_invitation_outbox
  where superseded_at is null and method = 'CANCEL' and shift_code = '7A'),
  '12:00'::time, 'cancellations retain the old Shift code start time');

select * from finish();
rollback;
