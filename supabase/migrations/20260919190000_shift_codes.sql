-- The catalog is the authority for display and working-time interpretation.
-- Schedule cells deliberately retain their original text when a code changes.
create table public.shift_codes (
  code text primary key check (code = upper(trim(code)) and length(code) > 0),
  meaning text,
  start_time time,
  end_time time,
  is_working boolean not null,
  active boolean not null default true,
  display_order integer not null default 0,
  check ((start_time is null) = (end_time is null))
);

insert into public.shift_codes(code, meaning, start_time, end_time, is_working, display_order) values
  ('16D', null, '07:00', '23:00', true, 1),
  ('7A', null, '07:00', '19:00', true, 2),
  ('D', null, '07:00', '15:00', true, 3),
  ('MM', null, '11:00', '19:00', true, 4),
  ('11A', null, '11:00', '23:00', true, 5),
  ('3P', null, '15:00', '03:00', true, 6),
  ('7P', null, '19:00', '07:00', true, 7),
  ('ME', null, '19:00', '03:00', true, 8),
  ('N', null, '23:00', '07:00', true, 9),
  ('X', 'Off', null, null, false, 10),
  ('R/O', 'Requested off', null, null, false, 11),
  ('H', null, null, null, false, 12),
  ('S/L', 'Sick leave', null, null, false, 13),
  ('4P', null, null, null, true, 14),
  ('9-7', null, null, null, true, 15),
  ('7-5', null, null, null, true, 16);

-- Keep the open-ended codes already written in the Schedule and its history.
insert into public.shift_codes(code, is_working, display_order)
select distinct upper(trim(shift_code)), true, 1000
from (
  select shift_code from public.schedule_cells
  union select old_shift_code from public.schedule_changes
  union select new_shift_code from public.schedule_changes
  union select shift_code from public.short_shifts
) history
where length(trim(shift_code)) > 0
on conflict (code) do nothing;

-- An authorized Schedule cell writer, including a Night scheduler in an assigned
-- Section, may introduce a code immediately. It is active so Staff and printed
-- legends can show it without Manager approval. The Manager-only save_shift_code
-- RPC governs explicit catalog edits, not registration through a cell edit.
create function public.register_shift_code()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if length(trim(new.shift_code)) > 0 then
    insert into public.shift_codes(code, is_working, display_order)
    values (upper(trim(new.shift_code)), true, 1000)
    on conflict (code) do nothing;
  end if;
  return new;
end;
$$;
create trigger register_shift_code after insert or update of shift_code
on public.schedule_cells for each row execute function public.register_shift_code();

alter table public.shift_codes enable row level security;
revoke all on public.shift_codes from public, anon, authenticated;
grant select on public.shift_codes to authenticated;
create policy "Staff can read Shift codes" on public.shift_codes
  for select to authenticated using (public.current_staff_member_id() is not null);

create function public.shift_code_in_use(p_code text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.schedule_cells where upper(trim(shift_code)) = p_code)
    or exists (select 1 from public.schedule_changes where upper(trim(old_shift_code)) = p_code
      or upper(trim(new_shift_code)) = p_code)
    or exists (select 1 from public.short_shifts where upper(trim(shift_code)) = p_code)
    or exists (select 1 from public.swaps where upper(trim(requester_code)) = p_code
      or upper(trim(colleague_code)) = p_code or upper(trim(requester_target_code)) = p_code
      or upper(trim(colleague_target_code)) = p_code)
$$;
revoke all on function public.shift_code_in_use(text) from public, anon, authenticated;

