begin;

create extension if not exists pgtap with schema extensions;
select plan(28);

insert into auth.users (id, email)
values
  ('00000000-0000-0000-0000-000000000301', 'manager@example.test'),
  ('00000000-0000-0000-0000-000000000302', 'administrator@example.test'),
  ('00000000-0000-0000-0000-000000000303', 'staff@example.test'),
  ('00000000-0000-0000-0000-000000000304', 'uninvited@example.test');

insert into public.sections (id, name, display_order)
values ('00000000-0000-0000-0000-000000000311', 'Release test days', 95);

insert into public.staff_members (id, display_name, role)
values
  ('00000000-0000-0000-0000-000000000321', 'Test Manager', 'manager'),
  ('00000000-0000-0000-0000-000000000322', 'Test Administrator', 'administrator'),
  ('00000000-0000-0000-0000-000000000323', 'Listed Nurse', 'staff_member'),
  ('00000000-0000-0000-0000-000000000325', 'Second Nurse', 'staff_member');

insert into public.staff_members (id, display_name, active)
values ('00000000-0000-0000-0000-000000000324', 'Former Nurse', false);

insert into public.staff_accounts (
  staff_member_id,
  auth_user_id,
  personal_email,
  accepted_invite_at
)
values
  (
    '00000000-0000-0000-0000-000000000321',
    '00000000-0000-0000-0000-000000000301',
    'manager@example.test',
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000322',
    '00000000-0000-0000-0000-000000000302',
    'administrator@example.test',
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000323',
    '00000000-0000-0000-0000-000000000303',
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
    '00000000-0000-0000-0000-000000000323',
    '00000000-0000-0000-0000-000000000311',
    0,
    '2026-09-01'
  ),
  (
    '00000000-0000-0000-0000-000000000324',
    '00000000-0000-0000-0000-000000000311',
    1,
    '2026-09-01'
  ),
  (
    '00000000-0000-0000-0000-000000000325',
    '00000000-0000-0000-0000-000000000311',
    2,
    '2026-09-01'
  );

create function pg_temp.cell(staff_member_id text, work_date text, shift_code text)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'staff_member_id', staff_member_id,
    'section_id', '00000000-0000-0000-0000-000000000311',
    'work_date', work_date,
    'shift_code', shift_code
  )
$$;

grant execute on function pg_temp.cell(text, text, text) to authenticated;

insert into public.schedule_months (month_start, loaded_from_page_at)
values ('2027-05-01', now());

set local role authenticated;

-- A Staff member may not start a month.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000303","role":"authenticated"}',
  true
);

select throws_ok(
  $$select public.start_month('2027-03-01', jsonb_build_array(
      pg_temp.cell('00000000-0000-0000-0000-000000000323', '2027-03-01', '7A')
    ))$$,
  'Only the Manager can start a month',
  'a Staff member cannot start a month'
);

-- The Manager starts next month.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000301","role":"authenticated"}',
  true
);

select throws_ok(
  $$select public.start_month('2027-03-01', jsonb_build_array(
      pg_temp.cell('00000000-0000-0000-0000-000000000324', '2027-03-01', '7A')
    ))$$,
  'Every cell must be for someone on the Staff list in that Section',
  'a cell for a deactivated Staff member is refused'
);

select throws_ok(
  $$select public.start_month('2027-03-01', jsonb_build_array(
      pg_temp.cell('00000000-0000-0000-0000-000000000323', '2027-04-01', '7A')
    ))$$,
  'Schedule cell date must belong to its Schedule month',
  'a cell outside the month is refused'
);

select is(
  (select count(*)::integer from public.schedule_months where month_start = '2027-03-01'),
  0,
  'a refused start leaves no month behind'
);

select lives_ok(
  $$select public.start_month('2027-03-01', jsonb_build_array(
      pg_temp.cell('00000000-0000-0000-0000-000000000323', '2027-03-01', '7A'),
      pg_temp.cell('00000000-0000-0000-0000-000000000323', '2027-03-02', 'X')
    ))$$,
  'the Manager starts next month'
);

select is(
  (select release_state::text from public.schedule_months where month_start = '2027-03-01'),
  'unpublished',
  'a started month is unpublished'
);

select is(
  (select count(*)::integer from public.schedule_changes
    where work_date >= '2027-03-01' and work_date < '2027-04-01'),
  0,
  'starting a month logs no changes'
);

select throws_ok(
  $$select public.start_month('2027-03-01', '[]'::jsonb)$$,
  'That month has already been started',
  'a month is started only once'
);

select lives_ok(
  $$select public.save_schedule_cell(
      '00000000-0000-0000-0000-000000000323',
      '00000000-0000-0000-0000-000000000311',
      '2027-03-02',
      'D'
    )$$,
  'the Manager edits the unpublished month'
);

-- The Administrator sees the unpublished month; a Staff member does not.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000302","role":"authenticated"}',
  true
);

