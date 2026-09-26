begin;

create extension if not exists pgtap with schema extensions;
select plan(24);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000003431', 'giveaway-manager@example.test'),
  ('00000000-0000-0000-0000-000000003432', 'giveaway-giver@example.test'),
  ('00000000-0000-0000-0000-000000003433', 'giveaway-receiver@example.test'),
  ('00000000-0000-0000-0000-000000003434', 'giveaway-wrong-role@example.test'),
  ('00000000-0000-0000-0000-000000003442', 'giveaway-no-section@example.test');
insert into public.sections (id, name, display_order) values
  ('00000000-0000-0000-0000-000000003435', 'Giveaway RN', 343),
  ('00000000-0000-0000-0000-000000003436', 'Giveaway LPN', 344),
  ('00000000-0000-0000-0000-000000003437', 'Giveaway CNA', 345);
insert into public.staff_members (id, display_name, role) values
  ('00000000-0000-0000-0000-000000003438', 'Giveaway Manager', 'manager'),
  ('00000000-0000-0000-0000-000000003439', 'Giveaway Giver', 'staff_member'),
  ('00000000-0000-0000-0000-000000003440', 'Giveaway Receiver', 'staff_member'),
  ('00000000-0000-0000-0000-000000003441', 'Giveaway Wrong Role', 'staff_member'),
  ('00000000-0000-0000-0000-000000003443', 'Giveaway No Section', 'staff_member');
