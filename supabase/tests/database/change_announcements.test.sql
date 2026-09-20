begin;

create extension if not exists pgtap with schema extensions;
select plan(29);

insert into auth.users (id, email)
values
  ('00000000-0000-0000-0000-000000000181', 'manager@example.test'),
  ('00000000-0000-0000-0000-000000000182', 'staff@example.test'),
  ('00000000-0000-0000-0000-000000000183', 'scheduler@example.test');

insert into public.sections (id, name, display_order)
values
  ('00000000-0000-0000-0000-000000000184', 'Announcing day Section', 94),
  ('00000000-0000-0000-0000-000000000190', 'Announcing night Section', 95);

insert into public.staff_members (id, display_name, role, cell_number)
values
  ('00000000-0000-0000-0000-000000000185', 'Test Manager', 'manager', null),
  (
    '00000000-0000-0000-0000-000000000186',
    'Test day RN',
    'staff_member',
    '5550100'
  ),
  (
    '00000000-0000-0000-0000-000000000187',
    'Test Night scheduler',
    'staff_member',
    '5550101'
  );

insert into public.staff_accounts (
  staff_member_id,
  auth_user_id,
  personal_email,
  accepted_invite_at
)
values
  (
    '00000000-0000-0000-0000-000000000185',
    '00000000-0000-0000-0000-000000000181',
    'manager@example.test',
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000186',
    '00000000-0000-0000-0000-000000000182',
    'staff@example.test',
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000187',
    '00000000-0000-0000-0000-000000000183',
    'scheduler@example.test',
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
    '00000000-0000-0000-0000-000000000186',
    '00000000-0000-0000-0000-000000000184',
    0,
    '2027-01-01'
  ),
  (
    '00000000-0000-0000-0000-000000000187',
    '00000000-0000-0000-0000-000000000190',
    0,
    '2027-01-01'
  );

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000181","role":"authenticated"}',
  true
);

select public.assign_night_scheduler(
  '00000000-0000-0000-0000-000000000187',
  array['00000000-0000-0000-0000-000000000190']::uuid[]
);

select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000186',
  '00000000-0000-0000-0000-000000000184',
  '2027-04-05',
  '7A'
);
select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000186',
  '00000000-0000-0000-0000-000000000184',
  '2027-04-06',
  'N'
);
select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000187',
  '00000000-0000-0000-0000-000000000190',
  '2027-04-07',
  '7P'
);

select results_eq(
  $$
    select display_name, cell_number
    from public.schedule_rows('2027-04-01')
    where section_id in (
      '00000000-0000-0000-0000-000000000184',
      '00000000-0000-0000-0000-000000000190'
    )
  $$,
  $$
    values
      ('Test day RN'::text, '+15550100'::text),
      ('Test Night scheduler'::text, '+15550101'::text)
  $$,
  'schedule rows carry the cell number announcements are texted to'
);

create temporary table april_changes on commit drop as
select id, work_date
from public.schedule_changes
where work_date between '2027-04-05' and '2027-04-07';

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000182","role":"authenticated"}',
  true
);

select throws_ok(
  $$
    select public.mark_changes_announced(
      array(select id from april_changes), '{}'::uuid[])
  $$,
  'Only a scheduler can announce changes',
  'a Staff member cannot mark changes announced'
);

-- The Night scheduler announces only the changes in their Sections.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000183","role":"authenticated"}',
  true
);

select lives_ok(
  $$
    select public.mark_changes_announced(
      array(select id from april_changes), '{}'::uuid[])
  $$,
  'the Night scheduler marks the changes they texted announced'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000181","role":"authenticated"}',
  true
);

select results_eq(
  $$
    select work_date, announced_at is not null
    from public.schedule_changes
    where id in (select id from april_changes)
    order by work_date
  $$,
  $$
    values
      ('2027-04-05'::date, false),
      ('2027-04-06'::date, false),
      ('2027-04-07'::date, true)
  $$,
  'a Night scheduler cannot announce changes outside their Sections'
);

select lives_ok(
  $$
    select public.mark_changes_announced(
      array(select id from april_changes where work_date = '2027-04-05'),
      '{}'::uuid[]
    )
  $$,
  'the Manager marks the changes she texted announced'
);

select isnt(
  (
    select announced_at
    from public.schedule_changes
    where work_date = '2027-04-05'
  ),
  null,
  'the texted change is announced'
);

select is(
  (
    select announced_at
    from public.schedule_changes
    where work_date = '2027-04-06'
  ),
  null,
  'a change not in the announcement stays unannounced'
);

-- Make the month live so notice creation and Reach can be tested together.
set local role postgres;
insert into public.staff_members (id, display_name, role, cell_number)
values ('00000000-0000-0000-0000-000000000188', 'No number RN',
  'staff_member', null);