select is(
  (select count(*)::integer from public.schedule_cells
    where work_date >= '2027-03-01' and work_date < '2027-04-01'),
  2,
  'a scheduler reads the unpublished month'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000303","role":"authenticated"}',
  true
);

select is(
  (select count(*)::integer from public.schedule_months where month_start = '2027-03-01'),
  0,
  'a Staff member cannot see the unpublished month'
);

select is(
  (select count(*)::integer from public.schedule_cells
    where work_date >= '2027-03-01' and work_date < '2027-04-01'),
  0,
  'a Staff member cannot read cells of the unpublished month'
);

select throws_ok(
  $$select public.release_month_checked('2027-03-01', true)$$,
  'Only the Manager can release a month',
  'a Staff member cannot release a month'
);

-- An account without an accepted Invite sees nothing.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000304","role":"authenticated"}',
  true
);

select is(
  (select count(*)::integer from public.schedule_cells
    where work_date >= '2027-03-01' and work_date < '2027-04-01'),
  0,
  'an uninvited account cannot read the unpublished month'
);

-- The Manager releases it.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000301","role":"authenticated"}',
  true
);

select throws_ok(
  $$select public.release_month_checked('2027-05-01', true)$$,
  'There is no unpublished month to release',
  'a month loaded from the printed page is released by confirming it'
);

select lives_ok(
  $$select public.release_month_checked('2027-03-01', true)$$,
  'the Manager releases the month'
);

-- pgTAP runs this script in one transaction, where now() never advances.
-- Set distinct timestamps to model edits before and after release.
reset role;
update public.schedule_changes
set changed_at = now() - interval '2 hours'
where work_date >= '2027-03-01' and work_date < '2027-04-01';
update public.schedule_months
set released_at = now() - interval '1 hour'
where month_start = '2027-03-01';
set local role authenticated;

select is(
  (select count(*)::integer from public.schedule_changes
    where work_date >= '2027-03-01' and work_date < '2027-04-01'
      and announced_at is null),
  0,
  'edits made while building the month need no announcement'
);

select throws_ok(
  $$select public.release_month_checked('2027-03-01', true)$$,
  'There is no unpublished month to release',
  'a month is released only once'
);

-- Now a Staff member sees it.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000303","role":"authenticated"}',
  true
);

select is(
  (select release_state::text from public.schedule_months where month_start = '2027-03-01'),
  'released',
  'a Staff member sees the released month'
);

select is(
  (select shift_code from public.schedule_cells
    where staff_member_id = '00000000-0000-0000-0000-000000000323'
      and work_date = '2027-03-02'),
  'D',
  'a Staff member reads cells of the released month'
);

select is(
  (select count(*)::integer from public.schedule_changes
    where work_date >= '2027-03-01' and work_date < '2027-04-01'),
  0,
  'a Staff member cannot read changes made before month release'
);

select throws_ok(
  $$select public.save_schedule_cell(
      '00000000-0000-0000-0000-000000000323',
      '00000000-0000-0000-0000-000000000311',
      '2027-03-02', 'X'
    )$$,
  'Only the Manager can edit the Schedule',
  'a Staff member cannot write a cell through the save function'
);
select throws_ok(
  $$insert into public.schedule_cells (
      schedule_month_id, staff_member_id, section_id, work_date, shift_code
    ) values (
      '00000000-0000-0000-0000-000000000000',
      '00000000-0000-0000-0000-000000000323',
      '00000000-0000-0000-0000-000000000311', '2027-03-03', '7A'
    )$$,
  '42501', null,
  'a Staff member cannot insert a cell directly'
);
select throws_ok(
  $$update public.schedule_cells set shift_code = 'X'
    where staff_member_id = '00000000-0000-0000-0000-000000000323'
      and work_date = '2027-03-02'$$,
  '42501', null,
  'a Staff member cannot update a cell directly'
);
select throws_ok(
  $$delete from public.schedule_cells
    where staff_member_id = '00000000-0000-0000-0000-000000000323'
      and work_date = '2027-03-02'$$,
  '42501', null,
  'a Staff member cannot delete a cell directly'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000301","role":"authenticated"}',
  true
);
select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000323',
  '00000000-0000-0000-0000-000000000311', '2027-03-02', 'X'
);
select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000325',
  '00000000-0000-0000-0000-000000000311', '2027-03-02', '7A'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000303","role":"authenticated"}',
  true
);
select is(
  (select count(*)::integer from public.schedule_changes
    where work_date >= '2027-03-01' and work_date < '2027-04-01'),
  1,
  'a Staff member reads only their own post-release change'
);
select is(
  (select count(*)::integer from public.schedule_changes
    where staff_member_id = '00000000-0000-0000-0000-000000000325'),
  0,
  'a Staff member cannot read another person’s changes'
);
select is(
  (select count(*)::integer from public.schedule_cells
    where staff_member_id = '00000000-0000-0000-0000-000000000323'
      and work_date = '2027-03-02' and shift_code = 'X'),
  1,
  'the Staff member sees the changed cell'
);

select * from finish();
rollback;
