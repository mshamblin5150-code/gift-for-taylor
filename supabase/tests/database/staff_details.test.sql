begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

insert into auth.users (id, email) values
 ('00000000-0000-0000-0000-000000000901', 'details-manager@example.test'),
 ('00000000-0000-0000-0000-000000000902', 'details-staff@example.test'),
 ('00000000-0000-0000-0000-000000000907', 'details-observer@example.test');
insert into public.sections (id, name, display_order)
values ('00000000-0000-0000-0000-000000000903', 'Details test Section', 900);
insert into public.staff_members (id, display_name, cell_number, role) values
 ('00000000-0000-0000-0000-000000000904', 'Details Manager', '5550000000', 'manager'),
 ('00000000-0000-0000-0000-000000000905', 'Details Staff', '5551111111', 'staff_member'),
 ('00000000-0000-0000-0000-000000000906', 'Details Observer', '5554444444', 'staff_member');
insert into public.staff_accounts (staff_member_id, auth_user_id, personal_email, accepted_invite_at) values
 ('00000000-0000-0000-0000-000000000904', '00000000-0000-0000-0000-000000000901', 'details-manager@example.test', now()),
 ('00000000-0000-0000-0000-000000000905', '00000000-0000-0000-0000-000000000902', 'details-staff@example.test', now()),
 ('00000000-0000-0000-0000-000000000906', '00000000-0000-0000-0000-000000000907', 'details-observer@example.test', now());
insert into public.staff_section_assignments (staff_member_id, section_id, display_order, effective_from)
values ('00000000-0000-0000-0000-000000000905',
 '00000000-0000-0000-0000-000000000903', 0, current_date);

set local role authenticated;
select set_config('request.jwt.claims',
 '{"sub":"00000000-0000-0000-0000-000000000901","role":"authenticated"}', true);
select is((select cell_number from public.staff_member_details('00000000-0000-0000-0000-000000000905')),
 '5551111111', 'Manager reads cell number');
select is((select personal_email from public.staff_member_details('00000000-0000-0000-0000-000000000905')),
 'details-staff@example.test', 'Manager reads sign-up email');
select lives_ok($$select public.update_staff_contact(
 '00000000-0000-0000-0000-000000000905', 'Updated Staff', '5552222222')$$,
 'Manager edits name and cell number');
select results_eq($$select kind, old_value, new_value from public.staff_changes
 where staff_member_id = '00000000-0000-0000-0000-000000000905' order by kind$$,
 $$values ('cell_number', '5551111111', '5552222222'),
          ('name', 'Details Staff', 'Updated Staff')$$,
 'each edit enters the Staff change log');
select is((select display_name from public.staff_list_entries where id =
 '00000000-0000-0000-0000-000000000905'), 'Updated Staff',
 'Staff list reflects edited name');

reset role;
update public.staff_members set active = false, last_day = current_date
where id = '00000000-0000-0000-0000-000000000905';
update public.staff_accounts set revoked_at = now()
where staff_member_id = '00000000-0000-0000-0000-000000000905';
set local role authenticated;
select is((select personal_email from public.staff_member_details(
 '00000000-0000-0000-0000-000000000905')),
 'details-staff@example.test', 'Manager sees a former member''s sign-up email');
select lives_ok($$select public.update_staff_contact(
 '00000000-0000-0000-0000-000000000905', 'Former Staff', '5553333333')$$,
 'Manager can correct contact details for a former member on a historical Schedule');

select set_config('request.jwt.claims',
 '{"sub":"00000000-0000-0000-0000-000000000907","role":"authenticated"}', true);
select throws_ok($$select cell_number from public.staff_members limit 1$$,
 '42501', null, 'Staff cannot read raw cell numbers');
select is((select count(*)::integer from public.staff_accounts
 where staff_member_id = '00000000-0000-0000-0000-000000000904'),
 0, 'Staff cannot read another person''s account');
select is((select cell_number from public.staff_list_entries where id =
 '00000000-0000-0000-0000-000000000904'), null::text,
 'Staff list hides another person''s cell number');
select is((select personal_email from public.staff_list_entries where id =
 '00000000-0000-0000-0000-000000000904'), null::text,
 'Staff list hides another person''s email');
select throws_ok($$select * from public.staff_member_details(
 '00000000-0000-0000-0000-000000000904')$$,
 'P0001', 'Only the Manager or administrator can view Staff member details',
 'Staff cannot open another person''s details');
select throws_ok($$select public.update_staff_contact(
 '00000000-0000-0000-0000-000000000904', 'Changed', '5559999999')$$,
 'P0001', 'Only the Manager or administrator can manage the Staff list',
 'Staff cannot edit contact information');
select is((select count(*)::integer from public.staff_changes), 0,
 'Staff cannot read contact edits in the change log');

select * from finish();
rollback;
