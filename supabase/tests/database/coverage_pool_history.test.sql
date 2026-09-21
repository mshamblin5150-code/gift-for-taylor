begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000002166', 'pool-manager@example.test'),
  ('00000000-0000-0000-0000-000000002167', 'pool-lpn@example.test');
insert into public.sections(id, name, display_order) values
  ('00000000-0000-0000-0000-000000002168', 'Pool section', 216);
insert into public.staff_members(id, display_name, role) values
  ('00000000-0000-0000-0000-000000002166', 'Pool Manager', 'manager'),
  ('00000000-0000-0000-0000-000000002167', 'Pool LPN', 'staff_member');
insert into public.staff_accounts(staff_member_id, auth_user_id,
  personal_email, accepted_invite_at) values
  ('00000000-0000-0000-0000-000000002166',
   '00000000-0000-0000-0000-000000002166', 'pool-manager@example.test', now()),
  ('00000000-0000-0000-0000-000000002167',
   '00000000-0000-0000-0000-000000002167', 'pool-lpn@example.test', now());
insert into public.staff_section_assignments(staff_member_id, section_id,
  display_order, effective_from) values
  ('00000000-0000-0000-0000-000000002167',
   '00000000-0000-0000-0000-000000002168', 1, current_date);
insert into public.staff_job_roles(staff_member_id, job_role, effective_from)
values ('00000000-0000-0000-0000-000000002167', 'lpn', current_date);
create temporary table test_date as select
  date_trunc('month', current_date + interval '1 month')::date as month_start;
insert into public.schedule_months(month_start, release_state, released_at,
  released_by_staff_member_id)
select month_start, 'released', now(),
  '00000000-0000-0000-0000-000000002166' from test_date;
insert into public.short_shifts(schedule_month_id, work_date, shift_code,
  reason, job_role)
select month.id, month.month_start + 1, '7A', 'manual', 'rn'
from public.schedule_months month where month.month_start =
  (select month_start from test_date);
grant select on test_date to authenticated;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000002166","role":"authenticated"}', true);

select is(public.coverage_pool_on('lpn', current_date), 'nurses',
  'seeded LPN membership is Nurses');
select is((public.coverage_pool_version_on('nurses', current_date)).name,
  'Nurses', 'seeded name is historical');
select is(public.preview_coverage_pools(current_date + 1,
  '[{"id":"nurses","name":"Registered nurses","sort_order":1,"retired":false,"floor_role":"rn"},
    {"id":"cna","name":"CNAs","sort_order":2,"retired":false},
    {"id":"unit_clerk","name":"Unit clerks","sort_order":3,"retired":false},
    {"id":"lpn_team","name":"LPN team","sort_order":0,"retired":false}]'::jsonb,
  '[{"job_role":"rn","pool":"nurses"},{"job_role":"lpn","pool":"lpn_team"},
    {"job_role":"cna","pool":"cna"},{"job_role":"unit_clerk","pool":"unit_clerk"}]'::jsonb),
  '[]'::jsonb, 'unreleased months need no Open shift batch');
select is(public.coverage_pool_on('lpn', current_date + 1), 'nurses',
  'preview leaves membership unchanged');

select lives_ok($$
  select public.commit_coverage_pools(current_date + 1,
    '[{"id":"nurses","name":"Registered nurses","sort_order":1,"retired":false,"floor_role":"rn"},
      {"id":"cna","name":"CNAs","sort_order":2,"retired":false},
      {"id":"unit_clerk","name":"Unit clerks","sort_order":3,"retired":false},
      {"id":"lpn_team","name":"LPN team","sort_order":0,"retired":false}]'::jsonb,
    '[{"job_role":"rn","pool":"nurses"},{"job_role":"lpn","pool":"lpn_team"},
      {"job_role":"cna","pool":"cna"},{"job_role":"unit_clerk","pool":"unit_clerk"}]'::jsonb,
    '[]'::jsonb, '[]'::jsonb)
$$, 'confirmed pool configuration saves atomically');
select is(public.coverage_pool_on('lpn', current_date), 'nurses',
  'past membership remains Nurses');
select is(public.coverage_pool_on('lpn', current_date + 1), 'lpn_team',
  'new membership applies on its date');
