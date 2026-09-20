begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000000901', 'print-caps@example.test');
insert into public.staff_members(id, display_name, role) values
  ('00000000-0000-0000-0000-000000000902', 'Caps Manager', 'manager');
insert into public.staff_accounts(staff_member_id, auth_user_id, personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000000902',
   '00000000-0000-0000-0000-000000000901', 'print-caps@example.test', now());
insert into public.sections(id, name, display_order) values
  ('00000000-0000-0000-0000-000000000903', 'Caps Section', 999);
insert into public.staff_section_assignments(staff_member_id, section_id, display_order, effective_from)
values ('00000000-0000-0000-0000-000000000902',
        '00000000-0000-0000-0000-000000000903', 0, current_date);

select is((select count(*)::int from pg_constraint
  where conname in ('sections_print_name_limit', 'staff_print_name_limit',
    'schedule_cells_print_code_limit', 'shift_codes_print_code_limit',
    'shift_codes_print_meaning_limit') and not convalidated), 5,
  'all five caps preserve historical rows without validation');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000901","role":"authenticated"}', true);

select lives_ok($$select public.add_section(repeat('S', 32))$$,
  'a Section at the cap can be added');
select throws_ok($$select public.add_section(repeat('S', 33))$$,
  'Section name must be 32 characters or fewer', 'add Section rejects overlong name');
select throws_ok($$select public.rename_section('00000000-0000-0000-0000-000000000903', repeat('S', 33))$$,
  'Section name must be 32 characters or fewer', 'rename Section rejects overlong name');
select throws_ok($$select public.update_staff_contact('00000000-0000-0000-0000-000000000902', repeat('N', 41), null)$$,
  'Staff name must be 30 characters or fewer', 'edit Staff rejects overlong name');
select throws_ok($$select public.create_staff_member_with_invite(repeat('N', 41), '3045550199', '00000000-0000-0000-0000-000000000903')$$,
  'Staff name must be 30 characters or fewer', 'add Staff rejects overlong name');
select throws_ok($$select public.save_shift_code(repeat('C', 9), null, null, null, true, null)$$,
  'Shift code must be 5 characters or fewer', 'catalog rejects overlong code');
select throws_ok($$select public.save_shift_code('CAP', repeat('M', 41), null, null, true, null)$$,
  'Shift meaning must be 40 characters or fewer', 'catalog rejects overlong meaning');
select lives_ok($$select public.save_shift_code('CAP', repeat('M', 40), null, null, true, null)$$,
  'catalog accepts meaning at the cap');
select throws_ok($$select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000902',
  '00000000-0000-0000-0000-000000000903', '2027-09-01', repeat('C', 9))$$,
  'Shift code must be 5 characters or fewer', 'cell RPC rejects overlong code');

reset role;
insert into public.schedule_months(id, month_start) values
  ('00000000-0000-0000-0000-000000000904', '2027-09-01');
select throws_ok($$insert into public.schedule_cells(schedule_month_id, staff_member_id,
  section_id, work_date, shift_code) values
  ('00000000-0000-0000-0000-000000000904',
   '00000000-0000-0000-0000-000000000902',
   '00000000-0000-0000-0000-000000000903', '2027-09-01', repeat('C', 9))$$,
  '23514', null, 'column check rejects overlong cell code');
select throws_ok($$insert into public.shift_codes(code, meaning, is_working)
  values ('COLCAP', repeat('M', 41), true)$$,
  '23514', null, 'column check rejects overlong legend meaning');
select throws_ok($$insert into public.sections(name, display_order)
  values (repeat('S', 33), 999)$$,
  '23514', null, 'column check rejects overlong Section name');
select throws_ok($$insert into public.staff_members(display_name)
  values (repeat('N', 41))$$,
  '23514', null, 'column check rejects overlong Staff name');
select throws_ok($$insert into public.shift_codes(code, is_working)
  values (repeat('C', 9), true)$$,
  '23514', null, 'column check rejects overlong catalog code');

select * from finish();
rollback;
