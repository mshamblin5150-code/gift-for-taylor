begin;

create extension if not exists pgtap with schema extensions;
select plan(18);

insert into auth.users (id, email)
values
  ('00000000-0000-0000-0000-000000000201', 'manager@example.test'),
  ('00000000-0000-0000-0000-000000000202', 'scheduler@example.test'),
  ('00000000-0000-0000-0000-000000000203', 'staff@example.test');

insert into public.sections (id, name, display_order)
values
  ('00000000-0000-0000-0000-000000000204', 'Night test day Section', 96),
  ('00000000-0000-0000-0000-000000000205', 'Night test night Section', 97);

insert into public.staff_members (id, display_name, role)
values
  ('00000000-0000-0000-0000-000000000206', 'Test Manager', 'manager'),
  ('00000000-0000-0000-0000-000000000207', 'Test Night scheduler', 'staff_member'),
  ('00000000-0000-0000-0000-000000000208', 'Test day RN', 'staff_member'),
  ('00000000-0000-0000-0000-000000000209', 'Test night RN', 'staff_member');

insert into public.staff_accounts (
  staff_member_id,
  auth_user_id,
  personal_email,
  accepted_invite_at
)
values
  (
    '00000000-0000-0000-0000-000000000206',
    '00000000-0000-0000-0000-000000000201',
    'manager@example.test',
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000207',
    '00000000-0000-0000-0000-000000000202',
    'scheduler@example.test',
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000208',
    '00000000-0000-0000-0000-000000000203',
    'staff@example.test',
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
    '00000000-0000-0000-0000-000000000207',
    '00000000-0000-0000-0000-000000000205',
    0,
    current_date
  ),
  (
    '00000000-0000-0000-0000-000000000208',
    '00000000-0000-0000-0000-000000000204',
    0,
    current_date
  ),
  (
    '00000000-0000-0000-0000-000000000209',
    '00000000-0000-0000-0000-000000000205',
    1,
    current_date
  );

set local role authenticated;

-- A Staff member cannot hand out the role.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000203","role":"authenticated"}',
  true
);

select throws_ok(
  $$
    select public.assign_night_scheduler(
      '00000000-0000-0000-0000-000000000208',
      array['00000000-0000-0000-0000-000000000204']::uuid[]
    )
  $$,
  'Only the Manager can assign the Night scheduler',
  'a Staff member cannot make themselves the Night scheduler'
);

-- The Manager gives the role.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000201","role":"authenticated"}',
  true
);

select throws_ok(
  $$
    select public.assign_night_scheduler(
      '00000000-0000-0000-0000-000000000207',
      array[]::uuid[]
    )
  $$,
  'The Night scheduler needs at least one Section',
  'the role needs at least one Section'
);

select throws_ok(
  $$
    select public.assign_night_scheduler(
      '00000000-0000-0000-0000-000000000206',
      array['00000000-0000-0000-0000-000000000205']::uuid[]
    )
  $$,
  'Only a Staff member can be the Night scheduler',
  'the Manager cannot be demoted to Night scheduler'
);

select lives_ok(
  $$
    select public.assign_night_scheduler(
      '00000000-0000-0000-0000-000000000207',
      array[
        '00000000-0000-0000-0000-000000000204',
        '00000000-0000-0000-0000-000000000205'
      ]::uuid[]
    )
  $$,
  'the Manager gives the role with two Sections'
);

select lives_ok(
  $$
    select public.assign_night_scheduler(
      '00000000-0000-0000-0000-000000000207',
      array['00000000-0000-0000-0000-000000000205']::uuid[]
    )
  $$,
  'the Manager narrows the Sections'
);

select results_eq(
  $$
    select staff_member_id, section_id
    from public.night_scheduler_sections
    where staff_member_id = '00000000-0000-0000-0000-000000000207'
  $$,
  $$
    values (
      '00000000-0000-0000-0000-000000000207'::uuid,
      '00000000-0000-0000-0000-000000000205'::uuid
    )
  $$,
  'assigning again replaces the Sections'
);

