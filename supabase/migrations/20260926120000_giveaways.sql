-- A Giveaway is one atomic, one-way set of shifts between named colleagues.
create type public.giveaway_status as enum
  ('proposed', 'accepted', 'declined', 'approved', 'withdrawn', 'voided');

create table public.giveaways (
  id uuid primary key default gen_random_uuid(),
  giver_id uuid not null references public.staff_members(id),
  colleague_id uuid not null references public.staff_members(id),
  status public.giveaway_status not null default 'proposed',
  reason text,
  created_at timestamptz not null default now(),
  answered_at timestamptz,
  approved_at timestamptz,
  approved_by uuid references public.staff_members(id),
  withdrawn_at timestamptz,
  voided_staff_member_id uuid references public.staff_members(id),
  voided_work_date date,
  check (giver_id <> colleague_id),
  constraint giveaways_void_record check (
    (status = 'voided') =
      (voided_staff_member_id is not null and voided_work_date is not null)
  )
);

create table public.giveaway_shifts (
  id uuid primary key default gen_random_uuid(),
  giveaway_id uuid not null references public.giveaways(id) on delete cascade,
  work_date date not null,
  shift_code text not null,
  target_code text not null,
  section_id uuid not null references public.sections(id),
  unique (giveaway_id, work_date)
);

create index giveaways_by_participants
  on public.giveaways (giver_id, colleague_id, created_at desc);
create index giveaways_approval_queue on public.giveaways (created_at)
  where status = 'accepted';
create index giveaway_shifts_by_giveaway
  on public.giveaway_shifts (giveaway_id, work_date);
create index giveaway_shifts_by_date
  on public.giveaway_shifts (work_date, giveaway_id);

alter table public.giveaways enable row level security;
alter table public.giveaway_shifts enable row level security;
revoke all on public.giveaways, public.giveaway_shifts
  from public, anon, authenticated;
grant select on public.giveaways, public.giveaway_shifts to authenticated;

create policy "Giveaway participants and Manager can read"
on public.giveaways for select using (
  public.current_staff_role() = 'manager'
  or giver_id = public.current_staff_member_id()
  or colleague_id = public.current_staff_member_id()
);
create policy "Giveaway participants and Manager can read shifts"
on public.giveaway_shifts for select using (exists (
  select 1 from public.giveaways giveaway
  where giveaway.id = giveaway_id
    and (public.current_staff_role() = 'manager'
      or giveaway.giver_id = public.current_staff_member_id()
      or giveaway.colleague_id = public.current_staff_member_id())
));

alter table public.schedule_changes add column giveaway_id uuid
  references public.giveaways(id);
create index schedule_changes_by_giveaway
  on public.schedule_changes (giveaway_id) where giveaway_id is not null;

create function public.attribute_schedule_change_giveaway()
returns trigger language plpgsql set search_path = '' as $$
declare
  v_giveaway text := current_setting('app.giveaway_id', true);
begin
  if v_giveaway is not null and v_giveaway <> '' then
    new.giveaway_id := v_giveaway::uuid;
  end if;
  return new;
end;
$$;
create trigger attribute_schedule_change_giveaway
before insert on public.schedule_changes for each row
execute function public.attribute_schedule_change_giveaway();
revoke all on function public.attribute_schedule_change_giveaway() from public;

create function public.giveaway_colleague_eligible(
  p_giver_id uuid, p_colleague_id uuid, p_work_date date
)
returns boolean language sql stable security definer set search_path = '' as $$
  select p_colleague_id is distinct from p_giver_id
    and exists (
      select 1 from public.staff_members member
      join public.staff_accounts account
        on account.staff_member_id = member.id
      where member.id = p_colleague_id and member.active
        and account.accepted_invite_at is not null
        and account.revoked_at is null
    )
    and exists (
      select 1
      from public.staff_job_roles giver_role
      join public.staff_job_roles colleague_role on true
      where giver_role.staff_member_id = p_giver_id
        and giver_role.effective_from <= p_work_date
        and (giver_role.effective_through is null
          or giver_role.effective_through >= p_work_date)
        and colleague_role.staff_member_id = p_colleague_id
        and colleague_role.effective_from <= p_work_date
        and (colleague_role.effective_through is null
          or colleague_role.effective_through >= p_work_date)
        and (colleague_role.job_role = giver_role.job_role
          or (colleague_role.job_role in ('rn', 'lpn')
            and giver_role.job_role in ('rn', 'lpn')))
    )
    and exists (
      select 1 from public.staff_section_assignments assignment
      where assignment.staff_member_id = p_colleague_id
        and assignment.effective_from <= p_work_date
        and (assignment.effective_through is null
          or assignment.effective_through >= p_work_date)
    )
    and not public.staff_member_has_day_conflict(
      p_colleague_id, p_work_date
    );
