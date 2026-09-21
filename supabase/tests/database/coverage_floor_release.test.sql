begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000002171', 'floor-manager@example.test');
insert into public.staff_members(id, display_name, role) values
  ('00000000-0000-0000-0000-000000002171', 'Floor Manager', 'manager');
insert into public.staff_accounts(staff_member_id, auth_user_id,
  personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000002171',
   '00000000-0000-0000-0000-000000002171', 'floor-manager@example.test', now());
create temporary table test_dates as select
  date_trunc('month', current_date + interval '1 month')::date as released_month,
  date_trunc('month', current_date + interval '2 months')::date as draft_month;
grant select on test_dates to authenticated;
insert into public.schedule_months(month_start, release_state, released_at,
  released_by_staff_member_id)
select released_month, 'released', now(),
  '00000000-0000-0000-0000-000000002171' from test_dates;
insert into public.schedule_months(month_start, release_state)
select draft_month, 'unpublished' from test_dates;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000002171","role":"authenticated"}', true);
select public.set_open_shift_approval_default(false);
select throws_ok($$
  select public.preview_coverage_weekday_rule('nurses', 'day', 0,
    current_date - 1, 3, 'rn', 2)
$$, 'Invalid effective-dated Staffing minimum or floor',
  'standing rule cannot start in the past');
create temporary table floor_preview as
select public.preview_coverage_weekday_rule('nurses', 'day',
  extract(dow from (select released_month from test_dates))::integer,
  current_date, 3, 'rn', 2) as plan;
select ok(jsonb_array_length((select plan from floor_preview)) between 4 and 5,
  'released weekdays appear in the preview');
select ok((select bool_and(item->>'floor_role' = 'rn' and
  (item->>'post_floor')::integer = 1 and
  (item->>'post_ordinary')::integer = 0)
  from jsonb_array_elements((select plan from floor_preview)) item),
  'preview identifies only the newly needed RN floor shifts');
select is((select count(*)::integer from public.short_shifts
  where reason = 'rule_change'), 0,
  'preview does not post on either month');
select lives_ok($$
  select public.commit_coverage_weekday_rule('nurses', 'day',
    extract(dow from (select released_month from test_dates))::integer,
    current_date, 3, 'rn', 2, (select plan from floor_preview),
    (select jsonb_agg(jsonb_build_object(
      'work_date', item->>'work_date', 'pool', item->>'pool',
      'window', item->>'window', 'floor_role', 'rn',
      'floor_shift_code', '7A'))
      from jsonb_array_elements((select plan from floor_preview)) item))
$$, 'Manager confirms the floor-critical batch');
select ok((select bool_and(requires_approval and rn_floor_critical
    and job_role = 'rn') from public.short_shifts where reason = 'rule_change'),
  'floor-critical shifts require approval despite self-service default');
select is((select count(*)::integer from public.short_shifts shift
  join public.schedule_months month on month.id = shift.schedule_month_id
  where month.month_start = (select draft_month from test_dates)), 0,
  'rule edit does not post Open shifts in an unpublished month');
select throws_ok($$
  select public.release_month_checked(
    (select draft_month from test_dates), false)
$$, 'Review and acknowledge the short days before Month release',
  'short Month release requires acknowledgement');
select lives_ok($$
  select public.release_month_checked(
    (select draft_month from test_dates), true)
$$, 'Manager can release a short month after acknowledgement');

select * from finish();
rollback;
