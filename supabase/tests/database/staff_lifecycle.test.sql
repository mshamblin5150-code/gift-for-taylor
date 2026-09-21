begin;

create extension if not exists pgtap with schema extensions;
select plan(67);

insert into auth.users (id, email)
values
  ('00000000-0000-0000-0000-000000000191', 'manager@example.test'),
  ('00000000-0000-0000-0000-000000000192', 'leaver@example.test'),
  ('00000000-0000-0000-0000-000000000193', 'colleague@example.test');

insert into public.sections (id, name, display_order)
values
  ('00000000-0000-0000-0000-000000000194', 'Lifecycle day Section', 96),
  ('00000000-0000-0000-0000-000000000195', 'Lifecycle night Section', 97);

insert into public.staff_members (id, display_name, role)
values
  ('00000000-0000-0000-0000-000000000196', 'Test Manager', 'manager'),
  ('00000000-0000-0000-0000-000000000197', 'Leaving Staff member', 'staff_member'),
  ('00000000-0000-0000-0000-000000000198', 'Moving Staff member', 'staff_member');

insert into public.staff_accounts (
  staff_member_id,
  auth_user_id,
  personal_email,
  accepted_invite_at
)
values
  (
    '00000000-0000-0000-0000-000000000196',
    '00000000-0000-0000-0000-000000000191',
    'manager@example.test',
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000197',
    '00000000-0000-0000-0000-000000000192',
    'leaver@example.test',
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000198',
    '00000000-0000-0000-0000-000000000193',
    'colleague@example.test',
    now()
  );

insert into public.staff_section_assignments (
  staff_member_id,
  section_id,
  display_order,
  effective_from
)
values
  (
    '00000000-0000-0000-0000-000000000197',
    '00000000-0000-0000-0000-000000000194',
    0,
    '2027-01-01'
  ),
  (
    '00000000-0000-0000-0000-000000000198',
    '00000000-0000-0000-0000-000000000194',
    1,
    '2027-01-01'
  );

insert into public.schedule_months (id, month_start, release_state, released_at, released_by_staff_member_id)
values (
  '00000000-0000-0000-0000-000000000199',
  '2027-01-01',
  'released',
  now(),
  '00000000-0000-0000-0000-000000000196'
);

insert into public.schedule_cells (
  schedule_month_id,
  staff_member_id,
  section_id,
  work_date,
  shift_code
)
values
  ('00000000-0000-0000-0000-000000000199', '00000000-0000-0000-0000-000000000197', '00000000-0000-0000-0000-000000000194', '2027-01-10', '7A'),
  ('00000000-0000-0000-0000-000000000199', '00000000-0000-0000-0000-000000000197', '00000000-0000-0000-0000-000000000194', '2027-01-11', '16D'),
  ('00000000-0000-0000-0000-000000000199', '00000000-0000-0000-0000-000000000197', '00000000-0000-0000-0000-000000000194', '2027-01-12', 'X'),
  ('00000000-0000-0000-0000-000000000199', '00000000-0000-0000-0000-000000000197', '00000000-0000-0000-0000-000000000194', '2027-01-13', '4P-8A');

-- A Staff member cannot remove anyone.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000193","role":"authenticated"}',
  true
);

select throws_ok(
  $$select public.set_staff_last_day('00000000-0000-0000-0000-000000000197', '2027-01-10')$$,
  'Only the Manager or administrator can manage the Staff list',
  'a Staff member cannot set a Last day'
);

-- The Manager sets a Last day.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000191","role":"authenticated"}',
  true
);

-- A past Cell number offers reactivation, but may belong to a different person.
reset role;
insert into public.staff_members (id, display_name, cell_number, active, last_day)
values ('00000000-0000-0000-0000-000000000190', 'Jane Kemp',
  '+15558675309', false, '2026-03-01');
set local role authenticated;
select is(
  (select id from public.past_staff_entries where cell_number = '+15558675309'),
  '00000000-0000-0000-0000-000000000190'::uuid,
  'the Manager can find the past Staff member by canonical Cell number'
);
select throws_ok(
  $$select public.create_staff_member_with_invite(
    'Jane Kemp', '(555) 867-5309', '00000000-0000-0000-0000-000000000194')$$,
  'A past Staff member has this cell number. Offer reactivation first.',
  'Add Staff cannot silently duplicate a past Staff member'
);
select is(
  (select count(*)::integer from public.past_staff_entries where cell_number = '+15558675309'),
  1,
  'the match creates no new Staff member'
);
create temporary table recycled_number_invite as
select * from public.create_staff_member_with_invite(
  'Different Person', '555-867-5309',
  '00000000-0000-0000-0000-000000000194', true
);
select isnt(
  (select staff_member_id from recycled_number_invite),
  '00000000-0000-0000-0000-000000000190'::uuid,
  'declining reactivation creates a different Staff member'
);
select is(
  (select count(*)::integer from public.staff_list_entries where cell_number = '+15558675309'),
  1,
  'the inactive and active people may share a recycled Cell number'
);
select throws_ok(
  format('select public.accept_invite(%L, %L)',
    (select token from recycled_number_invite), '5558675309'),
  'This email is already signed in as another Staff member.',
  'a duplicate sign-in fails with a readable message'
);

