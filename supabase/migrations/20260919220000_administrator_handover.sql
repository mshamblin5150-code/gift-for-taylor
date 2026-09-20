-- Protect the last active Manager, including when an administrator sets a Last day.
create function public.keep_active_manager()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.active and old.role = 'manager'
      and (tg_op = 'DELETE' or not new.active or new.role <> 'manager') then
    perform pg_advisory_xact_lock(810081);
    if not exists (
      select 1 from public.staff_members member
      where member.id <> old.id and member.active and member.role = 'manager'
    ) then
      raise exception 'The unit needs an active Manager';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function public.keep_active_manager() from public;
create trigger keep_active_manager before update or delete on public.staff_members
for each row execute function public.keep_active_manager();

alter table public.staff_changes drop constraint staff_changes_kind_check;
alter table public.staff_changes add constraint staff_changes_kind_check
  check (kind in ('last_day', 'reactivated', 'section', 'job_role',
    'name', 'cell_number', 'access_role'));

create function public.assign_administrator(p_staff_member_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(810081);
  if public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the Manager can assign an administrator';
  end if;
  update public.staff_members set role = 'administrator'
  where id = p_staff_member_id and active and role = 'staff_member';
  if not found then raise exception 'Only an active Staff member can become administrator'; end if;
  perform public.log_staff_change(p_staff_member_id, 'access_role',
    'staff_member', 'administrator', current_date);
end;
$$;
revoke all on function public.assign_administrator(uuid) from public;
grant execute on function public.assign_administrator(uuid) to authenticated;

create function public.remove_administrator(p_staff_member_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(810081);
  if public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the Manager can remove an administrator';
  end if;
  update public.staff_members set role = 'staff_member'
  where id = p_staff_member_id and active and role = 'administrator';
  if not found then raise exception 'That person is not an active administrator'; end if;
  perform public.log_staff_change(p_staff_member_id, 'access_role',
    'administrator', 'staff_member', current_date);
end;
$$;
revoke all on function public.remove_administrator(uuid) from public;
grant execute on function public.remove_administrator(uuid) to authenticated;

create function public.transfer_manager(p_new_manager_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_old_manager_id uuid;
  v_old_role public.staff_role;
begin
  -- Check authority after the handover lock, so a concurrent handover cannot
  -- use a Manager role that has already been transferred away.
  perform pg_advisory_xact_lock(810081);
  if public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the Manager can transfer the Manager role';
  end if;
  v_old_manager_id := public.current_staff_member_id();
  if p_new_manager_id = v_old_manager_id then
    raise exception 'Choose another Staff member as Manager';
  end if;
  select member.role into v_old_role
  from public.staff_members member
  join public.staff_accounts account on account.staff_member_id = member.id
  where member.id = p_new_manager_id and member.active
    and account.revoked_at is null and account.accepted_invite_at is not null
    and member.role in ('staff_member', 'administrator')
  for update of member;
  if not found then
    raise exception 'Choose an active Staff member with an accepted Invite';
  end if;
  update public.staff_members set role = 'manager' where id = p_new_manager_id;
  update public.staff_members set role = 'administrator' where id = v_old_manager_id;
  perform public.log_staff_change(p_new_manager_id, 'access_role',
    v_old_role::text, 'manager', current_date);
  perform public.log_staff_change(v_old_manager_id, 'access_role',
    'manager', 'administrator', current_date);
end;
$$;
revoke all on function public.transfer_manager(uuid) from public;
grant execute on function public.transfer_manager(uuid) to authenticated;