$$;
revoke all on function public.giveaway_colleague_eligible(uuid, uuid, date)
  from public;

create function public.eligible_giveaway_colleagues(p_dates date[])
returns table(staff_member_id uuid, display_name text)
language sql stable security definer set search_path = '' as $$
  select member.id, member.display_name
  from public.staff_members member
  where public.current_staff_member_id() is not null
    and member.id <> public.current_staff_member_id()
    and coalesce(cardinality(p_dates), 0) between 1 and 31
    and cardinality(p_dates) = cardinality(
      array(select distinct day from unnest(p_dates) day))
    and not exists (
      select 1 from unnest(p_dates) day
      where not public.giveaway_colleague_eligible(
        public.current_staff_member_id(), member.id, day)
    )
  order by lower(member.display_name), member.id;
$$;

create function public.propose_giveaway(
  p_colleague_id uuid, p_dates date[]
)
returns uuid language plpgsql volatile security definer set search_path = '' as $$
declare
  v_giver_id uuid := public.current_staff_member_id();
  v_giveaway_id uuid;
  v_date date;
  v_cell public.schedule_cells%rowtype;
  v_target text;
begin
  if v_giver_id is null or p_colleague_id is null
    or p_colleague_id = v_giver_id then
    raise exception using errcode = 'P2823',
      message = 'Choose another Staff member';
  end if;
  if coalesce(cardinality(p_dates), 0) = 0 then
    raise exception using errcode = 'P2824',
      message = 'Choose at least one shift';
  end if;
  if cardinality(p_dates) > 31 then
    raise exception using errcode = 'P2825',
      message = 'A Giveaway can include at most 31 shifts';
  end if;
  if cardinality(p_dates) <> cardinality(
      array(select distinct day from unnest(p_dates) day)) then
    raise exception using errcode = 'P2826',
      message = 'Choose each shift only once';
  end if;
  if not exists (select 1 from public.staff_members
      where id = p_colleague_id and active)
    or not exists (select 1 from public.staff_accounts
      where staff_member_id = p_colleague_id
        and accepted_invite_at is not null and revoked_at is null) then
    raise exception using errcode = 'P2827',
      message = 'Colleague must have an active Invite';
  end if;
  if exists (select 1 from unnest(p_dates) day where day <= current_date) then
    raise exception using errcode = 'P2828',
      message = 'Giveaway days must be after today';
  end if;

  insert into public.giveaways(giver_id, colleague_id)
  values (v_giver_id, p_colleague_id) returning id into v_giveaway_id;

  foreach v_date in array p_dates loop
    select cell.* into v_cell from public.schedule_cells cell
    join public.schedule_months month on month.id = cell.schedule_month_id
    where cell.staff_member_id = v_giver_id and cell.work_date = v_date
      and month.release_state = 'released';
    if v_cell.id is null or not public.is_working_shift(v_cell.shift_code) then
      raise exception using errcode = 'P2829',
        message = 'Every selected day needs a working shift on a released Schedule';
    end if;
    if not public.giveaway_colleague_eligible(
        v_giver_id, p_colleague_id, v_date) then
      raise exception using errcode = 'P2830',
        message = 'The colleague cannot take every selected shift';
    end if;
    select coalesce((select shift_code from public.schedule_cells
      where staff_member_id = p_colleague_id and work_date = v_date), '')
      into v_target;
    insert into public.giveaway_shifts(
      giveaway_id, work_date, shift_code, target_code, section_id
    ) values (
      v_giveaway_id, v_date, v_cell.shift_code, v_target, v_cell.section_id
    );
  end loop;
  return v_giveaway_id;
end;
$$;

create function public.answer_giveaway(
  p_giveaway_id uuid, p_accept boolean, p_reason text default null
)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  update public.giveaways
  set status = case when p_accept then 'accepted'::public.giveaway_status
      else 'declined'::public.giveaway_status end,
    reason = nullif(trim(p_reason), ''), answered_at = clock_timestamp()
  where id = p_giveaway_id
    and colleague_id = public.current_staff_member_id()
    and status = 'proposed';
  if not found then raise exception 'This Giveaway cannot be answered'; end if;
end;
$$;

