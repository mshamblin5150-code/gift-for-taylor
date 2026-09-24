begin;
create extension if not exists pgtap with schema extensions;
select plan(23);

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000003061', 'manager-306@example.test'),
  ('00000000-0000-0000-0000-000000003062', 'eligible-306@example.test'),
  ('00000000-0000-0000-0000-000000003063', 'pending-306@example.test'),
  ('00000000-0000-0000-0000-000000003064', 'revoked-306@example.test'),
  ('00000000-0000-0000-0000-000000003065', 'inactive-306@example.test'),
  ('00000000-0000-0000-0000-000000003066', 'unassigned-306@example.test'),
  ('00000000-0000-0000-0000-000000003067', 'maintainer-306@example.test');
insert into public.sections(id, name, display_order) values
  ('00000000-0000-0000-0000-000000003070', 'Handover days', 306),
  ('00000000-0000-0000-0000-000000003071', 'Handover nights', 307);
insert into public.staff_members(id, display_name, role, active) values
  ('00000000-0000-0000-0000-000000003080', 'Current Manager', 'manager', true),
  ('00000000-0000-0000-0000-000000003081', 'Ready Riley', 'administrator', true),
  ('00000000-0000-0000-0000-000000003082', 'Pending Parker', 'staff_member', true),
  ('00000000-0000-0000-0000-000000003083', 'Revoked Reese', 'staff_member', true),
  ('00000000-0000-0000-0000-000000003084', 'Inactive Indy', 'staff_member', false),
  ('00000000-0000-0000-0000-000000003085', 'Uninvited Uma', 'staff_member', true),
  ('00000000-0000-0000-0000-000000003086', 'Unassigned Uri', 'staff_member', true),
  ('00000000-0000-0000-0000-000000003087', 'Maintainer Morgan', 'staff_member', true);
insert into public.staff_section_assignments(
  staff_member_id, section_id, display_order, effective_from) values
  ('00000000-0000-0000-0000-000000003080',
   '00000000-0000-0000-0000-000000003070', 0, current_date),
  ('00000000-0000-0000-0000-000000003081',
   '00000000-0000-0000-0000-000000003070', 1, current_date),
  ('00000000-0000-0000-0000-000000003082',
   '00000000-0000-0000-0000-000000003070', 2, current_date),
  ('00000000-0000-0000-0000-000000003083',
   '00000000-0000-0000-0000-000000003070', 3, current_date),
  ('00000000-0000-0000-0000-000000003084',
   '00000000-0000-0000-0000-000000003070', 4, current_date),
  ('00000000-0000-0000-0000-000000003085',
   '00000000-0000-0000-0000-000000003070', 5, current_date),
  ('00000000-0000-0000-0000-000000003087',
   '00000000-0000-0000-0000-000000003070', 6, current_date);
insert into public.staff_accounts(
  staff_member_id, auth_user_id, personal_email, accepted_invite_at, revoked_at)
values
  ('00000000-0000-0000-0000-000000003080',
   '00000000-0000-0000-0000-000000003061', 'manager-306@example.test', now(), null),
  ('00000000-0000-0000-0000-000000003081',
   '00000000-0000-0000-0000-000000003062', 'eligible-306@example.test', now(), null),
  ('00000000-0000-0000-0000-000000003083',
   '00000000-0000-0000-0000-000000003064', 'revoked-306@example.test', now(), now()),
  ('00000000-0000-0000-0000-000000003084',
   '00000000-0000-0000-0000-000000003065', 'inactive-306@example.test', now(), null),
  ('00000000-0000-0000-0000-000000003086',
   '00000000-0000-0000-0000-000000003066', 'unassigned-306@example.test', now(), null),
  ('00000000-0000-0000-0000-000000003087',
   '00000000-0000-0000-0000-000000003067', 'maintainer-306@example.test', now(), null);
insert into private.maintainer_identity(auth_user_id)
values ('00000000-0000-0000-0000-000000003067');
insert into public.invites(id, staff_member_id, token_hash, accepted_at)
values ('00000000-0000-0000-0000-000000003090',
  '00000000-0000-0000-0000-000000003082',
  extensions.digest(convert_to('pending-306', 'UTF8'), 'sha256'), now());
insert into public.pending_invite_acceptances(
  invite_id, staff_member_id, auth_user_id, personal_email)
values ('00000000-0000-0000-0000-000000003090',
  '00000000-0000-0000-0000-000000003082',
  '00000000-0000-0000-0000-000000003063', 'pending-306@example.test');
insert into public.night_scheduler_sections(staff_member_id, section_id)
values ('00000000-0000-0000-0000-000000003081',
  '00000000-0000-0000-0000-000000003071');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003061","role":"authenticated"}', true);

select is((select eligibility_code::text from public.manager_handover_candidates()
  where staff_member_id = '00000000-0000-0000-0000-000000003080'),
  'already_manager', 'the incumbent is distinguishable from a successor');
select is((select eligibility_code::text from public.manager_handover_candidates()
  where staff_member_id = '00000000-0000-0000-0000-000000003081'),
  null, 'an active confirmed Staff member with a Section is eligible');
select is((select eligibility_code::text from public.manager_handover_candidates()
  where staff_member_id = '00000000-0000-0000-0000-000000003082'),
  'invite_acceptance_pending', 'accepted but unconfirmed is named distinctly');