-- The Night scheduler edits only the assigned Section.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000202","role":"authenticated"}',
  true
);

select ok(not public.can_edit_schedule(), 'the Night scheduler is not the Manager');

select results_eq(
  $$ select * from public.editable_section_ids() $$,
  $$ values ('00000000-0000-0000-0000-000000000205'::uuid) $$,
  'the Night scheduler can edit only the assigned Section'
);

select lives_ok(
  $$
    select public.save_schedule_cell(
      '00000000-0000-0000-0000-000000000209',
      '00000000-0000-0000-0000-000000000205',
      '2027-04-10',
      '7P'
    )
  $$,
  'the Night scheduler saves in the assigned Section'
);

select results_eq(
  $$
    select new_shift_code, changed_by_staff_member_id, announced_at is null
    from public.schedule_changes
    where staff_member_id = '00000000-0000-0000-0000-000000000209'
  $$,
  $$
    values ('7P', '00000000-0000-0000-0000-000000000207'::uuid, true)
  $$,
  'the edit is logged under the Night scheduler, unannounced'
);

select throws_ok(
  $$
    select public.save_schedule_cell(
      '00000000-0000-0000-0000-000000000208',
      '00000000-0000-0000-0000-000000000204',
      '2027-04-10',
      'X'
    )
  $$,
  'Only the Manager can edit that Section',
  'the database refuses a save outside the assigned Section'
);

select throws_ok(
  $$
    select public.save_schedule_cell(
      '00000000-0000-0000-0000-000000000208',
      '00000000-0000-0000-0000-000000000205',
      '2027-04-10',
      'X'
    )
  $$,
  'That Staff member is not on the Staff list in this Section',
  'naming an assigned Section for someone outside it is refused'
);

select throws_ok(
  $$
    insert into public.night_scheduler_sections (staff_member_id, section_id)
    values (
      '00000000-0000-0000-0000-000000000207',
      '00000000-0000-0000-0000-000000000204'
    )
  $$,
  '42501',
  null,
  'the Night scheduler cannot add Sections directly'
);

select throws_ok(
  $$
    select public.assign_night_scheduler(
      '00000000-0000-0000-0000-000000000207',
      array['00000000-0000-0000-0000-000000000204']::uuid[]
    )
  $$,
  'Only the Manager can assign the Night scheduler',
  'the Night scheduler cannot widen their own Sections'
);

-- The Manager overrides their edit, then takes the role back.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000201","role":"authenticated"}',
  true
);

select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000209',
  '00000000-0000-0000-0000-000000000205',
  '2027-04-10',
  'N'
);

select results_eq(
  $$
    select old_shift_code, new_shift_code, changed_by_staff_member_id
    from public.schedule_changes
    where staff_member_id = '00000000-0000-0000-0000-000000000209'
    order by changed_at, id
  $$,
  $$
    values
      ('', '7P', '00000000-0000-0000-0000-000000000207'::uuid),
      ('7P', 'N', '00000000-0000-0000-0000-000000000206'::uuid)
  $$,
  'the Manager overrides the Night scheduler edit'
);

select public.remove_night_scheduler('00000000-0000-0000-0000-000000000207');

select is(
  (
    select role::text
    from public.staff_members
    where id = '00000000-0000-0000-0000-000000000207'
  ),
  'staff_member',
  'removing the role makes them a Staff member again'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000202","role":"authenticated"}',
  true
);

select is_empty(
  $$ select * from public.editable_section_ids() $$,
  'a former Night scheduler can edit no Section'
);

select throws_ok(
  $$
    select public.save_schedule_cell(
      '00000000-0000-0000-0000-000000000209',
      '00000000-0000-0000-0000-000000000205',
      '2027-04-11',
      'N'
    )
  $$,
  'Only the Manager can edit the Schedule',
  'a former Night scheduler cannot save'
);

select * from finish();
rollback;
