-- Adding, changing and removing employees. A Last day deactivates the person
-- at once; their later shifts are cleared and marked short. Past staff can be
-- reactivated as the same person. Section and role changes are dated, so the
-- month grid shows each person in the Section they're in during that month.

create type public.job_role as enum ('rn', 'lpn', 'cna', 'unit_clerk');

create table public.staff_job_roles (
  id uuid primary key default gen_random_uuid(),
  staff_member_id uuid not null references public.staff_members(id),
  job_role public.job_role not null,
  effective_from date not null,
  effective_through date,
  created_at timestamptz not null default now(),
  check (effective_through is null or effective_through >= effective_from)
);

create unique index one_current_job_role_per_staff_member
on public.staff_job_roles (staff_member_id)
where effective_through is null;

-- A shift left uncovered. Open shifts will be posted from these once that
-- increment exists.
create table public.short_shifts (
  id uuid primary key default gen_random_uuid(),
  schedule_month_id uuid not null references public.schedule_months(id) on delete cascade,
  section_id uuid not null references public.sections(id),
  work_date date not null,
  shift_code text not null,
  staff_member_id uuid not null references public.staff_members(id),
  reason text not null check (reason in ('last_day')),
  created_at timestamptz not null default now()
);

create index short_shifts_by_month
on public.short_shifts (schedule_month_id, work_date);

-- Append-only log of Staff list changes. Sections are recorded by name and
-- roles by label, as they were at the time.
create table public.staff_changes (
  id uuid primary key default gen_random_uuid(),
  staff_member_id uuid not null references public.staff_members(id),
  kind text not null check (kind in ('last_day', 'reactivated', 'section', 'job_role')),
  old_value text,
  new_value text,
  effective_from date not null,
  changed_by_staff_member_id uuid not null references public.staff_members(id),
  changed_at timestamptz not null default clock_timestamp()
);

alter table public.staff_job_roles enable row level security;
alter table public.short_shifts enable row level security;
alter table public.staff_changes enable row level security;

grant select on public.staff_job_roles to authenticated;
grant select on public.short_shifts to authenticated;
grant select on public.staff_changes to authenticated;

create policy "active staff can read roles"
on public.staff_job_roles for select
using (public.is_active_staff_member());

create policy "staff can read short shifts in visible months"
on public.short_shifts for select
using (
  exists (
    select 1
    from public.schedule_months month
    where month.id = schedule_month_id
  )
);

create policy "schedulers can read the Staff list change log"
on public.staff_changes for select
using (public.can_read_change_log());

