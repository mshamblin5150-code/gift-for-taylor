begin;
create extension if not exists pgtap with schema extensions;
select plan(4);

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000003071', 'first-307@example.test'),
  ('00000000-0000-0000-0000-000000003072', 'pending-307@example.test'),
  ('00000000-0000-0000-0000-000000003073', 'accepted-307@example.test'),
  ('00000000-0000-0000-0000-000000003074', 'email-pending-307@example.test'),
  ('00000000-0000-0000-0000-000000003075', null);

insert into public.staff_members(id, display_name, cell_number) values
  ('00000000-0000-0000-0000-000000003081', 'Pending target', '+15553070001'),
  ('00000000-0000-0000-0000-000000003082', 'Accepted target', '+15553070002'),
  ('00000000-0000-0000-0000-000000003083', 'Earlier target', '+15553070003'),
  ('00000000-0000-0000-0000-000000003084', 'Email pending target', '+15553070004'),
  ('00000000-0000-0000-0000-000000003085', 'No email target', '+15553070005');

insert into public.invites(id, staff_member_id, token_hash, accepted_at) values
  ('00000000-0000-0000-0000-000000003091',
   '00000000-0000-0000-0000-000000003081',
   extensions.digest(convert_to('old-pending-307', 'UTF8'), 'sha256'), now()),
  ('00000000-0000-0000-0000-000000003092',
   '00000000-0000-0000-0000-000000003083',
   extensions.digest(convert_to('old-email-307', 'UTF8'), 'sha256'), now());
insert into public.pending_invite_acceptances(
  invite_id, staff_member_id, auth_user_id, personal_email) values
  ('00000000-0000-0000-0000-000000003091',
   '00000000-0000-0000-0000-000000003081',
   '00000000-0000-0000-0000-000000003072', 'pending-307@example.test'),
  ('00000000-0000-0000-0000-000000003092',
   '00000000-0000-0000-0000-000000003083',
   '00000000-0000-0000-0000-000000003074', 'email-pending-307@example.test');
insert into public.staff_accounts(
  staff_member_id, auth_user_id, accepted_invite_at, personal_email) values
  ('00000000-0000-0000-0000-000000003082',
   '00000000-0000-0000-0000-000000003073', now(),
   'accepted-307@example.test');
insert into public.invites(staff_member_id, token_hash) values
  ('00000000-0000-0000-0000-000000003081',
   extensions.digest(convert_to('pending-target-307', 'UTF8'), 'sha256')),
  ('00000000-0000-0000-0000-000000003082',
   extensions.digest(convert_to('accepted-target-307', 'UTF8'), 'sha256')),
  ('00000000-0000-0000-0000-000000003084',
   extensions.digest(convert_to('email-pending-target-307', 'UTF8'), 'sha256')),
  ('00000000-0000-0000-0000-000000003085',
   extensions.digest(convert_to('no-email-target-307', 'UTF8'), 'sha256'));

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003071","role":"authenticated"}', true);
select throws_ok($$select public.accept_invite(
  'pending-target-307', '+15553070001')$$,
  'P2807', 'This Staff member already has an Invite awaiting confirmation',
  'an existing acceptance for the Staff member has a distinct code');
select throws_ok($$select public.accept_invite(
  'accepted-target-307', '+15553070002')$$,
  'P2808', 'This Staff member has already accepted an Invite',
  'an existing Staff account has a distinct code');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003074","role":"authenticated"}', true);
select throws_ok($$select public.accept_invite(
  'email-pending-target-307', '+15553070004')$$,
  'P2809', 'This email already has an Invite awaiting confirmation',
  'an email awaiting confirmation has a distinct code');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003075","role":"authenticated"}', true);
select throws_ok($$select public.accept_invite(
  'no-email-target-307', '+15553070005')$$,
  'P2810', 'The signed-in account does not have an email address',
  'an account without email has a distinct code');

select * from finish();
rollback;