select is((select eligibility_code::text from public.manager_handover_candidates()
  where staff_member_id = '00000000-0000-0000-0000-000000003083'),
  'account_revoked', 'a revoked account is named distinctly');
select is((select eligibility_code::text from public.manager_handover_candidates()
  where staff_member_id = '00000000-0000-0000-0000-000000003084'),
  'inactive', 'an inactive Staff member is named distinctly');
select is((select eligibility_code::text from public.manager_handover_candidates()
  where staff_member_id = '00000000-0000-0000-0000-000000003085'),
  'no_staff_account', 'a Staff member with no account is named distinctly');
select is((select eligibility_code::text from public.manager_handover_candidates()
  where staff_member_id = '00000000-0000-0000-0000-000000003086'),
  'no_current_section', 'a Staff member without a current Section remains visible');
select throws_ok($$select public.transfer_manager_with_access(
  '00000000-0000-0000-0000-000000003086', false, '{}'::uuid[])$$,
  'P2806', 'Manager successor is not eligible: no_current_section',
  'a successor without a current Section receives a distinct refusal code');
select lives_ok($$select public.change_staff_section(
  '00000000-0000-0000-0000-000000003086',
  '00000000-0000-0000-0000-000000003070', current_date)$$,
  'the Manager can assign the missing current Section from Staff details');
select is((select eligibility_code::text from public.manager_handover_candidates()
  where staff_member_id = '00000000-0000-0000-0000-000000003086'),
  null, 'assigning the missing Section makes the successor eligible');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003062","role":"authenticated"}', true);
select lives_ok($$select * from public.manager_handover_candidates()$$,
  'an Administrator can read readiness while managing Staff details');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003061","role":"authenticated"}', true);

select throws_ok($$select public.transfer_manager_with_access(
  '00000000-0000-0000-0000-000000003080', false, '{}'::uuid[])$$,
  'P2799', 'Choose another Staff member as Manager',
  'self-transfer receives a distinct refusal code');
select throws_ok($$select public.transfer_manager_with_access(
  '00000000-0000-0000-0000-000000003081', false,
  array['00000000-0000-0000-0000-000000003099']::uuid[])$$,
  'P2800', 'Section not found',
  'a missing retained Section receives a distinct refusal code');
select throws_ok($$select public.transfer_manager_with_access(
  '00000000-0000-0000-0000-000000003085', false, '{}'::uuid[])$$,
  'P2801', 'Manager successor is not eligible: no_staff_account',
  'a successor without an account receives a distinct refusal code');
select throws_ok($$select public.transfer_manager_with_access(
  '00000000-0000-0000-0000-000000003082', false, '{}'::uuid[])$$,
  'P2802', 'Manager successor is not eligible: invite_acceptance_pending',
  'the transfer enforces the same pending-acceptance answer');
select throws_ok($$select public.transfer_manager_with_access(
  '00000000-0000-0000-0000-000000003083', false, '{}'::uuid[])$$,
  'P2803', 'Manager successor is not eligible: account_revoked',
  'a successor with a revoked account receives a distinct refusal code');
select throws_ok($$select public.transfer_manager_with_access(
  '00000000-0000-0000-0000-000000003084', false, '{}'::uuid[])$$,
  'P2804', 'Manager successor is not eligible: inactive',
  'an inactive successor receives a distinct refusal code');
select ok(
  pg_get_functiondef(
    'public.transfer_manager_with_access(uuid,boolean,uuid[])'::regprocedure)
      like '%P2805%',
  'the defensive already-Manager refusal keeps its stable code');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003062","role":"authenticated"}', true);
select throws_ok($$select public.transfer_manager_with_access(
  '00000000-0000-0000-0000-000000003082', false, '{}'::uuid[])$$,
  'P2797', 'Only the Manager can transfer the Manager role',
  'a caller without Manager access receives a distinct refusal code');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003061","role":"authenticated"}', true);
select lives_ok($$select public.transfer_manager_with_access(
  '00000000-0000-0000-0000-000000003081', true,
  array['00000000-0000-0000-0000-000000003071']::uuid[])$$,
  'a successor holding Administrator and Night scheduler grants can take over');
select is((select role::text from public.staff_members
  where id = '00000000-0000-0000-0000-000000003081'),
  'manager', 'the eligible successor becomes Manager atomically');
select results_eq($$select role::text,
    exists(select 1 from public.night_scheduler_sections section
      where section.staff_member_id = member.id
        and section.section_id = '00000000-0000-0000-0000-000000003071')
  from public.staff_members member
  where member.id = '00000000-0000-0000-0000-000000003080'$$,
  $$values ('administrator', true)$$,
  'the outgoing Manager keeps both selected grants');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003067","role":"authenticated"}', true);
select public.open_maintainer_repair('manager_handover', null);
set local role postgres;
alter table public.staff_members disable trigger keep_active_manager;
update public.staff_members set role = 'staff_member'
where role = 'manager' and active;
alter table public.staff_members enable trigger keep_active_manager;
set local role authenticated;
select throws_ok($$select public.transfer_manager_with_access(
  '00000000-0000-0000-0000-000000003085', false, '{}'::uuid[])$$,
  'P2798', 'Manager transfer cannot continue: no active Manager',
  'a missing active Manager refuses before any handover write');

select * from finish();
rollback;