insert into public.staff_section_assignments (
  staff_member_id, section_id, display_order, effective_from
) values ('00000000-0000-0000-0000-000000000188',
  '00000000-0000-0000-0000-000000000184', 1, '2027-01-01');
set local role authenticated;

select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000188',
  '00000000-0000-0000-0000-000000000184', '2027-04-12', '7A');
select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000188',
  '00000000-0000-0000-0000-000000000184', '2027-04-15', '7A');
select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000188',
  '00000000-0000-0000-0000-000000000184', '2027-04-15', '');
select public.mark_changes_announced(
  array(select id from public.schedule_changes
    where work_date = '2027-04-15'), '{}'::uuid[]);
select public.release_month('2027-04-01');
select is((select count(*)::integer from public.schedule_changes
  where work_date = '2027-04-15' and moot_at is not null
    and announced_at is null), 2,
  'release leaves already-moot draft edits terminal');

set local role postgres;
insert into public.push_subscriptions (endpoint, staff_member_id, subscription)
values ('https://push.example.test/reach',
  '00000000-0000-0000-0000-000000000186',
  '{"endpoint":"https://push.example.test/reach","keys":{}}');
set local role authenticated;

select results_eq(
  $$select display_name, has_push_subscription
    from public.schedule_rows('2027-04-01')
    where staff_member_id in (
      '00000000-0000-0000-0000-000000000186',
      '00000000-0000-0000-0000-000000000188'
    ) order by display_name$$,
  $$values ('No number RN'::text, false), ('Test day RN'::text, true)$$,
  'the announce sheet sees a live subscription separately from cell number'
);
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000182","role":"authenticated"}', true);
select is((select has_push_subscription from public.schedule_rows('2027-04-01')
  where staff_member_id = '00000000-0000-0000-0000-000000000186'), false,
  'a Staff member cannot read another person''s notification reachability');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000181","role":"authenticated"}', true);

select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000186',
  '00000000-0000-0000-0000-000000000184', '2027-04-08', '7A');
select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000187',
  '00000000-0000-0000-0000-000000000190', '2027-04-09', '7P');
select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000187',
  '00000000-0000-0000-0000-000000000190', '2027-04-10', '7P');
select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000188',
  '00000000-0000-0000-0000-000000000184', '2027-04-11', '7A');
select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000188',
  '00000000-0000-0000-0000-000000000184', '2027-04-12', '16D');
select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000188',
  '00000000-0000-0000-0000-000000000184', '2027-04-12', '7A');

select public.mark_changes_announced(
  array(select id from public.schedule_changes
    where work_date between '2027-04-08' and '2027-04-12'),
  array['00000000-0000-0000-0000-000000000186',
        '00000000-0000-0000-0000-000000000187',
        '00000000-0000-0000-0000-000000000188']::uuid[]
);

select is((select reach from public.schedule_changes
  where work_date = '2027-04-08'), 'notified',
  'a live subscription takes precedence over draft evidence');
select is((select reach from public.schedule_changes
  where work_date = '2027-04-09'), 'draft_opened',
  'a numbered person with an opened draft is stamped draft_opened');
select is((select reach from public.schedule_changes
  where work_date = '2027-04-10'), 'draft_opened',
  'draft evidence applies to every changed day for that person in the batch');
select is((select reach from public.schedule_changes
  where work_date = '2027-04-11'), 'nobody',
  'a person with no number is nobody even when draft evidence is supplied');
select is((select count(*)::integer from public.schedule_changes
  where work_date = '2027-04-12' and moot_at is not null
    and announced_at is null and reach is null), 2,
  'both reverted edits are stamped moot without Reach');
set local role postgres;
select is((select count(*)::integer from public.staff_notices
  where kind = 'schedule_change' and staff_member_id =
    '00000000-0000-0000-0000-000000000188'), 1,
  'the reverted cell adds no notice for the person with a separate real change');
delete from public.push_subscriptions
where endpoint = 'https://push.example.test/reach';
set local role authenticated;
select is((select reach from public.schedule_changes
  where work_date = '2027-04-08'), 'notified',
  'Reach stays frozen after the subscription is removed');
select is((select count(*)::integer from public.schedule_changes
  where work_date between '2027-04-08' and '2027-04-12'
    and announced_at is null and moot_at is null), 0,
  'the batch leaves no pending rows');

select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000187',
  '00000000-0000-0000-0000-000000000190', '2027-04-13', '7P');
select public.mark_changes_announced(
  array(select id from public.schedule_changes
    where work_date = '2027-04-13'), '{}'::uuid[]);
select is((select reach from public.schedule_changes
  where work_date = '2027-04-13'), 'nobody',
  'a numbered person without a subscription or opened draft is stamped nobody');

select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000187',
  '00000000-0000-0000-0000-000000000190', '2027-04-14', '7P');
