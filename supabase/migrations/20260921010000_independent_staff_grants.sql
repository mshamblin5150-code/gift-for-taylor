-- A Staff member's Administrator grant is represented by role; assigned
-- Night scheduler Sections are independent and may coexist with it.
create function public.staff_role_for_grants(
  p_administrator boolean, p_section_ids uuid[]
)
returns public.staff_role language sql immutable set search_path = '' as $$
  select case when p_administrator then 'administrator'::public.staff_role
    when cardinality(coalesce(p_section_ids, '{}'::uuid[])) > 0
      then 'night_scheduler'::public.staff_role
    else 'staff_member'::public.staff_role end
$$;
revoke all on function public.staff_role_for_grants(boolean, uuid[]) from public;

create function public.staff_access_label(
  p_role public.staff_role, p_section_ids uuid[]
)
returns text language sql stable security definer set search_path = '' as $$
  select case when cardinality(coalesce(p_section_ids, '{}'::uuid[])) = 0
    or p_role = 'manager' then p_role::text
    else (case when p_role = 'administrator'
      then 'administrator + night_scheduler' else 'night_scheduler' end)
      || ' (' || (select string_agg(section.name, ', ' order by section.name)
        from public.sections section where section.id = any(p_section_ids)) || ')'
    end
$$;
revoke all on function public.staff_access_label(public.staff_role, uuid[]) from public;

