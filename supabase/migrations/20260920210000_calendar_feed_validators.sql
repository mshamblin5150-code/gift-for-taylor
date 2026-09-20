-- Keep the feed timestamp aware of nonworking cells: clearing the last shift
-- must advance the feed even though that cell no longer produces a VEVENT.
create index schedule_changes_by_staff_date
on public.schedule_changes (staff_member_id, work_date);

-- Editing a Shift code can change event hours or remove events without writing
-- a Schedule cell. Advance those cells so subscribers can detect that change.
create function public.touch_calendar_cells_for_shift_code()
returns trigger language plpgsql set search_path = '' as $$
begin
  if (old.start_time, old.end_time, old.is_working) is distinct from
     (new.start_time, new.end_time, new.is_working) then
    update public.schedule_cells
    set updated_at = clock_timestamp()
    where upper(trim(shift_code)) = new.code;
  end if;
  return new;
end;
$$;
revoke all on function public.touch_calendar_cells_for_shift_code() from public;
create trigger touch_calendar_cells_for_shift_code
after update of start_time, end_time, is_working on public.shift_codes
for each row execute function public.touch_calendar_cells_for_shift_code();

create function public.calendar_feed_last_modified(p_token text)
returns timestamptz
language sql stable security definer set search_path = ''
as $$
  select coalesce((
    select max(greatest(cell.updated_at, month.released_at))
    from public.schedule_cells cell
    join public.schedule_months month on month.id = cell.schedule_month_id
    where cell.staff_member_id = member.id
      and month.release_state = 'released'
  ), token.created_at)
  from public.calendar_feed_tokens token
  join public.staff_members member on member.id = token.staff_member_id
  where p_token ~ '^[0-9a-f]{64}$'
    and token.token_hash = encode(sha256(decode(p_token, 'hex')), 'hex')
    and token.revoked_at is null
    and member.active
$$;
revoke all on function public.calendar_feed_last_modified(text) from public, anon, authenticated;
grant execute on function public.calendar_feed_last_modified(text) to service_role;

drop function public.calendar_feed_events(text);
create function public.calendar_feed_events(p_token text)
returns table (
  staff_member_id uuid,
  work_date date,
  shift_code text,
  starts_at timestamptz,
  ends_at timestamptz,
  updated_at timestamptz,
  sequence bigint
)
language sql stable security definer set search_path = ''
as $$
  select member.id, cell.work_date, cell.shift_code,
    case when code.start_time is not null then
      (cell.work_date + code.start_time) at time zone 'America/New_York'
    end,
    case when code.end_time is not null then
      (cell.work_date + code.end_time +
        case when code.end_time <= code.start_time
          then interval '1 day' else interval '0 day' end)
        at time zone 'America/New_York'
    end,
    cell.updated_at,
    (select count(*) from public.schedule_changes change
     where change.staff_member_id = member.id
       and change.work_date = cell.work_date) as sequence
  from public.calendar_feed_tokens token
  join public.staff_members member on member.id = token.staff_member_id
  join public.schedule_cells cell on cell.staff_member_id = member.id
  join public.schedule_months month on month.id = cell.schedule_month_id
  left join public.shift_codes code on code.code = upper(trim(cell.shift_code))
  where p_token ~ '^[0-9a-f]{64}$'
    and token.token_hash = encode(sha256(decode(p_token, 'hex')), 'hex')
    and token.revoked_at is null
    and member.active
    and month.release_state = 'released'
    and public.is_working_shift(cell.shift_code)
  order by cell.work_date;
$$;
revoke all on function public.calendar_feed_events(text) from public, anon, authenticated;
grant execute on function public.calendar_feed_events(text) to service_role;
