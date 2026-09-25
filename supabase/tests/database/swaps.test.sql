begin;

create extension if not exists pgtap with schema extensions;
select plan(25);

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
insert into public.staff_accounts
  (staff_member_id, auth_user_id, personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000000285', '00000000-0000-0000-0000-000000000281', 'swap-manager@example.test', now()),
  ('00000000-0000-0000-0000-000000000286', '00000000-0000-0000-0000-000000000282', 'swap-a@example.test', now()),
  ('00000000-0000-0000-0000-000000000287', '00000000-0000-0000-0000-000000000283', 'swap-b@example.test', now());
insert into public.staff_section_assignments
  (staff_member_id, section_id, display_order, effective_from) values
  ('00000000-0000-0000-0000-000000000286', '00000000-0000-0000-0000-000000000284', 0, '2000-01-01'),
  ('00000000-0000-0000-0000-000000000287', '00000000-0000-0000-0000-000000000284', 1, '2000-01-01');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000281","role":"authenticated"}', true);
select public.save_schedule_cell('00000000-0000-0000-0000-000000000286',
  '00000000-0000-0000-0000-000000000284', day, '7A')
from unnest(array['2027-06-28'::date, '2027-06-29', '2027-07-01',
  '2027-07-10', '2027-07-15', '2027-07-20', '2027-07-21']) day;
select public.save_schedule_cell('00000000-0000-0000-0000-000000000287',
  '00000000-0000-0000-0000-000000000284', day, '7P')
from unnest(array['2027-06-30'::date, '2027-07-02', '2027-07-03',
  '2027-07-10', '2027-07-16', '2027-07-22', '2027-07-23']) day;
select public.release_month_checked('2027-06-01', true);
select public.release_month_checked('2027-07-01', true);

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000282","role":"authenticated"}', true);
select throws_ok($$select public.propose_swap(
  '00000000-0000-0000-0000-000000000287',
  array['2027-06-28'::date, '2027-06-29'], array['2027-06-30'::date])$$,
  'Choose the same number of shifts for each Staff member',
  'uneven sets are refused with the rule named');
select throws_ok($$select public.propose_swap(
  '00000000-0000-0000-0000-000000000287',
  array(select current_date + n from generate_series(1, 32) n),
  array(select current_date + n + 40 from generate_series(1, 32) n))$$,
  'A Swap can include at most 31 shifts for each Staff member',
  'the transaction guard rail refuses 32 shifts a side');

select lives_ok($$select public.propose_swap(
  '00000000-0000-0000-0000-000000000287',
  array['2027-06-28'::date, '2027-06-29', '2027-07-01'],
  array['2027-06-30'::date, '2027-07-02', '2027-07-03'])$$,
  'a multi-day cross-month Swap is proposed');
select is((select count(*)::int from public.swaps), 1,
  'one agreement represents the whole Swap');
select is((select count(*)::int from public.swap_shifts), 6,
  'one child row records each offered shift');
select is((select count(distinct date_trunc('month', work_date))::int
  from public.swap_shifts), 2, 'offered shifts may span Schedule months');
reset role;
select is((select count(*)::int from public.staff_notices
  where kind = 'swap_proposed'), 1, 'the colleague receives one proposal notice');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000283","role":"authenticated"}', true);
select lives_ok($$select public.answer_swap((select id from public.swaps), true)$$,
  'the colleague accepts the whole Swap once');
select is((select status::text from public.swaps), 'accepted',
  'the accepted Swap awaits one Manager decision');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000281","role":"authenticated"}', true);
select lives_ok($$select public.approve_swap((select id from public.swaps))$$,
  'the Manager approves every offered shift atomically');
select is((select count(*)::int from public.schedule_changes
  where swap_id = (select id from public.swaps)), 12,
  'all twelve changes carry the Swap grouping hint');
select is((select shift_code from public.schedule_cells where staff_member_id =
  '00000000-0000-0000-0000-000000000286' and work_date = '2027-06-30'),
  '7P', 'requester receives a colleague shift');
select is((select shift_code from public.schedule_cells where staff_member_id =
  '00000000-0000-0000-0000-000000000287' and work_date = '2027-06-28'),
  '7A', 'colleague receives a requester shift');
select is((select status::text from public.swaps), 'approved',
  'the agreement is approved once');

-- A date on both sides is ordinary: clear both offered cells, then fill both.
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000282","role":"authenticated"}', true);
select lives_ok($$select public.propose_swap(
  '00000000-0000-0000-0000-000000000287',
  array['2027-07-10'::date], array['2027-07-10'::date])$$,
  'same-date shifts with different codes can be proposed');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000283","role":"authenticated"}', true);
select public.answer_swap((select id from public.swaps where status = 'proposed'), true);
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000281","role":"authenticated"}', true);
select lives_ok($$select public.approve_swap(
  (select id from public.swaps where status = 'accepted'))$$,
  'same-date exchange approves without a special branch');
select is((select shift_code from public.schedule_cells where staff_member_id =
  '00000000-0000-0000-0000-000000000286' and work_date = '2027-07-10'),
  '7P', 'requester receives the same-date colleague code');
select is((select shift_code from public.schedule_cells where staff_member_id =
  '00000000-0000-0000-0000-000000000287' and work_date = '2027-07-10'),
  '7A', 'colleague receives the same-date requester code');

-- Keep the approval-time all-or-nothing stale check as a backstop.
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000282","role":"authenticated"}', true);
select public.propose_swap('00000000-0000-0000-0000-000000000287',
  array['2027-07-15'::date], array['2027-07-16'::date]);
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000283","role":"authenticated"}', true);
select public.answer_swap((select id from public.swaps where status = 'proposed'), true);
reset role;
alter table public.schedule_cells disable trigger void_swaps_for_changed_cell;
update public.schedule_cells set shift_code = 'D'
where staff_member_id = '00000000-0000-0000-0000-000000000286'
  and work_date = '2027-07-15';
alter table public.schedule_cells enable trigger void_swaps_for_changed_cell;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000281","role":"authenticated"}', true);
select throws_ok($$select public.approve_swap(
  (select swap_id from public.swap_shifts where work_date = '2027-07-15'))$$,
  'A Shift code changed; propose a new Swap',
  'one stale code refuses the entire Swap at approval');
select is((select shift_code from public.schedule_cells where staff_member_id =
  '00000000-0000-0000-0000-000000000287' and work_date = '2027-07-16'),
  '7P', 'the stale refusal writes none of the other cells');

-- An ordinary cell edit voids immediately and tells both parties plus its Manager actor.
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000282","role":"authenticated"}', true);
select public.propose_swap('00000000-0000-0000-0000-000000000287',
  array['2027-07-20'::date, '2027-07-21'],
  array['2027-07-22'::date, '2027-07-23']);
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000283","role":"authenticated"}', true);
select public.answer_swap((select id from public.swaps where status = 'proposed'), true);
reset role;
delete from public.staff_notices where kind like 'swap_%';
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000281","role":"authenticated"}', true);
select public.save_schedule_cell('00000000-0000-0000-0000-000000000286',
  '00000000-0000-0000-0000-000000000284', '2027-07-21', 'D');
select is((select status::text from public.swaps where status = 'voided'),
  'voided', 'a depended-on cell edit voids the whole Swap');
select is((select voided_staff_member_id::text from public.swaps
  where status = 'voided'), '00000000-0000-0000-0000-000000000286',
  'the void records which Staff member moved');
select is((select voided_work_date from public.swaps where status = 'voided'),
  '2027-07-21'::date, 'the void records which day moved');
reset role;
select is((select count(*)::int from public.staff_notices
  where kind = 'swap_voided'), 3,
  'both parties and the Manager actor receive the void notice');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000281","role":"authenticated"}', true);
select throws_ok($$select public.approve_swap(
  (select id from public.swaps where status = 'voided'))$$,
  'This Swap is not awaiting approval', 'a voided Swap cannot be approved');

select * from finish();
rollback;