create function public.save_shift_code(
  p_code text, p_meaning text, p_start_time time, p_end_time time,
  p_is_working boolean, p_original_code text default null
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_code text := upper(trim(p_code));
  v_order integer;
begin
  if public.current_staff_role() <> 'manager' then
    raise exception 'Only the Manager can edit Shift codes';
  end if;
  if v_code is null or length(v_code) = 0
    or (p_start_time is null) <> (p_end_time is null) then
    raise exception 'Invalid Shift code or hours';
  end if;
  if p_original_code is not null and v_code <> p_original_code then
    -- Keep a used code for historical cells and feeds, but leave it out of
    -- the active legend. No past cell text is rewritten.
    select display_order into v_order from public.shift_codes where code = p_original_code;
    if v_order is null then raise exception 'Shift code not found'; end if;
    if exists (select 1 from public.shift_codes where code = v_code) then
      raise exception 'That Shift code already exists';
    end if;
    if public.shift_code_in_use(p_original_code) then
      update public.shift_codes set active = false where code = p_original_code;
    else
      delete from public.shift_codes where code = p_original_code;
    end if;
  end if;
  insert into public.shift_codes(code, meaning, start_time, end_time, is_working, display_order)
  values (v_code, nullif(trim(p_meaning), ''), p_start_time, p_end_time,
    p_is_working, coalesce(v_order, (select display_order from public.shift_codes where code = p_original_code),
      (select coalesce(max(display_order), 0) + 1 from public.shift_codes)))
  on conflict (code) do update set meaning = excluded.meaning,
    start_time = excluded.start_time, end_time = excluded.end_time,
    is_working = excluded.is_working, active = true;
end;
$$;

create function public.delete_shift_code(p_code text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if public.current_staff_role() <> 'manager' then
    raise exception 'Only the Manager can delete Shift codes';
  end if;
  if public.shift_code_in_use(p_code) then
    raise exception 'A Shift code in use cannot be deleted';
  end if;
  delete from public.shift_codes where code = p_code;
end;
$$;

revoke all on function public.save_shift_code(text,text,time,time,boolean,text) from public, anon;
revoke all on function public.delete_shift_code(text) from public, anon;
grant execute on function public.save_shift_code(text,text,time,time,boolean,text) to authenticated;
grant execute on function public.delete_shift_code(text) to authenticated;

create or replace function public.is_working_shift(p_shift_code text)
returns boolean language sql stable set search_path = '' as $$
  select length(trim(p_shift_code)) > 0 and coalesce(
    (select is_working from public.shift_codes where code = upper(trim(p_shift_code))), true)
$$;

create or replace function public.calendar_feed_events(p_token text)
returns table (staff_member_id uuid, work_date date, shift_code text,
  starts_at timestamptz, ends_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select member.id, cell.work_date, cell.shift_code,
    case when code.start_time is not null then
      (cell.work_date + code.start_time) at time zone 'America/New_York'
    end,
    case when code.end_time is not null then
      (cell.work_date + code.end_time +
        case when code.end_time <= code.start_time then interval '1 day'
          else interval '0 day' end) at time zone 'America/New_York'
    end
  from public.calendar_feed_tokens token
  join public.staff_members member on member.id = token.staff_member_id
  join public.schedule_cells cell on cell.staff_member_id = member.id
  join public.schedule_months month on month.id = cell.schedule_month_id
  left join public.shift_codes code on code.code = upper(trim(cell.shift_code))
  where p_token ~ '^[0-9a-f]{64}$'
    and token.token_hash = encode(sha256(decode(p_token, 'hex')), 'hex')
    and token.revoked_at is null and member.active
    and month.release_state = 'released'
    and public.is_working_shift(cell.shift_code)
  order by cell.work_date;
$$;

-- A formerly working code marked nonworking no longer appears as an Open shift.
create or replace function public.visible_open_shifts()
returns table (id uuid, section_id uuid, work_date date, shift_code text,
  original_staff_member_id uuid, job_role public.job_role, pickup_id uuid,
  pickup_staff_member_id uuid, pickup_status text)
language sql stable security definer set search_path = '' as $$
  select short.id, short.section_id, short.work_date, short.shift_code,
    short.staff_member_id, original_role.job_role,
    pickup.id, pickup.staff_member_id, pickup.status
  from public.short_shifts short
  join public.schedule_months month on month.id = short.schedule_month_id
  join lateral (
    select role.job_role from public.staff_job_roles role
    where role.staff_member_id = short.staff_member_id
      and role.effective_from <= short.work_date
    order by role.effective_from desc limit 1
  ) original_role on true
  left join public.open_shift_pickups pickup
    on pickup.short_shift_id = short.id
    and (public.current_staff_role() = 'manager'
      or pickup.staff_member_id = public.current_staff_member_id())
  where month.release_state = 'released' and short.filled_at is null
    and public.is_working_shift(short.shift_code)
    and (public.current_staff_role() = 'manager' or exists (
      select 1 from public.staff_job_roles mine
      where mine.staff_member_id = public.current_staff_member_id()
        and mine.effective_from <= short.work_date
        and (mine.effective_through is null or mine.effective_through >= short.work_date)
        and (mine.job_role = original_role.job_role
          or (mine.job_role in ('rn', 'lpn') and original_role.job_role in ('rn', 'lpn')))
    ));
$$;

create function public.check_open_shift_code()
returns trigger language plpgsql set search_path = '' as $$
begin
  if (tg_op = 'INSERT' or (new.status = 'approved' and old.status is distinct from 'approved'))
    and not public.is_working_shift((select shift_code from public.short_shifts
      where id = new.short_shift_id)) then
    raise exception 'This is no longer a working Shift code';
  end if;
  return new;
end;
$$;
create trigger check_open_shift_code before insert or update on public.open_shift_pickups
for each row execute function public.check_open_shift_code();

alter publication supabase_realtime add table public.shift_codes;
