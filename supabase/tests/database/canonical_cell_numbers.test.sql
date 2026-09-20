begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000331', 'cell-manager@example.test');
insert into public.sections (id, name, display_order) values
  ('00000000-0000-0000-0000-000000000332', 'Cell test Section', 99);
insert into public.staff_members (id, display_name, role) values
  ('00000000-0000-0000-0000-000000000333', 'Cell Manager', 'manager');
insert into public.staff_accounts (staff_member_id, auth_user_id, personal_email, accepted_invite_at)
values ('00000000-0000-0000-0000-000000000333',
  '00000000-0000-0000-0000-000000000331', 'cell-manager@example.test', now());
create function pg_temp.cell_of(p_name text) returns text
language sql security definer set search_path = '' as $$
  select cell_number from public.staff_members where display_name = p_name
$$;
create function pg_temp.id_of(p_name text) returns uuid
language sql security definer set search_path = '' as $$
  select id from public.staff_members where display_name = p_name
$$;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000331","role":"authenticated"}', true);

select is((select cell_number from public.create_staff_member_with_invite(
  'First Cell', '(555) 013-7', '00000000-0000-0000-0000-000000000332')),
  '+15550137', 'add returns the canonical Cell number');
select is(pg_temp.cell_of('First Cell'),
  '+15550137', 'add stores the canonical Cell number');
select throws_ok($$select public.create_staff_member_with_invite(
  'Duplicate Cell', '555-0137', '00000000-0000-0000-0000-000000000332')$$,
  'P0001', 'An active Staff member already has this cell number',
  'the equivalent active number gets a readable error');
select throws_ok($$select public.create_staff_member_with_invite(
  'Bad Cell', 'junk', '00000000-0000-0000-0000-000000000332')$$,
  'P0001', 'Enter a cell number with its area code.', 'add rejects invalid input');

select lives_ok($$select public.update_staff_contact(
  pg_temp.id_of('First Cell'),
  'First Cell', '+1 555 013 7')$$, 'contact update accepts the same canonical value');
select is(pg_temp.cell_of('First Cell'),
  '+15550137', 'contact update stores canonical form');
select throws_ok($$select public.update_staff_contact(
  pg_temp.id_of('First Cell'),
  'First Cell', 'bad')$$, 'P0001', 'Enter a cell number with its area code.',
  'contact update rejects invalid input');

reset role;
update public.staff_members set active = false where display_name = 'First Cell';
set local role authenticated;
select lives_ok($$select public.create_staff_member_with_invite(
  'Recycled Cell', '+1 555 013 7', '00000000-0000-0000-0000-000000000332')$$,
  'a past Staff member does not reserve the Cell number');
select is(pg_temp.cell_of('Recycled Cell'),
  '+15550137', 'the recycled number remains canonical');

reset role;
create function pg_temp.codes() returns jsonb language sql as $$
  select jsonb_agg('X'::text order by day) from generate_series(1, 28) day
$$;
select lives_ok($$select public.load_first_month('2027-02-01', jsonb_build_array(
  jsonb_build_object('section', 'Cell test Section', 'name', 'No Cell',
    'codes', pg_temp.codes()),
  jsonb_build_object('section', 'Cell test Section', 'name', 'Blank Cell',
    'cell', '  ', 'codes', pg_temp.codes()),
  jsonb_build_object('section', 'Cell test Section', 'name', 'Imported Cell',
    'cell', '555-0199', 'codes', pg_temp.codes())))$$,
  'the import accepts missing and blank Cell columns');
select is((select cell_number from public.staff_members where display_name = 'Imported Cell'),
  '+15550199', 'the import canonicalizes Cell numbers');
select is((select cell_number from public.staff_members where display_name = 'No Cell'),
  null, 'a missing imported Cell number remains null');
select is((select cell_number from public.staff_members where display_name = 'Blank Cell'),
  null, 'a blank imported Cell number remains null');

select * from finish();
rollback;
