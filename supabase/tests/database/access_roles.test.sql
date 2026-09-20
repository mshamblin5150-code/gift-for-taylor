begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000601', 'access-manager@example.test'),
  ('00000000-0000-0000-0000-000000000602', 'access-staff@example.test'),
  ('00000000-0000-0000-0000-000000000606', 'access-successor@example.test');
insert into public.sections (id, name, display_order) values
  ('00000000-0000-0000-0000-000000000603', 'Access test Section', 98);
insert into public.staff_members (id, display_name, role) values
  ('00000000-0000-0000-0000-000000000604', 'Access Manager', 'manager'),
  ('00000000-0000-0000-0000-000000000605', 'Access Staff', 'staff_member'),
  ('00000000-0000-0000-0000-000000000607', 'Access Successor', 'staff_member'),
  ('00000000-0000-0000-0000-000000000608', 'Departing Scheduler', 'staff_member');
insert into public.staff_accounts
  (staff_member_id, auth_user_id, personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000000604',
   '00000000-0000-0000-0000-000000000601', 'access-manager@example.test', now()),
  ('00000000-0000-0000-0000-000000000605',
   '00000000-0000-0000-0000-000000000602', 'access-staff@example.test', now()),
  ('00000000-0000-0000-0000-000000000607',
   '00000000-0000-0000-0000-000000000606', 'access-successor@example.test', now());

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000602","role":"authenticated"}', true);
select throws_ok($$select public.set_staff_access_role(
  '00000000-0000-0000-0000-000000000605', 'administrator')$$,
  'Only the Manager can change access roles', 'Staff member cannot change access');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000601","role":"authenticated"}', true);
select lives_ok($$select public.set_staff_access_role(
  '00000000-0000-0000-0000-000000000605', 'administrator')$$,
  'Manager promotes a Staff member');
select lives_ok($$select public.set_staff_access_role(
  '00000000-0000-0000-0000-000000000605', 'night_scheduler',
  array['00000000-0000-0000-0000-000000000603']::uuid[])$$,
  'Manager moves administrator directly to Night scheduler');
select is((select role::text from public.staff_members
  where id = '00000000-0000-0000-0000-000000000605'),
  'night_scheduler', 'recipient becomes Night scheduler');
select is((select count(*)::integer from public.night_scheduler_sections
  where staff_member_id = '00000000-0000-0000-0000-000000000605'),
  1, 'Night scheduler receives one Section');
select lives_ok($$select public.set_staff_access_role(
  '00000000-0000-0000-0000-000000000605', 'staff_member')$$,
  'Manager removes Night scheduler access');
select is((select count(*)::integer from public.night_scheduler_sections
  where staff_member_id = '00000000-0000-0000-0000-000000000605'),
  0, 'removing the role removes editable Sections');
select lives_ok($$select public.set_staff_access_role(
  '00000000-0000-0000-0000-000000000605', 'administrator')$$,
  'Manager restores administrator access');
select public.set_staff_last_day(
  '00000000-0000-0000-0000-000000000605', current_date);
select lives_ok($$select public.set_staff_access_role(
  '00000000-0000-0000-0000-000000000605', 'staff_member')$$,
  'Manager removes administrator access after Last day');
select is((select role::text from public.staff_members
  where id = '00000000-0000-0000-0000-000000000605'),
  'staff_member', 'departed administrator access is removed');
select results_eq($$select old_value, new_value from public.staff_changes
  where staff_member_id = '00000000-0000-0000-0000-000000000605'
    and kind = 'access_role' order by changed_at$$,
  $$values ('staff_member', 'administrator'),
    ('administrator', 'night_scheduler'),
    ('night_scheduler', 'staff_member'),
    ('staff_member', 'administrator'),
    ('administrator', 'staff_member')$$,
  'every access transition is recorded');

select lives_ok($$select public.set_staff_access_role(
  '00000000-0000-0000-0000-000000000608', 'night_scheduler',
  array['00000000-0000-0000-0000-000000000603']::uuid[])$$,
  'Manager assigns a departing Night scheduler');
select lives_ok($$select public.set_staff_last_day(
  '00000000-0000-0000-0000-000000000608', current_date)$$,
  'setting Last day removes Night scheduler access');
select results_eq($$select old_value, new_value from public.staff_changes
  where staff_member_id = '00000000-0000-0000-0000-000000000608'
    and kind = 'access_role' order by changed_at$$,
  $$values ('staff_member', 'night_scheduler'),
    ('night_scheduler', 'staff_member')$$,
  'automatic Night scheduler revocation is recorded once');

select lives_ok($$select public.set_staff_access_role(
  '00000000-0000-0000-0000-000000000607', 'night_scheduler',
  array['00000000-0000-0000-0000-000000000603']::uuid[])$$,
  'Manager gives successor Night scheduler access');
select lives_ok($$select public.set_staff_access_role(
  '00000000-0000-0000-0000-000000000607', 'manager')$$,
  'Manager transfers directly to Night scheduler');
select is((select role::text from public.staff_members
  where id = '00000000-0000-0000-0000-000000000607'),
  'manager', 'Night scheduler becomes Manager');
select results_eq($$select old_value, new_value from public.staff_changes
  where staff_member_id = '00000000-0000-0000-0000-000000000607'
    and kind = 'access_role' order by changed_at$$,
  $$values ('staff_member', 'night_scheduler'), ('night_scheduler', 'manager')$$,
  'Night scheduler transfer is recorded');

select * from finish();
rollback;
