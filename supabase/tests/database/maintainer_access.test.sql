begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000002190', 'maintainer@example.test'),
  ('00000000-0000-0000-0000-000000002191', 'manager-219@example.test'),
  ('00000000-0000-0000-0000-000000002192', 'successor-219@example.test'),
  ('00000000-0000-0000-0000-000000002193', 'replacement-219@example.test');
insert into public.staff_members(id, display_name, role) values
  ('00000000-0000-0000-0000-000000002194', 'Manager 219', 'manager'),
  ('00000000-0000-0000-0000-000000002195', 'Successor 219', 'staff_member');
insert into public.staff_accounts(staff_member_id, auth_user_id,
  personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000002194',
   '00000000-0000-0000-0000-000000002191', 'manager-219@example.test', now()),
  ('00000000-0000-0000-0000-000000002195',
   '00000000-0000-0000-0000-000000002192', 'successor-219@example.test', now());
insert into private.maintainer_identity(auth_user_id)
values ('00000000-0000-0000-0000-000000002190');
insert into public.schedule_months(month_start) values ('2032-01-01');
insert into public.sections(id, name, display_order) values
  ('00000000-0000-0000-0000-000000002196', 'Section 219', 0);
insert into public.staff_section_assignments(staff_member_id, section_id,
  display_order, effective_from) values
  ('00000000-0000-0000-0000-000000002195',
   '00000000-0000-0000-0000-000000002196', 0, '2032-01-01');

select is((select count(*)::integer from private.maintainer_identity), 1,
  'only one external Auth binding exists');
select is((select count(*)::integer from public.staff_accounts
  where auth_user_id = '00000000-0000-0000-0000-000000002190'), 0,
  'Maintainer has no Staff account');
select throws_ok($$insert into public.staff_accounts(staff_member_id,
  auth_user_id, personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000002195',
   '00000000-0000-0000-0000-000000002190', 'maintainer@example.test', now())$$,
  'Maintainer Auth user cannot have a Staff account',
  'Staff Invite path cannot link the Maintainer identity');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000002190","role":"authenticated"}', true);
select is(public.current_access_role(), 'maintainer',
  'Maintainer identity is distinct in the client');
select is(public.current_staff_role()::text, 'manager',
  'Manager capability is available independently of Staff');
select is(public.current_staff_member_id(), null::uuid,
  'Maintainer is never attributed to a Staff member');
select ok(exists (select 1 from public.sections
  where id = '00000000-0000-0000-0000-000000002196'),
  'Maintainer can enter the app through the Sections read');
select is((select count(*)::integer from public.staff_members), 2,
  'Maintainer can read Staff members without a Staff account');
select is((select count(*)::integer from public.staff_list_entries), 1,
  'Maintainer can see an assigned successor in the handover picker');
select ok(public.can_manage_staff(), 'Maintainer can use Staff management');
select ok(public.can_edit_schedule(), 'Maintainer can edit the Schedule');
select ok(public.can_manage_unit(), 'Maintainer can use Unit Settings');
select throws_ok($$select public.set_print_wording('Print', 'Repair title', '')$$,
  'Maintainer changes require a repair reason (3-240 characters)',
  'Unit write without a reason is refused');
select set_config('request.headers',
  '{"x-repair-reason":"Correct the unit print heading"}', true);
select lives_ok($$select public.set_print_wording('Print', 'Repair title', '')$$,
  'Unit repair with a reason succeeds');
select is((select actor_auth_user_id from public.unit_setting_audit
  where kind = 'Print wording' order by id desc limit 1),
  '00000000-0000-0000-0000-000000002190'::uuid,
  'Settings audit records Maintainer Auth actor');
select is((select repair_reason from public.unit_setting_audit
  where kind = 'Print wording' order by id desc limit 1),
  'Correct the unit print heading', 'Settings audit includes repair reason');
select is((select repair_reason from public.maintainer_repair_audit
  where relation_name = 'print_wording' order by id desc limit 1),
  'Correct the unit print heading', 'Unit repair audit includes the change');
select is((select count(*)::integer from public.coverage_pools), 3,
  'Maintainer can read the Coverage pools Settings view');
select lives_ok($$select public.commit_coverage_date_rule(
  'cna', 'day', '2032-03-01', 1, null::public.job_role, 0,
  '[]'::jsonb, '[]'::jsonb)$$,
  'Maintainer can save an effective-dated Coverage rule');
select is((select actor_auth_user_id from public.coverage_rule_audit
  where action = 'date_minimum' order by changed_at desc limit 1),
  '00000000-0000-0000-0000-000000002190'::uuid,
  'Coverage rule history attributes Maintainer Auth identity');
