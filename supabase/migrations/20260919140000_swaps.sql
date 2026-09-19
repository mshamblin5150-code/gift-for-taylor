create type public.swap_status as enum ('proposed', 'accepted', 'declined', 'approved');

create table public.swaps (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.staff_members(id),
  colleague_id uuid not null references public.staff_members(id),
  requester_date date not null,
  colleague_date date not null,
  requester_code text not null,
  colleague_code text not null,
  requester_target_code text not null,
  colleague_target_code text not null,
  requester_section_id uuid not null references public.sections(id),
  colleague_section_id uuid not null references public.sections(id),
  status public.swap_status not null default 'proposed',
  reason text,
  created_at timestamptz not null default now(),
  answered_at timestamptz,
  approved_at timestamptz,
  approved_by uuid references public.staff_members(id),
  check (requester_id <> colleague_id)
);

create index swaps_by_participants on public.swaps (requester_id, colleague_id, created_at desc);
create index swaps_approval_queue on public.swaps (created_at) where status = 'accepted';

alter table public.swaps enable row level security;
revoke insert, update, delete on public.swaps from public, anon, authenticated;
grant select on public.swaps to authenticated;

create policy "Swap participants and Manager can read"
on public.swaps for select
using (
  public.current_staff_role() = 'manager'
  or requester_id = public.current_staff_member_id()
  or colleague_id = public.current_staff_member_id()
);

create function public.propose_swap(
  p_colleague_id uuid,
  p_requester_date date,
  p_colleague_date date
)
returns public.swaps
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_requester_id uuid := public.current_staff_member_id();
  v_requester_cell public.schedule_cells%rowtype;
  v_colleague_cell public.schedule_cells%rowtype;
  v_swap public.swaps%rowtype;
  v_requester_target text;
  v_colleague_target text;
begin
  if v_requester_id is null or p_colleague_id is null or p_colleague_id = v_requester_id then
    raise exception 'Choose another Staff member';
  end if;
  if not exists (select 1 from public.staff_members where id = p_colleague_id and active)
    or not exists (select 1 from public.staff_accounts where staff_member_id = p_colleague_id and accepted_invite_at is not null) then
    raise exception 'Colleague must have an active Invite';
  end if;
  select cell.* into v_requester_cell
  from public.schedule_cells cell
  join public.schedule_months month on month.id = cell.schedule_month_id
  where cell.staff_member_id = v_requester_id and cell.work_date = p_requester_date
    and month.release_state = 'released';
  select cell.* into v_colleague_cell
  from public.schedule_cells cell
  join public.schedule_months month on month.id = cell.schedule_month_id
  where cell.staff_member_id = p_colleague_id and cell.work_date = p_colleague_date
    and month.release_state = 'released';
  if v_requester_cell.id is null or v_colleague_cell.id is null
    or not public.is_working_shift(v_requester_cell.shift_code)
    or not public.is_working_shift(v_colleague_cell.shift_code) then
    raise exception 'Both Staff members need working shifts on released Schedules';
  end if;
  if p_requester_date = p_colleague_date and v_requester_cell.shift_code = v_colleague_cell.shift_code then
    raise exception 'Choose shifts that would change the Schedule';
  end if;
  select coalesce((select shift_code from public.schedule_cells
    where staff_member_id = v_requester_id and work_date = p_colleague_date), '')
    into v_requester_target;
  select coalesce((select shift_code from public.schedule_cells
    where staff_member_id = p_colleague_id and work_date = p_requester_date), '')
    into v_colleague_target;
  if p_requester_date <> p_colleague_date and
    (v_requester_target not in ('', 'X') or v_colleague_target not in ('', 'X')) then
    raise exception 'Both destination dates must be free';
  end if;
  insert into public.swaps (
    requester_id, colleague_id, requester_date, colleague_date,
    requester_code, colleague_code, requester_target_code, colleague_target_code,
    requester_section_id, colleague_section_id
  ) values (
    v_requester_id, p_colleague_id, p_requester_date, p_colleague_date,
    v_requester_cell.shift_code, v_colleague_cell.shift_code,
    v_requester_target, v_colleague_target,
    v_requester_cell.section_id, v_colleague_cell.section_id
  ) returning * into v_swap;
  return v_swap;
