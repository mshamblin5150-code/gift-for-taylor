begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000002161', 'coverage-manager@example.test'),
  ('00000000-0000-0000-0000-000000002162', 'coverage-cna@example.test');
insert into public.sections(id, name, display_order) values
  ('00000000-0000-0000-0000-000000002163', 'Coverage section', 216);
insert into public.staff_members(id, display_name, role) values
  ('00000000-0000-0000-0000-000000002161', 'Coverage Manager', 'manager'),
  ('00000000-0000-0000-0000-000000002162', 'Coverage CNA', 'staff_member');
insert into public.staff_accounts(staff_member_id, auth_user_id,
  personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000002161',
    '00000000-0000-0000-0000-000000002161', 'coverage-manager@example.test', now()),
  ('00000000-0000-0000-0000-000000002162',
    '00000000-0000-0000-0000-000000002162', 'coverage-cna@example.test', now());
insert into public.staff_section_assignments(staff_member_id, section_id,
  display_order, effective_from) values
  ('00000000-0000-0000-0000-000000002162',
    '00000000-0000-0000-0000-000000002163', 1, current_date);
insert into public.staff_job_roles(staff_member_id, job_role, effective_from)
values ('00000000-0000-0000-0000-000000002162', 'cna', current_date);

create temporary table test_date as select
  date_trunc('month', current_date + interval '1 month')::date as month_start;
grant select on test_date to authenticated;
insert into public.schedule_months(month_start, release_state, released_at,
  released_by_staff_member_id)
select month_start, 'released', now(),
  '00000000-0000-0000-0000-000000002161' from test_date;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000002161","role":"authenticated"}', true);

create temporary table first_preview as
select public.preview_coverage_weekday_rule('cna', 'day',
  extract(dow from (select month_start from test_date))::integer,
  current_date, 1, null, 0) as plan;
select ok(jsonb_array_length((select plan from first_preview)) between 4 and 5,
  'preview lists only the affected weekday dates');
select is((select count(*)::integer from public.short_shifts
  where reason = 'rule_change'), 0, 'preview does not post');
select is((select count(*)::integer from public.coverage_rule_audit), 0,
  'preview rolls back its audit row');

select lives_ok($$
  select public.commit_coverage_weekday_rule('cna', 'day',
    extract(dow from (select month_start from test_date))::integer,
    current_date, 1, null, 0,
    (select plan from first_preview),
    (select jsonb_agg(jsonb_build_object(
      'work_date', item->>'work_date', 'pool', item->>'pool',
      'window', item->>'window', 'ordinary_role', 'cna',
      'ordinary_shift_code', '7A'))
      from jsonb_array_elements((select plan from first_preview)) item))
$$, 'confirmed rule edit posts its reviewed batch');
select is((select count(*)::integer from public.short_shifts
  where reason = 'rule_change'),
  jsonb_array_length((select plan from first_preview)),
  'one new Open shift per affected date');
set local role postgres;
select is((select count(*)::integer from public.staff_notices
  where kind = 'open_shift_batch' and staff_member_id =
    '00000000-0000-0000-0000-000000002162'), 1,
  'eligible Staff member gets one batch summary');
select is((select count(*)::integer from public.staff_notices
  where kind = 'open_shift_posted'), 0,
  'batch posting suppresses per-shift notices');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000002162","role":"authenticated"}', true);
select is((select (public.request_open_shift_pickup(
    (select id from public.short_shifts where reason = 'rule_change'
      order by work_date offset 1 limit 1))).status), 'pending',
  'eligible Staff member can request a rule-created Open shift');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000002161","role":"authenticated"}', true);
set local role postgres;
update public.short_shifts set filled_at = now()
where id = (select id from public.short_shifts where reason = 'rule_change'
  order by work_date limit 1);
set local role authenticated;
select is((select count(*)::integer from public.short_shifts
  where reason = 'rule_change' and filled_at is not null), 1,
  'one previously filled rule-created shift is protected');

create temporary table second_preview as
select public.preview_coverage_weekday_rule('cna', 'day',
  extract(dow from (select month_start from test_date))::integer,
  current_date, 0, null, 0) as plan;
select ok((select bool_and((item->>'withdraw_ordinary')::integer = 1)
  from jsonb_array_elements((select plan from second_preview)) item),
  'lower minimum previews safe withdrawals');
select lives_ok($$
  select public.commit_coverage_weekday_rule('cna', 'day',
    extract(dow from (select month_start from test_date))::integer,
    current_date, 0, null, 0, (select plan from second_preview), '[]'::jsonb)
$$, 'confirmed lower minimum withdraws rule-created Open shifts');
select is((select count(*)::integer from public.short_shifts
  where reason = 'rule_change' and filled_at is null), 0,
  'no rule-created Open shifts remain');
select is((select count(*)::integer from public.short_shifts
  where reason = 'rule_change' and filled_at is not null), 1,
  'filled Open shift remains after a lower minimum');
set local role postgres;
select is((select count(*)::integer from public.staff_notices
  where staff_member_id = '00000000-0000-0000-0000-000000002162'
    and title = 'Open shift withdrawn'), 1,
  'pending applicant is informed of withdrawal');

select * from finish();
rollback;
