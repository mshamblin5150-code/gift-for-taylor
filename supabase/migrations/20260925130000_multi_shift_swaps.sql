-- A Swap is one atomic exchange of two equal-sized sets of shifts.
drop function public.propose_swap(uuid, date, date);
drop function public.answer_swap(uuid, boolean, text);
drop function public.approve_swap(uuid);
drop index public.swaps_approval_queue;

alter table public.swaps alter column status drop default;
alter table public.swaps alter column status type text using status::text;
drop type public.swap_status;
create type public.swap_status as enum
  ('proposed', 'accepted', 'declined', 'approved', 'voided');
alter table public.swaps alter column status type public.swap_status
  using status::public.swap_status;
alter table public.swaps alter column status set default 'proposed';
create index swaps_approval_queue on public.swaps (created_at)
  where status = 'accepted';

create type public.swap_side as enum ('requester', 'colleague');
create table public.swap_shifts (
  id uuid primary key default gen_random_uuid(),
  swap_id uuid not null references public.swaps(id) on delete cascade,
  side public.swap_side not null,
  work_date date not null,
  shift_code text not null,
  target_code text not null,
  section_id uuid not null references public.sections(id),
  unique (swap_id, side, work_date)
);

insert into public.swap_shifts
  (swap_id, side, work_date, shift_code, target_code, section_id)
select id, 'requester'::public.swap_side, requester_date, requester_code,
  colleague_target_code, requester_section_id from public.swaps
union all
select id, 'colleague'::public.swap_side, colleague_date, colleague_code,
  requester_target_code, colleague_section_id from public.swaps;

alter table public.swaps
  add column voided_staff_member_id uuid references public.staff_members(id),
  add column voided_work_date date,
  add constraint swaps_void_record check (
    (status = 'voided') =
      (voided_staff_member_id is not null and voided_work_date is not null)
  ),
  drop column requester_date,
  drop column colleague_date,
  drop column requester_code,
  drop column colleague_code,
  drop column requester_target_code,
  drop column colleague_target_code,
  drop column requester_section_id,
  drop column colleague_section_id;

create index swap_shifts_by_swap on public.swap_shifts (swap_id, side, work_date);
create index swap_shifts_by_date on public.swap_shifts (work_date, swap_id);
alter table public.swap_shifts enable row level security;
revoke all on public.swap_shifts from public, anon, authenticated;
grant select on public.swap_shifts to authenticated;
create policy "Swap participants and Manager can read shifts"
on public.swap_shifts for select using (exists (
  select 1 from public.swaps swap where swap.id = swap_id
    and (public.current_staff_role() = 'manager'
      or swap.requester_id = public.current_staff_member_id()
      or swap.colleague_id = public.current_staff_member_id())
));

alter table public.schedule_changes add column swap_id uuid
  references public.swaps(id);
create index schedule_changes_by_swap on public.schedule_changes (swap_id)
  where swap_id is not null;

create function public.attribute_schedule_change_swap()
returns trigger language plpgsql set search_path = '' as $$
declare
  v_swap text := current_setting('app.swap_id', true);
begin
  if v_swap is not null and v_swap <> '' then new.swap_id := v_swap::uuid; end if;
  return new;
end;
$$;
create trigger attribute_schedule_change_swap
before insert on public.schedule_changes for each row
execute function public.attribute_schedule_change_swap();
revoke all on function public.attribute_schedule_change_swap() from public;

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
$$;

create function public.propose_swap(
  p_colleague_id uuid,
  p_requester_dates date[],
  p_colleague_dates date[]
)
returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_requester_id uuid := public.current_staff_member_id();
  v_swap_id uuid;
  v_date date;
  v_cell public.schedule_cells%rowtype;
  v_target text;
