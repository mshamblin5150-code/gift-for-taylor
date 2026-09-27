begin;

create extension if not exists pgtap with schema extensions;
select plan(12);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000003611', 'swap-eligibility-manager@example.test'),
  ('00000000-0000-0000-0000-000000003612', 'swap-eligibility-rn@example.test'),
  ('00000000-0000-0000-0000-000000003613', 'swap-eligibility-lpn@example.test'),
  ('00000000-0000-0000-0000-000000003614', 'swap-eligibility-cna@example.test');
insert into public.sections (id, name, display_order) values
  ('00000000-0000-0000-0000-000000003615', 'Swap eligibility RN', 361),
  ('00000000-0000-0000-0000-000000003616', 'Swap eligibility LPN', 362),
  ('00000000-0000-0000-0000-000000003617', 'Swap eligibility CNA', 363);
insert into public.staff_members (id, display_name, role) values
  ('00000000-0000-0000-0000-000000003618', 'Swap eligibility Manager', 'manager'),
  ('00000000-0000-0000-0000-000000003619', 'Swap eligibility RN', 'staff_member'),
  ('00000000-0000-0000-0000-000000003620', 'Swap eligibility LPN', 'staff_member'),
  ('00000000-0000-0000-0000-000000003621', 'Swap eligibility CNA', 'staff_member'),
  ('00000000-0000-0000-0000-000000003622', 'Swap eligibility no Section', 'staff_member');
