-- Unit settings have one authorization rule and one readable change history.
create function public.can_manage_unit()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.current_staff_role() in ('manager', 'administrator'), false)
$$;
revoke all on function public.can_manage_unit() from public;
grant execute on function public.can_manage_unit() to authenticated;

create or replace function public.can_manage_sections()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.can_manage_unit()
$$;

-- These existing RPCs remain the sole write path. Broaden only Unit choices;
-- Schedule edits, month release, and individual shift decisions stay separate.
do $migration$
declare
  v_function record;
  v_definition text;
begin
  for v_function in
    select p.oid, p.proname from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in (
      'set_pool_weekday_minimum', 'set_open_shift_approval_default',
      'set_print_wording', 'save_shift_code', 'delete_shift_code',
      'set_shift_code_coverage_window', 'set_staff_access_role',
      'assign_administrator', 'remove_administrator'
    )
  loop
    v_definition := pg_get_functiondef(v_function.oid);
    v_definition := replace(v_definition,
      'public.current_staff_role() is distinct from ''manager''::public.staff_role',
      'not public.can_manage_unit()');
    v_definition := replace(v_definition,
      'public.current_staff_role() <> ''manager''',
      'not public.can_manage_unit()');
    if v_function.proname = 'set_staff_access_role' then
      v_definition := replace(v_definition,
        '  if p_new_role = ''manager'' and not exists (',
        '  if p_new_role = ''manager'' and public.current_staff_role() is distinct from ''manager''::public.staff_role then
    raise exception ''Only the current Manager can transfer the Manager role'';
  end if;
  if p_new_role = ''manager'' and not exists (');
    end if;
    execute v_definition;
  end loop;
end;
$migration$;

create function public.guard_manager_transfer()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.role = 'manager' and old.role is distinct from 'manager'
      and public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the current Manager can transfer the Manager role';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_manager_transfer() from public;
create trigger guard_manager_transfer before update of role on public.staff_members
  for each row execute function public.guard_manager_transfer();

create table public.unit_setting_audit (
  id bigint generated always as identity primary key,
  kind text not null,
  actor_id uuid not null references public.staff_members(id),
  actor_name text not null,
  changed_at timestamptz not null default now(),
  before_value jsonb,
  after_value jsonb
);
alter table public.unit_setting_audit enable row level security;
revoke all on public.unit_setting_audit from public, anon, authenticated;
grant select on public.unit_setting_audit to authenticated;
create policy "unit managers read audit" on public.unit_setting_audit
  for select using (public.can_manage_unit());

create function public.audit_unit_setting()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := public.current_staff_member_id();
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
  -- Rows can be seeded by migrations without an authenticated actor.
  if v_actor is not null then
    select display_name into v_name from public.staff_members where id = v_actor;
    insert into public.unit_setting_audit(kind, actor_id, actor_name,
      before_value, after_value)
    values (tg_argv[0], v_actor, coalesce(v_name, 'Staff member'),
      v_before, v_after);
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function public.audit_unit_setting() from public;

create trigger audit_weekday_minimum after insert or update or delete
  on public.pool_weekday_minimums for each row
  execute function public.audit_unit_setting('Staffing minimum');
create trigger audit_approval_default after update
  on public.open_shift_approval_settings for each row
  execute function public.audit_unit_setting('Open shift pickup approval');
create trigger audit_print_wording after update
  on public.print_wording for each row
  execute function public.audit_unit_setting('Print wording');
create trigger audit_shift_codes after insert or update or delete
  on public.shift_codes for each row
  execute function public.audit_unit_setting('Shift codes');
create trigger audit_sections after insert or update or delete
  on public.sections for each row
  execute function public.audit_unit_setting('Sections');
create trigger audit_permissions after update of role
  on public.staff_members for each row
  when (old.role is distinct from new.role)
  execute function public.audit_unit_setting('Permission assignment');
create trigger audit_night_scheduler_sections after insert or delete
  on public.night_scheduler_sections for each row
  execute function public.audit_unit_setting('Permission assignment');

-- A release captures the current default in the same transaction as its state
-- change. Historic months predating this migration get the best available value.
alter table public.schedule_months
  add column print_tooltip text,
  add column print_title text,
  add column print_notice text;
update public.schedule_months month set
  print_tooltip = wording.tooltip,
  print_title = wording.title,
  print_notice = wording.notice
from public.print_wording wording
where month.release_state = 'released' and wording.id;

create function public.capture_month_print_wording()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.release_state = 'released' and old.release_state <> 'released' then
    select tooltip, title, notice into
      new.print_tooltip, new.print_title, new.print_notice
    from public.print_wording where id;
  end if;
  return new;
end;
$$;
revoke all on function public.capture_month_print_wording() from public;
create trigger capture_month_print_wording before update of release_state
  on public.schedule_months for each row
  execute function public.capture_month_print_wording();

create function public.correct_month_print_wording(
  p_month_start date, p_tooltip text, p_title text, p_notice text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.can_manage_unit() then
    raise exception 'Only Unit managers can correct print wording';
  end if;
  if length(trim(coalesce(p_tooltip, ''))) not between 1 and 80
      or length(trim(coalesce(p_title, ''))) not between 1 and 80
      or length(coalesce(p_notice, '')) > 80 then
    raise exception 'Invalid print wording';
  end if;
  update public.schedule_months set
    print_tooltip = p_tooltip, print_title = p_title, print_notice = p_notice
  where month_start = p_month_start and release_state = 'released';
  if not found then raise exception 'Released month not found'; end if;
end;
$$;
revoke all on function public.correct_month_print_wording(date, text, text, text) from public;
grant execute on function public.correct_month_print_wording(date, text, text, text) to authenticated;

create function public.audit_month_print_wording()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := public.current_staff_member_id();
  v_name text;
begin
  if old.release_state = 'released' and
      (old.print_tooltip, old.print_title, old.print_notice) is distinct from
      (new.print_tooltip, new.print_title, new.print_notice) and v_actor is not null then
    select display_name into v_name from public.staff_members where id = v_actor;
    insert into public.unit_setting_audit(kind, actor_id, actor_name,
      before_value, after_value)
    values ('Released month print wording', v_actor, coalesce(v_name, 'Staff member'),
      jsonb_build_object('month', old.month_start, 'tooltip', old.print_tooltip,
        'title', old.print_title, 'notice', old.print_notice),
      jsonb_build_object('month', new.month_start, 'tooltip', new.print_tooltip,
        'title', new.print_title, 'notice', new.print_notice));
  end if;
  return new;
end;
$$;
revoke all on function public.audit_month_print_wording() from public;
create trigger audit_month_print_wording after update of print_tooltip, print_title, print_notice
  on public.schedule_months for each row
  execute function public.audit_month_print_wording();
