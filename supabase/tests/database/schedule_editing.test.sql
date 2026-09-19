begin;

create extension if not exists pgtap with schema extensions;
select plan(12);

insert into auth.users (id, email)
values
  ('00000000-0000-0000-0000-000000000171', 'manager@example.test'),
  ('00000000-0000-0000-0000-000000000172', 'staff@example.test'),
  ('00000000-0000-0000-0000-000000000173', 'outsider@example.test');

insert into public.sections (id, name, display_order)
values ('00000000-0000-0000-0000-000000000174', 'Editing test Section', 98);

insert into public.staff_members (id, display_name, role)
values
  ('00000000-0000-0000-0000-000000000175', 'Test Manager', 'manager'),
  ('00000000-0000-0000-0000-000000000176', 'Test Staff member', 'staff_member');

insert into public.staff_accounts (
  staff_member_id,
  auth_user_id,
  personal_email,
  accepted_invite_at
)
values
  (
    '00000000-0000-0000-0000-000000000175',
    '00000000-0000-0000-0000-000000000171',
    'manager@example.test',
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000176',
    '00000000-0000-0000-0000-000000000172',
    'staff@example.test',
    now()
  );

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000171","role":"authenticated"}',
  true
);

select ok(public.can_edit_schedule(), 'the Manager can edit the Schedule');

select lives_ok(
  $$
    select public.save_schedule_cell(
      '00000000-0000-0000-0000-000000000176',
      '00000000-0000-0000-0000-000000000174',
      '2027-03-18',
      '7A'
    )
  $$,
  'the Manager saves a Shift code in a month not yet started'
);

select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000176',
  '00000000-0000-0000-0000-000000000174',
  '2027-03-18',
  ' X '
);

select is(
  (
    select shift_code
    from public.schedule_cells
    where staff_member_id = '00000000-0000-0000-0000-000000000176'
      and work_date = '2027-03-18'
  ),
  'X',
  'the saved Shift code is live and trimmed'
);

select results_eq(
  $$
    select old_shift_code, new_shift_code, changed_by_staff_member_id
    from public.schedule_changes
    where staff_member_id = '00000000-0000-0000-0000-000000000176'
      and work_date = '2027-03-18'
    order by changed_at, id
  $$,
  $$
    values
      ('', '7A', '00000000-0000-0000-0000-000000000175'::uuid),
      ('7A', 'X', '00000000-0000-0000-0000-000000000175'::uuid)
  $$,
  'each save is written to the change log with who, old and new value'
);

select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000176',
  '00000000-0000-0000-0000-000000000174',
  '2027-03-18',
  'X'
);

select is(
  (
    select count(*)::integer
    from public.schedule_changes
    where staff_member_id = '00000000-0000-0000-0000-000000000176'
  ),
  2,
  'saving an unchanged Shift code logs nothing'
);

select is(
  (
    select announced_at
    from public.schedule_changes
    where staff_member_id = '00000000-0000-0000-0000-000000000176'
    order by changed_at desc, id
    limit 1
  ),
  null,
  'a new change is unannounced'
);

select throws_ok(
  $$
    insert into public.schedule_cells (
      schedule_month_id, staff_member_id, section_id, work_date, shift_code
    )
    select id,
      '00000000-0000-0000-0000-000000000176',
      '00000000-0000-0000-0000-000000000174',
      '2027-03-19',
      'N'
    from public.schedule_months
    where month_start = '2027-03-01'
  $$,
  '42501',
  null,
  'even the Manager writes cells only through the logged save'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000172","role":"authenticated"}',
  true
);

select ok(not public.can_edit_schedule(), 'a Staff member cannot edit');

select throws_ok(
  $$
    select public.save_schedule_cell(
      '00000000-0000-0000-0000-000000000176',
      '00000000-0000-0000-0000-000000000174',
      '2027-03-18',
      'R/O'
    )
  $$,
  'Only the Manager can edit the Schedule',
  'a Staff member cannot save a Shift code'
);

select is(
  (select count(*)::integer from public.schedule_changes),
  0,
  'a Staff member cannot read the change log'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000173","role":"authenticated"}',
  true
);

select is(
  (select count(*)::integer from public.schedule_changes),
  0,
  'an account without an accepted Invite reads no change log'
);

select throws_ok(
  $$
    select public.save_schedule_cell(
      '00000000-0000-0000-0000-000000000176',
      '00000000-0000-0000-0000-000000000174',
      '2027-03-18',
      '7P'
    )
  $$,
  'Only the Manager can edit the Schedule',
  'an account without an accepted Invite cannot save'
);

select * from finish();
rollback;
