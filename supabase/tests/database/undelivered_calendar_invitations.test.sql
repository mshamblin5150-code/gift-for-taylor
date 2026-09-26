begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000003371', 'maintainer-337@example.test'),
  ('00000000-0000-0000-0000-000000003372', 'staff-337@example.test');
insert into private.maintainer_identity(auth_user_id)
values ('00000000-0000-0000-0000-000000003371');
insert into public.staff_members(id, display_name) values
  ('00000000-0000-0000-0000-000000003373', 'Taylor Nurse');
insert into public.calendar_invitation_outbox
  (id, staff_member_id, work_date, recipient, method, shift_code, sequence)
values
  ('00000000-0000-0000-0000-000000003374',
   '00000000-0000-0000-0000-000000003373', '2027-01-04',
   'taylor@example.test', 'REQUEST', '7A', 0),
  ('00000000-0000-0000-0000-000000003375',
   '00000000-0000-0000-0000-000000003373', '2027-01-05',
   'taylor@example.test', 'REQUEST', '7A', 0),
  ('00000000-0000-0000-0000-000000003376',
   '00000000-0000-0000-0000-000000003373', '2027-01-06',
   'taylor@example.test', 'REQUEST', '7A', 0),
  ('00000000-0000-0000-0000-000000003377',
   '00000000-0000-0000-0000-000000003373', '2027-01-07',
   'taylor@example.test', 'REQUEST', '7A', 0);

create temp table failed_claim(delivery_claim uuid);
grant select, insert, delete on failed_claim to service_role;
set local role service_role;
insert into failed_claim
select delivery_claim from public.calendar_invitation_claim(
  '00000000-0000-0000-0000-000000003374');
select public.record_calendar_invitation_failure(
  '00000000-0000-0000-0000-000000003374', 'taylor@example.test', 'REQUEST',
  (select delivery_claim from failed_claim), 'refused',
  'ETEMP', '451', 'Temporary provider refusal');
delete from failed_claim;
insert into failed_claim
select delivery_claim from public.calendar_invitation_claim(
  '00000000-0000-0000-0000-000000003374');
select public.record_calendar_invitation_failure(
  '00000000-0000-0000-0000-000000003374', 'taylor@example.test', 'REQUEST',
  (select delivery_claim from failed_claim), 'refused',
  'EENVELOPE', '550', 'Daily email quota exhausted');
delete from failed_claim;
insert into failed_claim
select delivery_claim from public.calendar_invitation_claim(
  '00000000-0000-0000-0000-000000003375');
select public.calendar_invitation_sending(
  '00000000-0000-0000-0000-000000003375', 'taylor@example.test', 'REQUEST',
  (select delivery_claim from failed_claim));
select public.calendar_invitation_sent(
  '00000000-0000-0000-0000-000000003375', 'taylor@example.test', 'REQUEST',
  (select delivery_claim from failed_claim));
delete from failed_claim;
insert into failed_claim
select delivery_claim from public.calendar_invitation_claim(
  '00000000-0000-0000-0000-000000003377');
select public.calendar_invitation_sending(
  '00000000-0000-0000-0000-000000003377', 'taylor@example.test', 'REQUEST',
  (select delivery_claim from failed_claim));
reset role;

select is((select delivery_attempts from public.calendar_invitation_outbox
    where id = '00000000-0000-0000-0000-000000003374'), 2,
  'the invitation records both delivery attempts');
select is((select count(*)::integer
    from public.calendar_invitation_delivery_outcomes
    where invitation_id = '00000000-0000-0000-0000-000000003374'), 2,
  'each refused attempt keeps its own outcome');
select is((select error_message
    from public.calendar_invitation_delivery_outcomes
    where invitation_id = '00000000-0000-0000-0000-000000003374'
      and attempt_number = 1), 'Temporary provider refusal',
  'an earlier provider reply is retained after a retry');
select ok((select bool_and(happened_at is not null)
    from public.calendar_invitation_delivery_outcomes
    where invitation_id = '00000000-0000-0000-0000-000000003374'),
  'every outcome records when it happened');
select is((select error_code
    from public.calendar_invitation_delivery_outcomes
    where invitation_id = '00000000-0000-0000-0000-000000003374'
      and attempt_number = 2), 'EENVELOPE',
  'the latest provider error code is retained');
select is((select status_code
    from public.calendar_invitation_delivery_outcomes
    where invitation_id = '00000000-0000-0000-0000-000000003374'
      and attempt_number = 2), '550',
  'the latest provider status is retained');
select is((select error_message
    from public.calendar_invitation_delivery_outcomes
    where invitation_id = '00000000-0000-0000-0000-000000003374'
      and attempt_number = 2), 'Daily email quota exhausted',
  'quota exhaustion is retained as itself');
select ok((select delivery_claim is null
    from public.calendar_invitation_outbox
    where id = '00000000-0000-0000-0000-000000003374'),
  'a recorded refusal is released for retry');
select is((select outcome from public.calendar_invitation_delivery_outcomes
    where invitation_id = '00000000-0000-0000-0000-000000003375'), 'sent',
  'a successful delivery records its outcome');
select is((select error_message from public.calendar_invitation_delivery_outcomes
    where invitation_id = '00000000-0000-0000-0000-000000003375'), null::text,
  'a successful outcome carries no provider error');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003372","role":"authenticated"}',
  true);
select throws_ok($$select * from public.read_undelivered_calendar_invitations()$$,
  '42501',
  'An active Maintainer Repair is required to read Undelivered invitations',
  'ordinary Staff cannot read Undelivered invitations');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003371","role":"authenticated"}',
  true);
select throws_ok($$select * from public.read_undelivered_calendar_invitations()$$,
  '42501',
  'An active Maintainer Repair is required to read Undelivered invitations',
  'the Maintainer cannot read them outside a Repair');
select lives_ok($$select public.open_maintainer_repair(
  'investigation', 'Review Undelivered invitations')$$,
  'the Maintainer can open an investigation Repair');
select is((select count(*)::integer
    from public.read_undelivered_calendar_invitations()), 2,
  'failed and unrecorded outcomes appear while never-attempted invitations do not');
select is((select delivery_error_message
    from public.read_undelivered_calendar_invitations()
    where work_date = '2027-01-07'),
  'Delivery outcome could not be recorded',
  'a post-SMTP persistence failure is visible instead of silent');
select is((select staff_display_name
    from public.read_undelivered_calendar_invitations()
    where work_date = '2027-01-04'), 'Taylor Nurse',
  'the Maintainer sees who the invitation belongs to');
select is((select delivery_attempts
    from public.read_undelivered_calendar_invitations()
    where work_date = '2027-01-04'), 2,
  'the Maintainer sees how many times it was tried');
select is((select delivery_error_message
    from public.read_undelivered_calendar_invitations()
    where work_date = '2027-01-04'),
  'Daily email quota exhausted', 'the Maintainer sees the latest provider reply');

select * from finish();
rollback;
