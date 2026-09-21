-- Read independent grants in one round trip. The Maintainer has no Staff row.
create function public.current_access()
returns table (
  manager boolean,
  administrator boolean,
  maintainer boolean,
  staff_member_id uuid,
  night_scheduler_section_ids uuid[]
)
language sql stable security definer set search_path = '' as $$
  select
    coalesce(member.role = 'manager', false),
    coalesce(member.role = 'administrator', false),
    public.is_maintainer(),
    member.id,
    coalesce((select array_agg(assignment.section_id order by assignment.section_id)
      from public.night_scheduler_sections assignment
      where assignment.staff_member_id = member.id), '{}'::uuid[])
  from (select 1) singleton
  left join public.staff_accounts account on account.auth_user_id = auth.uid()
    and account.accepted_invite_at is not null and account.revoked_at is null
  left join public.staff_members member on member.id = account.staff_member_id
    and member.active
$$;
revoke all on function public.current_access() from public;
grant execute on function public.current_access() to authenticated;

-- A person with no active Staff access has a negative answer, not NULL.
create or replace function public.can_manage_staff()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.current_staff_role() in ('manager', 'administrator'), false)
$$;

-- A combined Administrator/Night scheduler retains Change log access even
-- though their stored role is Administrator. Do not infer it from role ranking.
create or replace function public.can_read_change_log()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.current_staff_role() in ('manager', 'administrator')
    or exists (select 1 from public.night_scheduler_sections assignment
      where assignment.staff_member_id = public.current_staff_member_id()), false)
$$;
