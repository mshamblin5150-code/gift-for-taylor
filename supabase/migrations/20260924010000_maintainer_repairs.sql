-- ADR-0020 makes Maintainer authority a temporary hat worn by a real Staff
-- member. The database binding stays private; the anti-link rule does not.
drop trigger reject_staff_maintainer_binding on private.maintainer_identity;
drop trigger reject_maintainer_staff_account on public.staff_accounts;
drop function private.reject_maintainer_staff_link();

create type public.maintainer_repair_reason_category as enum (
  'manager_handover',
  'schedule_or_month',
  'unit_settings',
  'staff_or_invite',
  'investigation',
  'something_else'
);

create table public.maintainer_repairs (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users(id) on delete restrict,
  reason_category public.maintainer_repair_reason_category not null,
  detail text,
  opened_at timestamptz not null default statement_timestamp(),
  closed_at timestamptz,
  expires_at timestamptz not null,
  check (detail is null or length(detail) between 3 and 240),
  check (reason_category <> 'something_else' or detail is not null),
  check (expires_at > opened_at and expires_at <= opened_at + interval '1 hour'),
  check (closed_at is null or closed_at >= opened_at)
);
alter table public.maintainer_repairs enable row level security;
revoke all on public.maintainer_repairs from public, anon, authenticated;
create unique index one_unclosed_maintainer_repair
  on public.maintainer_repairs(auth_user_id)
  where closed_at is null;

create function private.cap_maintainer_repair()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.expires_at is null then
    new.expires_at := new.opened_at + interval '1 hour';
  end if;
  return new;
end;
$$;
revoke all on function private.cap_maintainer_repair() from public;
create trigger cap_maintainer_repair
  before insert on public.maintainer_repairs
  for each row execute function private.cap_maintainer_repair();

create function private.active_maintainer_repair_id()
returns uuid language sql stable security definer set search_path = '' as $$
  select repair.id
  from public.maintainer_repairs repair
  where repair.auth_user_id = auth.uid()
    and repair.closed_at is null
    and repair.expires_at > statement_timestamp()
    and public.is_maintainer()
  order by repair.opened_at desc
  limit 1
$$;
revoke all on function private.active_maintainer_repair_id() from public;

create function private.maintainer_repair_summary(p_repair_id uuid)
returns text language sql stable security definer set search_path = '' as $$
  select case repair.reason_category
      when 'manager_handover' then 'Manager handover'
      when 'schedule_or_month' then 'Schedule or Month'
      when 'unit_settings' then 'Unit settings'
      when 'staff_or_invite' then 'Staff record or Invite'
      when 'investigation' then 'Investigating a fault'
      when 'something_else' then 'Something else'
    end || coalesce(' — ' || repair.detail, '')
  from public.maintainer_repairs repair
  where repair.id = p_repair_id
$$;
revoke all on function private.maintainer_repair_summary(uuid) from public;

create function public.current_maintainer_repair()
returns table (
  id uuid,
  reason_category public.maintainer_repair_reason_category,
  detail text,
  opened_at timestamptz,
  expires_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  select repair.id, repair.reason_category, repair.detail,
    repair.opened_at, repair.expires_at
  from public.maintainer_repairs repair
  where repair.id = private.active_maintainer_repair_id()
$$;
revoke all on function public.current_maintainer_repair() from public;
grant execute on function public.current_maintainer_repair() to authenticated;

create function public.open_maintainer_repair(
  p_reason_category public.maintainer_repair_reason_category,
  p_detail text default null
)
returns setof public.maintainer_repairs
language plpgsql volatile security definer set search_path = '' as $$
declare v_detail text := nullif(trim(p_detail), '');
begin
  if not public.is_maintainer() then
    raise exception 'Only the Maintainer can open a Repair';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('maintainer-repair:' || auth.uid()::text, 0));
  if v_detail is not null and length(v_detail) not between 3 and 240 then
    raise exception 'Repair detail must be 3-240 characters';
  end if;
  if p_reason_category = 'something_else' and v_detail is null then
    raise exception 'Something else requires repair detail (3-240 characters)';
  end if;

  update public.maintainer_repairs
  set closed_at = expires_at
  where auth_user_id = auth.uid() and closed_at is null
    and expires_at <= clock_timestamp();
  if private.active_maintainer_repair_id() is not null then
    raise exception 'Close the current Repair before opening another';
  end if;

  return query insert into public.maintainer_repairs(
      auth_user_id, reason_category, detail)
    values (auth.uid(), p_reason_category, v_detail)
    returning *;