select throws_ok(
  $$select public.set_staff_last_day('00000000-0000-0000-0000-000000000196', '2027-01-10')$$,
  'You can''t set your own Last day',
  'the Manager cannot set her own Last day'
);

select lives_ok(
  $$select public.set_staff_last_day('00000000-0000-0000-0000-000000000197', '2027-01-10')$$,
  'the Manager sets a Last day'
);

select results_eq(
  $$
    select work_date::text, shift_code
    from public.schedule_cells
    where staff_member_id = '00000000-0000-0000-0000-000000000197'
    order by work_date
  $$,
  $$values
    ('2027-01-10', '7A'),
    ('2027-01-11', ''),
    ('2027-01-12', ''),
    ('2027-01-13', '')$$,
  'shifts through the Last day stay; later ones are cleared'
);

select results_eq(
  $$
    select work_date::text, shift_code, section_id, reason
    from public.short_shifts
    where staff_member_id = '00000000-0000-0000-0000-000000000197'
    order by work_date
  $$,
  $$values
    ('2027-01-11', '16D', '00000000-0000-0000-0000-000000000194'::uuid, 'last_day'),
    ('2027-01-13', '4P-8A', '00000000-0000-0000-0000-000000000194'::uuid, 'last_day')$$,
  'each cleared working shift is marked short; a day off is not'
);

select results_eq(
  $$
    select old_shift_code, new_shift_code, changed_by_staff_member_id
    from public.schedule_changes
    where staff_member_id = '00000000-0000-0000-0000-000000000197'
    order by work_date
  $$,
  $$values
    ('16D', '', '00000000-0000-0000-0000-000000000196'::uuid),
    ('X', '', '00000000-0000-0000-0000-000000000196'::uuid),
    ('4P-8A', '', '00000000-0000-0000-0000-000000000196'::uuid)$$,
  'every cleared cell is in the change log'
);

select results_eq(
  $$
    select kind, new_value, effective_from::text
    from public.staff_changes
    where staff_member_id = '00000000-0000-0000-0000-000000000197'
  $$,
  $$values ('last_day', '2027-01-10', '2027-01-10')$$,
  'the Last day is in the Staff list change log'
);

select is(
  (
    select count(*)::integer
    from public.staff_list_entries
    where id = '00000000-0000-0000-0000-000000000197'
  ),
  0,
  'the person leaves the Staff list at once'
);

select results_eq(
  $$
    select last_day::text, section_id
    from public.past_staff_entries
    where id = '00000000-0000-0000-0000-000000000197'
  $$,
  $$values ('2027-01-10', '00000000-0000-0000-0000-000000000194'::uuid)$$,
  'the person is on the past-staff list with their last Section'
);

select results_eq(
  $$
    select display_name, last_day::text
    from public.schedule_rows('2027-01-01')
    where staff_member_id = '00000000-0000-0000-0000-000000000197'
  $$,
  $$values ('Leaving Staff member', '2027-01-10')$$,
  'the month of their Last day still shows them'
);

select lives_ok(
  $$select public.save_schedule_cell(
    '00000000-0000-0000-0000-000000000197',
    '00000000-0000-0000-0000-000000000194',
    '2027-01-10',
    'S/L'
  )$$,
  'a cell through the Last day can still be corrected'
);

select throws_ok(
  $$select public.save_schedule_cell(
    '00000000-0000-0000-0000-000000000197',
    '00000000-0000-0000-0000-000000000194',
    '2027-01-11',
    '7A'
  )$$,
  'That day is after their Last day',
  'no cell after the Last day can be saved'
);

select throws_ok(
  $$select public.set_staff_last_day('00000000-0000-0000-0000-000000000197', '2027-01-20')$$,
  'That person is not on the Staff list',
  'a Last day is set only once'
);

-- The deactivated person can no longer sign in or read anything.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000192","role":"authenticated"}',
  true
);

