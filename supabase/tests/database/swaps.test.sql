begin;

create extension if not exists pgtap with schema extensions;
select plan(15);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000281', 'swap-manager@example.test'),
  ('00000000-0000-0000-0000-000000000282', 'swap-a@example.test'),
  ('00000000-0000-0000-0000-000000000283', 'swap-b@example.test');
insert into public.sections (id, name, display_order) values
  ('00000000-0000-0000-0000-000000000284', 'Swap test Section', 97);
insert into public.staff_members (id, display_name, role) values
  ('00000000-0000-0000-0000-000000000285', 'Swap Manager', 'manager'),
  ('00000000-0000-0000-0000-000000000286', 'Swap A', 'staff_member'),
  ('00000000-0000-0000-0000-000000000287', 'Swap B', 'staff_member');
insert into public.staff_accounts (staff_member_id, auth_user_id, personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000000285', '00000000-0000-0000-0000-000000000281', 'swap-manager@example.test', now()),
  ('00000000-0000-0000-0000-000000000286', '00000000-0000-0000-0000-000000000282', 'swap-a@example.test', now()),
  ('00000000-0000-0000-0000-000000000287', '00000000-0000-0000-0000-000000000283', 'swap-b@example.test', now());
insert into public.staff_section_assignments (staff_member_id, section_id, display_order, effective_from) values
  ('00000000-0000-0000-0000-000000000286', '00000000-0000-0000-0000-000000000284', 0, '2027-01-01'),
  ('00000000-0000-0000-0000-000000000287', '00000000-0000-0000-0000-000000000284', 1, '2027-01-01');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000281","role":"authenticated"}', true);
select public.save_schedule_cell('00000000-0000-0000-0000-000000000286',
  '00000000-0000-0000-0000-000000000284', '2027-06-03', '7A');
select public.save_schedule_cell('00000000-0000-0000-0000-000000000287',
  '00000000-0000-0000-0000-000000000284', '2027-06-05', '7P');
select public.release_month('2027-06-01');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000282","role":"authenticated"}', true);
select lives_ok($$select public.propose_swap(
  '00000000-0000-0000-0000-000000000287', '2027-06-03', '2027-06-05')$$,
  'Staff member proposes a Swap');
select is((select count(*)::int from public.swaps), 1,
  'requester sees the proposed Swap');
select throws_ok($$select public.approve_swap((select id from public.swaps limit 1))$$,
  'Only the Manager can approve a Swap');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000283","role":"authenticated"}', true);
select is((select count(*)::int from public.swaps), 1,
  'colleague sees the proposed Swap');
select lives_ok($$select public.answer_swap((select id from public.swaps limit 1), true, null)$$,
  'colleague accepts');
select is((select status::text from public.swaps limit 1), 'accepted',
  'accepted Swap awaits Manager approval');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000281","role":"authenticated"}', true);
select lives_ok($$select public.approve_swap((select id from public.swaps limit 1))$$,
  'Manager approves the Swap');
select is((select shift_code from public.schedule_cells where staff_member_id =
  '00000000-0000-0000-0000-000000000286' and work_date = '2027-06-03'),
  'X', 'requester leaves original date');
select is((select shift_code from public.schedule_cells where staff_member_id =
  '00000000-0000-0000-0000-000000000287' and work_date = '2027-06-05'),
  'X', 'colleague leaves original date');
select is((select shift_code from public.schedule_cells where staff_member_id =
  '00000000-0000-0000-0000-000000000286' and work_date = '2027-06-05'),
  '7P', 'requester receives colleague shift on colleague date');
select is((select shift_code from public.schedule_cells where staff_member_id =
  '00000000-0000-0000-0000-000000000287' and work_date = '2027-06-03'),
  '7A', 'colleague receives requester shift on requester date');
select is((select count(*)::int from public.schedule_changes change
  where change.work_date in ('2027-06-03', '2027-06-05')
    and change.announced_at is null), 4,
  'all four Schedule changes are logged for the Change announcement');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000282","role":"authenticated"}', true);
select lives_ok($$select public.propose_swap(
  '00000000-0000-0000-0000-000000000287', '2027-06-05', '2027-06-03')$$,
  'Staff member may propose another Swap');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000283","role":"authenticated"}', true);
select lives_ok($$select public.answer_swap(
  (select id from public.swaps where status = 'proposed'), false, 'Cannot cover')$$,
  'colleague declines with a reason');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000282","role":"authenticated"}', true);
select is((select reason from public.swaps where status = 'declined'),
  'Cannot cover', 'requester sees the decline reason');

select * from finish();
rollback;