-- Mirrors isWorkingShift in the schedule rules: anything but blank or a
-- legend code without hours.
create function public.is_working_shift(p_shift_code text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select length(trim(p_shift_code)) > 0
    and upper(trim(p_shift_code)) not in ('X', 'R/O', 'H', 'S/L')
$$;

-- Every placement of each person, for building a month's rows. A month shows
-- each person once, in their latest placement that overlaps it.
create view public.schedule_row_assignments
with (security_invoker = true)
as
select
  assignment.staff_member_id,
  member.display_name,
  member.last_day,
  assignment.section_id,
  assignment.display_order,
  assignment.effective_from,
  assignment.effective_through
from public.staff_section_assignments assignment
join public.staff_members member on member.id = assignment.staff_member_id;

grant select on public.schedule_row_assignments to authenticated;

create or replace view public.staff_list_entries
with (security_invoker = true)
as
select
  member.id,
  member.display_name,
  member.cell_number,
  assignment.section_id,
  assignment.display_order,
  account.personal_email,
  assignment.effective_from as section_from,
  job_role.job_role
from public.staff_members member
join public.staff_section_assignments assignment
  on assignment.staff_member_id = member.id
  and assignment.effective_through is null
left join public.staff_accounts account
  on account.staff_member_id = member.id
left join public.staff_job_roles job_role
  on job_role.staff_member_id = member.id
  and job_role.effective_through is null
where member.active;

-- People who have left, each with the Section they were last in.
create view public.past_staff_entries
with (security_invoker = true)
as
select
  member.id,
  member.display_name,
  member.cell_number,
  member.last_day,
  (
    select assignment.section_id
    from public.staff_section_assignments assignment
    where assignment.staff_member_id = member.id
    order by assignment.effective_from desc
    limit 1
  ) as section_id
from public.staff_members member
where not member.active;

grant select on public.past_staff_entries to authenticated;

create function public.log_staff_change(
  p_staff_member_id uuid,
  p_kind text,
  p_old_value text,
  p_new_value text,
  p_effective_from date
)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  insert into public.staff_changes (
    staff_member_id,
    kind,
    old_value,
    new_value,
    effective_from,
    changed_by_staff_member_id
  ) values (
    p_staff_member_id,
    p_kind,
    p_old_value,
    p_new_value,
    p_effective_from,
    public.current_staff_member_id()
  )
$$;

revoke all on function public.log_staff_change(uuid, text, text, text, date) from public;

create function public.set_staff_last_day(
  p_staff_member_id uuid,
  p_last_day date
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_cell record;
begin
  if not public.can_manage_staff() then
    raise exception 'Only the Manager or administrator can manage the Staff list';
  end if;
  if p_last_day is null then
    raise exception 'A Last day is required';
  end if;
  if p_staff_member_id = public.current_staff_member_id() then
    raise exception 'You can''t set your own Last day';
  end if;

  update public.staff_members
  set active = false,
      last_day = p_last_day
  where id = p_staff_member_id
    and active;
  if not found then
    raise exception 'That person is not on the Staff list';
  end if;

  -- Placements planned to start after the Last day no longer apply.
  delete from public.staff_section_assignments
  where staff_member_id = p_staff_member_id
    and effective_from > p_last_day;
  update public.staff_section_assignments
  set effective_through = p_last_day
  where staff_member_id = p_staff_member_id
    and (effective_through is null or effective_through > p_last_day);

  delete from public.staff_job_roles
  where staff_member_id = p_staff_member_id
    and effective_from > p_last_day;
  update public.staff_job_roles
  set effective_through = p_last_day
  where staff_member_id = p_staff_member_id
    and (effective_through is null or effective_through > p_last_day);

  -- Sign-in stops at once; an unused Invite can no longer be accepted.
  update public.invites
  set revoked_at = now()
  where staff_member_id = p_staff_member_id
    and accepted_at is null
    and revoked_at is null;

  for v_cell in
    select cell.id, cell.schedule_month_id, cell.section_id, cell.work_date, cell.shift_code
    from public.schedule_cells cell
    where cell.staff_member_id = p_staff_member_id
      and cell.work_date > p_last_day
      and cell.shift_code <> ''
    order by cell.work_date
    for update
  loop
    update public.schedule_cells
    set shift_code = '',
        updated_at = now()
    where id = v_cell.id;

    insert into public.schedule_changes (
      schedule_month_id,
      staff_member_id,
      section_id,
      work_date,
      old_shift_code,
      new_shift_code,
      changed_by_staff_member_id
    ) values (
      v_cell.schedule_month_id,
      p_staff_member_id,
      v_cell.section_id,
      v_cell.work_date,
      v_cell.shift_code,
      '',
      public.current_staff_member_id()
    );

    if public.is_working_shift(v_cell.shift_code) then
      insert into public.short_shifts (
        schedule_month_id,
        section_id,
        work_date,
        shift_code,
        staff_member_id,
        reason
      ) values (
        v_cell.schedule_month_id,
        v_cell.section_id,
        v_cell.work_date,
        v_cell.shift_code,
        p_staff_member_id,
        'last_day'
      );
    end if;
  end loop;

  perform public.log_staff_change(
    p_staff_member_id, 'last_day', null, p_last_day::text, p_last_day
  );
end;
$$;

revoke all on function public.set_staff_last_day(uuid, date) from public;
grant execute on function public.set_staff_last_day(uuid, date) to authenticated;

-- The returning person is the same Staff member, so their past months and
-- change log stay connected. Their old sign-in link is dropped: it is access,
-- not history, and they come back in through a fresh Invite.
create function public.reactivate_staff_member(
  p_staff_member_id uuid,
  p_section_id uuid,
  p_first_day date
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_last_day date;
  v_display_order integer;
  v_job_role public.job_role;
  v_section_name text;
begin
  if not public.can_manage_staff() then
    raise exception 'Only the Manager or administrator can manage the Staff list';
  end if;

  select member.last_day
  into v_last_day
  from public.staff_members member
  where member.id = p_staff_member_id
    and not member.active
  for update;
  if not found then
    raise exception 'That person is already on the Staff list';
  end if;
  if p_first_day is null or p_first_day <= coalesce(v_last_day, '-infinity'::date) then
    raise exception 'Their first day back must be after their Last day';
  end if;

  select section.name
  into v_section_name
  from public.sections section
  where section.id = p_section_id;
  if not found then
    raise exception 'Section not found';
  end if;

  update public.staff_members
  set active = true,
      last_day = null
  where id = p_staff_member_id;

  perform pg_advisory_xact_lock(hashtext(p_section_id::text));
  select coalesce(max(assignment.display_order) + 1, 0)
  into v_display_order
  from public.staff_section_assignments assignment
  where assignment.section_id = p_section_id
    and assignment.effective_through is null;

  insert into public.staff_section_assignments (
    staff_member_id,
    section_id,
    display_order,
    effective_from
  ) values (
    p_staff_member_id,
    p_section_id,
    v_display_order,
    p_first_day
  );

  select job_role.job_role
  into v_job_role
  from public.staff_job_roles job_role
  where job_role.staff_member_id = p_staff_member_id
  order by job_role.effective_from desc
  limit 1;
  if found then
    insert into public.staff_job_roles (staff_member_id, job_role, effective_from)
    values (p_staff_member_id, v_job_role, p_first_day);
  end if;

  delete from public.staff_accounts
  where staff_member_id = p_staff_member_id;

  perform public.log_staff_change(
    p_staff_member_id, 'reactivated', null, v_section_name, p_first_day
  );
end;
$$;

revoke all on function public.reactivate_staff_member(uuid, uuid, date) from public;
grant execute on function public.reactivate_staff_member(uuid, uuid, date)
to authenticated;

-- The row moves to the new Section from p_from. Scheduled cells keep their
-- codes for the Manager to adjust.
create function public.change_staff_section(
  p_staff_member_id uuid,
  p_section_id uuid,
  p_from date
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_current public.staff_section_assignments%rowtype;
  v_display_order integer;
  v_old_name text;
  v_new_name text;
begin
  if not public.can_manage_staff() then
    raise exception 'Only the Manager or administrator can manage the Staff list';
  end if;

  select assignment.*
  into v_current
  from public.staff_section_assignments assignment
  join public.staff_members member on member.id = assignment.staff_member_id
  where assignment.staff_member_id = p_staff_member_id
    and assignment.effective_through is null
    and member.active
  for update of assignment;
  if not found then
    raise exception 'That person is not on the Staff list';
  end if;

  select section.name into v_new_name
  from public.sections section
  where section.id = p_section_id;
  if not found then
    raise exception 'Section not found';
  end if;
  if v_current.section_id = p_section_id then
    raise exception 'They are already in that Section';
  end if;
  if p_from is null or p_from < v_current.effective_from then
    raise exception 'The move must start on or after their current Section did';
  end if;

  select section.name into v_old_name
  from public.sections section
  where section.id = v_current.section_id;

  if p_from = v_current.effective_from then
    delete from public.staff_section_assignments where id = v_current.id;
  else
    update public.staff_section_assignments
    set effective_through = p_from - 1
    where id = v_current.id;
  end if;

  perform pg_advisory_xact_lock(hashtext(p_section_id::text));
  select coalesce(max(assignment.display_order) + 1, 0)
  into v_display_order
  from public.staff_section_assignments assignment
  where assignment.section_id = p_section_id
    and assignment.effective_through is null;

  insert into public.staff_section_assignments (
    staff_member_id,
    section_id,
    display_order,
    effective_from
  ) values (
    p_staff_member_id,
    p_section_id,
    v_display_order,
    p_from
  );

  perform public.log_staff_change(
    p_staff_member_id, 'section', v_old_name, v_new_name, p_from
  );
end;
$$;

revoke all on function public.change_staff_section(uuid, uuid, date) from public;
grant execute on function public.change_staff_section(uuid, uuid, date)
to authenticated;

create function public.job_role_label(p_job_role public.job_role)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_job_role
    when 'rn' then 'RN'
    when 'lpn' then 'LPN'
    when 'cna' then 'CNA'
    when 'unit_clerk' then 'Unit clerk'
  end
$$;

create function public.change_staff_job_role(
  p_staff_member_id uuid,
  p_job_role public.job_role,
  p_from date
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_current public.staff_job_roles%rowtype;
begin
  if not public.can_manage_staff() then
    raise exception 'Only the Manager or administrator can manage the Staff list';
  end if;
  perform 1
  from public.staff_members member
  where member.id = p_staff_member_id
    and member.active
  for update;
  if not found then
    raise exception 'That person is not on the Staff list';
  end if;
  if p_from is null then
    raise exception 'A start date is required';
  end if;

  select job_role.*
  into v_current
  from public.staff_job_roles job_role
  where job_role.staff_member_id = p_staff_member_id
    and job_role.effective_through is null;

  if found then
    if v_current.job_role = p_job_role then
      raise exception 'They already have that role';
    end if;
    if p_from < v_current.effective_from then
      raise exception 'The change must start on or after their current role did';
    end if;
    if p_from = v_current.effective_from then
      delete from public.staff_job_roles where id = v_current.id;
    else
      update public.staff_job_roles
      set effective_through = p_from - 1
      where id = v_current.id;
    end if;
  end if;

  insert into public.staff_job_roles (staff_member_id, job_role, effective_from)
  values (p_staff_member_id, p_job_role, p_from);

  perform public.log_staff_change(
    p_staff_member_id,
    'job_role',
    public.job_role_label(v_current.job_role),
    public.job_role_label(p_job_role),
    p_from
  );
end;
$$;

revoke all on function public.change_staff_job_role(uuid, public.job_role, date) from public;
grant execute on function public.change_staff_job_role(uuid, public.job_role, date)
to authenticated;

-- A cell can be saved for anyone placed in that Section during its month, up
-- to their Last day, including someone who has since left.
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
  v_month_start date := date_trunc('month', p_work_date)::date;
  v_month_id uuid;
  v_new_code text := trim(coalesce(p_shift_code, ''));
  v_old_code text;
  v_last_day date;
begin
  if not public.can_edit_schedule() then
    raise exception 'Only the Manager can edit the Schedule';
  end if;

  -- Waits for a Last day being set at the same time.
  select member.last_day
  into v_last_day
  from public.staff_members member
  where member.id = p_staff_member_id
  for share;
  if not found or not exists (
    select 1
    from public.staff_section_assignments assignment
    where assignment.staff_member_id = p_staff_member_id
      and assignment.section_id = p_section_id
      and assignment.effective_from < (v_month_start + interval '1 month')::date
      and (assignment.effective_through is null
        or assignment.effective_through >= v_month_start)
  ) then
    raise exception 'That Staff member is not on the Staff list in this Section';
  end if;
  if p_work_date > v_last_day then
    raise exception 'That day is after their Last day';
  end if;

  insert into public.schedule_months (month_start)
  values (v_month_start)
  on conflict (month_start) do nothing;

  select month.id
  into v_month_id
  from public.schedule_months month
  where month.month_start = v_month_start;

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
