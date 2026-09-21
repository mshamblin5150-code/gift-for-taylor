begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000b61', 'manager-confirm@example.test'),
  ('00000000-0000-0000-0000-000000000b62', 'wrong-person@example.test'),
  ('00000000-0000-0000-0000-000000000b63', 'right-person@example.test'),
  ('00000000-0000-0000-0000-000000000b66', 'admin-confirm@example.test');
insert into public.staff_members (id, display_name, role, cell_number) values
  ('00000000-0000-0000-0000-000000000b64', 'Confirm Manager', 'manager', '+15551230001'),
  ('00000000-0000-0000-0000-000000000b65', 'Jane Kemp', 'staff_member', '+15551230002'),
  ('00000000-0000-0000-0000-000000000b67', 'Confirm Administrator', 'administrator', '+15551230003');
insert into public.staff_accounts (staff_member_id, auth_user_id,
  personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000000b64',
   '00000000-0000-0000-0000-000000000b61',
   'manager-confirm@example.test', now()),
  ('00000000-0000-0000-0000-000000000b67',
   '00000000-0000-0000-0000-000000000b66',
   'admin-confirm@example.test', now());

create temporary table confirmation_token as
select public.issue_staff_invite('00000000-0000-0000-0000-000000000b65') token;
grant select on confirmation_token to authenticated;
create temporary table confirmation_invite as
select id from public.invites where staff_member_id =
  '00000000-0000-0000-0000-000000000b65';
grant select on confirmation_invite to authenticated;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000b61","role":"authenticated"}', true);
select throws_ok($$select public.accept_invite(
  (select token from confirmation_token), '+15551230002')$$,
  'P2793', 'This email is already signed in as another Staff member.',
  'an already linked account receives a distinct refusal code');
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
  'P0001', 'Only the Manager or Administrator can reject an Invite',
  'the invitee cannot decide their own acceptance');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000b61","role":"authenticated"}', true);
select lives_ok($$select public.reject_invite_acceptance(
  (select id from confirmation_invite))$$,
  'the Manager rejects the wrong person');
select is((select count(*)::integer from public.staff_accounts
  where staff_member_id = '00000000-0000-0000-0000-000000000b65'), 0,
  'rejection leaves no account binding');
create temporary table confirmation_resend as select * from public.resend_staff_invite(
  '00000000-0000-0000-0000-000000000b65');
grant select on confirmation_resend to authenticated;
select is((select count(*)::integer from confirmation_resend), 1,
  'the Manager can reissue the Invite after correcting the Cell number');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000b63","role":"authenticated"}', true);
select lives_ok($$select public.accept_invite(
  (select token from confirmation_resend), '+15551230002')$$,
  'the right person submits the new Invite');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000b66","role":"authenticated"}', true);
select is((select count(*)::integer from public.pending_invite_acceptances), 1,
  'Administrator sees the pending acceptance');
select lives_ok($$select public.confirm_invite_acceptance(
  (select invite_id from public.pending_invite_acceptances))$$,
  'Administrator confirms the Invite');
select is((select count(*)::integer from public.staff_accounts
  where staff_member_id = '00000000-0000-0000-0000-000000000b65'
    and revoked_at is null), 1,
  'confirmed Staff account is active');
reset role;
select is((select count(*)::integer from auth.users where id =
  '00000000-0000-0000-0000-000000000b62'), 1,
  'rejection does not remove the auth user');

select * from finish();
rollback;
