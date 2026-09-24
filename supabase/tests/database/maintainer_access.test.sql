begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000002190', 'maintainer@example.test'),
  ('00000000-0000-0000-0000-000000002191', 'manager-304@example.test'),
  ('00000000-0000-0000-0000-000000002192', 'successor-304@example.test');
insert into public.staff_members(id, display_name, role) values
  ('00000000-0000-0000-0000-000000002193', 'Maintainer Nurse', 'staff_member'),
  ('00000000-0000-0000-0000-000000002194', 'Manager 304', 'manager'),
  ('00000000-0000-0000-0000-000000002195', 'Successor 304', 'staff_member');
insert into public.staff_accounts(staff_member_id, auth_user_id,
  personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000002193',
   '00000000-0000-0000-0000-000000002190', 'maintainer@example.test', now()),
  ('00000000-0000-0000-0000-000000002194',
   '00000000-0000-0000-0000-000000002191', 'manager-304@example.test', now()),
  ('00000000-0000-0000-0000-000000002195',
   '00000000-0000-0000-0000-000000002192', 'successor-304@example.test', now());
insert into private.maintainer_identity(auth_user_id)
values ('00000000-0000-0000-0000-000000002190');
insert into public.sections(id, name, display_order) values
  ('00000000-0000-0000-0000-000000002196', 'Section 304', 0);
insert into public.staff_section_assignments(staff_member_id, section_id,
  display_order, effective_from) values
  ('00000000-0000-0000-0000-000000002193',
   '00000000-0000-0000-0000-000000002196', 0, '2032-01-01'),
  ('00000000-0000-0000-0000-000000002195',
   '00000000-0000-0000-0000-000000002196', 1, '2032-01-01');
insert into public.schedule_months(month_start) values ('2032-01-01');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000002191","role":"authenticated"}', true);
select public.release_month_checked('2032-01-01', true);
reset role;

select is((select count(*)::integer from private.maintainer_identity), 1,
  'the database-only Maintainer binding remains a singleton');
select is((select count(*)::integer from public.staff_accounts
  where auth_user_id = '00000000-0000-0000-0000-000000002190'), 1,
  'the Maintainer Auth user can also hold a Staff account');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000002190","role":"authenticated"}', true);
select is(public.current_access_role(), 'maintainer',
  'the hat remains visible to the client outside a Repair');
select is(public.current_staff_role()::text, 'staff_member',
  'the hat alone gives only the linked Staff authority');
select is(public.current_staff_member_id(),
  '00000000-0000-0000-0000-000000002193'::uuid,
  'the human is the linked Staff member');
select is((select count(*)::integer from public.staff_list_entries
  where id = '00000000-0000-0000-0000-000000002193'), 1,
  'the human appears on the Staff list');
select is((select count(*)::integer from public.schedule_rows('2032-01-01')
  where staff_member_id = '00000000-0000-0000-0000-000000002193'), 1,
  'the human appears on the Schedule through the Staff row');
select ok(not public.can_manage_staff(),
  'Manager controls are unavailable without a Repair');
select ok(not public.can_edit_schedule(),
  'Schedule repair authority is unavailable without a Repair');

select throws_ok($$select public.open_maintainer_repair(
  'something_else', null)$$,
  'Something else requires repair detail (3-240 characters)',
  'Something else cannot hide an unspecified reason');
select throws_ok($$select public.open_maintainer_repair(
  'unit_settings', 'x')$$,
  'Repair detail must be 3-240 characters',
  'short optional detail is refused');
select lives_ok($$select public.open_maintainer_repair(
  'unit_settings', 'Correct the unit print heading')$$,
  'the Maintainer can break the glass without a request header');
select is(public.current_staff_role()::text, 'manager',
  'an open Repair grants Manager authority');
select ok(public.can_manage_staff(), 'an open Repair enables Staff management');
select ok(public.can_edit_schedule(), 'an open Repair enables Schedule repair');
select is((select reason_category::text from public.current_maintainer_repair()),
  'unit_settings', 'the open Repair exposes its reason category');
set local role postgres;
select is((select count(*)::integer from public.staff_notices
  where kind = 'maintainer_repair'), 1,
  'opening a Repair raises exactly one Notice');
select is((select staff_member_id from public.staff_notices
  where kind = 'maintainer_repair'),
  '00000000-0000-0000-0000-000000002194'::uuid,
  'the Repair Notice goes to the current Manager');
