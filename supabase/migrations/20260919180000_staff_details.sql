-- Contact details are available only through Manager/Administrator guarded RPCs.
revoke select on public.staff_members from anon, authenticated;
grant select (id, display_name, role, active, last_day, created_at)
on public.staff_members to anon, authenticated;
-- staff_accounts already limits Staff members to their own account with RLS.

-- Keep the list useful to staff without exposing contact details.
create or replace view public.staff_list_entries
with (security_invoker = false)
as
select
  member.id, member.display_name,
  case when public.can_manage_staff() then member.cell_number end as cell_number,
  assignment.section_id, assignment.display_order,
  case when public.can_manage_staff() then account.personal_email end as personal_email,
  assignment.effective_from as section_from, job_role.job_role
from public.staff_members member
join public.staff_section_assignments assignment
  on assignment.staff_member_id = member.id and assignment.effective_through is null
left join public.staff_accounts account
  on account.staff_member_id = member.id and account.revoked_at is null
left join public.staff_job_roles job_role
  on job_role.staff_member_id = member.id and job_role.effective_through is null
where member.active and public.is_active_staff_member();

create or replace view public.past_staff_entries
with (security_invoker = false)
as
select member.id, member.display_name,
  case when public.can_manage_staff() then member.cell_number end as cell_number,
  member.last_day,
  (select assignment.section_id from public.staff_section_assignments assignment
   where assignment.staff_member_id = member.id
   order by assignment.effective_from desc limit 1) as section_id
from public.staff_members member
where not member.active and public.can_manage_staff();

create or replace function public.schedule_rows(p_month_start date)
returns table (staff_member_id uuid, display_name text, section_id uuid,
  cell_number text, last_day date)
language sql stable security definer set search_path = ''
as $$
  with bounds as (
    select date_trunc('month', p_month_start)::date as month_start,
      (date_trunc('month', p_month_start) + interval '1 month - 1 day')::date as month_end
  ), held as (
    select distinct on (assignment.staff_member_id) assignment.staff_member_id,
      assignment.section_id, assignment.display_order, assignment.effective_through
    from public.staff_section_assignments assignment cross join bounds
    where assignment.effective_from <= bounds.month_end
      and (assignment.effective_through is null
        or assignment.effective_through >= bounds.month_start)
    order by assignment.staff_member_id, assignment.effective_from desc
  )
  select member.id, member.display_name, held.section_id,
    case when public.can_manage_staff() and member.active then member.cell_number end,
    held.effective_through
  from held
  join public.staff_members member on member.id = held.staff_member_id
  join public.sections section on section.id = held.section_id
  cross join bounds
  where public.is_active_staff_member()
    and (public.current_staff_role() <> 'staff_member' or exists (
      select 1 from public.schedule_months month
      where month.month_start = bounds.month_start and month.release_state = 'released'
    ))
    and (member.active or exists (
      select 1 from public.schedule_cells cell
      where cell.staff_member_id = member.id
        and cell.work_date between bounds.month_start and bounds.month_end
    ))
  order by section.display_order, held.display_order, member.display_name
$$;

alter table public.staff_changes drop constraint staff_changes_kind_check;
alter table public.staff_changes add constraint staff_changes_kind_check
  check (kind in ('last_day', 'reactivated', 'section', 'job_role', 'name', 'cell_number'));
drop policy "schedulers can read the Staff list change log" on public.staff_changes;
create policy "schedulers can read permitted Staff list changes"
on public.staff_changes for select
using (public.can_read_change_log()
  and (kind not in ('name', 'cell_number') or public.can_manage_staff()));

create function public.staff_member_details(p_staff_member_id uuid)
returns table (id uuid, display_name text, cell_number text,
  section_id uuid, job_role public.job_role, role public.staff_role,
  last_day date, personal_email text)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.can_manage_staff() then
    raise exception 'Only the Manager or administrator can view Staff member details';
  end if;
  return query
  select member.id, member.display_name, member.cell_number,
    assignment.section_id, job.job_role, member.role, member.last_day,
    account.personal_email
  from public.staff_members member
  left join lateral (
    select position.section_id from public.staff_section_assignments position
    where position.staff_member_id = member.id
    order by (position.effective_through is null) desc, position.effective_from desc
    limit 1
  ) assignment on true
  left join public.staff_job_roles job
    on job.staff_member_id = member.id and job.effective_through is null
  left join public.staff_accounts account
    on account.staff_member_id = member.id
  where member.id = p_staff_member_id;
end;
$$;
revoke all on function public.staff_member_details(uuid) from public;
grant execute on function public.staff_member_details(uuid) to authenticated;

create function public.update_staff_contact(p_staff_member_id uuid,
  p_display_name text, p_cell_number text)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_old public.staff_members%rowtype;
  v_name text := nullif(trim(p_display_name), '');
  v_cell text := nullif(trim(p_cell_number), '');
begin
  if not public.can_manage_staff() then
    raise exception 'Only the Manager or administrator can manage the Staff list';
  end if;
  if v_name is null then raise exception 'Name is required'; end if;
  select * into v_old from public.staff_members member
  where member.id = p_staff_member_id for update;
  if not found then raise exception 'That person is not on the Staff list'; end if;
  update public.staff_members set display_name = v_name, cell_number = v_cell
  where id = p_staff_member_id;
  if v_old.display_name is distinct from v_name then
    perform public.log_staff_change(p_staff_member_id, 'name',
      v_old.display_name, v_name, current_date);
  end if;
  if v_old.cell_number is distinct from v_cell then
    perform public.log_staff_change(p_staff_member_id, 'cell_number',
      v_old.cell_number, v_cell, current_date);
  end if;
end;
$$;
revoke all on function public.update_staff_contact(uuid, text, text) from public;
grant execute on function public.update_staff_contact(uuid, text, text) to authenticated;