insert into public.staff_accounts
  (staff_member_id, auth_user_id, personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000003618', '00000000-0000-0000-0000-000000003611', 'swap-eligibility-manager@example.test', now()),
  ('00000000-0000-0000-0000-000000003619', '00000000-0000-0000-0000-000000003612', 'swap-eligibility-rn@example.test', now()),
  ('00000000-0000-0000-0000-000000003620', '00000000-0000-0000-0000-000000003613', 'swap-eligibility-lpn@example.test', now()),
  ('00000000-0000-0000-0000-000000003621', '00000000-0000-0000-0000-000000003614', 'swap-eligibility-cna@example.test', now());
insert into public.staff_section_assignments
  (staff_member_id, section_id, display_order, effective_from,
    effective_through) values
  ('00000000-0000-0000-0000-000000003619', '00000000-0000-0000-0000-000000003615', 0, '2000-01-01', null),
  ('00000000-0000-0000-0000-000000003620', '00000000-0000-0000-0000-000000003616', 1, '2000-01-01', null),
  ('00000000-0000-0000-0000-000000003621', '00000000-0000-0000-0000-000000003617', 2, '2000-01-01', null);
insert into public.staff_job_roles
  (staff_member_id, job_role, effective_from, effective_through) values
  ('00000000-0000-0000-0000-000000003619', 'rn', '2000-01-01', '2027-11-10'),
  ('00000000-0000-0000-0000-000000003619', 'cna', '2027-11-11', '2027-11-13'),
  ('00000000-0000-0000-0000-000000003619', 'rn', '2027-11-14', null),
  ('00000000-0000-0000-0000-000000003620', 'lpn', '2000-01-01', '2027-11-15'),
  ('00000000-0000-0000-0000-000000003620', 'cna', '2027-11-16', null),
  ('00000000-0000-0000-0000-000000003621', 'cna', '2000-01-01', null),
  ('00000000-0000-0000-0000-000000003622', 'rn', '2000-01-01', null);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003611","role":"authenticated"}', true);
select public.save_schedule_cell('00000000-0000-0000-0000-000000003619',
  '00000000-0000-0000-0000-000000003615', day, '7A')
from unnest(array['2027-11-01'::date, '2027-11-03', '2027-11-05',
  '2027-11-07', '2027-11-09', '2027-11-16']) day;
select public.save_schedule_cell('00000000-0000-0000-0000-000000003620',
  '00000000-0000-0000-0000-000000003616', day, '7P')
from unnest(array['2027-11-02'::date, '2027-11-08', '2027-11-12',
  '2027-11-17']) day;
select public.save_schedule_cell('00000000-0000-0000-0000-000000003621',
  '00000000-0000-0000-0000-000000003617', '2027-11-04', '7P');
select public.release_month_checked('2027-11-01', true);

reset role;

select is(public.can_take_shift(
  '00000000-0000-0000-0000-000000003619'::uuid,
  '00000000-0000-0000-0000-000000003620'::uuid, '2027-11-01'::date), true,
  'an LPN can take an RN shift');
select is(public.can_take_shift(
  '00000000-0000-0000-0000-000000003619'::uuid,
  '00000000-0000-0000-0000-000000003621'::uuid, '2027-11-03'::date), false,
  'a CNA cannot take an RN shift');
select is(public.can_take_shift(
  '00000000-0000-0000-0000-000000003619'::uuid,
  '00000000-0000-0000-0000-000000003622'::uuid, '2027-11-03'::date), false,
  'a matching Job role without a Section cannot take the shift');
select is(public.can_take_shift(
  '00000000-0000-0000-0000-000000003619'::uuid,
  '00000000-0000-0000-0000-000000003620'::uuid, '2027-11-16'::date), false,
  'effective-dated Job roles are evaluated on each shift date');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003612","role":"authenticated"}', true);
select results_eq(
  $$select unnest(public.eligible_swap_dates(
    '00000000-0000-0000-0000-000000003619',
    '00000000-0000-0000-0000-000000003620',
    array['2027-11-01'::date, '2027-11-16']))$$,
  $$values ('2027-11-01'::date)$$,
  'the dialog RPC returns only dates the receiver can work');
select lives_ok($$select public.propose_swap(
  '00000000-0000-0000-0000-000000003620',
  array['2027-11-01'::date], array['2027-11-02'::date])$$,
  'an RN and LPN may propose a Swap');
select throws_ok($$select public.propose_swap(
  '00000000-0000-0000-0000-000000003621',
  array['2027-11-03'::date], array['2027-11-04'::date])$$,
  'P2831', 'A Staff member cannot work the offered shift on 2027-11-03',
  'an RN and CNA Swap is refused at proposal');
select throws_ok($$select public.propose_swap(
  '00000000-0000-0000-0000-000000003620',
  array['2027-11-09'::date], array['2027-11-12'::date])$$,
  'P2831', 'A Staff member cannot work the offered shift on 2027-11-12',
  'the pickup rule is checked in the reverse direction too');
select throws_ok($$select public.propose_swap(
  '00000000-0000-0000-0000-000000003620',
  array['2027-11-16'::date], array['2027-11-17'::date])$$,
  'P2831', 'A Staff member cannot work the offered shift on 2027-11-16',
  'a Job role change mid-stretch is applied on the later date');

-- A pending Swap is not voided when Job roles change, but approval rechecks.
select public.propose_swap('00000000-0000-0000-0000-000000003620',
  array['2027-11-07'::date], array['2027-11-08'::date]);
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003613","role":"authenticated"}', true);
select public.answer_swap((select id from public.swaps where status = 'proposed'
  and exists (select 1 from public.swap_shifts where swap_id = swaps.id
    and work_date = '2027-11-07')), true);
reset role;
update public.staff_job_roles set effective_through = '2027-11-06'
where staff_member_id = '00000000-0000-0000-0000-000000003620'
  and job_role = 'lpn';
update public.staff_job_roles set effective_from = '2027-11-07'
where staff_member_id = '00000000-0000-0000-0000-000000003620'
  and job_role = 'cna';
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003611","role":"authenticated"}', true);
select throws_ok($$select public.approve_swap((select id from public.swaps
  where status = 'accepted'))$$,
  'P2831', 'A Staff member can no longer work one of the offered shifts',
  'approval refuses a pending Swap that no longer qualifies');
select is((select status::text from public.swaps where status = 'accepted'),
  'accepted', 'the pickup eligibility refusal does not void the pending Swap');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003612","role":"authenticated"}', true);
select throws_ok($$select public.propose_giveaway(
  '00000000-0000-0000-0000-000000003621', array['2027-11-05'::date])$$,
  'The colleague cannot take every selected shift',
  'Giveaways still apply the same pickup rule');

select * from finish();
rollback;
