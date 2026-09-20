-- All Manager-controlled access transitions share one atomic operation.
create function public.set_staff_access_role(
  p_staff_member_id uuid,
  p_new_role public.staff_role,
  p_section_ids uuid[] default '{}'
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_old_role public.staff_role;
  v_active boolean;
  v_manager_id uuid;
begin
  perform pg_advisory_xact_lock(810081);
  if public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the Manager can change access roles';
  end if;
  v_manager_id := public.current_staff_member_id();
  if p_staff_member_id = v_manager_id then
    raise exception 'Choose another Staff member';
  end if;
  select role, active into v_old_role, v_active
  from public.staff_members where id = p_staff_member_id for update;
  if not found then raise exception 'Staff member not found'; end if;
  if v_old_role = 'manager' then
    raise exception 'Transfer the Manager role before changing this person';
  end if;
  if not v_active and p_new_role <> 'staff_member' then
    raise exception 'A person with a Last day can only have access removed';
  end if;
  if p_new_role = 'night_scheduler' then
    if coalesce(cardinality(p_section_ids), 0) = 0 then
      raise exception 'The Night scheduler needs at least one Section';
    end if;
    if exists (
      select 1 from unnest(p_section_ids) as requested(section_id)
      where not exists (select 1 from public.sections where id = requested.section_id)
    ) then raise exception 'Section not found'; end if;
  end if;
  if p_new_role = 'manager' and not exists (
    select 1 from public.staff_accounts account
    where account.staff_member_id = p_staff_member_id
      and account.revoked_at is null and account.accepted_invite_at is not null
  ) then raise exception 'Choose an active Staff member with an accepted Invite'; end if;

  if p_new_role <> v_old_role then
    update public.staff_members set role = p_new_role where id = p_staff_member_id;
    if p_new_role = 'manager' then
      update public.staff_members set role = 'administrator' where id = v_manager_id;
      perform public.log_staff_change(v_manager_id, 'access_role',
        'manager', 'administrator', current_date);
    end if;
    -- The Last day trigger logs this unusual already-departed transition.
    if not (v_old_role = 'night_scheduler' and p_new_role = 'staff_member'
        and not v_active) then
      perform public.log_staff_change(p_staff_member_id, 'access_role',
        v_old_role::text, p_new_role::text, current_date);
    end if;
  end if;
  delete from public.night_scheduler_sections where staff_member_id = p_staff_member_id;
  if p_new_role = 'night_scheduler' then
    insert into public.night_scheduler_sections (staff_member_id, section_id)
    select distinct p_staff_member_id, requested.section_id
    from unnest(p_section_ids) as requested(section_id);
  end if;
end;
$$;
revoke all on function public.set_staff_access_role(uuid, public.staff_role, uuid[]) from public;
grant execute on function public.set_staff_access_role(uuid, public.staff_role, uuid[]) to authenticated;

-- Setting a Last day automatically removes Night scheduler access. Record it.
create function public.log_departing_night_scheduler()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.role = 'night_scheduler' and new.role = 'staff_member'
      and not old.active and old.last_day is not null then
    perform public.log_staff_change(new.id, 'access_role',
      'night_scheduler', 'staff_member', current_date);
  end if;
  return new;
end;
$$;
revoke all on function public.log_departing_night_scheduler() from public;
create trigger log_departing_night_scheduler after update of role on public.staff_members
for each row execute function public.log_departing_night_scheduler();

-- Keep the older Schedule screen's actions in the same access history.
create or replace function public.assign_night_scheduler(
  p_staff_member_id uuid, p_section_ids uuid[]
)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  perform public.set_staff_access_role(
    p_staff_member_id, 'night_scheduler'::public.staff_role, p_section_ids
  );
end;
$$;

create or replace function public.remove_night_scheduler(p_staff_member_id uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  perform public.set_staff_access_role(
    p_staff_member_id, 'staff_member'::public.staff_role, '{}'::uuid[]
  );
end;
$$;