end;
$$;
revoke all on function public.open_maintainer_repair(
  public.maintainer_repair_reason_category, text) from public;
grant execute on function public.open_maintainer_repair(
  public.maintainer_repair_reason_category, text) to authenticated;

create function public.close_maintainer_repair(p_repair_id uuid default null)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if not public.is_maintainer() then
    raise exception 'Only the Maintainer can close a Repair';
  end if;
  update public.maintainer_repairs
  set closed_at = least(clock_timestamp(), expires_at)
  where id = coalesce(p_repair_id, (
      select repair.id from public.maintainer_repairs repair
      where repair.auth_user_id = auth.uid() and repair.closed_at is null
      order by repair.opened_at desc limit 1))
    and auth_user_id = auth.uid() and closed_at is null;
end;
$$;
revoke all on function public.close_maintainer_repair(uuid) from public;
grant execute on function public.close_maintainer_repair(uuid) to authenticated;

-- The hat only supplies Manager capability while a Repair is active. Without
-- one, the same Auth user follows their ordinary Staff row.
create or replace function public.current_staff_role()
returns public.staff_role language sql stable security definer set search_path = '' as $$
  select case
    when private.active_maintainer_repair_id() is not null
      then 'manager'::public.staff_role
    else (select member.role
      from public.staff_accounts account
      join public.staff_members member on member.id = account.staff_member_id
      where account.auth_user_id = auth.uid() and member.active
        and account.accepted_invite_at is not null and account.revoked_at is null)
    end
$$;

drop function public.current_access();
create function public.current_access()
returns table (
  manager boolean,
  administrator boolean,
  maintainer boolean,
  staff_member_id uuid,
  night_scheduler_section_ids uuid[],
  repair_id uuid,
  repair_reason_category public.maintainer_repair_reason_category,
  repair_detail text,
  repair_opened_at timestamptz,
  repair_expires_at timestamptz,
  repair_seconds_remaining double precision
)
language sql stable security definer set search_path = '' as $$
  select
    coalesce(public.current_staff_role() = 'manager', false),
    coalesce(member.role = 'administrator', false),
    public.is_maintainer(),
    member.id,
    coalesce((select array_agg(assignment.section_id order by assignment.section_id)
      from public.night_scheduler_sections assignment
      where assignment.staff_member_id = member.id), '{}'::uuid[]),
    repair.id,
    repair.reason_category,
    repair.detail,
    repair.opened_at,
    repair.expires_at,
    greatest(
      extract(epoch from repair.expires_at - statement_timestamp()), 0)
  from (select 1) singleton
  left join public.staff_accounts account on account.auth_user_id = auth.uid()
    and account.accepted_invite_at is not null and account.revoked_at is null
  left join public.staff_members member on member.id = account.staff_member_id
    and member.active
  left join lateral public.current_maintainer_repair() repair on true
$$;
revoke all on function public.current_access() from public;
grant execute on function public.current_access() to authenticated;

-- Every repair audit row names the human Staff member, the Auth-bound hat and
-- the Repair. The existing summary remains for history readers.
alter table public.maintainer_repair_audit
  add column actor_staff_member_id uuid references public.staff_members(id),
  add column repair_id uuid references public.maintainer_repairs(id);
alter table public.unit_setting_audit
  add column repair_id uuid references public.maintainer_repairs(id);
alter table public.schedule_changes
  add column repair_id uuid references public.maintainer_repairs(id);
alter table public.staff_changes
  add column repair_id uuid references public.maintainer_repairs(id);
alter table public.coverage_rule_audit
  add column repair_id uuid references public.maintainer_repairs(id);
alter table public.coverage_rule_batches
  add column repair_id uuid references public.maintainer_repairs(id);

