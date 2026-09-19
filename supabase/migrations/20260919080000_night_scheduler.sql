-- The Manager gives the Night scheduler role to a Staff member and chooses the
-- Sections they may edit. Their saves in those Sections go through the same
-- logged save as the Manager's; everywhere else the database refuses them.

create table public.night_scheduler_sections (
  staff_member_id uuid not null references public.staff_members(id),
  section_id uuid not null references public.sections(id),
  created_at timestamptz not null default now(),
  primary key (staff_member_id, section_id)
);

alter table public.night_scheduler_sections enable row level security;

grant select on public.night_scheduler_sections to authenticated;

create policy "active staff can read Night scheduler Sections"
on public.night_scheduler_sections for select
using (public.is_active_staff_member());

create function public.can_edit_section(p_section_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    public.current_staff_role() = 'manager'
    or (
      public.current_staff_role() = 'night_scheduler'
      and exists (
        select 1
        from public.night_scheduler_sections assigned
        where assigned.staff_member_id = public.current_staff_member_id()
          and assigned.section_id = p_section_id
      )
    ),
    false
  )
$$;

revoke all on function public.can_edit_section(uuid) from public;
grant execute on function public.can_edit_section(uuid) to authenticated;

create function public.editable_section_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select section.id
  from public.sections section
  where public.can_edit_section(section.id)
  order by section.display_order
$$;

revoke all on function public.editable_section_ids() from public;
grant execute on function public.editable_section_ids() to authenticated;

create function public.assign_night_scheduler(
  p_staff_member_id uuid,
  p_section_ids uuid[]
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not public.can_edit_schedule() then
    raise exception 'Only the Manager can assign the Night scheduler';
  end if;
  if coalesce(cardinality(p_section_ids), 0) = 0 then
    raise exception 'The Night scheduler needs at least one Section';
  end if;
  if exists (
    select 1
    from unnest(p_section_ids) as requested(section_id)
    where not exists (
      select 1 from public.sections where id = requested.section_id
    )
  ) then
    raise exception 'Section not found';
  end if;

  update public.staff_members
  set role = 'night_scheduler'
  where id = p_staff_member_id
    and active
    and role in ('staff_member', 'night_scheduler');
  if not found then
    raise exception 'Only a Staff member can be the Night scheduler';
  end if;

  delete from public.night_scheduler_sections
  where staff_member_id = p_staff_member_id;

  insert into public.night_scheduler_sections (staff_member_id, section_id)
  select distinct p_staff_member_id, requested.section_id
  from unnest(p_section_ids) as requested(section_id);
end;
$$;

revoke all on function public.assign_night_scheduler(uuid, uuid[]) from public;
grant execute on function public.assign_night_scheduler(uuid, uuid[])
to authenticated;

create function public.remove_night_scheduler(p_staff_member_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not public.can_edit_schedule() then
    raise exception 'Only the Manager can remove the Night scheduler';
  end if;

  update public.staff_members
  set role = 'staff_member'
  where id = p_staff_member_id
    and role = 'night_scheduler';

  delete from public.night_scheduler_sections
  where staff_member_id = p_staff_member_id;
end;
$$;

revoke all on function public.remove_night_scheduler(uuid) from public;
grant execute on function public.remove_night_scheduler(uuid) to authenticated;

-- The logged save now admits the Night scheduler in their Sections.
create or replace function public.save_schedule_cell(
  p_staff_member_id uuid,
  p_section_id uuid,
  p_work_date date,
  p_shift_code text
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_month_id uuid;
  v_new_code text := trim(coalesce(p_shift_code, ''));
  v_old_code text;
begin
  if not public.can_edit_section(p_section_id) then
    if public.current_staff_role() = 'night_scheduler' then
      raise exception 'Only the Manager can edit that Section';
    end if;
    raise exception 'Only the Manager can edit the Schedule';
  end if;
  if not exists (
    select 1
    from public.staff_members member
    join public.staff_section_assignments assignment
      on assignment.staff_member_id = member.id
      and assignment.section_id = p_section_id
      and assignment.effective_through is null
    where member.id = p_staff_member_id
      and member.active
  ) then
    raise exception 'That Staff member is not on the Staff list in this Section';
  end if;

  insert into public.schedule_months (month_start)
  values (date_trunc('month', p_work_date)::date)
  on conflict (month_start) do nothing;

  select month.id
  into v_month_id
  from public.schedule_months month
  where month.month_start = date_trunc('month', p_work_date)::date;

  perform pg_advisory_xact_lock(
    hashtext(p_staff_member_id::text || ':' || p_work_date::text)
  );

  select cell.shift_code
  into v_old_code
  from public.schedule_cells cell
  where cell.schedule_month_id = v_month_id
    and cell.staff_member_id = p_staff_member_id
    and cell.work_date = p_work_date;
  v_old_code := coalesce(v_old_code, '');

  if v_old_code = v_new_code then
    return;
  end if;

  insert into public.schedule_cells (
    schedule_month_id,
    staff_member_id,
    section_id,
    work_date,
    shift_code
  ) values (
    v_month_id,
    p_staff_member_id,
    p_section_id,
    p_work_date,
    v_new_code
  )
  on conflict (schedule_month_id, staff_member_id, work_date) do update
  set shift_code = excluded.shift_code,
      section_id = excluded.section_id,
      updated_at = now();

  insert into public.schedule_changes (
    schedule_month_id,
    staff_member_id,
    section_id,
    work_date,
    old_shift_code,
    new_shift_code,
    changed_by_staff_member_id
  ) values (
    v_month_id,
    p_staff_member_id,
    p_section_id,
    p_work_date,
    v_old_code,
    v_new_code,
    public.current_staff_member_id()
  );
end;
$$;
