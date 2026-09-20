begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000b61', 'manager-confirm@example.test'),
  ('00000000-0000-0000-0000-000000000b62', 'wrong-person@example.test'),
  ('00000000-0000-0000-0000-000000000b63', 'right-person@example.test');
insert into public.staff_members (id, display_name, role, cell_number) values
  ('00000000-0000-0000-0000-000000000b64', 'Confirm Manager', 'manager', '+15551230001'),
  ('00000000-0000-0000-0000-000000000b65', 'Jane Kemp', 'staff_member', '+15551230002');
insert into public.staff_accounts (staff_member_id, auth_user_id,
  personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000000b64',
   '00000000-0000-0000-0000-000000000b61',
   'manager-confirm@example.test', now());

create temporary table confirmation_token as
select public.issue_staff_invite('00000000-0000-0000-0000-000000000b65') token;
grant select on confirmation_token to authenticated;
create temporary table confirmation_invite as
select id from public.invites where staff_member_id =
  '00000000-0000-0000-0000-000000000b65';
grant select on confirmation_invite to authenticated;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000b62","role":"authenticated"}', true);
select lives_ok($$select public.accept_invite(
  (select token from confirmation_token), '+15551230002')$$,
  'the first person can submit an Invite acceptance');
select is(public.current_staff_role()::text, null::text,
  'the pending person has no Staff role');
select is(public.current_staff_member_id(), null::uuid,
  'the pending person has no Staff identity');
select is((select count(*)::integer from public.staff_members), 0,
  'the pending person cannot read the Staff list');
select throws_ok($$select public.reject_invite_acceptance(
  (select id from confirmation_invite))$$,
  'P0001', 'Only the Manager can reject an Invite',
  'the invitee cannot decide their own acceptance');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000b61","role":"authenticated"}', true);
select lives_ok($$select public.reject_invite_acceptance(
  (select id from confirmation_invite))$$,
  'the Manager rejects the wrong person');
select is((select count(*)::integer from public.staff_accounts
  where staff_member_id = '00000000-0000-0000-0000-000000000b65'), 0,
  'rejection leaves no account binding');
select lives_ok($$select public.resend_staff_invite(
  '00000000-0000-0000-0000-000000000b65')$$,
  'the Manager can reissue the Invite after correcting the Cell number');
reset role;
select is((select count(*)::integer from auth.users where id =
  '00000000-0000-0000-0000-000000000b62'), 1,
  'rejection does not remove the auth user');

select * from finish();
rollback;