select is((select title from public.staff_notices
  where kind = 'maintainer_repair'),
  'Repair: Unit settings', 'the Repair Notice names its category');
select is((select body from public.staff_notices
  where kind = 'maintainer_repair'),
  'Correct the unit print heading',
  'the Repair Notice carries the Maintainer detail');
select ok(not (select push_eligible from public.staff_notices
  where kind = 'maintainer_repair'), 'the Repair Notice does not push');
set local role authenticated;

select lives_ok($$select public.set_print_wording(
  'Print', 'Repair title', '')$$,
  'a Repair authorises a Unit write with no request header');
select is((select actor_id from public.unit_setting_audit
  where kind = 'Print wording' order by id desc limit 1),
  '00000000-0000-0000-0000-000000002193'::uuid,
  'Settings history names the human Staff member');
select is((select actor_auth_user_id from public.unit_setting_audit
  where kind = 'Print wording' order by id desc limit 1),
  '00000000-0000-0000-0000-000000002190'::uuid,
  'Settings history names the Maintainer hat');
select is((select repair_id from public.unit_setting_audit
  where kind = 'Print wording' order by id desc limit 1),
  (select id from public.current_maintainer_repair()),
  'Settings history references the authorising Repair');
select is((select actor_staff_member_id from public.maintainer_repair_audit
  where relation_name = 'print_wording' order by id desc limit 1),
  '00000000-0000-0000-0000-000000002193'::uuid,
  'Repair history names the human Staff member');
select is((select actor_auth_user_id from public.maintainer_repair_audit
  where relation_name = 'print_wording' order by id desc limit 1),
  '00000000-0000-0000-0000-000000002190'::uuid,
  'Repair history names the Maintainer hat');
select is((select repair_id from public.maintainer_repair_audit
  where relation_name = 'print_wording' order by id desc limit 1),
  (select id from public.current_maintainer_repair()),
  'Repair history references the authorising Repair');

select lives_ok($$select public.close_maintainer_repair()$$,
  'the Repair can be closed mid-session');
select is(public.current_staff_role()::text, 'staff_member',
  'closing the Repair immediately ends Manager authority');
select ok(not public.can_manage_unit(),
  'closed Repair controls disappear without signing in again');

select public.open_maintainer_repair('investigation', null);
set local role postgres;
with instant as (select clock_timestamp() as value)
update public.maintainer_repairs
set opened_at = instant.value - interval '2 hours',
  expires_at = instant.value - interval '1 hour'
from instant
where auth_user_id = '00000000-0000-0000-0000-000000002190'
  and closed_at is null;
set local role authenticated;
select is(public.current_staff_role()::text, 'staff_member',
  'the one-hour cap ends authority for a Repair left open');

select lives_ok($$select public.open_maintainer_repair(
  'manager_handover', null)$$,
  'an expired Repair does not block a new Repair');
select lives_ok($$select public.transfer_manager_with_access(
  '00000000-0000-0000-0000-000000002195', false, '{}'::uuid[])$$,
  'a Maintainer performs Manager transfer end to end without a header');
select is((select role::text from public.staff_members
  where id = '00000000-0000-0000-0000-000000002194'),
  'staff_member', 'the former Manager becomes a Staff member');
select is((select role::text from public.staff_members
  where id = '00000000-0000-0000-0000-000000002195'),
  'manager', 'the successor becomes Manager');
select is((select actor_staff_member_id from public.maintainer_repair_audit
  where relation_name = 'staff_members' order by id desc limit 1),
  '00000000-0000-0000-0000-000000002193'::uuid,
  'handover Repair history names the human');
select is((select repair_id from public.maintainer_repair_audit
  where relation_name = 'staff_members' order by id desc limit 1),
  (select id from public.current_maintainer_repair()),
  'handover Repair history names its authorising Repair');

select public.close_maintainer_repair();
set local role postgres;
update private.maintainer_identity
set auth_user_id = '00000000-0000-0000-0000-000000002192';
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000002192","role":"authenticated"}', true);
select public.open_maintainer_repair('investigation', 'Check the handover result');
select is((select count(*)::integer from public.staff_notices
  where kind = 'maintainer_repair'
    and staff_member_id = '00000000-0000-0000-0000-000000002195'), 0,
  'a Maintainer who is the Manager does not receive a self-notice');

select throws_ok($$update private.maintainer_identity
  set auth_user_id = '00000000-0000-0000-0000-000000002192'$$,
  'permission denied for schema private',
  'app roles still cannot replace the Maintainer binding');

select * from finish();
rollback;