select is(public.current_staff_role(), null, 'a deactivated person has no role');
select is(
  (select count(*)::integer from public.sections),
  0,
  'a deactivated person reads no Sections'
);
select is(
  (select count(*)::integer from public.staff_members),
  0,
  'a deactivated person reads no Staff members'
);
select is(
  (select count(*)::integer from public.schedule_months),
  0,
  'a deactivated person reads no Schedule months'
);
select is(
  (select count(*)::integer from public.schedule_cells),
  0,
  'a deactivated person reads no Schedule cells'
);
select is(
  (select count(*)::integer from public.short_shifts),
  0,
  'a deactivated person reads no short shifts'
);
select is(
  (select count(*)::integer from public.schedule_changes),
  0,
  'a deactivated person reads no change log'
);
select is(
  (select count(*)::integer from public.staff_changes),
  0,
  'a deactivated person reads no Staff list change log'
);
select is(
  (select count(*)::integer from public.staff_section_assignments),
  0,
  'a deactivated person reads no Section placements'
);
select is(
  (select count(*)::integer from public.staff_job_roles),
  0,
  'a deactivated person reads no roles'
);
select is(
  (select count(*)::integer from public.staff_accounts),
  0,
  'a deactivated person cannot read even their own account'
);

-- A colleague still sees the past month as it was.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000193","role":"authenticated"}',
  true
);

select is(
  (
    select count(*)::integer
    from public.schedule_cells
    where staff_member_id = '00000000-0000-0000-0000-000000000197'
  ),
  4,
  'past months still show the person to active staff'
);

-- Reactivation.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000191","role":"authenticated"}',
  true
);

select throws_ok(
  $$select public.reactivate_staff_member(
    '00000000-0000-0000-0000-000000000197',
    '00000000-0000-0000-0000-000000000195',
    '2027-01-10'
  )$$,
  'Their first day back must be after their Last day',
  'reactivation starts after the Last day'
);

select lives_ok(
  $$select public.reactivate_staff_member(
    '00000000-0000-0000-0000-000000000197',
    '00000000-0000-0000-0000-000000000195',
    '2027-03-01'
  )$$,
  'the Manager reactivates a past Staff member'
);

select results_eq(
  $$
    select section_id, personal_email
    from public.staff_list_entries
    where id = '00000000-0000-0000-0000-000000000197'
  $$,
  $$values ('00000000-0000-0000-0000-000000000195'::uuid, null::text)$$,
  'the same person is back on the Staff list, waiting for a fresh Invite'
);

-- A returning person whose imported contact lacked a Cell number needs one
-- before the Manager can send the fresh Invite.
select public.update_staff_contact(
  '00000000-0000-0000-0000-000000000197',
  'Leaving Staff member',
  '5552223333'
);

create temporary table fresh_invite as
select * from public.resend_staff_invite('00000000-0000-0000-0000-000000000197');

select is(
  (select count(*)::integer from fresh_invite),
  1,
  'a fresh Invite can be sent to the returning person'
);

select throws_ok(
  $$select public.save_schedule_cell(
    '00000000-0000-0000-0000-000000000197',
    '00000000-0000-0000-0000-000000000194',
    '2027-01-20',
    '7A'
  )$$,
  'That day is after their Last day',
  'the month they left still ends at their old Last day'
);

reset role;
select is(
  (
    select revoked_at is not null
    from public.staff_accounts
    where staff_member_id = '00000000-0000-0000-0000-000000000197'
  ),
  true,
  'their old sign-in link is revoked, not deleted'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000192","role":"authenticated"}',
  true
);

select is(
  public.current_staff_role(),
  null,
  'the old sign-in link does not work before the fresh Invite is accepted'
);

select is(
  public.accept_invite((select token from fresh_invite), '5552223333'),
  'accepted',
  'the returning person accepts the fresh Invite'
);

select is(public.current_staff_role(), null::public.staff_role,
  'the returning person waits for Manager confirmation');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000191","role":"authenticated"}',
  true
);
select lives_ok(
  $$select public.confirm_invite_acceptance(
    (select invite_id from public.pending_invite_acceptances
     where staff_member_id = '00000000-0000-0000-0000-000000000197'))$$,
  'the Manager confirms the returning person'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000192","role":"authenticated"}',
  true
);

select is(
  public.current_staff_role(),
  'staff_member'::public.staff_role,
  'the returning person can sign in again'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000191","role":"authenticated"}',
  true
);

select is(
  (
    select count(*)::integer
    from public.schedule_changes
    where staff_member_id = '00000000-0000-0000-0000-000000000197'
  ),
  4,
  'their change log history stays connected'
);

-- A mid-month Section change.
select lives_ok(
  $$select public.change_staff_section(
    '00000000-0000-0000-0000-000000000198',
    '00000000-0000-0000-0000-000000000195',
    '2027-01-15'
  )$$,
  'the Manager moves a Staff member from a chosen date'
);

select results_eq(
  $$
    select section_id, effective_from::text, effective_through::text
    from public.staff_section_assignments
    where staff_member_id = '00000000-0000-0000-0000-000000000198'
    order by effective_from
  $$,
  $$values
    ('00000000-0000-0000-0000-000000000194'::uuid, '2027-01-01', '2027-01-14'),
    ('00000000-0000-0000-0000-000000000195'::uuid, '2027-01-15', null::text)$$,
  'the row moves to the new Section from that date'
);

