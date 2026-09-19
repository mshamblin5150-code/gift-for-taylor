begin;

create extension if not exists pgtap with schema extensions;
select plan(4);

insert into auth.users (id, email)
values
  ('00000000-0000-0000-0000-000000000181', 'manager@example.test'),
  ('00000000-0000-0000-0000-000000000182', 'staff@example.test');

insert into public.sections (id, name, display_order)
values ('00000000-0000-0000-0000-000000000184', 'Announcing test Section', 97);

insert into public.staff_members (id, display_name, role)
values
  ('00000000-0000-0000-0000-000000000185', 'Test Manager', 'manager'),
  ('00000000-0000-0000-0000-000000000186', 'Test Staff member', 'staff_member');

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
  );

insert into public.staff_section_assignments (
  staff_member_id,
  section_id,
  display_order,
  effective_from
)
values (
  '00000000-0000-0000-0000-000000000186',
  '00000000-0000-0000-0000-000000000184',
  0,
  current_date
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000181","role":"authenticated"}',
  true
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

create temporary table first_change on commit drop as
select id
from public.schedule_changes
where work_date = '2027-04-05';

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000182","role":"authenticated"}',
  true
);

select throws_ok(
  $$
    select public.mark_changes_announced(array(select id from first_change))
  $$,
  'Only the Manager can announce changes',
  'a Staff member cannot mark changes announced'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000181","role":"authenticated"}',
  true
);

select lives_ok(
  $$
    select public.mark_changes_announced(array(select id from first_change))
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
