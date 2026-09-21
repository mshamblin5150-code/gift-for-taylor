begin;

create extension if not exists pgtap with schema extensions;
select plan(23);

insert into auth.users (id, email)
values
  ('00000000-0000-0000-0000-000000000201', 'manager@example.test'),
  ('00000000-0000-0000-0000-000000000202', 'administrator@example.test'),
  ('00000000-0000-0000-0000-000000000203', 'staff@example.test');

insert into public.sections (id, name, display_order)
values
  ('00000000-0000-0000-0000-000000000211', 'First month days', 90),
  ('00000000-0000-0000-0000-000000000212', 'First month nights', 91);

insert into public.staff_members (id, display_name, role)
values
  ('00000000-0000-0000-0000-000000000221', 'Test Manager', 'manager'),
  ('00000000-0000-0000-0000-000000000222', 'Test Administrator', 'administrator'),
  ('00000000-0000-0000-0000-000000000223', 'Listed Nurse', 'staff_member');

insert into public.staff_members (display_name, active)
values ('Former Nurse', false);

insert into public.staff_accounts (
  staff_member_id,
  auth_user_id,
  personal_email,
  accepted_invite_at
)
values
  (
    '00000000-0000-0000-0000-000000000221',
    '00000000-0000-0000-0000-000000000201',
    'manager@example.test',
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000222',
    '00000000-0000-0000-0000-000000000202',
    'administrator@example.test',
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000223',
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
values (
  '00000000-0000-0000-0000-000000000223',
  '00000000-0000-0000-0000-000000000211',
  0,
  '2026-09-01'
);

-- A February page keeps the fixture short: 28 day cells per row.
create function pg_temp.codes(first_code text)
returns jsonb
language sql
as $$
  select jsonb_build_array(first_code) || (
    select jsonb_agg(case when day % 7 = 0 then 'X' else '7A' end)
    from generate_series(2, 28) as day
  )
$$;

select throws_ok(
  $$select public.load_first_month('2027-02-01', jsonb_build_array(
      jsonb_build_object('section', 'First month days', 'name', 'Short Row',
        'codes', '["7A"]'::jsonb)
    ))$$,
  'Row 1 must have 28 day cells',
  'a row with the wrong number of days is refused'
);

select throws_ok(
  $$select public.load_first_month('2027-02-01', jsonb_build_array(
      jsonb_build_object('section', 'No such Section', 'name', 'Lost Row',
        'codes', pg_temp.codes('7A'))
    ))$$,
  'Row 1 has an unknown Section',
  'a row in an unknown Section is refused'
);

select throws_ok(
  $$select public.load_first_month('2027-02-01', jsonb_build_array(
      jsonb_build_object('section', 'First month days', 'name', 'Former Nurse',
        'codes', pg_temp.codes('7A'))
    ))$$,
  'Row 1 names a deactivated Staff member',
  'a deactivated Staff member is not silently duplicated'
);

select is(
  (select count(*)::integer from public.schedule_months where month_start = '2027-02-01'),
  0,
  'a refused load leaves no month behind'
);

select lives_ok(
  $$select public.load_first_month('2027-02-01', jsonb_build_array(
      jsonb_build_object('section', 'First month days', 'name', 'Listed Nurse',
        'codes', pg_temp.codes('16D')),
      jsonb_build_object('section', 'First month days', 'name', 'Page Nurse',
        'cell', ' 5551234567 ', 'codes', pg_temp.codes('4P-8A')),
      jsonb_build_object('section', 'First month nights', 'name', 'Night Nurse',
        'codes', pg_temp.codes(''))
    ))$$,
  'the transcription of the printed page loads'
);

select is(
  (
    select count(*)::integer
    from public.schedule_cells cell
    join public.schedule_months month on month.id = cell.schedule_month_id
    where month.month_start = '2027-02-01'
  ),
  84,
  'every cell of every row is in the database'
);

select is(
  (
    select count(*)::integer
    from public.staff_members
    where display_name in ('Listed Nurse', 'Page Nurse', 'Night Nurse')
  ),
  3,
  'a name already on the Staff list is reused and new names are added'
);

select results_eq(
  $$select member.display_name, assignment.display_order
    from public.staff_section_assignments assignment
    join public.staff_members member on member.id = assignment.staff_member_id
    where assignment.section_id = '00000000-0000-0000-0000-000000000211'
      and assignment.effective_through is null
    order by assignment.display_order$$,
  $$values ('Listed Nurse', 0), ('Page Nurse', 1)$$,
  'new rows join the bottom of their Section in page order'
);

select results_eq(
  $$select display_name, cell_number
    from public.staff_members
    where display_name in ('Page Nurse', 'Night Nurse')
    order by display_name$$,
  $$values ('Night Nurse', null::text), ('Page Nurse', '+15551234567')$$,
  'each new Staff member keeps the cell number their Invite goes to'
);

select is(
  (
    select cell.shift_code
    from public.schedule_cells cell
    join public.staff_members member on member.id = cell.staff_member_id
    where member.display_name = 'Page Nurse' and cell.work_date = '2027-02-01'
  ),
  '4P-8A',
  'an off-legend Shift code is kept as written'
);

select is(
  (
    select release_state::text
    from public.schedule_months
    where month_start = '2027-02-01' and loaded_from_page_at is not null
  ),
  'unpublished',
  'the loaded month waits for the Manager before it is released'
);

select throws_ok(
  $$select public.load_first_month('2027-02-01', jsonb_build_array(
      jsonb_build_object('section', 'First month days', 'name', 'Page Nurse',
        'codes', pg_temp.codes('7A'))
    ))$$,
  'That month is already in the database',
  'the same month cannot be loaded twice'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000201","role":"authenticated"}',
  true
);

select throws_ok(
  $$select public.load_first_month('2027-03-01', '[]'::jsonb)$$,
  '42501',
  null,
  'the load cannot be called through the API'
);

select lives_ok(
  $$select public.save_schedule_cell(
      (select id from public.staff_members where display_name = 'Page Nurse'),
      '00000000-0000-0000-0000-000000000211',
      '2027-02-01',
      ' 7P '
    )$$,
  'the Manager corrects a misread cell'
);

select results_eq(
  $$select old_shift_code, new_shift_code, changed_by_staff_member_id
    from public.schedule_changes change
    join public.staff_members member on member.id = change.staff_member_id
    where member.display_name = 'Page Nurse' and change.work_date = '2027-02-01'$$,
  $$values ('4P-8A', '7P', '00000000-0000-0000-0000-000000000221'::uuid)$$,
  'the correction is written to the change log like any other edit'
);

select public.save_schedule_cell(
  (select id from public.staff_members where display_name = 'Page Nurse'),
  '00000000-0000-0000-0000-000000000211',
  '2027-02-01',
  '7P'
);
select is(
  (select count(*)::integer from public.schedule_changes where work_date = '2027-02-01'),
  1,
  'saving the same code again logs nothing'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000203","role":"authenticated"}',
  true
);

select throws_ok(
  $$select public.save_schedule_cell(
      (select id from public.staff_members where display_name = 'Page Nurse'),
      '00000000-0000-0000-0000-000000000211',
      '2027-02-02',
      'X'
    )$$,
  'Only the Manager can edit the Schedule',
  'a Staff member cannot edit a cell'
);

select is(
  (select count(*)::integer from public.schedule_changes),
  0,
  'a Staff member cannot read the change log'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000202","role":"authenticated"}',
  true
);

select throws_ok(
  $$select public.confirm_loaded_month_checked('2027-02-01', true)$$,
  'Only the Manager can confirm the month',
  'the administrator cannot confirm the month'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000201","role":"authenticated"}',
  true
);

select lives_ok(
  $$select public.confirm_loaded_month_checked('2027-02-01', true)$$,
  'the Manager confirms the checked month'
);

select results_eq(
  $$select release_state::text, confirmed_by_staff_member_id, released_by_staff_member_id
    from public.schedule_months
    where month_start = '2027-02-01'$$,
  $$values (
      'released',
      '00000000-0000-0000-0000-000000000221'::uuid,
      '00000000-0000-0000-0000-000000000221'::uuid
    )$$,
  'confirming the month records who confirmed it and releases it'
);

select is(
  (select count(*)::integer from public.schedule_changes where announced_at is null),
  0,
  'corrections made while checking the month need no Change announcement'
);

select throws_ok(
  $$select public.confirm_loaded_month_checked('2027-02-01', true)$$,
  'There is no loaded month waiting to be confirmed',
  'a month is confirmed only once'
);

select * from finish();
rollback;
