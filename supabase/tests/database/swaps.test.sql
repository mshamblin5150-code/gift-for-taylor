begin;

create extension if not exists pgtap with schema extensions;
select plan(41);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000281', 'swap-manager@example.test'),
  ('00000000-0000-0000-0000-000000000282', 'swap-a@example.test'),
  ('00000000-0000-0000-0000-000000000283', 'swap-b@example.test');
insert into public.sections (id, name, display_order) values
  ('00000000-0000-0000-0000-000000000284', 'Swap test Section', 97);
insert into public.staff_members (id, display_name, role, cell_number) values
  ('00000000-0000-0000-0000-000000000285', 'Swap Manager', 'manager', null),
  ('00000000-0000-0000-0000-000000000286', 'Swap A', 'staff_member', '+15551112222'),
  ('00000000-0000-0000-0000-000000000287', 'Swap B', 'staff_member', '+15553334444');
insert into public.staff_accounts (staff_member_id, auth_user_id, personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000000285', '00000000-0000-0000-0000-000000000281', 'swap-manager@example.test', now()),
  ('00000000-0000-0000-0000-000000000286', '00000000-0000-0000-0000-000000000282', 'swap-a@example.test', now()),
  ('00000000-0000-0000-0000-000000000287', '00000000-0000-0000-0000-000000000283', 'swap-b@example.test', now());
insert into public.staff_section_assignments (staff_member_id, section_id, display_order, effective_from) values
  ('00000000-0000-0000-0000-000000000286', '00000000-0000-0000-0000-000000000284', 0, '2000-01-01'),
  ('00000000-0000-0000-0000-000000000287', '00000000-0000-0000-0000-000000000284', 1, '2000-01-01');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000281","role":"authenticated"}', true);
select public.save_schedule_cell('00000000-0000-0000-0000-000000000286',
  '00000000-0000-0000-0000-000000000284', '2027-06-03', '7A');
select public.save_schedule_cell('00000000-0000-0000-0000-000000000287',
  '00000000-0000-0000-0000-000000000284', '2027-06-05', '7P');
select public.release_month_checked('2027-06-01', true);

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000282","role":"authenticated"}', true);
select lives_ok($$select public.propose_swap(
  '00000000-0000-0000-0000-000000000287', '2027-06-03', '2027-06-05')$$,
  'Staff member proposes a Swap');
select is((select count(*)::int from public.swaps), 1,
  'requester sees the proposed Swap');
select is(public.swap_colleague_cell_number((select id from public.swaps limit 1)),
  '+15553334444'::text,
  'the requester can open a text draft to the proposed colleague');
select is((select count(*)::int from public.staff_notices where kind = 'swap_proposed' and staff_member_id = '00000000-0000-0000-0000-000000000286'), 0,
  'requester does not receive their own proposal');
select throws_ok($$select public.approve_swap((select id from public.swaps limit 1))$$,
  'Only the Manager can approve a Swap');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000283","role":"authenticated"}', true);
select is((select count(*)::int from public.swaps), 1,
  'colleague sees the proposed Swap');
select is(public.swap_colleague_cell_number((select id from public.swaps limit 1)),
  null::text,
  'the colleague cannot use the requester-only contact path');
select is((select count(*)::int from public.staff_notices where kind = 'swap_proposed'), 1,
  'colleague receives the proposal');
select lives_ok($$select public.answer_swap((select id from public.swaps limit 1), true, null)$$,
  'colleague accepts');
select is((select status::text from public.swaps limit 1), 'accepted',
  'accepted Swap awaits Manager approval');
reset role;
select is((select count(*)::int from public.staff_notices where kind = 'swap_accepted'), 2,
  'requester and Manager receive acceptance');
set local role authenticated;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000281","role":"authenticated"}', true);
select lives_ok($$select public.approve_swap((select id from public.swaps limit 1))$$,
  'Manager approves the Swap');
reset role;
select is((select count(*)::int from public.staff_notices where kind = 'swap_approved'), 2,
  'both Staff members receive approval');
set local role authenticated;
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
select is((select count(*)::int from public.staff_notices where kind = 'swap_declined'), 1,
  'requester receives the declined Swap');
select is((select reason from public.swaps where status = 'declined'),
  'Cannot cover', 'requester sees the decline reason');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000281","role":"authenticated"}', true);
select public.save_schedule_cell('00000000-0000-0000-0000-000000000286',
  '00000000-0000-0000-0000-000000000284', '2027-06-10', '7A');
select public.save_schedule_cell('00000000-0000-0000-0000-000000000287',
  '00000000-0000-0000-0000-000000000284', '2027-06-12', '7P');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000282","role":"authenticated"}', true);
select lives_ok($$select public.propose_swap(
  '00000000-0000-0000-0000-000000000287', '2027-06-10', '2027-06-12')$$,
  'Staff member proposes another working Swap');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000283","role":"authenticated"}', true);
select lives_ok($$select public.answer_swap(
  (select id from public.swaps where requester_date = '2027-06-10'), true)$$,
  'colleague accepts another Swap');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000281","role":"authenticated"}', true);
select public.save_schedule_cell('00000000-0000-0000-0000-000000000286',
  '00000000-0000-0000-0000-000000000284', '2027-06-10', '7P');
select throws_ok($$select public.approve_swap(
  (select id from public.swaps where requester_date = '2027-06-10'))$$,
  'A Shift code changed; propose a new Swap',
  'Manager cannot approve when requester Shift code changed');
select public.save_schedule_cell('00000000-0000-0000-0000-000000000286',
  '00000000-0000-0000-0000-000000000284', '2027-06-10', '7A');
select public.save_schedule_cell('00000000-0000-0000-0000-000000000287',
  '00000000-0000-0000-0000-000000000284', '2027-06-12', '7A');
select throws_ok($$select public.approve_swap(
  (select id from public.swaps where requester_date = '2027-06-10'))$$,
  'A Shift code changed; propose a new Swap',
  'Manager cannot approve when colleague Shift code changed');

select throws_ok($$select public.approve_swap(
  (select id from public.swaps where status = 'declined' limit 1))$$,
  'This Swap is not awaiting approval',
  'Manager cannot approve a declined Swap');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000282","role":"authenticated"}', true);
select throws_ok($$select public.decline_swap(
  (select id from public.swaps where requester_date = '2027-06-10'), 'No')$$,
  'Only the Manager can decline a Swap',
  'Staff member cannot decline an accepted Swap');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000281","role":"authenticated"}', true);
select lives_ok($$select public.decline_swap(
  (select id from public.swaps where requester_date = '2027-06-10'), '  Coverage needed  ')$$,
  'Manager declines an accepted Swap');
select is((select status::text from public.swaps where requester_date = '2027-06-10'),
  'declined', 'Manager decline records the Swap state');
select is((select reason from public.swaps where requester_date = '2027-06-10'),
  'Coverage needed', 'Manager decline trims and records the reason');
select is((select shift_code from public.schedule_cells where staff_member_id =
  '00000000-0000-0000-0000-000000000286' and work_date = '2027-06-10'),
  '7A', 'Manager decline leaves the Schedule unchanged');
select throws_ok($$select public.approve_swap(
  (select id from public.swaps where requester_date = '2027-06-10'))$$,
  'This Swap is not awaiting approval',
  'Manager cannot approve a Swap they declined');

select public.save_schedule_cell('00000000-0000-0000-0000-000000000286',
  '00000000-0000-0000-0000-000000000284', '2027-06-14', 'H');
select public.save_schedule_cell('00000000-0000-0000-0000-000000000287',
  '00000000-0000-0000-0000-000000000284', '2027-06-16', '7P');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000282","role":"authenticated"}', true);
select throws_ok($$select public.propose_swap(
  '00000000-0000-0000-0000-000000000287', '2027-06-14', '2027-06-16')$$,
  'Both Staff members need working shifts on released Schedules',
  'day off cannot be offered in a Swap');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000281","role":"authenticated"}', true);
select public.save_schedule_cell('00000000-0000-0000-0000-000000000286',
  '00000000-0000-0000-0000-000000000284', '2027-06-14', '7A');
select public.save_schedule_cell('00000000-0000-0000-0000-000000000287',
  '00000000-0000-0000-0000-000000000284', '2027-06-16', 'S/L');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000282","role":"authenticated"}', true);
select throws_ok($$select public.propose_swap(
  '00000000-0000-0000-0000-000000000287', '2027-06-14', '2027-06-16')$$,
  'Both Staff members need working shifts on released Schedules',
  'colleague Sick leave cannot be offered in a Swap');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000281","role":"authenticated"}', true);
select public.save_schedule_cell('00000000-0000-0000-0000-000000000286',
  '00000000-0000-0000-0000-000000000284', '2027-06-18', '7A');
select public.save_schedule_cell('00000000-0000-0000-0000-000000000287',
  '00000000-0000-0000-0000-000000000284', '2027-06-18', '7A');
select public.save_schedule_cell('00000000-0000-0000-0000-000000000286',
  '00000000-0000-0000-0000-000000000284', '2027-06-20', '7A');
select public.save_schedule_cell('00000000-0000-0000-0000-000000000287',
  '00000000-0000-0000-0000-000000000284', '2027-06-22', '7P');
select public.save_schedule_cell('00000000-0000-0000-0000-000000000286',
  '00000000-0000-0000-0000-000000000284', '2027-06-22', '7A');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000282","role":"authenticated"}', true);
select throws_ok($$select public.propose_swap(
  '00000000-0000-0000-0000-000000000287', '2027-06-18', '2027-06-18')$$,
  'Choose shifts that would change the Schedule',
  'same-day same-code Swap is refused');
select throws_ok($$select public.propose_swap(
  '00000000-0000-0000-0000-000000000287', '2027-06-20', '2027-06-22')$$,
  'Both destination dates must be free',
  'occupied destination date refuses a Swap');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000281","role":"authenticated"}', true);
select public.save_schedule_cell('00000000-0000-0000-0000-000000000286',
  '00000000-0000-0000-0000-000000000284', current_date - 1, '7A');
select public.save_schedule_cell('00000000-0000-0000-0000-000000000287',
  '00000000-0000-0000-0000-000000000284', current_date + 1, '7P');
select public.save_schedule_cell('00000000-0000-0000-0000-000000000286',
  '00000000-0000-0000-0000-000000000284', current_date + 2, '7A');
select public.save_schedule_cell('00000000-0000-0000-0000-000000000287',
  '00000000-0000-0000-0000-000000000284', current_date - 2, '7P');
select public.save_schedule_cell('00000000-0000-0000-0000-000000000286',
  '00000000-0000-0000-0000-000000000284', current_date, '7A');
select public.save_schedule_cell('00000000-0000-0000-0000-000000000287',
  '00000000-0000-0000-0000-000000000284', current_date + 3, '7P');
select public.release_month_checked(month_start, true)
from (
  select distinct date_trunc('month', work_date)::date as month_start
  from (values
    (current_date - 2),
    (current_date - 1),
    (current_date),
    (current_date + 1),
    (current_date + 2),
    (current_date + 3)
  ) dates(work_date)
) months;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000282","role":"authenticated"}', true);
select throws_ok(
  format($query$select public.propose_swap(
    '00000000-0000-0000-0000-000000000287', %L, %L)$query$,
    current_date - 1, current_date + 1),
  format('Swap day %s must be after today', current_date - 1),
  'requester cannot offer a past day');
select throws_ok(
  format($query$select public.propose_swap(
    '00000000-0000-0000-0000-000000000287', %L, %L)$query$,
    current_date + 2, current_date - 2),
  format('Swap day %s must be after today', current_date - 2),
  'colleague cannot offer a past day');
select throws_ok(
  format($query$select public.propose_swap(
    '00000000-0000-0000-0000-000000000287', %L, %L)$query$,
    current_date, current_date + 3),
  format('Swap day %s must be after today', current_date),
  'today is not offered because both sides must be after today');

reset role;
insert into public.swaps (
  requester_id, colleague_id, requester_date, colleague_date,
  requester_code, colleague_code, requester_target_code, colleague_target_code,
  requester_section_id, colleague_section_id, status
) values (
  '00000000-0000-0000-0000-000000000286',
  '00000000-0000-0000-0000-000000000287',
  current_date, current_date + 1, '7A', '7P', '', '',
  '00000000-0000-0000-0000-000000000284',
  '00000000-0000-0000-0000-000000000284', 'accepted'
);
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000281","role":"authenticated"}', true);
select throws_ok(
  format($query$select public.approve_swap(%L)$query$,
    (select id from public.swaps
      where requester_date = current_date and status = 'accepted')),
  format('Swap day %s must be after today', current_date),
  'a Swap cannot be approved after an offered day arrives');

select * from finish();
rollback;
