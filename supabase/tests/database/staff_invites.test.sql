begin;

create extension if not exists pgtap with schema extensions;
select plan(36);

insert into auth.users (id, email)
values
  ('00000000-0000-0000-0000-000000000151', 'manager@example.test'),
  ('00000000-0000-0000-0000-000000000152', 'administrator@example.test'),
  ('00000000-0000-0000-0000-000000000153', 'invitee@example.test'),
  ('00000000-0000-0000-0000-000000000154', 'outsider@example.test');

insert into public.sections (id, name, display_order)
values ('00000000-0000-0000-0000-000000000155', 'Invite test Section', 99);

insert into public.staff_members (id, display_name, role)
values
  ('00000000-0000-0000-0000-000000000156', 'Test Manager', 'manager'),
  ('00000000-0000-0000-0000-000000000157', 'Test Administrator', 'administrator'),
  ('00000000-0000-0000-0000-000000000158', 'Existing Staff member', 'staff_member');

insert into public.staff_accounts (
  staff_member_id,
  auth_user_id,
  personal_email,
  accepted_invite_at
)
values
  (
    '00000000-0000-0000-0000-000000000156',
    '00000000-0000-0000-0000-000000000151',
    'manager@example.test',
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000157',
    '00000000-0000-0000-0000-000000000152',
    'administrator@example.test',
    now()
  );

insert into public.staff_section_assignments (
  staff_member_id,
  section_id,
  display_order,
  effective_from
)
values (
  '00000000-0000-0000-0000-000000000158',
  '00000000-0000-0000-0000-000000000155',
  0,
  current_date
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000151","role":"authenticated"}',
  true
);

create temporary table initial_invite as
select * from public.create_staff_member_with_invite(
  'New Staff member',
  '5550137',
  '00000000-0000-0000-0000-000000000155'
);

select is(
  (select count(*)::integer from initial_invite),
  1,
  'the Manager can add a Staff member'
);

select is(
  (
    select assignment.display_order
    from public.staff_section_assignments assignment
    join public.staff_members member on member.id = assignment.staff_member_id
    where member.display_name = 'New Staff member'
      and assignment.effective_through is null
  ),
  1,
  'a new Staff member is placed at the bottom of the Section'
);

reset role;
select is(
  (
    select count(*)::integer
    from public.invites invite
    join public.staff_members member on member.id = invite.staff_member_id
    where member.display_name = 'New Staff member'
      and invite.accepted_at is null
      and invite.revoked_at is null
  ),
  1,
  'adding a Staff member creates one active Invite'
);

select is(
  (
    select invite.expires_at - invite.created_at
    from public.invites invite
    join public.staff_members member on member.id = invite.staff_member_id
    where member.display_name = 'New Staff member'
      and invite.revoked_at is null
  ),
  interval '30 days',
  'a newly issued Invite expires 30 days after creation'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000151","role":"authenticated"}',
  true
);

select lives_ok(
  $$select public.reorder_staff_section(
    '00000000-0000-0000-0000-000000000155',
    array[
      (select id from public.staff_members where display_name = 'New Staff member'),
      '00000000-0000-0000-0000-000000000158'::uuid
    ]
  )$$,
  'the Manager can reorder a Section'
);

select is(
  (
    select display_order
    from public.staff_section_assignments
    where staff_member_id = '00000000-0000-0000-0000-000000000158'
      and effective_through is null
  ),
  1,
  'the reordered Staff list persists'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000152","role":"authenticated"}',
  true
);
select lives_ok(
  $$select public.create_staff_member_with_invite(
    'Added by Administrator',
    '5550000000',
    '00000000-0000-0000-0000-000000000155'
  )$$,
  'the administrator can manage the Staff list'
);

reset role;
create temporary table invite_tokens as
select token
from public.resend_staff_invite(
  (select id from public.staff_members where display_name = 'New Staff member')
);
grant select on invite_tokens to authenticated;

select is(
  (
    select count(*)::integer
    from public.invites invite
    join public.staff_members member on member.id = invite.staff_member_id
    where member.display_name = 'New Staff member'
      and invite.revoked_at is not null
  ),
  1,
  'resending revokes the prior Invite'
);

select is(
  (
    select invite.expires_at - invite.created_at
    from public.invites invite
    join public.staff_members member on member.id = invite.staff_member_id
    where member.display_name = 'New Staff member'
      and invite.revoked_at is null
  ),
  interval '30 days',
  'a resent Invite also gets the 30-day default'
);

-- Move both timestamps to keep the row's expires_at > created_at constraint.
update public.invites invite
set created_at = now() - interval '31 days',
    expires_at = now() - interval '1 day'
from public.staff_members member
where member.id = invite.staff_member_id
  and member.display_name = 'New Staff member'
  and invite.revoked_at is null;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000153","role":"authenticated"}',
  true
);
select throws_ok(
  $$select public.accept_invite((select token from initial_invite), '555-0137')$$,
  'P2794',
  'This Invite is invalid, expired, or has already been used',
  'a revoked Invite cannot be accepted'
);
select throws_ok(
  $$select public.accept_invite((select token from invite_tokens), '555-0137')$$,
  'P2794',
  'This Invite is invalid, expired, or has already been used',
  'an expired Invite cannot be accepted'
);

