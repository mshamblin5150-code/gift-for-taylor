create table public.schedule_changes (
  id uuid primary key default gen_random_uuid(),
  schedule_month_id uuid not null references public.schedule_months(id) on delete cascade,
  staff_member_id uuid not null references public.staff_members(id),
  section_id uuid not null references public.sections(id),
  work_date date not null,
  old_shift_code text not null,
  new_shift_code text not null,
  changed_by_staff_member_id uuid not null references public.staff_members(id),
  changed_at timestamptz not null default clock_timestamp(),
  announced_at timestamptz
);

create index schedule_changes_by_month
on public.schedule_changes (schedule_month_id, changed_at);

create function public.current_staff_member_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select member.id
  from public.staff_accounts account
  join public.staff_members member on member.id = account.staff_member_id
  where account.auth_user_id = auth.uid()
    and member.active
    and account.accepted_invite_at is not null
$$;

revoke all on function public.current_staff_member_id() from public;

create function public.can_edit_schedule()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.current_staff_role() = 'manager', false)
$$;

revoke all on function public.can_edit_schedule() from public;
grant execute on function public.can_edit_schedule() to authenticated;

create function public.can_read_change_log()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    public.current_staff_role() in ('manager', 'administrator', 'night_scheduler'),
    false
  )
$$;

revoke all on function public.can_read_change_log() from public;
grant execute on function public.can_read_change_log() to authenticated;

alter table public.schedule_changes enable row level security;

grant select on public.schedule_changes to authenticated;

create policy "schedulers can read the change log"
on public.schedule_changes for select
using (public.can_read_change_log());

-- A save is live at once and logged in the same transaction. Cells have no
-- write grants, so this is the only way to change the Schedule.
create function public.save_schedule_cell(
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
  if not public.can_edit_schedule() then
    raise exception 'Only the Manager can edit the Schedule';
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

revoke all on function public.save_schedule_cell(uuid, uuid, date, text) from public;
grant execute on function public.save_schedule_cell(uuid, uuid, date, text)
to authenticated;

-- Other signed-in schedulers see a save as soon as it is logged.
alter publication supabase_realtime add table public.schedule_changes;
