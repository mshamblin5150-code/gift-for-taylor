begin;

create extension if not exists pgtap with schema extensions;
select plan(7);

insert into auth.users (id, email)
values
  ('00000000-0000-0000-0000-000000000181', 'manager@example.test'),
  ('00000000-0000-0000-0000-000000000182', 'staff@example.test'),
  ('00000000-0000-0000-0000-000000000183', 'scheduler@example.test');

insert into public.sections (id, name, display_order)
values
  ('00000000-0000-0000-0000-000000000184', 'Announcing day Section', 94),
  ('00000000-0000-0000-0000-000000000190', 'Announcing night Section', 95);

insert into public.staff_members (id, display_name, role, cell_number)
values
  ('00000000-0000-0000-0000-000000000185', 'Test Manager', 'manager', null),
  (
    '00000000-0000-0000-0000-000000000186',
    'Test day RN',
    'staff_member',
    '5550100'
  ),
  (
    '00000000-0000-0000-0000-000000000187',
    'Test Night scheduler',
    'staff_member',
    '5550101'
  );

insert into public.staff_accounts (
  staff_member_id,
  auth_user_id,
  personal_email,
  accepted_invite_at
)
values
  (
    '00000000-0000-0000-0000-000000000185',
    '00000000-0000-0000-0000-000000000181',
    'manager@example.test',
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000186',
    '00000000-0000-0000-0000-000000000182',
    'staff@example.test',
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000187',
    '00000000-0000-0000-0000-000000000183',
    'scheduler@example.test',
    now()
  );

insert into public.staff_section_assignments (
  staff_member_id,
  section_id,
  display_order,
  effective_from
)
values
  (
    '00000000-0000-0000-0000-000000000186',
    '00000000-0000-0000-0000-000000000184',
    0,
    '2027-01-01'
  ),
  (
    '00000000-0000-0000-0000-000000000187',
    '00000000-0000-0000-0000-000000000190',
    0,
    '2027-01-01'
  );

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000181","role":"authenticated"}',
  true
);

select public.assign_night_scheduler(
  '00000000-0000-0000-0000-000000000187',
  array['00000000-0000-0000-0000-000000000190']::uuid[]
);

select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000186',
  '00000000-0000-0000-0000-000000000184',
  '2027-04-05',
  '7A'
);
select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000186',
  '00000000-0000-0000-0000-000000000184',
  '2027-04-06',
  'N'
);
select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000187',
  '00000000-0000-0000-0000-000000000190',
  '2027-04-07',
  '7P'
);

select results_eq(
  $$
    select display_name, cell_number
    from public.schedule_rows('2027-04-01')
    where section_id in (
      '00000000-0000-0000-0000-000000000184',
      '00000000-0000-0000-0000-000000000190'
    )
  $$,
  $$
    values
      ('Test day RN'::text, '5550100'::text),
      ('Test Night scheduler'::text, '5550101'::text)
  $$,
  'schedule rows carry the cell number announcements are texted to'
);

create temporary table april_changes on commit drop as
select id, work_date
from public.schedule_changes
where work_date between '2027-04-05' and '2027-04-07';

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000182","role":"authenticated"}',
  true
);

select throws_ok(
  $$
    select public.mark_changes_announced(array(select id from april_changes))
  $$,
  'Only a scheduler can announce changes',
  'a Staff member cannot mark changes announced'
);

-- The Night scheduler announces only the changes in their Sections.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000183","role":"authenticated"}',
  true
);

select lives_ok(
  $$
    select public.mark_changes_announced(array(select id from april_changes))
  $$,
  'the Night scheduler marks the changes they texted announced'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000181","role":"authenticated"}',
  true
);

select results_eq(
  $$
    select work_date, announced_at is not null
    from public.schedule_changes
    where id in (select id from april_changes)
    order by work_date
  $$,
  $$
    values
      ('2027-04-05'::date, false),
      ('2027-04-06'::date, false),
      ('2027-04-07'::date, true)
  $$,
  'a Night scheduler cannot announce changes outside their Sections'
);

select lives_ok(
  $$
    select public.mark_changes_announced(
      array(select id from april_changes where work_date = '2027-04-05')
    )
  $$,
  'the Manager marks the changes she texted announced'
);

select isnt(
  (
    select announced_at
    from public.schedule_changes
    where work_date = '2027-04-05'
  ),
  null,
  'the texted change is announced'
);

select is(
  (
    select announced_at
    from public.schedule_changes
    where work_date = '2027-04-06'
  ),
  null,
  'a change not in the announcement stays unannounced'
);

select * from finish();
rollback;