create or replace function public.audit_maintainer_repair()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_repair uuid := private.active_maintainer_repair_id();
  v_before jsonb;
  v_after jsonb;
begin
  if v_repair is null then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  if tg_op <> 'INSERT' then v_before := to_jsonb(old); end if;
  if tg_op <> 'DELETE' then v_after := to_jsonb(new); end if;
  if tg_table_name = 'invites' then
    v_before := v_before - 'token_hash';
    v_after := v_after - 'token_hash';
  end if;
  if v_before is not distinct from v_after then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  insert into public.maintainer_repair_audit(
    actor_staff_member_id, actor_auth_user_id, repair_id, repair_reason,
    relation_name, operation, before_value, after_value)
  values (public.current_staff_member_id(), auth.uid(), v_repair,
    private.maintainer_repair_summary(v_repair), tg_table_name, tg_op,
    v_before, v_after);
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function public.attribute_maintainer_actor()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_repair uuid := private.active_maintainer_repair_id();
begin
  if v_repair is not null then
    new.changed_by_auth_user_id := auth.uid();
    new.repair_id := v_repair;
  end if;
  return new;
end;
$$;

create or replace function public.attribute_maintainer_decision()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if private.active_maintainer_repair_id() is not null then
    if tg_table_name = 'schedule_months' then
      if new.released_at is not null and old.released_at is null then
        new.released_by_auth_user_id := auth.uid();
      end if;
      if new.confirmed_at is not null and old.confirmed_at is null then
        new.confirmed_by_auth_user_id := auth.uid();
      end if;
    elsif tg_table_name = 'requests_off' and new.decided_at is not null
        and old.decided_at is null then
      new.decided_by_auth_user_id := auth.uid();
    elsif new.approved_at is not null and old.approved_at is null then
      new.approved_by_auth_user_id := auth.uid();
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.audit_unit_setting()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := public.current_staff_member_id();
  v_repair uuid := private.active_maintainer_repair_id();
  v_name text;
  v_before jsonb;
  v_after jsonb;
begin
  if tg_op <> 'INSERT' then v_before := to_jsonb(old); end if;
  if tg_op <> 'DELETE' then v_after := to_jsonb(new); end if;
  if v_before is not distinct from v_after then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  if v_actor is not null then
    select display_name into v_name from public.staff_members where id = v_actor;
    insert into public.unit_setting_audit(kind, actor_id, actor_auth_user_id,
      actor_name, repair_id, repair_reason, before_value, after_value)
    values (tg_argv[0], v_actor,
      case when v_repair is not null then auth.uid() end,
      coalesce(v_name, 'Staff member'), v_repair,
      private.maintainer_repair_summary(v_repair), v_before, v_after);
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function public.audit_month_print_wording()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := public.current_staff_member_id();
  v_repair uuid := private.active_maintainer_repair_id();
  v_name text;
begin
  if old.release_state = 'released' and
      (old.print_tooltip, old.print_title, old.print_notice) is distinct from
      (new.print_tooltip, new.print_title, new.print_notice)
      and v_actor is not null then
    select display_name into v_name from public.staff_members where id = v_actor;
    insert into public.unit_setting_audit(kind, actor_id, actor_auth_user_id,
      actor_name, repair_id, repair_reason, before_value, after_value)
    values ('Released month print wording', v_actor,
      case when v_repair is not null then auth.uid() end,
      coalesce(v_name, 'Staff member'), v_repair,
      private.maintainer_repair_summary(v_repair),
      jsonb_build_object('month', old.month_start, 'tooltip', old.print_tooltip,
        'title', old.print_title, 'notice', old.print_notice),
      jsonb_build_object('month', new.month_start, 'tooltip', new.print_tooltip,
        'title', new.print_title, 'notice', new.print_notice));
  end if;
  return new;
end;
$$;

create or replace function public.attribute_coverage_rule_actor()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_repair uuid := private.active_maintainer_repair_id();
begin
  if v_repair is not null then
    new.actor_auth_user_id := auth.uid();
    new.repair_id := v_repair;
  end if;
  return new;
end;
$$;

