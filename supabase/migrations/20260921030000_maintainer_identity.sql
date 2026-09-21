-- The Maintainer is a single Auth user, provisioned by a database operator.
-- No authenticated role can read or change the binding.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create table private.maintainer_identity (
  singleton boolean primary key default true check (singleton),
  auth_user_id uuid not null unique references auth.users(id) on delete restrict
);
revoke all on private.maintainer_identity from public, anon, authenticated;

create function public.is_maintainer()
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (
    select 1 from private.maintainer_identity
    where auth_user_id = auth.uid()
  )
$$;
revoke all on function public.is_maintainer() from public;
grant execute on function public.is_maintainer() to authenticated;

create function private.reject_maintainer_staff_link()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_table_name = 'maintainer_identity' then
    if exists (select 1 from public.staff_accounts
      where auth_user_id = new.auth_user_id) then
      raise exception 'Maintainer Auth user cannot have a Staff account';
    end if;
  elsif exists (select 1 from private.maintainer_identity
      where auth_user_id = new.auth_user_id) then
    raise exception 'Maintainer Auth user cannot have a Staff account';
  end if;
  return new;
end;
$$;
revoke all on function private.reject_maintainer_staff_link() from public;
create trigger reject_staff_maintainer_binding
  before insert or update of auth_user_id on private.maintainer_identity
  for each row execute function private.reject_maintainer_staff_link();
create trigger reject_maintainer_staff_account
  before insert or update of auth_user_id on public.staff_accounts
  for each row execute function private.reject_maintainer_staff_link();

-- This is a capability result for existing Manager checks, not the actor's
-- identity. current_staff_member_id() deliberately remains null.
create or replace function public.current_staff_role()
returns public.staff_role language sql stable security definer set search_path = '' as $$
  select case when public.is_maintainer() then 'manager'::public.staff_role
    else (select member.role
      from public.staff_accounts account
      join public.staff_members member on member.id = account.staff_member_id
      where account.auth_user_id = auth.uid() and member.active
        and account.accepted_invite_at is not null and account.revoked_at is null)
    end
$$;

create function public.current_access_role()
returns text language sql stable security definer set search_path = '' as $$
  select case when public.is_maintainer() then 'maintainer'
    else public.current_staff_role()::text end
$$;
revoke all on function public.current_access_role() from public;
grant execute on function public.current_access_role() to authenticated;

-- A request header travels through all SECURITY DEFINER calls and triggers in
-- the same transaction. The database validates it; a client cannot bypass it.
create function public.maintainer_repair_reason()
returns text language sql stable security definer set search_path = '' as $$
  select nullif(trim(coalesce(
    (nullif(current_setting('request.headers', true), '')::jsonb
      ->> 'x-repair-reason'), '')), '')
$$;
revoke all on function public.maintainer_repair_reason() from public;
grant execute on function public.maintainer_repair_reason() to authenticated;

create table public.maintainer_repair_audit (
  id bigint generated always as identity primary key,
  actor_auth_user_id uuid not null references auth.users(id),
  repair_reason text not null check (length(repair_reason) between 3 and 240),
  relation_name text not null,
  operation text not null,
  before_value jsonb,
  after_value jsonb,
  changed_at timestamptz not null default clock_timestamp()
);
alter table public.maintainer_repair_audit enable row level security;
revoke all on public.maintainer_repair_audit from public, anon, authenticated;
grant select on public.maintainer_repair_audit to authenticated;
create policy "Manager and Maintainer read repairs" on public.maintainer_repair_audit
  for select using (public.current_staff_role() = 'manager');

create function public.audit_maintainer_repair()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_reason text;
  v_before jsonb;
  v_after jsonb;
begin
  if not public.is_maintainer() then
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
  v_reason := public.maintainer_repair_reason();
  if v_reason is null or length(v_reason) not between 3 and 240 then
    raise exception 'Maintainer changes require a repair reason (3-240 characters)';
  end if;
  insert into public.maintainer_repair_audit(actor_auth_user_id,
    repair_reason, relation_name, operation, before_value, after_value)
  values (auth.uid(), v_reason, tg_table_name, tg_op, v_before, v_after);
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function public.audit_maintainer_repair() from public;

-- These are Unit-owned records. Personal notices, feed tokens and preferences
-- have their own identity and are intentionally outside repair auditing.
do $migration$
declare v_table text;
begin
  foreach v_table in array array[
    'sections', 'staff_members', 'staff_section_assignments',
    'staff_job_roles', 'staff_accounts', 'invites',
    'schedule_months', 'schedule_cells', 'schedule_changes',
    'staff_changes', 'short_shifts', 'shift_codes',
    'pool_weekday_minimums', 'pool_date_minimums',
    'open_shift_approval_settings', 'print_wording',
    'night_scheduler_sections', 'requests_off', 'request_off_dates',
    'swaps', 'open_shifts', 'open_shift_pickups',
    'coverage_pools', 'coverage_pool_versions', 'coverage_pool_memberships',
    'coverage_rule_audit', 'coverage_rule_batches'
  ] loop
    if to_regclass('public.' || v_table) is not null then
      execute format('create trigger audit_maintainer_repair after insert or update or delete on public.%I for each row execute function public.audit_maintainer_repair()', v_table);
    end if;
  end loop;
