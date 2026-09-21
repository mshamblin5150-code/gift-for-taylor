begin;

create extension if not exists pgtap with schema extensions;
select plan(15);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000481', 'sections-manager@example.test'),
  ('00000000-0000-0000-0000-000000000482', 'sections-admin@example.test'),
  ('00000000-0000-0000-0000-000000000483', 'sections-staff@example.test');

insert into public.staff_members (id, display_name, role) values
  ('00000000-0000-0000-0000-000000000484', 'Sections Manager', 'manager'),
  ('00000000-0000-0000-0000-000000000485', 'Sections Administrator', 'administrator'),
  ('00000000-0000-0000-0000-000000000486', 'Sections Staff', 'staff_member');

insert into public.staff_accounts (staff_member_id, auth_user_id, personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000000484', '00000000-0000-0000-0000-000000000481', 'sections-manager@example.test', now()),
  ('00000000-0000-0000-0000-000000000485', '00000000-0000-0000-0000-000000000482', 'sections-admin@example.test', now()),
  ('00000000-0000-0000-0000-000000000486', '00000000-0000-0000-0000-000000000483', 'sections-staff@example.test', now());

insert into public.sections (id, name, display_order) values
  ('00000000-0000-0000-0000-000000000487', 'Sections day', 0),
  ('00000000-0000-0000-0000-000000000488', 'Sections night', 1);

insert into public.staff_section_assignments (staff_member_id, section_id, display_order, effective_from) values
  ('00000000-0000-0000-0000-000000000486', '00000000-0000-0000-0000-000000000487', 0, current_date);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000481","role":"authenticated"}', true);

select ok(public.can_manage_sections(), 'Manager may manage Sections');
select lives_ok($$select public.reorder_sections(array(
  select id from public.sections
  order by case id
    when '00000000-0000-0000-0000-000000000488' then 0
    when '00000000-0000-0000-0000-000000000487' then 1
    else 2 end, display_order, id
))$$, 'Manager may reorder all Sections');
select is((select display_order from public.sections where id = '00000000-0000-0000-0000-000000000488'), 0, 'new order persists for grid and print queries');
select throws_ok($$select public.reorder_sections(array['00000000-0000-0000-0000-000000000488'::uuid])$$, 'The reorder must include every Section exactly once', 'partial order is rejected');
select throws_ok($$select public.reorder_sections(array(
  select '00000000-0000-0000-0000-000000000488'::uuid from public.sections
))$$, 'The reorder must include every Section exactly once', 'duplicate Section is rejected');
select lives_ok($$select public.rename_section('00000000-0000-0000-0000-000000000488', ' Sections renamed ')$$, 'Manager renames a Section');
select is((select name from public.sections where id = '00000000-0000-0000-0000-000000000488'), 'Sections renamed', 'Section name is trimmed and persists');
select throws_ok($$select public.delete_empty_section('00000000-0000-0000-0000-000000000487')$$, 'P2795', 'A Section with Staff members cannot be deleted', 'occupied Section is protected');
select lives_ok($$select public.delete_empty_section('00000000-0000-0000-0000-000000000488')$$, 'empty Section can be deleted');
select lives_ok($$select public.add_section('Sections clerks')$$, 'Manager can add a Section');
select is((select count(*)::integer from public.sections where name = 'Sections clerks'), 1, 'new Section is visible in the shared Section query');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000482","role":"authenticated"}', true);
select lives_ok($$select public.add_section('Administrator Section')$$, 'Administrator can manage Sections');
select lives_ok($$select public.rename_section('00000000-0000-0000-0000-000000000487', 'Administrator renamed')$$, 'Administrator can rename a Section');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000483","role":"authenticated"}', true);
select throws_ok($$select public.reorder_sections(array[]::uuid[])$$, 'Only the Manager can manage Sections', 'Staff cannot reorder Sections');
select throws_ok($$select public.delete_empty_section('00000000-0000-0000-0000-000000000487')$$, 'Only the Manager can manage Sections', 'Staff cannot delete Sections');

select * from finish();
rollback;
