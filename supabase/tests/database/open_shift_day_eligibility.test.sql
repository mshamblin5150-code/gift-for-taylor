begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000003121', 'eligibility-manager@example.test'),
  ('00000000-0000-0000-0000-000000003122', 'eligibility-staff@example.test');
insert into public.sections(id, name, display_order) values
  ('00000000-0000-0000-0000-000000003123', 'Eligibility RN', 312);
insert into public.staff_members(id, display_name, role) values
  ('00000000-0000-0000-0000-000000003124', 'Eligibility Manager', 'manager'),
  ('00000000-0000-0000-0000-000000003125', 'Eligibility RN', 'staff_member');
insert into public.staff_accounts(staff_member_id, auth_user_id, personal_email, accepted_invite_at)
values
  ('00000000-0000-0000-0000-000000003124', '00000000-0000-0000-0000-000000003121',
    'eligibility-manager@example.test', now()),
  ('00000000-0000-0000-0000-000000003125', '00000000-0000-0000-0000-000000003122',
    'eligibility-staff@example.test', now());
insert into public.staff_section_assignments(
  staff_member_id, section_id, display_order, effective_from
) values (
  '00000000-0000-0000-0000-000000003125',
  '00000000-0000-0000-0000-000000003123', 0, '2000-01-01'
);
insert into public.staff_job_roles(staff_member_id, job_role, effective_from)
values ('00000000-0000-0000-0000-000000003125', 'rn', '2000-01-01');

insert into public.schedule_months(
  month_start, release_state, released_at, released_by_staff_member_id
)
select distinct date_trunc('month', work_date)::date,
  'released'::public.month_release_state, now(),
  '00000000-0000-0000-0000-000000003124'::uuid
from (values
  ((clock_timestamp() at time zone 'America/New_York')::date),
  ((clock_timestamp() at time zone 'America/New_York')::date - 1)
) dates(work_date);

insert into public.schedule_cells(
  schedule_month_id, staff_member_id, section_id, work_date, shift_code
)
select month.id, '00000000-0000-0000-0000-000000003125',
  '00000000-0000-0000-0000-000000003123',
  (clock_timestamp() at time zone 'America/New_York')::date, '7A'
from public.schedule_months month
where month.month_start = date_trunc(
  'month', clock_timestamp() at time zone 'America/New_York'
)::date;

insert into public.short_shifts(
  schedule_month_id, work_date, shift_code, reason, job_role
)
select month.id, dates.work_date, '7A', 'manual', 'rn'
from (values
  ((clock_timestamp() at time zone 'America/New_York')::date),
  ((clock_timestamp() at time zone 'America/New_York')::date - 1)
) dates(work_date)
join public.schedule_months month
  on month.month_start = date_trunc('month', dates.work_date)::date;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003122","role":"authenticated"}',
  true
);
select is(
  (select count(*)::integer from public.visible_open_shifts()), 0,
  'Staff member does not see an Open shift on a working day or a past day'
);
select is(
  (select sum(public.hidden_open_shift_count(month_start))::integer
    from public.schedule_months), 2,
  'the hidden count accounts for the working day and the past shift'
);

reset role;
update public.schedule_cells set shift_code = 'X'
where staff_member_id = '00000000-0000-0000-0000-000000003125';
set local role authenticated;
select is(
  (select count(*)::integer from public.visible_open_shifts()), 1,
  'X leaves the Open shift later today visible'
);

reset role;
update public.schedule_cells set shift_code = ''
where staff_member_id = '00000000-0000-0000-0000-000000003125';
set local role authenticated;
select is(
  (select count(*)::integer from public.visible_open_shifts()), 1,
  'an empty cell leaves the Open shift visible'
);

reset role;
delete from public.schedule_cells
where staff_member_id = '00000000-0000-0000-0000-000000003125';
set local role authenticated;
select is(
  (select count(*)::integer from public.visible_open_shifts()), 1,
  'no Schedule cell leaves the Open shift visible'
);

reset role;
insert into public.schedule_cells(
  schedule_month_id, staff_member_id, section_id, work_date, shift_code
)
select month.id, '00000000-0000-0000-0000-000000003125',
  '00000000-0000-0000-0000-000000003123',
  (clock_timestamp() at time zone 'America/New_York')::date, 'R/O'
from public.schedule_months month
where month.month_start = date_trunc(
  'month', clock_timestamp() at time zone 'America/New_York'
)::date;
set local role authenticated;
select is(
  (select count(*)::integer from public.visible_open_shifts()), 0,
  'Request off hides the Open shift'
);
select throws_ok(
  $$select public.request_open_shift_pickup((
    select id from public.short_shifts
    where work_date = (clock_timestamp() at time zone 'America/New_York')::date
  ))$$,
  'P0001', 'You already have a Schedule entry that day',
  'Request off also refuses a direct pickup'
);
select is(
  (select count(*)::integer from public.visible_open_shifts()
    where work_date < (clock_timestamp() at time zone 'America/New_York')::date), 0,
  'a past Open shift is not listed for Staff'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003121","role":"authenticated"}',
  true
);
select is(
  (select count(*)::integer from public.visible_open_shifts()), 2,
  'the Manager still sees every Open shift in the month'
);
select is(
  (select sum(public.hidden_open_shift_count(month_start))::integer
    from public.schedule_months), 0,
  'the Manager has no hidden Open shift count'
);

select * from finish();
rollback;
