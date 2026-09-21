-- Pool identities are stable; their names, order and Job role membership are
-- resolved on the work date. Seed history before the first Schedule date.
create table public.coverage_pools (
  id text primary key check (id ~ '^[a-z][a-z0-9_]{0,39}$'),
  created_on date not null default current_date
);
create table public.coverage_pool_versions (
  pool text not null references public.coverage_pools(id),
  effective_from date not null,
  name text not null check (length(trim(name)) between 1 and 60),
  sort_order integer not null,
  retired boolean not null default false,
  floor_role public.job_role,
  primary key (pool, effective_from)
);
create table public.coverage_pool_memberships (
  job_role public.job_role not null,
  effective_from date not null,
  pool text not null references public.coverage_pools(id),
  primary key (job_role, effective_from)
);
insert into public.coverage_pools(id, created_on) values
  ('nurses', '0001-01-01'), ('cna', '0001-01-01'), ('unit_clerk', '0001-01-01');
insert into public.coverage_pool_versions(pool, effective_from, name, sort_order, floor_role)
values ('nurses', '0001-01-01', 'Nurses', 0, 'rn'),
  ('cna', '0001-01-01', 'CNAs', 1, null),
  ('unit_clerk', '0001-01-01', 'Unit clerks', 2, null);
insert into public.coverage_pool_memberships(job_role, effective_from, pool)
values ('rn', '0001-01-01', 'nurses'), ('lpn', '0001-01-01', 'nurses'),
  ('cna', '0001-01-01', 'cna'), ('unit_clerk', '0001-01-01', 'unit_clerk');

alter table public.coverage_pools enable row level security;
alter table public.coverage_pool_versions enable row level security;
alter table public.coverage_pool_memberships enable row level security;
grant select on public.coverage_pools, public.coverage_pool_versions,
  public.coverage_pool_memberships to authenticated;
create policy "staff read coverage pools" on public.coverage_pools
  for select using (public.is_active_staff_member());
create policy "staff read pool versions" on public.coverage_pool_versions
  for select using (public.is_active_staff_member());
create policy "staff read pool memberships" on public.coverage_pool_memberships
  for select using (public.is_active_staff_member());

create function public.coverage_pool_on(p_role public.job_role, p_date date)
returns text language sql stable security definer set search_path = '' as $$
  select membership.pool from public.coverage_pool_memberships membership
  where membership.job_role = p_role and membership.effective_from <= p_date
  order by membership.effective_from desc limit 1;
$$;
create function public.coverage_pool_version_on(p_pool text, p_date date)
returns public.coverage_pool_versions language sql stable security definer
set search_path = '' as $$
  select version from public.coverage_pool_versions version
  where version.pool = p_pool and version.effective_from <= p_date
  order by version.effective_from desc limit 1;
$$;
revoke all on function public.coverage_pool_on(public.job_role, date),
  public.coverage_pool_version_on(text, date) from public;
grant execute on function public.coverage_pool_on(public.job_role, date),
  public.coverage_pool_version_on(text, date) to authenticated;

-- Existing weekday rules start at the beginning of time. A new version only
-- changes dates at or after its effective date.
alter table public.pool_weekday_minimums drop constraint pool_weekday_minimums_pkey;
alter table public.pool_weekday_minimums add column effective_from date not null
  default '0001-01-01';
alter table public.pool_weekday_minimums add column floor_role public.job_role;
update public.pool_weekday_minimums set floor_role = 'rn' where pool = 'nurses';
alter table public.pool_weekday_minimums add constraint pool_weekday_minimums_pkey
  primary key (pool, coverage_window, weekday, effective_from);
alter table public.pool_weekday_minimums drop constraint pool_weekday_minimums_pool_check;
alter table public.pool_weekday_minimums drop constraint pool_weekday_minimums_check;
alter table public.pool_weekday_minimums add constraint weekday_floor_valid
  check ((floor_role is null and rn_floor = 0) or
    (floor_role is not null and rn_floor between 0 and minimum));