end;
$migration$;

-- Existing Staff references keep their values. A Maintainer write gets a
-- separate Auth actor; no synthetic staff row is created.
alter table public.schedule_changes
  alter column changed_by_staff_member_id drop not null,
  add column changed_by_auth_user_id uuid references auth.users(id);
alter table public.staff_changes
  alter column changed_by_staff_member_id drop not null,
  add column changed_by_auth_user_id uuid references auth.users(id);
alter table public.schedule_months
  add column released_by_auth_user_id uuid references auth.users(id),
  add column confirmed_by_auth_user_id uuid references auth.users(id);
alter table public.unit_setting_audit
  alter column actor_id drop not null,
  add column actor_auth_user_id uuid references auth.users(id),
  add column repair_reason text;
alter table public.requests_off
  add column decided_by_auth_user_id uuid references auth.users(id);
alter table public.swaps
  add column approved_by_auth_user_id uuid references auth.users(id);
alter table public.open_shift_pickups
  add column approved_by_auth_user_id uuid references auth.users(id);

alter table public.schedule_months drop constraint schedule_months_check;
alter table public.schedule_months add check (
  (release_state = 'released') =
  (released_at is not null and
    (released_by_staff_member_id is not null or released_by_auth_user_id is not null))
);
alter table public.schedule_months drop constraint schedule_months_check1;
alter table public.schedule_months add check (
  (confirmed_at is null) =
  (confirmed_by_staff_member_id is null and confirmed_by_auth_user_id is null)
);
alter table public.requests_off drop constraint requests_off_check;
alter table public.requests_off add check (
  (decision = 'pending') =
  (decided_at is null and decided_by_staff_member_id is null
    and decided_by_auth_user_id is null)
);

create function public.attribute_maintainer_actor()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if public.is_maintainer() then
    new.changed_by_auth_user_id := auth.uid();
  end if;
  return new;
end;
$$;
revoke all on function public.attribute_maintainer_actor() from public;
create trigger attribute_schedule_change before insert on public.schedule_changes
  for each row execute function public.attribute_maintainer_actor();
create trigger attribute_staff_change before insert on public.staff_changes
  for each row execute function public.attribute_maintainer_actor();

create function public.attribute_maintainer_decision()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if public.is_maintainer() then
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
revoke all on function public.attribute_maintainer_decision() from public;
create trigger attribute_month_decision before update on public.schedule_months
  for each row execute function public.attribute_maintainer_decision();
create trigger attribute_request_decision before update on public.requests_off
  for each row execute function public.attribute_maintainer_decision();
create trigger attribute_swap_decision before update on public.swaps
  for each row execute function public.attribute_maintainer_decision();
create trigger attribute_pickup_decision before update on public.open_shift_pickups
  for each row execute function public.attribute_maintainer_decision();

drop policy "Staff can read Shift codes" on public.shift_codes;
create policy "Staff and Maintainer can read Shift codes" on public.shift_codes
  for select to authenticated using (public.current_staff_role() is not null);

-- Reuse #176's audit for Unit choices, with the Auth actor and repair reason.
create or replace function public.audit_unit_setting()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := public.current_staff_member_id();
  v_maintainer boolean := public.is_maintainer();
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
  if v_actor is not null or v_maintainer then
    if v_maintainer then v_name := 'Maintainer';
    else select display_name into v_name from public.staff_members where id = v_actor;
    end if;
    insert into public.unit_setting_audit(kind, actor_id, actor_auth_user_id,
      actor_name, repair_reason, before_value, after_value)
    values (tg_argv[0], v_actor,
      case when v_maintainer then auth.uid() end,
      coalesce(v_name, 'Staff member'),
      case when v_maintainer then public.maintainer_repair_reason() end,
      v_before, v_after);
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function public.audit_month_print_wording()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := public.current_staff_member_id();
  v_maintainer boolean := public.is_maintainer();
  v_name text;
begin
  if old.release_state = 'released' and
      (old.print_tooltip, old.print_title, old.print_notice) is distinct from
      (new.print_tooltip, new.print_title, new.print_notice)
      and (v_actor is not null or v_maintainer) then
    if v_maintainer then v_name := 'Maintainer';
    else select display_name into v_name from public.staff_members where id = v_actor;
    end if;
    insert into public.unit_setting_audit(kind, actor_id, actor_auth_user_id,
      actor_name, repair_reason, before_value, after_value)
    values ('Released month print wording', v_actor,
      case when v_maintainer then auth.uid() end,
      coalesce(v_name, 'Staff member'),
      case when v_maintainer then public.maintainer_repair_reason() end,
      jsonb_build_object('month', old.month_start, 'tooltip', old.print_tooltip,
        'title', old.print_title, 'notice', old.print_notice),
      jsonb_build_object('month', new.month_start, 'tooltip', new.print_tooltip,
        'title', new.print_title, 'notice', new.print_notice));
  end if;
  return new;