begin
  if v_requester_id is null or p_colleague_id is null
    or p_colleague_id = v_requester_id then
    raise exception using errcode = 'P2814', message = 'Choose another Staff member';
  end if;
  if coalesce(cardinality(p_requester_dates), 0) = 0
    or cardinality(p_requester_dates) <> cardinality(p_colleague_dates) then
    raise exception using errcode = 'P2815', message = 'Choose the same number of shifts for each Staff member';
  end if;
  if cardinality(p_requester_dates) > 31 then
    raise exception using errcode = 'P2816', message = 'A Swap can include at most 31 shifts for each Staff member';
  end if;
  if cardinality(p_requester_dates) <> cardinality(
      array(select distinct day from unnest(p_requester_dates) day))
    or cardinality(p_colleague_dates) <> cardinality(
      array(select distinct day from unnest(p_colleague_dates) day)) then
    raise exception using errcode = 'P2817', message = 'Choose each shift only once';
  end if;
  if not exists (select 1 from public.staff_members
      where id = p_colleague_id and active)
    or not exists (select 1 from public.staff_accounts
      where staff_member_id = p_colleague_id
        and accepted_invite_at is not null and revoked_at is null) then
    raise exception using errcode = 'P2818', message = 'Colleague must have an active Invite';
  end if;
  if exists (select 1 from unnest(p_requester_dates || p_colleague_dates) day
      where day <= current_date) then
    select min(day) into v_date
    from unnest(p_requester_dates || p_colleague_dates) day
    where day <= current_date;
    raise exception using errcode = 'P2819', message = format('Swap day %s must be after today', v_date);
  end if;

  insert into public.swaps(requester_id, colleague_id)
  values (v_requester_id, p_colleague_id) returning id into v_swap_id;

  foreach v_date in array p_requester_dates loop
    select cell.* into v_cell from public.schedule_cells cell
    join public.schedule_months month on month.id = cell.schedule_month_id
    where cell.staff_member_id = v_requester_id and cell.work_date = v_date
      and month.release_state = 'released';
    if v_cell.id is null or not public.is_working_shift(v_cell.shift_code) then
      raise exception using errcode = 'P2820', message = 'Every offered day needs a working shift on a released Schedule';
    end if;
    select coalesce((select shift_code from public.schedule_cells
      where staff_member_id = p_colleague_id and work_date = v_date), '')
      into v_target;
    if v_target not in ('', 'X') and not (v_date = any(p_colleague_dates)) then
      raise exception using errcode = 'P2821', message = 'Every destination day must be free or offered in this Swap';
    end if;
    insert into public.swap_shifts
      (swap_id, side, work_date, shift_code, target_code, section_id)
    values (v_swap_id, 'requester', v_date, v_cell.shift_code,
      v_target, v_cell.section_id);
  end loop;

  foreach v_date in array p_colleague_dates loop
    select cell.* into v_cell from public.schedule_cells cell
    join public.schedule_months month on month.id = cell.schedule_month_id
    where cell.staff_member_id = p_colleague_id and cell.work_date = v_date
      and month.release_state = 'released';
    if v_cell.id is null or not public.is_working_shift(v_cell.shift_code) then
      raise exception using errcode = 'P2820', message = 'Every offered day needs a working shift on a released Schedule';
    end if;
    select coalesce((select shift_code from public.schedule_cells
      where staff_member_id = v_requester_id and work_date = v_date), '')
      into v_target;
    if v_target not in ('', 'X') and not (v_date = any(p_requester_dates)) then
      raise exception using errcode = 'P2821', message = 'Every destination day must be free or offered in this Swap';
    end if;
    insert into public.swap_shifts
      (swap_id, side, work_date, shift_code, target_code, section_id)
    values (v_swap_id, 'colleague', v_date, v_cell.shift_code,
      v_target, v_cell.section_id);
  end loop;

  if not exists (
    select 1 from public.swap_shifts offered
    where offered.swap_id = v_swap_id
    group by offered.work_date
    having count(*) = 1 or min(offered.shift_code) <> max(offered.shift_code)
  ) then
    raise exception using errcode = 'P2822', message = 'Choose shifts that would change the Schedule';
  end if;
  return v_swap_id;
end;
$$;

create function public.answer_swap(
  p_swap_id uuid, p_accept boolean, p_reason text default null)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  update public.swaps
  set status = case when p_accept then 'accepted'::public.swap_status
      else 'declined'::public.swap_status end,
    reason = nullif(trim(p_reason), ''), answered_at = clock_timestamp()
  where id = p_swap_id and colleague_id = public.current_staff_member_id()
    and status = 'proposed';
  if not found then raise exception 'This Swap cannot be answered'; end if;
end;
$$;