alter table public.pool_date_minimums drop constraint pool_date_minimums_pool_check;
alter table public.pool_date_minimums drop constraint pool_date_minimums_check;
alter table public.pool_date_minimums add column floor_role public.job_role;
update public.pool_date_minimums set floor_role = 'rn' where pool = 'nurses';
alter table public.pool_date_minimums add constraint date_floor_valid
  check ((floor_role is null and rn_floor = 0) or
    (floor_role is not null and rn_floor between 0 and minimum));

create table public.coverage_rule_audit (
  id uuid primary key default gen_random_uuid(),
  actor uuid not null references public.staff_members(id),
  changed_at timestamptz not null default clock_timestamp(),
  effective_from date not null,
  action text not null,
  before_value jsonb,
  after_value jsonb
);
alter table public.coverage_rule_audit enable row level security;
grant select on public.coverage_rule_audit to authenticated;
create policy "unit editors read coverage history" on public.coverage_rule_audit
  for select using (public.current_staff_role() in ('manager', 'administrator'));

create function public.save_coverage_pools(p_effective_from date, p_pools jsonb,
  p_memberships jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_pool record;
  v_role record;
  v_before jsonb;
  v_current jsonb;
  v_count integer;
begin
  if public.current_staff_role() not in ('manager', 'administrator') then
    raise exception 'Only a Manager or Administrator can edit Coverage pools';
  end if;
  if p_effective_from is null or p_effective_from < current_date then
    raise exception 'Coverage pool changes cannot start before today';
  end if;
  if jsonb_typeof(p_pools) <> 'array' or
    jsonb_typeof(p_memberships) <> 'array' then
    raise exception 'A complete pool configuration is required';
  end if;
  perform pg_advisory_xact_lock(hashtext('coverage-pool-configuration'));
  select jsonb_agg(to_jsonb(version) order by version.sort_order)
    into v_before from public.coverage_pools pool
    cross join lateral public.coverage_pool_version_on(pool.id, p_effective_from) version;

  create temporary table if not exists next_pools (
    id text primary key, name text not null, sort_order integer not null,
    retired boolean not null, floor_role public.job_role
  ) on commit drop;
  truncate pg_temp.next_pools;
  insert into pg_temp.next_pools
  select item.id, trim(item.name), item.sort_order,
    coalesce(item.retired, false), item.floor_role
  from jsonb_to_recordset(p_pools) as item(id text, name text,
    sort_order integer, retired boolean, floor_role public.job_role);
  if (select count(*) from pg_temp.next_pools) <> jsonb_array_length(p_pools)
    or exists (select 1 from pg_temp.next_pools where id !~ '^[a-z][a-z0-9_]{0,39}$'
      or length(name) not between 1 and 60 or sort_order is null)
    or exists (select 1 from public.coverage_pools old
      where not exists (select 1 from pg_temp.next_pools next where next.id = old.id))
    or exists (select 1 from pg_temp.next_pools next
      where next.retired and not exists (select 1 from public.coverage_pools old
        where old.id = next.id))
    or exists (select 1 from pg_temp.next_pools next
      join pg_temp.next_pools other on other.id <> next.id
        and not other.retired and not next.retired
        and (other.sort_order = next.sort_order or
          lower(other.name) = lower(next.name))) then
    raise exception 'Invalid Coverage pool list';
  end if;
  create temporary table if not exists next_memberships (
    job_role public.job_role primary key, pool text not null
  ) on commit drop;
  truncate pg_temp.next_memberships;
  insert into pg_temp.next_memberships
  select item.job_role, item.pool from jsonb_to_recordset(p_memberships)
    as item(job_role public.job_role, pool text);
  select count(*) into v_count from pg_temp.next_memberships;
  if v_count <> 4 or v_count <> jsonb_array_length(p_memberships)
    or exists (select 1 from pg_temp.next_memberships member
      left join pg_temp.next_pools pool on pool.id = member.pool
      where pool.id is null or pool.retired)
    or exists (select 1 from pg_temp.next_pools pool where pool.floor_role is not null
      and not exists (select 1 from pg_temp.next_memberships member
        where member.pool = pool.id and member.job_role = pool.floor_role)) then
    raise exception 'Every Job role needs one active pool; floors must belong to their pool';
  end if;
  -- A moved or retired pool cannot carry a dated floor that would become invalid.
  if exists (select 1 from public.pool_weekday_minimums rule
    join pg_temp.next_pools pool on pool.id = rule.pool
    where rule.effective_from <= p_effective_from
      and rule.rn_floor > 0 and not pool.retired
      and pool.floor_role is distinct from rule.floor_role
      and not exists (select 1 from public.pool_weekday_minimums later
        where later.pool = rule.pool and later.coverage_window = rule.coverage_window
          and later.weekday = rule.weekday and later.effective_from > rule.effective_from
          and later.effective_from <= p_effective_from))
    or exists (select 1 from public.pool_date_minimums rule
      join pg_temp.next_pools pool on pool.id = rule.pool
      where rule.work_date >= p_effective_from and
        rule.rn_floor > 0 and not pool.retired and
          pool.floor_role is distinct from rule.floor_role) then
    raise exception 'Move or clear affected Staffing minimum floors before changing pools';
  end if;
  insert into public.coverage_pools(id, created_on)
  select id, p_effective_from from pg_temp.next_pools on conflict do nothing;
  insert into public.coverage_pool_versions(pool, effective_from, name,
    sort_order, retired, floor_role)
  select id, p_effective_from, name, sort_order, retired, floor_role
  from pg_temp.next_pools
  on conflict (pool, effective_from) do update set name = excluded.name,
    sort_order = excluded.sort_order, retired = excluded.retired,
    floor_role = excluded.floor_role;
  insert into public.coverage_pool_memberships(job_role, effective_from, pool)
  select job_role, p_effective_from, pool from pg_temp.next_memberships
  on conflict (job_role, effective_from) do update set pool = excluded.pool;
  select jsonb_agg(to_jsonb(next) order by next.sort_order) into v_current
  from pg_temp.next_pools next;
  insert into public.coverage_rule_audit(actor, effective_from, action,
    before_value, after_value)
  values (public.current_staff_member_id(), p_effective_from, 'coverage_pools',
    v_before, v_current);
end;
$$;
revoke all on function public.save_coverage_pools(date, jsonb, jsonb) from public;
grant execute on function public.save_coverage_pools(date, jsonb, jsonb)
  to authenticated;

create function public.coverage_floor_role_on(p_pool text, p_window text,
  p_date date)
returns public.job_role language sql stable security definer set search_path = '' as $$
  select (public.coverage_pool_version_on(p_pool, p_date)).floor_role;
$$;
revoke all on function public.coverage_floor_role_on(text, text, date) from public;
grant execute on function public.coverage_floor_role_on(text, text, date)
  to authenticated;

create or replace function public.section_staffing_for_month(p_month date)
returns table(pool text, coverage_window text, work_date date, minimum integer,
  rn_floor integer, working_count integer, rn_count integer, open_count integer,
  rn_open_count integer, shortfall integer, rn_shortfall integer,
  weekday_minimum integer, date_minimum integer)
language sql stable security definer set search_path = '' as $$
  with days as (
    select day.work_date::date from generate_series(date_trunc('month', p_month)::date,
      (date_trunc('month', p_month) + interval '1 month - 1 day')::date,
      interval '1 day') as day(work_date)
  ), keys as (
    select identity.id as pool, cov.coverage_window, days.work_date
    from public.coverage_pools identity
    cross join (values ('day'), ('night')) as cov(coverage_window)
    cross join days
    cross join lateral public.coverage_pool_version_on(identity.id, days.work_date) version
    where not version.retired
  ), working_roles as (
    select cell.work_date, public.coverage_pool_on(role.job_role, cell.work_date) as pool,
      code.coverage_window, role.job_role, count(*)::integer as people
    from public.schedule_cells cell
    join public.schedule_months month on month.id = cell.schedule_month_id
      and month.release_state in ('unpublished', 'released')
    join public.staff_job_roles role on role.staff_member_id = cell.staff_member_id
      and role.effective_from <= cell.work_date
      and (role.effective_through is null or role.effective_through >= cell.work_date)
    join public.shift_codes code on code.code = upper(trim(cell.shift_code))
      and code.coverage_window is not null
    where cell.work_date in (select days.work_date from days)
      and public.is_working_shift(cell.shift_code)
    group by cell.work_date, 2, code.coverage_window, role.job_role
  ), open_roles as (
    select short.work_date,
      public.coverage_pool_on(coalesce(short.job_role, original.job_role), short.work_date) as pool,
      code.coverage_window, coalesce(short.job_role, original.job_role) as job_role,
      count(*)::integer as opened,
      count(*) filter (where short.rn_floor_critical)::integer as floor_opened
    from public.short_shifts short
    left join lateral (
      select role.job_role from public.staff_job_roles role
      where role.staff_member_id = short.staff_member_id
        and role.effective_from <= short.work_date
      order by role.effective_from desc limit 1
    ) original on true
    join public.shift_codes code on code.code = upper(trim(short.shift_code))
      and code.coverage_window is not null
    where short.work_date in (select days.work_date from days)
      and short.filled_at is null and public.is_working_shift(short.shift_code)
    group by short.work_date, 2, code.coverage_window, 4
  ), counts as (
    select keys.pool, keys.coverage_window, keys.work_date,
      coalesce(date_rule.minimum, week_rule.minimum) as minimum,
      coalesce(date_rule.rn_floor, week_rule.rn_floor, 0) as floor_minimum,
      public.coverage_floor_role_on(keys.pool, keys.coverage_window,
        keys.work_date) as floor_role,
      coalesce((select sum(people) from working_roles w where w.pool = keys.pool
        and w.coverage_window = keys.coverage_window and w.work_date = keys.work_date), 0)::integer
        as working_count,
      coalesce((select sum(people) from working_roles w where w.pool = keys.pool
        and w.coverage_window = keys.coverage_window and w.work_date = keys.work_date
        and w.job_role = public.coverage_floor_role_on(keys.pool,
          keys.coverage_window, keys.work_date)), 0)::integer
        as floor_count,
      coalesce((select sum(opened) from open_roles o where o.pool = keys.pool
        and o.coverage_window = keys.coverage_window and o.work_date = keys.work_date), 0)::integer
        as open_count,
      coalesce((select sum(floor_opened) from open_roles o where o.pool = keys.pool
        and o.coverage_window = keys.coverage_window and o.work_date = keys.work_date), 0)::integer
        as floor_open_count,
      week_rule.minimum as weekday_minimum, date_rule.minimum as date_minimum
    from keys
    left join lateral (
      select rule.* from public.pool_weekday_minimums rule
      where rule.pool = keys.pool and rule.coverage_window = keys.coverage_window
        and rule.weekday = extract(dow from keys.work_date)::integer
        and rule.effective_from <= keys.work_date
      order by rule.effective_from desc limit 1
    ) week_rule on true
    left join public.pool_date_minimums date_rule on date_rule.pool = keys.pool
      and date_rule.coverage_window = keys.coverage_window
      and date_rule.work_date = keys.work_date
  )
  select counts.pool, counts.coverage_window, counts.work_date, counts.minimum,
    counts.floor_minimum, counts.working_count, counts.floor_count,
    counts.open_count, counts.floor_open_count,
    case when counts.minimum is null then null else greatest(
      counts.minimum - counts.working_count,
      counts.floor_minimum - counts.floor_count, 0) end,
    case when counts.minimum is null then null else greatest(
      counts.floor_minimum - counts.floor_count, 0) end,
    counts.weekday_minimum, counts.date_minimum
  from counts where public.is_active_staff_member();
$$;

create or replace function public.set_pool_weekday_minimum(p_pool text, p_window text,
  p_weekday integer, p_minimum integer, p_rn_floor integer default 0)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_floor_role public.job_role;
  v_before jsonb;
begin
  if public.current_staff_role() not in ('manager', 'administrator') then
    raise exception 'Only the Manager can set staffing minimums';
  end if;
  if p_pool is null or
    (public.coverage_pool_version_on(p_pool, current_date)).pool is null or
    (public.coverage_pool_version_on(p_pool, current_date)).retired
    or p_window not in ('day', 'night') or p_weekday not between 0 and 6
    or p_minimum not between 0 and 100 or p_rn_floor not between 0 and p_minimum then
    raise exception 'Invalid Staffing minimum';
  end if;
  select rule.floor_role into v_floor_role from public.pool_weekday_minimums rule
  where rule.pool = p_pool and rule.coverage_window = p_window
    and rule.weekday = p_weekday and rule.effective_from <= current_date
  order by rule.effective_from desc limit 1;
  if p_rn_floor > 0 and (v_floor_role is null or
    public.coverage_pool_on(v_floor_role, current_date) <> p_pool) then
    raise exception 'Invalid staffing minimum';
  end if;
  select to_jsonb(rule) into v_before from public.pool_weekday_minimums rule
  where rule.pool = p_pool and rule.coverage_window = p_window
    and rule.weekday = p_weekday and rule.effective_from <= current_date
  order by rule.effective_from desc limit 1;
  insert into public.pool_weekday_minimums(pool, coverage_window, weekday,
    minimum, rn_floor, floor_role, effective_from)
  values (p_pool, p_window, p_weekday, p_minimum, p_rn_floor,
    v_floor_role, current_date)
  on conflict (pool, coverage_window, weekday, effective_from) do update
    set minimum = excluded.minimum, rn_floor = excluded.rn_floor,
      floor_role = excluded.floor_role;
  insert into public.coverage_rule_audit(actor, effective_from, action,
    before_value, after_value)
  values (public.current_staff_member_id(), current_date, 'weekday_minimum',
    v_before, jsonb_build_object('pool', p_pool, 'window', p_window,
      'weekday', p_weekday, 'minimum', p_minimum, 'floor', p_rn_floor,
      'floor_role', v_floor_role));
end;
$$;

create or replace function public.set_pool_date_minimum(p_pool text, p_window text,
  p_date date, p_minimum integer, p_rn_floor integer default 0)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_floor_role public.job_role;
begin
  if public.current_staff_role() not in ('manager', 'administrator') then
    raise exception 'Only the Manager can set staffing minimums';
  end if;
  if p_pool is null or p_window not in ('day', 'night') or p_date is null
    or (p_minimum is not null and (p_minimum not between 0 and 100
      or p_rn_floor not between 0 and p_minimum)) then
    raise exception 'Invalid staffing minimum';
  end if;
  v_floor_role := public.coverage_floor_role_on(p_pool, p_window, p_date);
  if p_minimum is not null and p_rn_floor > 0 and
    (v_floor_role is null or public.coverage_pool_on(v_floor_role, p_date) <> p_pool) then
    raise exception 'Invalid staffing minimum';
  end if;
  if p_minimum is null then
    delete from public.pool_date_minimums
    where pool = p_pool and coverage_window = p_window and work_date = p_date;
  else
    insert into public.pool_date_minimums(pool, coverage_window, work_date,
      minimum, rn_floor, floor_role)
    values (p_pool, p_window, p_date, p_minimum, p_rn_floor, v_floor_role)
    on conflict (pool, coverage_window, work_date) do update
      set minimum = excluded.minimum, rn_floor = excluded.rn_floor,
        floor_role = excluded.floor_role;
  end if;
end;
$$;

create function public.set_coverage_weekday_rule(p_pool text, p_window text,
  p_weekday integer, p_effective_from date, p_minimum integer,
  p_floor_role public.job_role, p_floor integer)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_before jsonb;
begin
  if public.current_staff_role() not in ('manager', 'administrator') then
    raise exception 'Only a Manager or Administrator can set Staffing minimums';
  end if;
  if p_effective_from is null or p_effective_from < current_date or
    p_pool is null or
    (public.coverage_pool_version_on(p_pool, p_effective_from)).pool is null or
    (public.coverage_pool_version_on(p_pool, p_effective_from)).retired or
    p_window not in ('day', 'night') or p_weekday not between 0 and 6 or
    p_minimum not between 0 and 100 or p_floor not between 0 and p_minimum or
    (p_floor_role is not null and
      (public.coverage_pool_on(p_floor_role, p_effective_from) <> p_pool or
      (public.coverage_pool_version_on(p_pool, p_effective_from)).floor_role
        is distinct from p_floor_role)) or
    (p_floor > 0 and p_floor_role is null) then
    raise exception 'Invalid effective-dated Staffing minimum or floor';
  end if;
  select to_jsonb(rule) into v_before from public.pool_weekday_minimums rule
  where rule.pool = p_pool and rule.coverage_window = p_window
    and rule.weekday = p_weekday and rule.effective_from <= p_effective_from
  order by rule.effective_from desc limit 1;
  insert into public.pool_weekday_minimums(pool, coverage_window, weekday,
    effective_from, minimum, floor_role, rn_floor)
  values (p_pool, p_window, p_weekday, p_effective_from, p_minimum,
    p_floor_role, p_floor)
  on conflict (pool, coverage_window, weekday, effective_from) do update
    set minimum = excluded.minimum, floor_role = excluded.floor_role,
      rn_floor = excluded.rn_floor;
  insert into public.coverage_rule_audit(actor, effective_from, action,
    before_value, after_value)
  values (public.current_staff_member_id(), p_effective_from, 'weekday_minimum',
    v_before, jsonb_build_object('pool', p_pool, 'window', p_window,
      'weekday', p_weekday, 'minimum', p_minimum, 'floor_role', p_floor_role,
      'floor', p_floor));
end;
$$;
revoke all on function public.set_coverage_weekday_rule(text, text, integer,
  date, integer, public.job_role, integer) from public;
grant execute on function public.set_coverage_weekday_rule(text, text, integer,
  date, integer, public.job_role, integer) to authenticated;

-- The absence path remains tied to C/I and S/L. Only its coverage lookup and
-- floor Job role change; the absent person's Shift code is retained.
create or replace function public.auto_post_absence_gap()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_role public.job_role;
  v_pool text;
  v_window text;
  v_floor_role public.job_role;
  v_other_role public.job_role;
  v_count integer;
  v_floor_count integer;
begin
  if new.new_shift_code not in ('C/I', 'S/L')
    or not public.is_working_shift(new.old_shift_code) then return new; end if;
  select job_role into v_role from public.staff_job_roles
  where staff_member_id = new.staff_member_id and effective_from <= new.work_date
    and (effective_through is null or effective_through >= new.work_date)
  order by effective_from desc limit 1;
  if v_role is null then return new; end if;
  v_pool := public.coverage_pool_on(v_role, new.work_date);
  select coverage_window into v_window from public.shift_codes
  where code = upper(trim(new.old_shift_code));
  v_floor_role := public.coverage_floor_role_on(v_pool, v_window, new.work_date);
  select membership.job_role into v_other_role
  from public.coverage_pool_memberships membership
  where public.coverage_pool_on(membership.job_role, new.work_date) = v_pool
    and membership.job_role is distinct from v_floor_role
  order by membership.job_role::text limit 1;
  select posting_count, floor_count into v_count, v_floor_count
  from public.open_shift_gap(new.work_date, new.old_shift_code, v_pool, 100);
  if coalesce(v_count, 0) = 0 then return new; end if;
  insert into public.short_shifts(schedule_month_id, section_id, work_date, shift_code,
    reason, job_role, requires_approval, rn_floor_critical, call_in_change_id)
  select new.schedule_month_id, null, new.work_date, upper(trim(new.old_shift_code)),
    case when new.new_shift_code = 'C/I' then 'call_in' else 'sick_leave' end,
    case when n <= v_floor_count then v_floor_role
      else coalesce(v_other_role, v_floor_role, v_role) end,
    n <= v_floor_count, n <= v_floor_count,
    case when new.new_shift_code = 'C/I' then new.id else null end
  from generate_series(1, v_count) as series(n);
  return new;
end;
$$;

create or replace function public.post_open_shifts(p_date date, p_shift_code text,
  p_pool text, p_count integer, p_fill_gap boolean,
  p_requires_approval boolean default null)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_month uuid;
  v_window text;
  v_count integer := p_count;
  v_floor_count integer := 0;
  v_floor_role public.job_role;
  v_other_role public.job_role;
begin
  if public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the Manager can post Open shifts';
  end if;
  select coverage_window into v_window from public.shift_codes
  where code = upper(trim(p_shift_code));
  if p_date is null or p_pool is null or
    (public.coverage_pool_version_on(p_pool, p_date)).pool is null or
    (public.coverage_pool_version_on(p_pool, p_date)).retired or
    v_window is null or not public.is_working_shift(coalesce(p_shift_code, ''))
    or p_count not between 1 and 100 then
    raise exception 'A date, working Shift code with a Coverage window, pool and count are required';
  end if;
  perform pg_advisory_xact_lock(hashtext(p_pool || ':' || v_window || ':' || p_date::text));
  select id into v_month from public.schedule_months
  where month_start = date_trunc('month', p_date)::date;
  if v_month is null then raise exception 'Start this Schedule month first'; end if;
  v_floor_role := public.coverage_floor_role_on(p_pool, v_window, p_date);
  select membership.job_role into v_other_role
  from public.coverage_pool_memberships membership
  where public.coverage_pool_on(membership.job_role, p_date) = p_pool
    and membership.job_role is distinct from v_floor_role
  order by membership.job_role::text limit 1;
  if p_fill_gap then
    select posting_count, floor_count into v_count, v_floor_count
    from public.open_shift_gap(p_date, p_shift_code, p_pool, p_count);
    if v_count is null then raise exception 'Set this Staffing minimum first'; end if;
  end if;
  insert into public.short_shifts(schedule_month_id, section_id, work_date,
    shift_code, reason, job_role, requires_approval, rn_floor_critical)
  select v_month, null, p_date, upper(trim(p_shift_code)), 'manual',
    case when n <= v_floor_count then v_floor_role
      else coalesce(v_other_role, v_floor_role) end,
    case when n <= v_floor_count then true
      else coalesce(p_requires_approval, public.open_shift_approval_default()) end,
    n <= v_floor_count
  from generate_series(1, v_count) as series(n);
  return v_count;
end;
$$;

-- A released short Schedule is a deliberate Manager decision. The existing
-- release implementation still performs the month transition and notices.
create function public.release_month_checked(p_month_start date,
  p_acknowledge_shortfalls boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_short_days integer;
begin
  if public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the Manager can release a month';
  end if;
  select count(distinct work_date) into v_short_days
  from public.section_staffing_for_month(p_month_start)
  where shortfall > 0;
  if v_short_days > 0 and p_acknowledge_shortfalls is distinct from true then
    raise exception 'Review and acknowledge the short days before Month release';
  end if;
  perform public.release_month(p_month_start);
end;
$$;
revoke all on function public.release_month_checked(date, boolean) from public;
grant execute on function public.release_month_checked(date, boolean)
  to authenticated;
revoke execute on function public.release_month(date) from public, authenticated;

create function public.confirm_loaded_month_checked(p_month_start date,
  p_acknowledge_shortfalls boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the Manager can confirm the month';
  end if;
  if exists (select 1 from public.section_staffing_for_month(p_month_start)
      where shortfall > 0) and p_acknowledge_shortfalls is distinct from true then
    raise exception 'Review and acknowledge the short days before Month release';
  end if;
  perform public.confirm_loaded_month(p_month_start);
end;
$$;
revoke all on function public.confirm_loaded_month_checked(date, boolean) from public;
grant execute on function public.confirm_loaded_month_checked(date, boolean)
  to authenticated;
revoke execute on function public.confirm_loaded_month(date) from public, authenticated;

\n