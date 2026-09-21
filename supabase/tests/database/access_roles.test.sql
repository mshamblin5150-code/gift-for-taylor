begin;
create extension if not exists pgtap with schema extensions;
select plan(30);
insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000000601', 'access-manager@example.test'),
  ('00000000-0000-0000-0000-000000000602', 'access-admin@example.test'),
  ('00000000-0000-0000-0000-000000000606', 'access-successor@example.test');
insert into public.sections(id, name, display_order) values
  ('00000000-0000-0000-0000-000000000603', 'Access test Section', 98),
  ('00000000-0000-0000-0000-000000000609', 'Other Section', 99);
insert into public.staff_members(id, display_name, role) values
  ('00000000-0000-0000-0000-000000000604', 'Access Manager', 'manager'),
  ('00000000-0000-0000-0000-000000000605', 'Access Staff', 'staff_member'),
  ('00000000-0000-0000-0000-000000000607', 'Access Successor', 'staff_member');
insert into public.staff_accounts
  (staff_member_id, auth_user_id, personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000000604',
   '00000000-0000-0000-0000-000000000601', 'access-manager@example.test', now()),
  ('00000000-0000-0000-0000-000000000605',
   '00000000-0000-0000-0000-000000000602', 'access-admin@example.test', now()),
  ('00000000-0000-0000-0000-000000000607',
   '00000000-0000-0000-0000-000000000606', 'access-successor@example.test', now());
insert into public.schedule_months(month_start) values ('2031-05-01');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000602","role":"authenticated"}', true);
select throws_ok($$select public.set_staff_access_grants(
  '00000000-0000-0000-0000-000000000607', true, '{}'::uuid[])$$,
  'Only the Manager or Administrator can change Staff access',
  'Staff cannot grant access');
select is((select count(*)::integer from public.schedule_months
  where month_start = '2031-05-01'), 0,
  'ordinary Staff cannot read an unpublished Schedule');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000601","role":"authenticated"}', true);
select lives_ok($$select public.set_staff_access_grants(
  '00000000-0000-0000-0000-000000000605', true,
  array['00000000-0000-0000-0000-000000000603']::uuid[])$$,
  'Manager grants Administrator and Night scheduler together');
select is((select role::text from public.staff_members
  where id = '00000000-0000-0000-0000-000000000605'),
  'administrator', 'combined recipient retains Administrator');
select lives_ok($$select public.remove_administrator(
  '00000000-0000-0000-0000-000000000605')$$,
  'removing Administrator preserves Night scheduler');
select is((select role::text from public.staff_members
  where id = '00000000-0000-0000-0000-000000000605'),
  'night_scheduler', 'Night scheduler remains');
select lives_ok($$select public.assign_administrator(
  '00000000-0000-0000-0000-000000000605')$$,
  'older Administrator RPC retains Sections');
select lives_ok($$select public.remove_night_scheduler(
  '00000000-0000-0000-0000-000000000605')$$,
  'removing Night scheduler retains Administrator');
select is((select role::text from public.staff_members
  where id = '00000000-0000-0000-0000-000000000605'),
  'administrator', 'Administrator remains');
select results_eq($$select old_value, new_value from public.staff_changes
  where staff_member_id = '00000000-0000-0000-0000-000000000605'
    and kind = 'access_role' order by changed_at, id$$,
  $$values ('staff_member', 'administrator + night_scheduler (Access test Section)'),
    ('administrator + night_scheduler (Access test Section)',
      'night_scheduler (Access test Section)'),
    ('night_scheduler (Access test Section)',
      'administrator + night_scheduler (Access test Section)'),
    ('administrator + night_scheduler (Access test Section)', 'administrator')$$,
  'grant changes retain an accurate history');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000602","role":"authenticated"}', true);
select is(public.can_edit_section('00000000-0000-0000-0000-000000000603'),
  false, 'Administrator alone cannot edit Schedule cells');
select is(public.can_edit_schedule(), false,
  'Administrator cannot make Manager Schedule decisions');
select is(public.can_read_change_log(), true,
  'Administrator can read the Change log');
select is((select count(*)::integer from public.schedule_months
  where month_start = '2031-05-01'), 1,
  'Administrator can read an unpublished Schedule');
select throws_ok($$select public.release_month('2031-05-01')$$,
  'Only the Manager can release a month',
  'Administrator cannot release the month');
select throws_ok($$select public.decide_request_off(
  '00000000-0000-0000-0000-000000000699', 'approved', null)$$,
  'Only the Manager can decide Requests off',
  'Administrator cannot make Manager approval decisions');
select throws_ok($$select public.set_staff_access_grants(
  '00000000-0000-0000-0000-000000000605', false, '{}'::uuid[])$$,
  'Choose another Staff member', 'Administrator cannot remove own authority');
select lives_ok($$select public.set_staff_access_grants(
  '00000000-0000-0000-0000-000000000607', true,
  array['00000000-0000-0000-0000-000000000603']::uuid[])$$,
  'Administrator grants both to another Staff member');
select throws_ok($$select public.transfer_manager(
  '00000000-0000-0000-0000-000000000607')$$,
  'Only the Manager can transfer the Manager role',
  'Administrator cannot transfer Manager');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000606","role":"authenticated"}', true);
select is(public.can_edit_section('00000000-0000-0000-0000-000000000603'),
  true, 'combined grant edits assigned Section');
select is(public.can_edit_section('00000000-0000-0000-0000-000000000609'),
  false, 'combined grant cannot edit another Section');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000602","role":"authenticated"}', true);
select lives_ok($$select public.set_staff_access_grants(
  '00000000-0000-0000-0000-000000000607', true,
  array['00000000-0000-0000-0000-000000000603',
    '00000000-0000-0000-0000-000000000609']::uuid[])$$,
  'Administrator changes only assigned Night scheduler Sections');
select is((select count(*)::integer from public.staff_changes
  where staff_member_id = '00000000-0000-0000-0000-000000000607'
    and kind = 'access_role'
    and old_value = 'administrator + night_scheduler (Access test Section)'
    and new_value = 'administrator + night_scheduler (Access test Section, Other Section)'),
  1, 'Section-only change appears in Staff access history');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000601","role":"authenticated"}', true);
select lives_ok($$select public.transfer_manager(
  '00000000-0000-0000-0000-000000000607')$$,
  'old handover RPC defaults former Manager to Staff member');
select is((select role::text from public.staff_members
  where id = '00000000-0000-0000-0000-000000000604'),
  'staff_member', 'former Manager is ordinary Staff member');
select is((select count(*)::integer from public.night_scheduler_sections
  where staff_member_id = '00000000-0000-0000-0000-000000000607'),
  0, 'successor has no inherited Night scheduler grant');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000606","role":"authenticated"}', true);
select is((select count(*)::integer from public.staff_changes
  where staff_member_id = '00000000-0000-0000-0000-000000000607'
    and kind = 'access_role'
    and old_value = 'administrator + night_scheduler (Access test Section, Other Section)'
    and new_value = 'manager'), 1,
  'incoming Manager history records both prior grants');
select lives_ok($$select public.transfer_manager_with_access(
  '00000000-0000-0000-0000-000000000604', true,
  array['00000000-0000-0000-0000-000000000603']::uuid[])$$,
  'explicit handover chooses both grants for the former Manager');
select is((select role::text from public.staff_members
  where id = '00000000-0000-0000-0000-000000000607'),
  'administrator', 'former Manager receives chosen Administrator access');
select is(public.can_edit_section('00000000-0000-0000-0000-000000000603'),
  true, 'former Manager receives chosen Night scheduler Section');
select * from finish();
rollback;