reset role;
update public.invites invite
set expires_at = now() + interval '30 days'
from public.staff_members member
where member.id = invite.staff_member_id
  and member.display_name = 'New Staff member'
  and invite.revoked_at is null;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000153","role":"authenticated"}',
  true
);
select throws_ok(
  $$select public.accept_invite('not-an-invite', '555-0000')$$,
  'P2794',
  'This Invite is invalid, expired, or has already been used',
  'an invalid token gives no Cell number detail'
);
select is(
  public.accept_invite((select token from invite_tokens), '555-0000'),
  'cell_mismatch',
  'a different Cell number cannot accept the Invite'
);
reset role;
select is(
  (select accepted_at is null and revoked_at is null from public.invites
   where token_hash = extensions.digest(convert_to((select token from invite_tokens), 'UTF8'), 'sha256')),
  true,
  'a mismatch leaves the Invite usable'
);
select is(
  (select count(*)::integer from public.invite_cell_mismatches
   where staff_member_id = (select staff_member_id from initial_invite)),
  1,
  'a mismatch is recorded against the Staff member'
);
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000153","role":"authenticated"}',
  true
);
select is(
  public.accept_invite((select token from invite_tokens), '555-0000'),
  'cell_mismatch',
  'another mismatch is reported'
);
select is(
  public.accept_invite((select token from invite_tokens), '555-0000'),
  'cell_mismatch',
  'a third mismatch is reported'
);
select is(
  public.accept_invite((select token from invite_tokens), '555-0000'),
  'throttled',
  'repeated failures are throttled'
);
select is(
  public.accept_invite((select token from invite_tokens), '(555) 013-7'),
  'accepted',
  'a correct Cell number in another format accepts the Invite'
);

select is(public.current_staff_role()::text, null::text,
  'a pending acceptance gives no Staff role');
select is(public.current_staff_member_id(), null::uuid,
  'a pending acceptance gives no Staff identity');
select is((select count(*)::integer from public.staff_accounts
  where auth_user_id = '00000000-0000-0000-0000-000000000153'), 0,
  'accepting an Invite creates no account binding');
select ok(public.my_invite_acceptance_pending(),
  'the invitee can see that confirmation is pending');

select throws_ok(
  $$select public.accept_invite((select token from invite_tokens), '+15550137')$$,
  'P2794',
  'This Invite is invalid, expired, or has already been used',
  'a used Invite cannot be accepted again'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000151","role":"authenticated"}',
  true
);
select is(
  (select invite_cell_mismatch_at is not null from public.staff_list_entries
   where id = (select staff_member_id from initial_invite)),
  true,
  'the Manager sees the Staff member with a mismatched Invite'
);
select lives_ok(
  $$select public.confirm_invite_acceptance(
    (select invite_id from public.pending_invite_acceptances
     where auth_user_id = '00000000-0000-0000-0000-000000000153'))$$,
  'the Manager confirms the acceptance'
);
select is((select personal_email from public.staff_accounts
  where auth_user_id = '00000000-0000-0000-0000-000000000153'),
  'invitee@example.test',
  'confirmation binds the accepted personal email'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000153","role":"authenticated"}',
  true
);
select is(public.current_staff_role(), 'staff_member'::public.staff_role,
  'the confirmed invitee gains the Staff role');
select is(public.current_staff_member_id(),
  (select staff_member_id from initial_invite),
  'the confirmed invitee resolves to the intended Staff member');
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000151","role":"authenticated"}',
  true
);
select throws_ok(
  $$select public.resend_staff_invite(
    (select id from public.staff_members where display_name = 'New Staff member')
  )$$,
  'P0001',
  'This Staff member has already accepted an Invite',
  'an accepted Staff member is not offered an unusable replacement Invite'
);

select throws_ok(
  $$select public.resend_staff_invite(
    '00000000-0000-0000-0000-000000000158'
  )$$,
  'P0001',
  'Add a cell number before sending an Invite',
  'a Staff member without a cell number cannot be sent an Invite'
);
select throws_ok(
  $$select public.create_staff_member_with_invite(
    'No Cell Nurse', null, '00000000-0000-0000-0000-000000000155'
  )$$,
  'P0001',
  'Add a cell number before sending an Invite',
  'adding a Staff member cannot issue an Invite without a cell number'
);

reset role;
select is(
  (select count(*)::integer from public.invites
   where staff_member_id = '00000000-0000-0000-0000-000000000158'),
  0,
  'a failed resend does not issue an Invite'
);
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000151","role":"authenticated"}',
  true
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000154","role":"authenticated"}',
  true
);
select is(
  (select count(*)::integer from public.staff_members),
  0,
  'an account without an accepted Invite reads no Staff members'
);
select is(
  (select count(*)::integer from public.staff_list_entries),
  0,
  'an account without an accepted Invite reads no Staff list entries'
);
select is(
  (select count(*)::integer from public.invite_cell_mismatches),
  0,
  'an outsider cannot read mismatch records'
);

select * from finish();
rollback;