end;
$$;

-- The independent-grants handover resolves the departing Manager through the
-- Staff account. A Maintainer has no Staff account, so locate the incumbent
-- Manager row instead while preserving the explicit grant choices from #220.
do $migration$
declare v_definition text;
begin
  select pg_get_functiondef('public.transfer_manager_with_access(uuid,boolean,uuid[])'::regprocedure)
    into v_definition;
  if strpos(v_definition, 'v_old_manager_id := public.current_staff_member_id();') = 0 then
    raise exception 'Expected Manager handover actor lookup missing';
  end if;
  v_definition := replace(v_definition,
    'v_old_manager_id := public.current_staff_member_id();',
    'select id into v_old_manager_id from public.staff_members
    where role = ''manager'' and active for update;');
  execute v_definition;
end;
$migration$;

-- Coverage configuration and rule batches were added after this work began.
-- Their Staff actor remains intact for ordinary edits; a Maintainer uses the
-- separate Auth actor and the same required repair reason.
alter table public.coverage_rule_audit
  alter column actor drop not null,
  add column actor_auth_user_id uuid references auth.users(id);
alter table public.coverage_rule_batches
  alter column actor drop not null,
  add column actor_auth_user_id uuid references auth.users(id);

create function public.attribute_coverage_rule_actor()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if public.is_maintainer() then
    new.actor := null;
    new.actor_auth_user_id := auth.uid();
  end if;
  return new;
end;
$$;
revoke all on function public.attribute_coverage_rule_actor() from public;
create trigger attribute_coverage_rule_actor before insert on public.coverage_rule_audit
  for each row execute function public.attribute_coverage_rule_actor();
create trigger attribute_coverage_batch_actor before insert on public.coverage_rule_batches
  for each row execute function public.attribute_coverage_rule_actor();

create or replace function public.audit_coverage_rule_for_unit()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_actor_name text;
begin
  if new.action = 'weekday_minimum' then return new; end if;
  if new.actor_auth_user_id is not null then v_actor_name := 'Maintainer';
  else select display_name into v_actor_name from public.staff_members
    where id = new.actor;
  end if;
  insert into public.unit_setting_audit(kind, actor_id, actor_auth_user_id,
    actor_name, repair_reason, changed_at, before_value, after_value)
  values (case new.action
      when 'coverage_pools' then 'Coverage pools'
      when 'date_minimum' then 'Date Staffing minimum'
      else 'Coverage rule'
    end,
    new.actor, new.actor_auth_user_id, coalesce(v_actor_name, 'Staff member'),
    case when new.actor_auth_user_id is not null
      then public.maintainer_repair_reason() end,
    new.changed_at,
    coalesce(new.before_value, '{}'::jsonb) ||
      jsonb_build_object('effective_from', new.effective_from),
    coalesce(new.after_value, '{}'::jsonb) ||
      jsonb_build_object('effective_from', new.effective_from));
  return new;
end;
$$;

create policy "Maintainer reads coverage pools" on public.coverage_pools
  for select to authenticated using (public.is_maintainer());
create policy "Maintainer reads coverage pool versions" on public.coverage_pool_versions
  for select to authenticated using (public.is_maintainer());
create policy "Maintainer reads coverage pool memberships" on public.coverage_pool_memberships
  for select to authenticated using (public.is_maintainer());
create policy "Maintainer reads coverage rule batches" on public.coverage_rule_batches
  for select to authenticated using (public.is_maintainer());

do $migration$
declare v_definition text;
begin
  select pg_get_functiondef('public.section_staffing_for_month(date)'::regprocedure)
    into v_definition;
  if strpos(v_definition, 'from counts where public.is_active_staff_member()') = 0 then
    raise exception 'Expected Staffing sheet reader filter missing';
  end if;
  execute replace(v_definition,
    'from counts where public.is_active_staff_member()',
    'from counts where public.is_active_staff_member() or public.is_maintainer()');
end;
$migration$;

-- A Maintainer has no Staff ID. Notification filters must still deliver to
-- Staff recipients when a repair releases a month or announces a change.
do $migration$
declare
  v_definition text;
  v_function regprocedure;
  v_before text;
  v_after text;
begin
  for v_function, v_before, v_after in
    select 'public.notice_swap()'::regprocedure,
      'recipient.id <> v_actor', 'recipient.id is distinct from v_actor'
    union all select 'public.notice_open_shift(public.short_shifts,uuid)'::regprocedure,
      'member.id <> p_actor', 'member.id is distinct from p_actor'
    union all select 'public.notice_schedule_change()'::regprocedure,
      'changed.staff_member_id <> changed.changed_by_staff_member_id',
      'changed.staff_member_id is distinct from changed.changed_by_staff_member_id'
  loop
    select pg_get_functiondef(v_function) into v_definition;
    if strpos(v_definition, v_before) = 0 then
      raise exception 'Expected notification filter missing in %', v_function;
    end if;
    execute replace(v_definition, v_before, v_after);
  end loop;
end;
$migration$;