select is((select repair_reason from public.unit_setting_audit
  where kind = 'Date Staffing minimum' order by id desc limit 1),
  'Correct the unit print heading',
  'Coverage rule Unit audit includes Maintainer repair reason');
select lives_ok($$select public.release_month_checked('2032-01-01', true)$$,
  'Maintainer can use Manager month release');
select is((select released_by_auth_user_id from public.schedule_months
  where month_start = '2032-01-01'),
  '00000000-0000-0000-0000-000000002190'::uuid,
  'month release attributes Maintainer, not Manager');
set local role postgres;
select is((select count(*)::integer from public.staff_notices
  where kind = 'month_release' and month_start = '2032-01-01'
    and staff_member_id = '00000000-0000-0000-0000-000000002195'), 1,
  'Maintainer month release notifies Staff');
set local role authenticated;
select lives_ok($$select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000002195',
  '00000000-0000-0000-0000-000000002196', '2032-02-01', '7A')$$,
  'Maintainer can save a Schedule cell');
select is((select changed_by_auth_user_id from public.schedule_changes
  where work_date = '2032-02-01' order by changed_at desc limit 1),
  '00000000-0000-0000-0000-000000002190'::uuid,
  'Schedule change attributes Maintainer under Auth identity');
select lives_ok($$select public.release_month_checked('2032-02-01', true)$$,
  'Maintainer can release a month with Schedule cells');
select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000002195',
  '00000000-0000-0000-0000-000000002196', '2032-02-02', '7A');
select public.mark_changes_announced(
  array(select id from public.schedule_changes
    where work_date = '2032-02-02'), '{}'::uuid[]);
set local role postgres;
select is((select count(*)::integer from public.staff_notices
  where kind = 'schedule_change' and month_start = '2032-02-01'
    and staff_member_id = '00000000-0000-0000-0000-000000002195'), 1,
  'Maintainer Change announcement notifies affected Staff');
set local role authenticated;
select lives_ok($$select public.transfer_manager(
  '00000000-0000-0000-0000-000000002195')$$,
  'Maintainer can repair Manager handover');
select is((select role::text from public.staff_members
  where id = '00000000-0000-0000-0000-000000002194'),
  'staff_member', 'former Manager defaults to Staff member');
select is((select role::text from public.staff_members
  where id = '00000000-0000-0000-0000-000000002195'),
  'manager', 'successor becomes Manager');
select is((select changed_by_auth_user_id from public.staff_changes
  where kind = 'access_role' order by changed_at desc limit 1),
  '00000000-0000-0000-0000-000000002190'::uuid,
  'Staff history attributes Maintainer without synthetic Staff actor');
select is(public.current_access_role(), 'maintainer',
  'Manager handover does not revoke Maintainer access');
select throws_ok($$update private.maintainer_identity
  set auth_user_id = '00000000-0000-0000-0000-000000002193'$$,
  'permission denied for schema private',
  'app roles cannot replace Maintainer identity');

reset role;
update private.maintainer_identity
set auth_user_id = '00000000-0000-0000-0000-000000002193';
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000002190","role":"authenticated"}', true);
select is(public.current_access_role(), null::text,
  'old Auth credentials lose access after external replacement');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000002193","role":"authenticated"}', true);
select is(public.current_access_role(), 'maintainer',
  'replacement Auth credentials receive Maintainer access');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000002191","role":"authenticated"}', true);
select is(public.current_access_role(), 'staff_member',
  'former Manager does not retain Manager capability');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000002192","role":"authenticated"}', true);
select lives_ok($$select public.set_staff_access_role(
  '00000000-0000-0000-0000-000000002194', 'manager')$$,
  'ordinary Staff-screen handover works');
select is((select role::text from public.staff_members
  where id = '00000000-0000-0000-0000-000000002195'),
  'staff_member', 'ordinary handover also defaults former Manager to Staff');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000002193","role":"authenticated"}', true);
select lives_ok($$select public.transfer_manager_with_access(
  '00000000-0000-0000-0000-000000002195', true,
  array['00000000-0000-0000-0000-000000002196']::uuid[])$$,
  'Maintainer can choose explicit grants for the former Manager');
select is((select role::text from public.staff_members
  where id = '00000000-0000-0000-0000-000000002194'),
  'administrator', 'Maintainer handover preserves chosen Administrator grant');
select is((select count(*)::integer from public.night_scheduler_sections
  where staff_member_id = '00000000-0000-0000-0000-000000002194'
    and section_id = '00000000-0000-0000-0000-000000002196'), 1,
  'Maintainer handover preserves chosen Night scheduler Section');

select * from finish();
rollback;