select lives_ok(
  $$select public.change_staff_job_role(
    '00000000-0000-0000-0000-000000000198',
    'rn',
    '2027-01-15'
  )$$,
  'the Manager changes a role from a chosen date'
);

select results_eq(
  $$
    select kind, old_value, new_value, effective_from::text
    from public.staff_changes
    where staff_member_id = '00000000-0000-0000-0000-000000000198'
    order by changed_at
  $$,
  $$values
    ('section', 'Lifecycle day Section', 'Lifecycle night Section', '2027-01-15'),
    ('job_role', null, 'RN', '2027-01-15')$$,
  'Section and role changes are logged'
);

-- Staff members cannot read the Staff list change log.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000193","role":"authenticated"}',
  true
);

select is(
  (select count(*)::integer from public.staff_changes),
  0,
  'a Staff member cannot read the Staff list change log'
);

-- Access roles and Manager handover.
select throws_ok(
  $$select public.assign_administrator('00000000-0000-0000-0000-000000000198')$$,
  'Only the Manager can assign an administrator',
  'a Staff member cannot grant administrator access'
);

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000191","role":"authenticated"}', true);
select lives_ok(
  $$select public.assign_administrator('00000000-0000-0000-0000-000000000198')$$,
  'Manager grants administrator access'
);
select is((select role::text from public.staff_members
  where id = '00000000-0000-0000-0000-000000000198'), 'administrator',
  'grant changes the access role');
select results_eq(
  $$select old_value, new_value from public.staff_changes
    where staff_member_id = '00000000-0000-0000-0000-000000000198'
      and kind = 'access_role' order by changed_at$$,
  $$values ('staff_member', 'administrator')$$,
  'the grant is logged and visible'
);

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000193","role":"authenticated"}', true);
select ok(public.can_manage_staff(), 'administrator can manage the Staff list');
select lives_ok(
  $$select public.update_staff_contact('00000000-0000-0000-0000-000000000198',
    'Moving Staff member', '5551234567')$$,
  'administrator can use a Staff list management function'
);
select lives_ok(
  $$select public.assign_administrator('00000000-0000-0000-0000-000000000197')$$,
  'administrator can grant administrator access'
);
select lives_ok(
  $$select public.remove_administrator('00000000-0000-0000-0000-000000000197')$$,
  'administrator can revoke administrator access'
);
select throws_ok(
  $$select public.set_staff_last_day('00000000-0000-0000-0000-000000000196', current_date)$$,
  'The unit needs an active Manager',
  'administrator cannot deactivate the final Manager'
);

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000191","role":"authenticated"}', true);
select lives_ok(
  $$select public.remove_administrator('00000000-0000-0000-0000-000000000198')$$,
  'Manager revokes administrator access'
);
select is((select role::text from public.staff_members
  where id = '00000000-0000-0000-0000-000000000198'), 'staff_member',
  'revocation restores Staff member access');
select results_eq(
  $$select old_value, new_value from public.staff_changes
    where staff_member_id = '00000000-0000-0000-0000-000000000198'
      and kind = 'access_role' order by changed_at$$,
  $$values ('staff_member', 'administrator'), ('administrator', 'staff_member')$$,
  'the revocation is logged'
);
select lives_ok(
  $$select public.transfer_manager('00000000-0000-0000-0000-000000000198')$$,
  'Manager transfers the role in one call'
);
select is((select role::text from public.staff_members
  where id = '00000000-0000-0000-0000-000000000198'), 'manager',
  'the recipient is Manager');
select is((select role::text from public.staff_members
  where id = '00000000-0000-0000-0000-000000000196'), 'administrator',
  'the former Manager is administrator');
select results_eq(
  $$select staff_member_id, old_value, new_value from public.staff_changes
    where kind = 'access_role' and new_value in ('manager', 'administrator')
    order by changed_at desc limit 2$$,
  $$values
    ('00000000-0000-0000-0000-000000000196'::uuid, 'manager', 'administrator'),
    ('00000000-0000-0000-0000-000000000198'::uuid, 'staff_member', 'manager')$$,
  'both sides of the handover are logged'
);
select lives_ok(
  $$select public.assign_administrator('00000000-0000-0000-0000-000000000197')$$,
  'former Manager as Administrator can grant administrator access'
);

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000193","role":"authenticated"}', true);
select lives_ok(
  $$select public.remove_administrator('00000000-0000-0000-0000-000000000196')$$,
  'new Manager can revoke former Manager administrator access'
);
select is((select count(*)::integer from public.staff_members
  where active and role = 'manager'), 1, 'one active Manager remains');

select * from finish();
rollback;