end;
$$;

create function public.answer_swap(p_swap_id uuid, p_accept boolean, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.swaps
  set status = case when p_accept then 'accepted'::public.swap_status else 'declined'::public.swap_status end,
      reason = nullif(trim(p_reason), ''), answered_at = clock_timestamp()
  where id = p_swap_id and colleague_id = public.current_staff_member_id()
    and status = 'proposed';
  if not found then raise exception 'This Swap cannot be answered'; end if;
end;
$$;

create function public.approve_swap(p_swap_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_swap public.swaps%rowtype;
  v_requester_code text;
  v_colleague_code text;
  v_requester_target text;
  v_colleague_target text;
  v_lock_key text;
begin
  if public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the Manager can approve a Swap';
  end if;
  select * into v_swap from public.swaps where id = p_swap_id for update;
  if v_swap.id is null or v_swap.status <> 'accepted' then
    raise exception 'This Swap is not awaiting approval';
  end if;
  for v_lock_key in
    select distinct key from unnest(array[
      v_swap.requester_id::text || ':' || v_swap.requester_date::text,
      v_swap.colleague_id::text || ':' || v_swap.colleague_date::text,
      v_swap.requester_id::text || ':' || v_swap.colleague_date::text,
      v_swap.colleague_id::text || ':' || v_swap.requester_date::text
    ]) as key order by key
  loop
    perform pg_advisory_xact_lock(hashtext(v_lock_key));
  end loop;
  select shift_code into v_requester_code from public.schedule_cells
  where staff_member_id = v_swap.requester_id and work_date = v_swap.requester_date;
  select shift_code into v_colleague_code from public.schedule_cells
  where staff_member_id = v_swap.colleague_id and work_date = v_swap.colleague_date;
  select coalesce((select shift_code from public.schedule_cells
    where staff_member_id = v_swap.requester_id and work_date = v_swap.colleague_date), '')
    into v_requester_target;
  select coalesce((select shift_code from public.schedule_cells
    where staff_member_id = v_swap.colleague_id and work_date = v_swap.requester_date), '')
    into v_colleague_target;
  if v_requester_code is distinct from v_swap.requester_code
    or v_colleague_code is distinct from v_swap.colleague_code
    or v_requester_target is distinct from v_swap.requester_target_code
    or v_colleague_target is distinct from v_swap.colleague_target_code then
    raise exception 'A Shift code changed; propose a new Swap';
  end if;
  if v_swap.requester_date = v_swap.colleague_date then
    perform public.save_schedule_cell(v_swap.requester_id, v_swap.requester_section_id,
                                      v_swap.requester_date, v_swap.colleague_code);
    perform public.save_schedule_cell(v_swap.colleague_id, v_swap.colleague_section_id,
                                      v_swap.colleague_date, v_swap.requester_code);
  else
    perform public.save_schedule_cell(v_swap.requester_id, v_swap.requester_section_id,
                                      v_swap.requester_date, 'X');
    perform public.save_schedule_cell(v_swap.colleague_id, v_swap.colleague_section_id,
                                      v_swap.colleague_date, 'X');
    perform public.save_schedule_cell(v_swap.requester_id, v_swap.requester_section_id,
                                      v_swap.colleague_date, v_swap.colleague_code);
    perform public.save_schedule_cell(v_swap.colleague_id, v_swap.colleague_section_id,
                                      v_swap.requester_date, v_swap.requester_code);
  end if;
  update public.swaps set status = 'approved', approved_at = clock_timestamp(),
    approved_by = public.current_staff_member_id() where id = p_swap_id;
end;
$$;

revoke all on function public.propose_swap(uuid, date, date) from public;
revoke all on function public.answer_swap(uuid, boolean, text) from public;
revoke all on function public.approve_swap(uuid) from public;
grant execute on function public.propose_swap(uuid, date, date) to authenticated;
grant execute on function public.answer_swap(uuid, boolean, text) to authenticated;
grant execute on function public.approve_swap(uuid) to authenticated;

alter publication supabase_realtime add table public.swaps;