insert into public.staff_accounts
  (staff_member_id, auth_user_id, personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000003438', '00000000-0000-0000-0000-000000003431', 'giveaway-manager@example.test', now()),
  ('00000000-0000-0000-0000-000000003439', '00000000-0000-0000-0000-000000003432', 'giveaway-giver@example.test', now()),
  ('00000000-0000-0000-0000-000000003440', '00000000-0000-0000-0000-000000003433', 'giveaway-receiver@example.test', now()),
  ('00000000-0000-0000-0000-000000003441', '00000000-0000-0000-0000-000000003434', 'giveaway-wrong-role@example.test', now()),
  ('00000000-0000-0000-0000-000000003443', '00000000-0000-0000-0000-000000003442', 'giveaway-no-section@example.test', now());
insert into public.staff_section_assignments
  (staff_member_id, section_id, display_order, effective_from) values
  ('00000000-0000-0000-0000-000000003439', '00000000-0000-0000-0000-000000003435', 0, '2000-01-01'),
  ('00000000-0000-0000-0000-000000003440', '00000000-0000-0000-0000-000000003436', 1, '2000-01-01'),
  ('00000000-0000-0000-0000-000000003441', '00000000-0000-0000-0000-000000003437', 2, '2000-01-01');
insert into public.staff_job_roles (staff_member_id, job_role, effective_from) values
  ('00000000-0000-0000-0000-000000003439', 'rn', '2000-01-01'),
  ('00000000-0000-0000-0000-000000003440', 'lpn', '2000-01-01'),
  ('00000000-0000-0000-0000-000000003441', 'cna', '2000-01-01'),
  ('00000000-0000-0000-0000-000000003443', 'rn', '2000-01-01');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003431","role":"authenticated"}', true);
select public.save_schedule_cell('00000000-0000-0000-0000-000000003439',
  '00000000-0000-0000-0000-000000003435', day, '7A')
from unnest(array['2027-10-01'::date, '2027-10-02', '2027-10-03',
  '2027-10-04', '2027-10-05', '2027-10-06']) day;
select public.release_month_checked('2027-10-01', true);

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003432","role":"authenticated"}', true);
select results_eq(
  $$select staff_member_id from public.eligible_giveaway_colleagues(
    array['2027-10-01'::date, '2027-10-02'])$$,
  $$values ('00000000-0000-0000-0000-000000003440'::uuid)$$,
  'the picker returns only a colleague eligible on every selected day');
select throws_ok($$select public.propose_giveaway(
  '00000000-0000-0000-0000-000000003441', array['2027-10-01'::date])$$,
  'The colleague cannot take every selected shift',
  'a colleague in the wrong Job role is refused');
select throws_ok($$select public.propose_giveaway(
  '00000000-0000-0000-0000-000000003443', array['2027-10-01'::date])$$,
  'The colleague cannot take every selected shift',
  'a colleague without a Section that day is refused');
reset role;
insert into public.schedule_cells(schedule_month_id, staff_member_id,
  section_id, work_date, shift_code)
select month.id, '00000000-0000-0000-0000-000000003440',
  '00000000-0000-0000-0000-000000003436', '2027-10-03', '7P'
from public.schedule_months month where month.month_start = '2027-10-01';
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003432","role":"authenticated"}', true);
select throws_ok($$select public.propose_giveaway(
  '00000000-0000-0000-0000-000000003440', array['2027-10-03'::date])$$,
  'The colleague cannot take every selected shift',
  'a colleague already working that day is refused');
reset role;
delete from public.schedule_cells where staff_member_id =
  '00000000-0000-0000-0000-000000003440' and work_date = '2027-10-03';
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003432","role":"authenticated"}', true);
select lives_ok($$select public.propose_giveaway(
  '00000000-0000-0000-0000-000000003440',
  array['2027-10-01'::date, '2027-10-02'])$$,
  'a multi-day Giveaway is proposed once');
select is((select count(*)::integer from public.giveaway_shifts), 2,
  'one child row records each given shift');
reset role;
select is((select count(*)::integer from public.staff_notices
  where kind = 'giveaway_proposed'), 1,
  'the colleague receives one proposal notice');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003433","role":"authenticated"}', true);
select lives_ok($$select public.answer_giveaway(
  (select id from public.giveaways where status = 'proposed'), true)$$,
  'the colleague accepts the whole Giveaway once');
select is((select status::text from public.giveaways where status = 'accepted'),
  'accepted', 'the accepted Giveaway awaits the Manager');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003431","role":"authenticated"}', true);
select public.set_pool_date_minimum('nurses', 'day', '2027-10-01', 1, 1);
select is(public.giveaway_creates_shortfall(
  (select id from public.giveaways where status = 'accepted')), true,
  'an RN-to-LPN Giveaway that breaches the RN floor warns without blocking');
select lives_ok($$select public.approve_giveaway(
  (select id from public.giveaways where status = 'accepted'))$$,
  'the Manager approves every given shift atomically');
select is((select shift_code from public.schedule_cells where staff_member_id =
  '00000000-0000-0000-0000-000000003439' and work_date = '2027-10-01'),
  'X', 'the giver is off after approval');
select is((select shift_code from public.schedule_cells where staff_member_id =
  '00000000-0000-0000-0000-000000003440' and work_date = '2027-10-01'),
  '7A', 'the colleague receives the shift in their Section');
select is((select count(*)::integer from public.schedule_changes
  where giveaway_id = (select id from public.giveaways where status = 'approved')),
  4, 'all Schedule changes carry the Giveaway grouping hint');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003432","role":"authenticated"}', true);
select public.propose_giveaway('00000000-0000-0000-0000-000000003440',
  array['2027-10-03'::date]);
select lives_ok($$select public.withdraw_giveaway(
  (select id from public.giveaways where status = 'proposed'))$$,
  'the giver can withdraw a proposed Giveaway');
select is((select status::text from public.giveaways where status = 'withdrawn'),
  'withdrawn', 'withdrawn is its own terminal outcome');

reset role;
delete from public.staff_notices where kind = 'giveaway_withdrawn';
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003432","role":"authenticated"}', true);
select public.propose_giveaway('00000000-0000-0000-0000-000000003440',
  array['2027-10-04'::date]);
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003433","role":"authenticated"}', true);
select public.answer_giveaway(
  (select id from public.giveaways where status = 'proposed'), true);
select throws_ok($$select public.withdraw_giveaway(
  (select id from public.giveaways where status = 'accepted'))$$,
  'This Giveaway cannot be withdrawn',
  'the colleague cannot withdraw the Giveaway');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003432","role":"authenticated"}', true);
select lives_ok($$select public.withdraw_giveaway(
  (select id from public.giveaways where status = 'accepted'))$$,
  'the giver can withdraw after acceptance');
reset role;
select is((select count(*)::integer from public.staff_notices
  where kind = 'giveaway_withdrawn'), 2,
  'an accepted withdrawal tells the colleague and the Manager');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003432","role":"authenticated"}', true);

select public.propose_giveaway('00000000-0000-0000-0000-000000003440',
  array['2027-10-03'::date]);
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003433","role":"authenticated"}', true);
select public.answer_giveaway(
  (select id from public.giveaways where status = 'proposed'), true);
reset role;
alter table public.schedule_cells disable trigger void_giveaways_for_changed_cell;
insert into public.schedule_cells(schedule_month_id, staff_member_id,
  section_id, work_date, shift_code)
select month.id, '00000000-0000-0000-0000-000000003440',
  '00000000-0000-0000-0000-000000003436', '2027-10-03', '7P'
from public.schedule_months month where month.month_start = '2027-10-01';
alter table public.schedule_cells enable trigger void_giveaways_for_changed_cell;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003431","role":"authenticated"}', true);
select throws_ok($$select public.approve_giveaway(
  (select id from public.giveaways where status = 'accepted'))$$,
  'A Shift code changed; propose a new Giveaway',
  'approval rechecks that every receiver day is still free');
select is((select shift_code from public.schedule_cells where staff_member_id =
  '00000000-0000-0000-0000-000000003439' and work_date = '2027-10-03'),
  '7A', 'a stale approval changes none of the selected cells');

reset role;
delete from public.schedule_cells where staff_member_id =
  '00000000-0000-0000-0000-000000003440' and work_date = '2027-10-03';
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003432","role":"authenticated"}', true);
select public.propose_giveaway('00000000-0000-0000-0000-000000003440',
  array['2027-10-05'::date, '2027-10-06']);
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003431","role":"authenticated"}', true);
select public.save_schedule_cell('00000000-0000-0000-0000-000000003439',
  '00000000-0000-0000-0000-000000003435', '2027-10-06', 'D');
select is((select status::text from public.giveaways
  where status = 'voided' and voided_work_date = '2027-10-06'),
  'voided', 'a depended-on cell edit voids the whole Giveaway');
select is((select voided_work_date from public.giveaways
  where status = 'voided' and voided_work_date = '2027-10-06'),
  '2027-10-06'::date, 'the void records which day moved');
select throws_ok($$select public.approve_giveaway(
  (select id from public.giveaways where status = 'voided'
    and voided_work_date = '2027-10-06'))$$,
  'This Giveaway is not awaiting approval',
  'a voided Giveaway cannot be approved');

select * from finish();
rollback;
