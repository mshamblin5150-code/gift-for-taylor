begin;

create extension if not exists pgtap with schema extensions;
select plan(17);

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
  '5558675309',
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

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000153","role":"authenticated"}',
  true
);
select throws_ok(
  $$select public.accept_invite((select token from initial_invite))$$,
  'P0001',
  'This Invite is invalid, expired, or has already been used',
  'a revoked Invite cannot be accepted'
);
select lives_ok(
  $$select public.accept_invite((select token from invite_tokens))$$,
  'an invitee can accept a fresh Invite after signing in'
);

select is(
  (
    select personal_email
    from public.staff_accounts
    where auth_user_id = '00000000-0000-0000-0000-000000000153'
  ),
  'invitee@example.test',
  'accepting an Invite links the personal email to the Staff member'
);

select throws_ok(
  $$select public.accept_invite((select token from invite_tokens))$$,
  'P0001',
  'This Invite is invalid, expired, or has already been used',
  'a used Invite cannot be accepted again'
);

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

select * from finish();
rollback;