select is((select before_value->'memberships'->>'lpn'
  from public.coverage_rule_audit where action = 'coverage_pools'
  order by changed_at desc limit 1), 'nurses',
  'pool audit records previous membership');
select is((select after_value->'memberships'->>'lpn'
  from public.coverage_rule_audit where action = 'coverage_pools'
  order by changed_at desc limit 1), 'lpn_team',
  'pool audit records new membership');
select is((public.coverage_pool_version_on('nurses', current_date)).name,
  'Nurses', 'past pool name is retained');
select is((public.coverage_pool_version_on('nurses', current_date + 1)).name,
  'Registered nurses', 'new pool name applies on its date');
select is(public.coverage_pool_on('lpn',
  (select month_start + 1 from test_date)), 'lpn_team',
  'LPN belongs to the new Coverage pool on the Open shift date');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000002167","role":"authenticated"}', true);
select lives_ok($$
  select public.request_open_shift_pickup((select id from public.short_shifts
    where reason = 'manual' limit 1))
$$, 'LPN can still request an RN Open shift after coverage membership moves');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000002166","role":"authenticated"}', true);
select throws_ok($$
  select public.commit_coverage_pools(current_date + 2,
    '[{"id":"nurses","name":"Nurses","sort_order":0,"retired":true,"floor_role":"rn"},
      {"id":"cna","name":"CNAs","sort_order":1,"retired":false},
      {"id":"unit_clerk","name":"Unit clerks","sort_order":2,"retired":false},
      {"id":"lpn_team","name":"LPN team","sort_order":3,"retired":false}]'::jsonb,
    '[{"job_role":"rn","pool":"nurses"},{"job_role":"lpn","pool":"lpn_team"},
      {"job_role":"cna","pool":"cna"},{"job_role":"unit_clerk","pool":"unit_clerk"}]'::jsonb,
    '[]'::jsonb, '[]'::jsonb)
$$, 'Every Job role needs one active pool; floors must belong to their pool',
  'cannot retire a pool while its Job role remains');

select throws_ok($$
  select public.commit_coverage_pools(current_date + 2,
    '[{"id":"nurses","name":"Registered nurses","sort_order":1,"retired":false,"floor_role":"rn"},
      {"id":"cna","name":"CNAs","sort_order":2,"retired":false},
      {"id":"unit_clerk","name":"Unit clerks","sort_order":3,"retired":false},
      {"id":"lpn_team","name":"LPN team","sort_order":0,"retired":false},
      {"id":"empty","name":"Empty","sort_order":4,"retired":false}]'::jsonb,
    '[{"job_role":"rn","pool":"nurses"},{"job_role":"lpn","pool":"lpn_team"},
      {"job_role":"cna","pool":"cna"},{"job_role":"unit_clerk","pool":"unit_clerk"}]'::jsonb,
    '[]'::jsonb, '[]'::jsonb)
$$, 'Every Job role needs one active pool; floors must belong to their pool',
  'active Coverage pools must contain a Job role');

reset role;
update public.coverage_pool_versions set floor_role = 'lpn'
where pool = 'lpn_team' and effective_from = current_date + 1;
insert into public.pool_weekday_minimums(pool, coverage_window, weekday,
  effective_from, minimum, rn_floor, floor_role)
values ('lpn_team', 'day', 1, current_date + 4, 1, 1, 'lpn');
set local role authenticated;
select throws_ok($$
  select public.commit_coverage_pools(current_date + 2,
    '[{"id":"nurses","name":"Registered nurses","sort_order":1,"retired":false,"floor_role":"rn"},
      {"id":"cna","name":"CNAs","sort_order":2,"retired":false},
      {"id":"unit_clerk","name":"Unit clerks","sort_order":3,"retired":false},
      {"id":"lpn_team","name":"LPN team","sort_order":0,"retired":false}]'::jsonb,
    '[{"job_role":"rn","pool":"nurses"},{"job_role":"lpn","pool":"lpn_team"},
      {"job_role":"cna","pool":"cna"},{"job_role":"unit_clerk","pool":"unit_clerk"}]'::jsonb,
    '[]'::jsonb, '[]'::jsonb)
$$, 'Move or clear affected Staffing minimum floors before changing pools',
  'a future weekday floor blocks an incompatible earlier pool edit');

select * from finish();
rollback;