create function public.approve_swap(p_swap_id uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  v_swap public.swaps%rowtype;
  v_shift public.swap_shifts%rowtype;
  v_code text;
  v_section uuid;
  v_key text;
begin
  if public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the Manager can approve a Swap';
  end if;
  select * into v_swap from public.swaps where id = p_swap_id for update;
  if v_swap.id is null or v_swap.status <> 'accepted' then
    raise exception 'This Swap is not awaiting approval';
  end if;
  for v_key in
    select distinct participant::text || ':' || shift.work_date::text
    from public.swap_shifts shift
    cross join unnest(array[v_swap.requester_id, v_swap.colleague_id]) participant
    where shift.swap_id = p_swap_id order by 1
  loop
    perform pg_advisory_xact_lock(hashtext(v_key));
  end loop;
  for v_shift in select * from public.swap_shifts
      where swap_id = p_swap_id order by side, work_date loop
    if v_shift.work_date <= current_date then
      raise exception 'Swap day % must be after today', v_shift.work_date;
    end if;
    select shift_code, section_id into v_code, v_section
    from public.schedule_cells
    where staff_member_id = case v_shift.side
        when 'requester' then v_swap.requester_id else v_swap.colleague_id end
      and work_date = v_shift.work_date;
    if v_code is distinct from v_shift.shift_code
      or v_section is distinct from v_shift.section_id then
      raise exception 'A Shift code changed; propose a new Swap';
    end if;
    select coalesce((select shift_code from public.schedule_cells
      where staff_member_id = case v_shift.side
          when 'requester' then v_swap.colleague_id else v_swap.requester_id end
        and work_date = v_shift.work_date), '') into v_code;
    if v_code is distinct from v_shift.target_code then
      raise exception 'A Shift code changed; propose a new Swap';
    end if;
  end loop;

  update public.swaps set status = 'approved', approved_at = clock_timestamp(),
    approved_by = public.current_staff_member_id() where id = p_swap_id;
  perform set_config('app.swap_id', p_swap_id::text, true);

  for v_shift in select * from public.swap_shifts
      where swap_id = p_swap_id order by side, work_date loop
    perform public.save_schedule_cell(
      case v_shift.side when 'requester' then v_swap.requester_id
        else v_swap.colleague_id end,
      v_shift.section_id, v_shift.work_date, 'X');
  end loop;
  for v_shift in select * from public.swap_shifts
      where swap_id = p_swap_id order by side, work_date loop
    select assignment.section_id into v_section
    from public.staff_section_assignments assignment
    where assignment.staff_member_id = case v_shift.side
        when 'requester' then v_swap.colleague_id else v_swap.requester_id end
      and assignment.effective_from <= v_shift.work_date
      and (assignment.effective_through is null
        or assignment.effective_through >= v_shift.work_date)
    order by assignment.effective_from desc limit 1;
    perform public.save_schedule_cell(
      case v_shift.side when 'requester' then v_swap.colleague_id
        else v_swap.requester_id end,
      v_section, v_shift.work_date, v_shift.shift_code);
  end loop;
end;
$$;

create function public.void_swaps_for_changed_cell()
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
  update public.swaps swap set status = 'voided',
    voided_staff_member_id = v_staff, voided_work_date = v_date
  where swap.status in ('proposed', 'accepted')
    and v_staff in (swap.requester_id, swap.colleague_id)
    and exists (select 1 from public.swap_shifts shift
      where shift.swap_id = swap.id and shift.work_date = v_date);
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
create trigger void_swaps_for_changed_cell
after insert or update or delete on public.schedule_cells
for each row execute function public.void_swaps_for_changed_cell();
revoke all on function public.void_swaps_for_changed_cell() from public;

alter table public.staff_notices drop constraint staff_notices_kind_check;
alter table public.staff_notices add constraint staff_notices_kind_check check (kind in (
  'month_release', 'schedule_change', 'open_shift_pickup', 'open_shift_posted',
  'request_submitted', 'request_decided', 'swap_proposed', 'swap_accepted',
  'swap_declined', 'swap_approved', 'swap_voided', 'test',
  'floor_critical_call_in', 'call_in_filled', 'open_shift_batch',
  'maintainer_repair'
));

create or replace function public.notice_swap()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := public.current_staff_member_id();
  v_kind text;
  v_title text;
  v_body text;
begin
  if tg_op = 'INSERT' then
    v_kind := 'swap_proposed';
    v_title := 'Swap proposed';
    v_body := 'A colleague proposed a Swap. Open Swaps to respond.';
  elsif new.status is distinct from old.status then
    v_kind := 'swap_' || new.status::text;
    v_title := 'Swap ' || new.status::text;
    v_body := 'Your Swap was ' || new.status::text || '. Open Swaps for details.';
  else
    return new;
  end if;
  insert into public.staff_notices(staff_member_id, kind, title, body)
  select recipient.id, v_kind, v_title, v_body
  from public.staff_members recipient
  where recipient.active and (
    (recipient.id in (new.requester_id, new.colleague_id)
      and recipient.id is distinct from v_actor)
    or (new.status = 'accepted' and recipient.role = 'manager'
      and recipient.id is distinct from v_actor)
    or (new.status = 'voided' and recipient.role = 'manager'
      and recipient.id = v_actor)
  );
  return new;
end;
$$;

revoke all on function public.propose_swap(uuid, date[], date[]) from public;
revoke all on function public.answer_swap(uuid, boolean, text) from public;
revoke all on function public.approve_swap(uuid) from public;
grant execute on function public.propose_swap(uuid, date[], date[]) to authenticated;
grant execute on function public.answer_swap(uuid, boolean, text) to authenticated;
grant execute on function public.approve_swap(uuid) to authenticated;
