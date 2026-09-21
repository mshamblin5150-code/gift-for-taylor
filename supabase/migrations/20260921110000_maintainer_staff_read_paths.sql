-- The separately provisioned Maintainer must be able to enter the app and
-- choose a successor without a Staff account of their own.
create policy "Maintainer reads Sections"
  on public.sections for select to authenticated
  using (public.is_maintainer());

create policy "Maintainer reads Staff members"
  on public.staff_members for select to authenticated
  using (public.is_maintainer());

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
  on assignment.staff_member_id = member.id and assignment.effective_through is null
left join public.staff_accounts account
  on account.staff_member_id = member.id and account.revoked_at is null
left join public.staff_job_roles job_role
  on job_role.staff_member_id = member.id and job_role.effective_through is null
where member.active
  and (public.is_active_staff_member() or public.is_maintainer());
