begin;

create extension if not exists pgtap with schema extensions;
select plan(6);

insert into auth.users (id, email)
values
  ('00000000-0000-0000-0000-000000000191', 'manager@example.test'),
  ('00000000-0000-0000-0000-000000000192', 'outsider@example.test');

insert into public.sections (id, name, display_order)
values
  ('00000000-0000-0000-0000-000000000193', 'Print test days', 96),
  ('00000000-0000-0000-0000-000000000194', 'Print test nights', 97);

insert into public.staff_members (id, display_name, role, active)
values
  ('00000000-0000-0000-0000-000000000195', 'Test Manager', 'manager', true),
  ('00000000-0000-0000-0000-000000000196', 'Moved RN', 'staff_member', true),
  ('00000000-0000-0000-0000-000000000197', 'Staying RN', 'staff_member', true),
  ('00000000-0000-0000-0000-000000000198', 'Departed RN', 'staff_member', false),
  ('00000000-0000-0000-0000-000000000199', 'Idle former RN', 'staff_member', false),
  ('00000000-0000-0000-0000-00000000019a', 'November RN', 'staff_member', true);

insert into public.staff_accounts (
  staff_member_id,
  auth_user_id,
  personal_email,
  accepted_invite_at
)
values (
  '00000000-0000-0000-0000-000000000195',
  '00000000-0000-0000-0000-000000000191',
  'manager@example.test',
  now()
);

insert into public.staff_section_assignments (
  staff_member_id,
  section_id,
  display_order,
  effective_from,
  effective_through
)
values
  -- Moved from days to nights on October 1.
  (
    '00000000-0000-0000-0000-000000000196',
    '00000000-0000-0000-0000-000000000193',
    0,
    '2026-08-01',
    '2026-09-30'
  ),
  (
    '00000000-0000-0000-0000-000000000196',
    '00000000-0000-0000-0000-000000000194',
    1,
    '2026-10-01',
    null
  ),
  (
    '00000000-0000-0000-0000-000000000197',
    '00000000-0000-0000-0000-000000000194',
    0,
    '2026-08-01',
    null
  ),
  (
    '00000000-0000-0000-0000-000000000198',
    '00000000-0000-0000-0000-000000000193',
    1,
    '2026-08-01',
    '2026-09-20'
  ),
  (
    '00000000-0000-0000-0000-000000000199',
    '00000000-0000-0000-0000-000000000193',
    2,
    '2026-08-01',
    '2026-09-20'
  ),
  (
    '00000000-0000-0000-0000-00000000019a',
    '00000000-0000-0000-0000-000000000193',
    3,
    '2026-11-01',
    null
  );

insert into public.schedule_months (id, month_start, release_state)
values ('00000000-0000-0000-0000-0000000001a0', '2026-09-01', 'unpublished');

insert into public.schedule_cells (
  schedule_month_id,
  staff_member_id,
  section_id,
  work_date,
  shift_code
)
values (
  '00000000-0000-0000-0000-0000000001a0',
  '00000000-0000-0000-0000-000000000198',
  '00000000-0000-0000-0000-000000000193',
  '2026-09-10',
  '7A'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000191","role":"authenticated"}',
  true
);

select results_eq(
  $$
    select display_name, section.name
    from public.schedule_rows('2026-09-01') row
    join public.sections section on section.id = row.section_id
    where section.display_order in (96, 97)
  $$,
  $$
    values
      ('Moved RN'::text, 'Print test days'::text),
      ('Departed RN', 'Print test days'),
      ('Staying RN', 'Print test nights')
  $$,
  'September shows each person in the Section they held that month, in order'
);

select results_eq(
  $$
    select display_name, section.name
    from public.schedule_rows('2026-10-01') row
    join public.sections section on section.id = row.section_id
    where section.display_order in (96, 97)
  $$,
  $$
    values
      ('Staying RN'::text, 'Print test nights'::text),
      ('Moved RN', 'Print test nights')
  $$,
  'October shows the moved person in their new Section'
);

select ok(
  not exists (
    select 1
    from public.schedule_rows('2026-09-01')
    where display_name = 'Idle former RN'
  ),
  'a deactivated person with no cells that month is left off'
);

select ok(
  not exists (
    select 1
    from public.schedule_rows('2026-10-01')
    where display_name = 'November RN'
  ),
  'someone who joins later is not on an earlier month'
);

select ok(
  exists (
    select 1
    from public.schedule_rows('2026-11-15')
    where display_name = 'November RN'
  ),
  'any date in the month finds that month'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000192","role":"authenticated"}',
  true
);

select is_empty(
  $$ select * from public.schedule_rows('2026-09-01') $$,
  'an account without an accepted Invite reads no rows'
);

select * from finish();
rollback;