create temporary table first_read on commit drop as
select id from public.schedule_changes where work_date = '2027-04-14';
select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000187',
  '00000000-0000-0000-0000-000000000190', '2027-04-14', '16D');
select public.mark_changes_announced(array(select id from first_read), '{}'::uuid[]);
select is((select count(*)::integer from public.schedule_changes
  where work_date = '2027-04-14' and announced_at is null and moot_at is null), 2,
  'a newer edit to the same cell keeps the older tray snapshot pending');
select public.mark_changes_announced(array(select id from public.schedule_changes
  where work_date = '2027-04-14'), '{}'::uuid[]);
select is((select count(*)::integer from public.schedule_changes
  where work_date = '2027-04-14' and announced_at is not null
    and reach = 'nobody'), 2,
  'a refreshed batch settles both edits against their shared baseline');

-- A live cell's edits net against the last announced code, independently by day.
select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000187',
  '00000000-0000-0000-0000-000000000190', '2027-04-20', '7P');
select public.mark_changes_announced(array(select id from public.schedule_changes
  where work_date = '2027-04-20'), '{}'::uuid[]);
set local role postgres;
create temporary table notice_count_before_reversal on commit drop as
select count(*)::integer as notices from public.staff_notices
where kind = 'schedule_change'
  and staff_member_id = '00000000-0000-0000-0000-000000000187';
set local role authenticated;

select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000187',
  '00000000-0000-0000-0000-000000000190', '2027-04-20', 'C/I');
select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000187',
  '00000000-0000-0000-0000-000000000190', '2027-04-20', 'X');
select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000187',
  '00000000-0000-0000-0000-000000000190', '2027-04-20', '7P');
select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000187',
  '00000000-0000-0000-0000-000000000190', '2027-04-21', 'X');
select public.mark_changes_announced(array(select id from public.schedule_changes
  where work_date = '2027-04-20'), '{}'::uuid[]);
select is((select count(*)::integer from public.schedule_changes
  where work_date = '2027-04-20' and moot_at is not null
    and announced_at is null and reach is null), 3,
  'all three unannounced steps back to 7P are moot');
set local role postgres;
select is((select count(*)::integer from public.staff_notices
  where kind = 'schedule_change'
    and staff_member_id = '00000000-0000-0000-0000-000000000187'),
  (select notices from notice_count_before_reversal),
  'a fully reversed cell sends no notice');
set local role authenticated;
select is((select count(*)::integer from public.schedule_changes
  where work_date = '2027-04-21' and announced_at is null and moot_at is null), 1,
  'a different day for the same person stays pending');
select public.mark_changes_announced(array(select id from public.schedule_changes
  where work_date = '2027-04-21'), '{}'::uuid[]);
select is((select count(*)::integer from public.schedule_changes
  where work_date = '2027-04-21' and announced_at is not null), 1,
  'the unrelated day can be announced separately');

select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000187',
  '00000000-0000-0000-0000-000000000190', '2027-04-20', 'C/I');
select public.mark_changes_announced(array(select id from public.schedule_changes
  where work_date = '2027-04-20' and announced_at is null and moot_at is null),
  '{}'::uuid[]);
select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000187',
  '00000000-0000-0000-0000-000000000190', '2027-04-20', '7P');
select public.mark_changes_announced(array(select id from public.schedule_changes
  where work_date = '2027-04-20' and announced_at is null and moot_at is null),
  '{}'::uuid[]);
select is((select count(*)::integer from public.schedule_changes
  where work_date = '2027-04-20' and announced_at is not null
    and moot_at is null), 3,
  'an announced call-in and its later reversal remain announced');
select is((select count(*)::integer from public.schedule_changes
  where work_date = '2027-04-20' and announced_at is not null
    and reach = 'nobody'), 3,
  'Reach for each announced change remains stamped');
set local role postgres;
select is((select count(*)::integer from public.staff_notices
  where kind = 'schedule_change'
    and staff_member_id = '00000000-0000-0000-0000-000000000187'),
  (select notices + 3 from notice_count_before_reversal),
  'the unrelated day and both post-announcement edits send notices');
set local role authenticated;

select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000188',
  '00000000-0000-0000-0000-000000000184', '2027-05-01', '7A');
select public.save_schedule_cell(
  '00000000-0000-0000-0000-000000000188',
  '00000000-0000-0000-0000-000000000184', '2027-05-01', '');
set local role postgres;
update public.schedule_months set loaded_from_page_at = now()
where month_start = '2027-05-01';
set local role authenticated;
select public.mark_changes_announced(
  array(select id from public.schedule_changes
    where work_date = '2027-05-01'), '{}'::uuid[]);
select public.confirm_loaded_month('2027-05-01');
select is((select count(*)::integer from public.schedule_changes
  where work_date = '2027-05-01' and moot_at is not null
    and announced_at is null), 2,
  'confirmation leaves already-moot loaded-month edits terminal');

select * from finish();
rollback;