create function public.withdraw_giveaway(p_giveaway_id uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  update public.giveaways set status = 'withdrawn',
    withdrawn_at = clock_timestamp()
  where id = p_giveaway_id
    and giver_id = public.current_staff_member_id()
    and status in ('proposed', 'accepted');
  if not found then raise exception 'This Giveaway cannot be withdrawn'; end if;
end;
$$;

create function public.decline_giveaway(
  p_giveaway_id uuid, p_reason text default null
)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the Manager can decline a Giveaway';
  end if;
  update public.giveaways set status = 'declined',
    reason = nullif(trim(p_reason), '')
  where id = p_giveaway_id and status = 'accepted';
  if not found then
    raise exception 'This Giveaway is not awaiting Manager approval';
  end if;
end;
$$;

create function public.giveaway_creates_shortfall(p_giveaway_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.giveaways giveaway
    join public.giveaway_shifts shift
      on shift.giveaway_id = giveaway.id
    join public.staff_job_roles giver_role
      on giver_role.staff_member_id = giveaway.giver_id
      and giver_role.effective_from <= shift.work_date
      and (giver_role.effective_through is null
        or giver_role.effective_through >= shift.work_date)
    join public.staff_job_roles colleague_role
      on colleague_role.staff_member_id = giveaway.colleague_id
      and colleague_role.effective_from <= shift.work_date
      and (colleague_role.effective_through is null
        or colleague_role.effective_through >= shift.work_date)
    join public.shift_codes code
      on code.code = upper(trim(shift.shift_code))
      and code.coverage_window is not null
    join lateral public.section_staffing_for_month(shift.work_date) staffing
      on staffing.work_date = shift.work_date
      and staffing.coverage_window = code.coverage_window
      and staffing.pool = public.coverage_pool_on(
        giver_role.job_role, shift.work_date)
    where giveaway.id = p_giveaway_id
      and (public.current_staff_role() = 'manager'
        or public.current_staff_member_id() in (
          giveaway.giver_id, giveaway.colleague_id
        ))
      and giver_role.job_role = 'rn'
      and colleague_role.job_role = 'lpn'
      and staffing.rn_floor > 0
      and staffing.rn_count <= staffing.rn_floor
  );
$$;

create function public.approve_giveaway(p_giveaway_id uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  v_giveaway public.giveaways%rowtype;
  v_shift public.giveaway_shifts%rowtype;
  v_code text;
  v_section uuid;
  v_key text;
begin
  if public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the Manager can approve a Giveaway';
  end if;
  select * into v_giveaway from public.giveaways
  where id = p_giveaway_id for update;
  if v_giveaway.id is null or v_giveaway.status <> 'accepted' then
    raise exception 'This Giveaway is not awaiting approval';
  end if;
  for v_key in
    select distinct participant::text || ':' || shift.work_date::text
    from public.giveaway_shifts shift
    cross join unnest(array[
      v_giveaway.giver_id, v_giveaway.colleague_id
    ]) participant
    where shift.giveaway_id = p_giveaway_id order by 1
  loop
    perform pg_advisory_xact_lock(hashtext(v_key));
  end loop;
  for v_shift in select * from public.giveaway_shifts
      where giveaway_id = p_giveaway_id order by work_date loop
    if v_shift.work_date <= current_date then
      raise exception 'Giveaway day % must be after today', v_shift.work_date;
    end if;
    select shift_code, section_id into v_code, v_section
    from public.schedule_cells
    where staff_member_id = v_giveaway.giver_id
      and work_date = v_shift.work_date;
    if v_code is distinct from v_shift.shift_code
      or v_section is distinct from v_shift.section_id then
      raise exception 'A Shift code changed; propose a new Giveaway';
    end if;
    select coalesce((select shift_code from public.schedule_cells
      where staff_member_id = v_giveaway.colleague_id
        and work_date = v_shift.work_date), '') into v_code;
    if v_code is distinct from v_shift.target_code then
      raise exception 'A Shift code changed; propose a new Giveaway';
    end if;
    if not public.giveaway_colleague_eligible(
        v_giveaway.giver_id, v_giveaway.colleague_id,
        v_shift.work_date) then
      raise exception 'The colleague can no longer take every selected shift';
    end if;
  end loop;

  update public.giveaways set status = 'approved',
    approved_at = clock_timestamp(),
    approved_by = public.current_staff_member_id()
  where id = p_giveaway_id;
  perform set_config('app.giveaway_id', p_giveaway_id::text, true);

  for v_shift in select * from public.giveaway_shifts
      where giveaway_id = p_giveaway_id order by work_date loop
    perform public.save_schedule_cell(v_giveaway.giver_id,
      v_shift.section_id, v_shift.work_date, 'X');
    select assignment.section_id into v_section
    from public.staff_section_assignments assignment
    where assignment.staff_member_id = v_giveaway.colleague_id
      and assignment.effective_from <= v_shift.work_date
      and (assignment.effective_through is null
        or assignment.effective_through >= v_shift.work_date)
    order by assignment.effective_from desc limit 1;
    perform public.save_schedule_cell(v_giveaway.colleague_id,
      v_section, v_shift.work_date, v_shift.shift_code);
  end loop;
end;
$$;

create function public.void_giveaways_for_changed_cell()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_staff uuid := coalesce(new.staff_member_id, old.staff_member_id);
  v_date date := coalesce(new.work_date, old.work_date);
begin
  if tg_op = 'UPDATE'
    and new.shift_code is not distinct from old.shift_code
    and new.section_id is not distinct from old.section_id then
    return new;
  end if;
  update public.giveaways giveaway set status = 'voided',
    voided_staff_member_id = v_staff, voided_work_date = v_date
  where giveaway.status in ('proposed', 'accepted')
    and v_staff in (giveaway.giver_id, giveaway.colleague_id)
    and exists (select 1 from public.giveaway_shifts shift
      where shift.giveaway_id = giveaway.id and shift.work_date = v_date);
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
create trigger void_giveaways_for_changed_cell
after insert or update or delete on public.schedule_cells
for each row execute function public.void_giveaways_for_changed_cell();
revoke all on function public.void_giveaways_for_changed_cell() from public;

alter table public.staff_notices drop constraint staff_notices_kind_check;
alter table public.staff_notices add constraint staff_notices_kind_check check (
  kind in (
    'month_release', 'schedule_change', 'open_shift_pickup',
    'open_shift_posted', 'request_submitted', 'request_decided',
    'swap_proposed', 'swap_accepted', 'swap_declined', 'swap_approved',
    'swap_voided', 'giveaway_proposed', 'giveaway_accepted',
    'giveaway_declined', 'giveaway_approved', 'giveaway_withdrawn',
    'giveaway_voided', 'test', 'floor_critical_call_in', 'call_in_filled',
    'open_shift_batch', 'maintainer_repair'
  )
);

create function public.notice_giveaway()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := public.current_staff_member_id();
  v_kind text;
  v_title text;
  v_body text;
begin
  if tg_op = 'INSERT' then
    v_kind := 'giveaway_proposed';
    v_title := 'Giveaway proposed';
    v_body := 'A colleague proposed a Giveaway. Open Giveaways to respond.';
  elsif new.status is distinct from old.status then
    v_kind := 'giveaway_' || new.status::text;
    v_title := 'Giveaway ' || new.status::text;
    v_body := 'Your Giveaway was ' || new.status::text ||
      '. Open Giveaways for details.';
  else
    return new;
  end if;
  insert into public.staff_notices(staff_member_id, kind, title, body)
  select recipient.id, v_kind, v_title, v_body
  from public.staff_members recipient
  where recipient.active and (
    (recipient.id in (new.giver_id, new.colleague_id)
      and recipient.id is distinct from v_actor)
    or (new.status = 'accepted' and recipient.role = 'manager'
      and recipient.id is distinct from v_actor)
    or (new.status = 'withdrawn' and old.status = 'accepted'
      and recipient.role = 'manager' and recipient.id is distinct from v_actor)
    or (new.status = 'voided' and recipient.role = 'manager'
      and recipient.id = v_actor)
  );
  return new;
end;
$$;
create trigger notice_giveaway after insert or update on public.giveaways
for each row execute function public.notice_giveaway();
revoke all on function public.notice_giveaway() from public;

create function public.giveaway_colleague_cell_number(p_giveaway_id uuid)
returns text language sql stable security definer set search_path = '' as $$
  select member.cell_number from public.giveaways giveaway
  join public.staff_members member on member.id = giveaway.colleague_id
  where giveaway.id = p_giveaway_id
    and giveaway.giver_id = public.current_staff_member_id();
$$;

create or replace function public.shift_code_in_use(p_code text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.schedule_cells
      where upper(trim(shift_code)) = p_code)
    or exists (select 1 from public.schedule_changes
      where upper(trim(old_shift_code)) = p_code
        or upper(trim(new_shift_code)) = p_code)
    or exists (select 1 from public.short_shifts
      where upper(trim(shift_code)) = p_code)
    or exists (select 1 from public.swap_shifts
      where upper(trim(shift_code)) = p_code
        or upper(trim(target_code)) = p_code)
    or exists (select 1 from public.giveaway_shifts
      where upper(trim(shift_code)) = p_code
        or upper(trim(target_code)) = p_code)
$$;

revoke all on function public.eligible_giveaway_colleagues(date[]),
  public.propose_giveaway(uuid, date[]),
  public.answer_giveaway(uuid, boolean, text),
  public.withdraw_giveaway(uuid), public.decline_giveaway(uuid, text),
  public.giveaway_creates_shortfall(uuid), public.approve_giveaway(uuid),
  public.giveaway_colleague_cell_number(uuid) from public;
grant execute on function public.eligible_giveaway_colleagues(date[]),
  public.propose_giveaway(uuid, date[]),
  public.answer_giveaway(uuid, boolean, text),
  public.withdraw_giveaway(uuid), public.decline_giveaway(uuid, text),
  public.giveaway_creates_shortfall(uuid), public.approve_giveaway(uuid),
  public.giveaway_colleague_cell_number(uuid) to authenticated;

alter publication supabase_realtime add table public.giveaways;