create or replace function public.audit_coverage_rule_for_unit()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_actor_name text;
begin
  if new.action = 'weekday_minimum' then return new; end if;
  select display_name into v_actor_name from public.staff_members
  where id = new.actor;
  insert into public.unit_setting_audit(kind, actor_id, actor_auth_user_id,
    actor_name, repair_id, repair_reason, changed_at, before_value, after_value)
  values (case new.action
      when 'coverage_pools' then 'Coverage pools'
      when 'date_minimum' then 'Date Staffing minimum'
      else 'Coverage rule'
    end,
    new.actor, new.actor_auth_user_id, coalesce(v_actor_name, 'Staff member'),
    new.repair_id, private.maintainer_repair_summary(new.repair_id),
    new.changed_at,
    coalesce(new.before_value, '{}'::jsonb) ||
      jsonb_build_object('effective_from', new.effective_from),
    coalesce(new.after_value, '{}'::jsonb) ||
      jsonb_build_object('effective_from', new.effective_from));
  return new;
end;
$$;

drop function public.maintainer_repair_reason();

-- Direct Maintainer read paths are Repair authority too. The linked Staff row
-- supplies all ordinary reads while the hat is off.
drop policy "Maintainer reads Sections" on public.sections;
create policy "Maintainer reads Sections" on public.sections
  for select to authenticated
  using (exists (select 1 from public.current_maintainer_repair()));
drop policy "Maintainer reads Staff members" on public.staff_members;
create policy "Maintainer reads Staff members" on public.staff_members
  for select to authenticated
  using (exists (select 1 from public.current_maintainer_repair()));

drop policy "Maintainer reads coverage pools" on public.coverage_pools;
create policy "Maintainer reads coverage pools" on public.coverage_pools
  for select to authenticated
  using (exists (select 1 from public.current_maintainer_repair()));
drop policy "Maintainer reads coverage pool versions" on public.coverage_pool_versions;
create policy "Maintainer reads coverage pool versions" on public.coverage_pool_versions
  for select to authenticated
  using (exists (select 1 from public.current_maintainer_repair()));
drop policy "Maintainer reads coverage pool memberships" on public.coverage_pool_memberships;
create policy "Maintainer reads coverage pool memberships" on public.coverage_pool_memberships
  for select to authenticated
  using (exists (select 1 from public.current_maintainer_repair()));
drop policy "Maintainer reads coverage rule batches" on public.coverage_rule_batches;
create policy "Maintainer reads coverage rule batches" on public.coverage_rule_batches
  for select to authenticated
  using (exists (select 1 from public.current_maintainer_repair()));

create or replace view public.staff_list_entries
with (security_invoker = false) as
select
  member.id, member.display_name,
  case when public.can_manage_staff() then member.cell_number end as cell_number,
  assignment.section_id, assignment.display_order,
  case when public.can_manage_staff() then account.personal_email end as personal_email,
  assignment.effective_from as section_from, job_role.job_role,
  case when public.can_manage_staff() then (
    select max(mismatch.attempted_at)
    from public.invite_cell_mismatches mismatch
    where mismatch.staff_member_id = member.id
  ) end as invite_cell_mismatch_at
from public.staff_members member
join public.staff_section_assignments assignment
  on assignment.staff_member_id = member.id
  and assignment.effective_through is null
left join public.staff_accounts account
  on account.staff_member_id = member.id and account.revoked_at is null
left join public.staff_job_roles job_role
  on job_role.staff_member_id = member.id and job_role.effective_through is null
where member.active
  and (public.is_active_staff_member()
    or exists (select 1 from public.current_maintainer_repair()));

do $migration$
declare v_definition text;
begin
  select pg_get_functiondef('public.section_staffing_for_month(date)'::regprocedure)
    into v_definition;
  if strpos(v_definition,
      'from counts where public.is_active_staff_member() or public.is_maintainer()') = 0 then
    raise exception 'Expected Maintainer Staffing sheet reader filter missing';
  end if;
  execute replace(v_definition,
    'from counts where public.is_active_staff_member() or public.is_maintainer()',
    'from counts where public.is_active_staff_member() or private.active_maintainer_repair_id() is not null');
end;
$migration$;
