begin;

create extension if not exists pgtap with schema extensions;
select plan(8);

insert into public.sections (id, name, display_order)
values ('00000000-0000-0000-0000-000000000101', 'Security test Section', 0);

insert into public.staff_members (id, display_name)
values ('00000000-0000-0000-0000-000000000102', 'Security test Staff member');

insert into public.schedule_months (id, month_start)
values ('00000000-0000-0000-0000-000000000103', '2026-09-01');

insert into public.schedule_cells (
  schedule_month_id,
  staff_member_id,
  section_id,
  work_date,
  shift_code
)
values (
  '00000000-0000-0000-0000-000000000103',
  '00000000-0000-0000-0000-000000000102',
  '00000000-0000-0000-0000-000000000101',
  '2026-09-18',
  '7A'
);

set local role anon;
select is(
  (select count(*)::integer from public.sections),
  0,
  'an unauthenticated request reads no Sections'
);
select is(
  (select count(*)::integer from public.staff_members),
  0,
  'an unauthenticated request reads no Staff members'
);
select is(
  (select count(*)::integer from public.schedule_months),
  0,
  'an unauthenticated request reads no Schedule months'
);
select is(
  (select count(*)::integer from public.schedule_cells),
  0,
  'an unauthenticated request reads no Schedule cells'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000014","role":"authenticated"}',
  true
);
select is(
  (select count(*)::integer from public.sections),
  0,
  'an account without an accepted Invite reads no Sections'
);
select is(
  (select count(*)::integer from public.staff_members),
  0,
  'an account without an accepted Invite reads no Staff members'
);
select is(
  (select count(*)::integer from public.schedule_months),
  0,
  'an account without an accepted Invite reads no Schedule months'
);
select is(
  (select count(*)::integer from public.schedule_cells),
  0,
  'an account without an accepted Invite reads no Schedule cells'
);

select * from finish();
rollback;