create function public.set_staff_access_grants(
  p_staff_member_id uuid, p_administrator boolean, p_section_ids uuid[]
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_member public.staff_members%rowtype;
  v_old_sections uuid[];
  v_new_sections uuid[];
  v_new_role public.staff_role;
  v_old_access text;
  v_new_access text;
begin
  perform pg_advisory_xact_lock(810081);
  if public.can_manage_staff() is not true then
    raise exception 'Only the Manager or Administrator can change Staff access';
  end if;
  if p_staff_member_id = public.current_staff_member_id() then
    raise exception 'Choose another Staff member';
  end if;
  select * into v_member from public.staff_members
    where id = p_staff_member_id for update;
  if not found then raise exception 'Staff member not found'; end if;
  if v_member.role = 'manager' then
    raise exception 'Transfer the Manager role before changing this person';
  end if;
  v_new_sections := coalesce(p_section_ids, '{}'::uuid[]);
  if not v_member.active and (p_administrator or cardinality(v_new_sections) > 0) then
    raise exception 'A person with a Last day can only have access removed';
  end if;
  if exists (select 1 from unnest(v_new_sections) as requested(section_id)
      where not exists (select 1 from public.sections
        where id = requested.section_id)) then
    raise exception 'Section not found';
  end if;
  select coalesce(array_agg(section_id order by section_id), '{}'::uuid[])
    into v_old_sections from public.night_scheduler_sections
    where staff_member_id = p_staff_member_id;
  select coalesce(array_agg(distinct section_id order by section_id), '{}'::uuid[])
    into v_new_sections from unnest(v_new_sections) as requested(section_id);
  v_new_role := public.staff_role_for_grants(p_administrator, v_new_sections);
  v_old_access := public.staff_access_label(v_member.role, v_old_sections);
  v_new_access := public.staff_access_label(v_new_role, v_new_sections);
  if v_member.role is distinct from v_new_role then
    update public.staff_members set role = v_new_role where id = p_staff_member_id;
  end if;
  delete from public.night_scheduler_sections
    where staff_member_id = p_staff_member_id
      and not (section_id = any(v_new_sections));
  insert into public.night_scheduler_sections(staff_member_id, section_id)
    select p_staff_member_id, requested.section_id
    from unnest(v_new_sections) as requested(section_id)
    on conflict do nothing;
  if v_old_access is distinct from v_new_access then
    perform public.log_staff_change(p_staff_member_id, 'access_role',
      v_old_access, v_new_access, current_date);
  end if;
end;
$$;
revoke all on function public.set_staff_access_grants(uuid, boolean, uuid[]) from public;
grant execute on function public.set_staff_access_grants(uuid, boolean, uuid[]) to authenticated;

create or replace function public.can_edit_section(p_section_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.current_staff_role() = 'manager' or exists (
    select 1 from public.night_scheduler_sections assigned
    where assigned.staff_member_id = public.current_staff_member_id()
      and assigned.section_id = p_section_id
  ), false)
$$;

create or replace function public.can_record_call_in(p_section_id uuid)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare
  v_local timestamp := clock_timestamp() at time zone 'America/New_York';
begin
  return public.can_edit_section(p_section_id) or coalesce(
    public.is_active_staff_member() and exists (
      select 1 from public.schedule_cells own
      left join public.shift_codes code on code.code = upper(trim(own.shift_code))
      where own.staff_member_id = public.current_staff_member_id()
        and public.is_working_shift(own.shift_code)
        and ((own.work_date = v_local::date
            and (code.start_time is null
              or (v_local::time >= code.start_time
                and (code.end_time > code.start_time
                  and v_local::time < code.end_time
                  or code.end_time <= code.start_time))))
          or (own.work_date = v_local::date - 1
            and code.end_time <= code.start_time
            and v_local::time < code.end_time))
    ), false);
end;
$$;

-- Invite identity confirmation belongs to Staff-list work.
drop policy "Manager reads pending Invite acceptances" on public.pending_invite_acceptances;
create policy "Staff managers read pending Invite acceptances"
on public.pending_invite_acceptances for select using (public.can_manage_staff());
drop policy "managers can read Invite Cell mismatches" on public.invite_cell_mismatches;
create policy "Staff managers read Invite Cell mismatches"
on public.invite_cell_mismatches for select using (public.can_manage_staff());
do $migration$
declare v_name text; v_definition text;
begin
  foreach v_name in array array['confirm_invite_acceptance', 'reject_invite_acceptance'] loop
    select pg_get_functiondef(p.oid) into v_definition from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = v_name;
    v_definition := replace(v_definition,
      'public.current_staff_role() is distinct from ''manager''::public.staff_role',
      'public.can_manage_staff() is not true');
    v_definition := replace(v_definition, 'Only the Manager can ',
      'Only the Manager or Administrator can ');
    execute v_definition;
  end loop;
end;
$migration$;

-- Former single-role callers retain their entry point. A grant operation
-- changes the named grant and leaves the other grant untouched.
create or replace function public.set_staff_access_role(
  p_staff_member_id uuid, p_new_role public.staff_role,
  p_section_ids uuid[] default '{}'
)
returns void language plpgsql security definer set search_path = '' as $$
declare v_admin boolean; v_sections uuid[];
begin
  if p_new_role = 'manager' then
    perform public.transfer_manager(p_staff_member_id);
    return;
  end if;
  select role = 'administrator' into v_admin from public.staff_members
    where id = p_staff_member_id;
  if p_new_role = 'administrator' then
    v_admin := true;
  elsif p_new_role = 'night_scheduler' then
    if cardinality(coalesce(p_section_ids, '{}'::uuid[])) = 0 then
      raise exception 'The Night scheduler needs at least one Section';
    end if;
  else
    v_admin := false;
  end if;
  select coalesce(array_agg(section_id), '{}'::uuid[]) into v_sections
    from public.night_scheduler_sections where staff_member_id = p_staff_member_id;
  if p_new_role = 'night_scheduler' then v_sections := p_section_ids; end if;
  if p_new_role = 'staff_member' then v_sections := '{}'::uuid[]; end if;
  perform public.set_staff_access_grants(p_staff_member_id, v_admin, v_sections);
end;
$$;

create or replace function public.assign_administrator(p_staff_member_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.set_staff_access_role(p_staff_member_id, 'administrator');
end;
$$;
create or replace function public.remove_administrator(p_staff_member_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_sections uuid[];
begin
  select coalesce(array_agg(section_id), '{}'::uuid[]) into v_sections
    from public.night_scheduler_sections where staff_member_id = p_staff_member_id;
  perform public.set_staff_access_grants(p_staff_member_id, false, v_sections);
end;
$$;
create or replace function public.assign_night_scheduler(
  p_staff_member_id uuid, p_section_ids uuid[]
)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.set_staff_access_role(p_staff_member_id, 'night_scheduler', p_section_ids);
end;
$$;
create or replace function public.remove_night_scheduler(p_staff_member_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.set_staff_access_grants(p_staff_member_id,
    (select role = 'administrator' from public.staff_members where id = p_staff_member_id),
    '{}'::uuid[]);
end;
$$;

-- The explicit handover path and the old RPC share the same default.
create function public.transfer_manager_with_access(
  p_new_manager_id uuid, p_former_administrator boolean,
  p_former_section_ids uuid[]
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_old_manager_id uuid;
  v_old_access text;
  v_new_role public.staff_role;
  v_new_sections uuid[];
  v_former_role public.staff_role;
begin
  perform pg_advisory_xact_lock(810081);
  if public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the Manager can transfer the Manager role';
  end if;
  v_old_manager_id := public.current_staff_member_id();
  if p_new_manager_id = v_old_manager_id then
    raise exception 'Choose another Staff member as Manager';
  end if;
  if exists (select 1 from unnest(coalesce(p_former_section_ids, '{}'::uuid[]))
      as requested(section_id) where not exists
      (select 1 from public.sections where id = requested.section_id)) then
    raise exception 'Section not found';
  end if;
  select member.role into v_new_role from public.staff_members member
    join public.staff_accounts account on account.staff_member_id = member.id
    where member.id = p_new_manager_id and member.active
      and account.revoked_at is null and account.accepted_invite_at is not null
    for update of member;
  if not found then
    raise exception 'Choose an active Staff member with an accepted Invite';
  end if;
  if v_new_role = 'manager' then raise exception 'Choose another Staff member'; end if;
  select coalesce(array_agg(section_id order by section_id), '{}'::uuid[])
    into v_new_sections from public.night_scheduler_sections
    where staff_member_id = p_new_manager_id;
  v_old_access := public.staff_access_label(v_new_role, v_new_sections);
  delete from public.night_scheduler_sections where staff_member_id = p_new_manager_id;
  update public.staff_members set role = 'manager' where id = p_new_manager_id;
  v_former_role := public.staff_role_for_grants(
    p_former_administrator, p_former_section_ids);
  update public.staff_members set role = v_former_role where id = v_old_manager_id;
  delete from public.night_scheduler_sections where staff_member_id = v_old_manager_id;
  insert into public.night_scheduler_sections(staff_member_id, section_id)
    select distinct v_old_manager_id, requested.section_id
    from unnest(coalesce(p_former_section_ids, '{}'::uuid[])) as requested(section_id);
  perform public.log_staff_change(p_new_manager_id, 'access_role',
    v_old_access, 'manager', current_date);
  perform public.log_staff_change(v_old_manager_id, 'access_role',
    'manager', public.staff_access_label(v_former_role, p_former_section_ids),
    current_date);
end;
$$;
revoke all on function public.transfer_manager_with_access(uuid, boolean, uuid[]) from public;
grant execute on function public.transfer_manager_with_access(uuid, boolean, uuid[]) to authenticated;
create or replace function public.transfer_manager(p_new_manager_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.transfer_manager_with_access(p_new_manager_id, false, '{}'::uuid[]);
end;
$$;

-- Last day revokes both grants, including an Administrator who also scheduled.
drop trigger if exists log_departing_night_scheduler on public.staff_members;
create function public.revoke_departing_access()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_old_access text;
begin
  if old.active and not new.active and old.role <> 'manager' then
    v_old_access := public.staff_access_label(old.role,
      (select coalesce(array_agg(section_id), '{}'::uuid[])
       from public.night_scheduler_sections where staff_member_id = old.id));
    delete from public.night_scheduler_sections where staff_member_id = new.id;
    if new.role <> 'staff_member' then
      update public.staff_members set role = 'staff_member' where id = new.id;
      perform public.log_staff_change(new.id, 'access_role',
        v_old_access, 'staff_member', current_date);
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.revoke_departing_access() from public;
create trigger revoke_departing_access after update of active on public.staff_members
for each row execute function public.revoke_departing_access();
