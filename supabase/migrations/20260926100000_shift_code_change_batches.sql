-- Shift code edits can reinterpret many released Schedule cells. Carry the
-- resulting Calendar invitations as a reviewed batch instead of silently
-- sending one message per cell.

-- Keep the unbatched queue interface used by ordinary cell changes, but let
-- the checked Shift-code operation supply a transaction-local batch. This
-- remains compatible with the later date-bound Calendar invitation migration,
-- which replaces the seven-argument queue implementation but not this wrapper.
create or replace function public.queue_calendar_invitation(
  p_staff_member_id uuid, p_work_date date, p_method text,
  p_shift_code text, p_starts_at timestamptz, p_ends_at timestamptz
) returns void language sql security definer set search_path = '' as $$
  select public.queue_calendar_invitation(p_staff_member_id, p_work_date,
    p_method, p_shift_code, p_starts_at, p_ends_at,
    nullif(current_setting('app.shift_code_change_batch', true), '')::uuid)
$$;

-- A Shift code edit cannot inform action on work that already happened. Keep
-- this bound here so the preview and the committed batch describe the same
-- current/future reach even before the broader sender migration from #335.
create or replace function public.calendar_shift_code_changed()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_cell record;
begin
  if old.is_working = new.is_working
    and old.start_time is not distinct from new.start_time
    and old.end_time is not distinct from new.end_time then return new; end if;
  for v_cell in
    select cell.staff_member_id, cell.work_date, cell.shift_code
    from public.schedule_cells cell
    join public.schedule_months month on month.id = cell.schedule_month_id
    join public.staff_members member on member.id = cell.staff_member_id
    where upper(trim(cell.shift_code)) = new.code
      and month.release_state = 'released' and member.active
      and member.calendar_channel = 'invitations'
      and cell.work_date >=
        (clock_timestamp() at time zone 'America/New_York')::date
  loop
    if new.is_working then
      perform public.queue_calendar_cell(v_cell.staff_member_id,
        v_cell.work_date, v_cell.shift_code);
    elsif old.is_working then
      perform public.queue_calendar_invitation(v_cell.staff_member_id,
        v_cell.work_date, 'CANCEL', v_cell.shift_code,
        case when old.start_time is not null then
          (v_cell.work_date + old.start_time) at time zone 'America/New_York' end,
        case when old.end_time is not null then
          (v_cell.work_date + old.end_time + case when old.end_time <= old.start_time
            then interval '1 day' else interval '0 day' end)
            at time zone 'America/New_York' end);
    end if;
  end loop;
  return new;
end;
$$;

alter function public.save_shift_code(text,text,time,time,boolean,text,text)
  rename to apply_shift_code;
revoke all on function public.apply_shift_code(
  text,text,time,time,boolean,text,text) from public, anon, authenticated;

create or replace function public.shift_code_change_plan(p_batch uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'work_date', grouped.work_date,
    'shift_code', grouped.shift_code,
    'method', grouped.method,
    'count', grouped.affected_count,
    'staff_member_ids', grouped.staff_member_ids
  ) order by grouped.work_date, grouped.shift_code, grouped.method), '[]'::jsonb)
  from (
    select event.work_date, event.shift_code, event.method,
      count(*)::integer as affected_count,
      jsonb_agg(event.staff_member_id order by event.staff_member_id)
        as staff_member_ids
    from public.calendar_invitation_outbox event
    where event.batch_id = p_batch and event.superseded_at is null
    group by event.work_date, event.shift_code, event.method
  ) grouped
$$;
revoke all on function public.shift_code_change_plan(uuid) from public;

create or replace function public.apply_shift_code_change(
  p_code text, p_meaning text, p_start_time time, p_end_time time,
  p_is_working boolean, p_coverage_window text, p_original_code text,
  p_batch uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(hashtext(
    'shift-code:' || coalesce(p_original_code, upper(trim(p_code)))));
  perform set_config('app.shift_code_change_batch', p_batch::text, true);
  perform public.apply_shift_code(p_code, p_meaning, p_start_time, p_end_time,
    p_is_working, p_coverage_window, p_original_code);
  return public.shift_code_change_plan(p_batch);
end;
$$;
revoke all on function public.apply_shift_code_change(
  text,text,time,time,boolean,text,text,uuid) from public, anon, authenticated;

-- Apply the real write and every resulting trigger inside a subtransaction,
-- read its exact invitation plan, then roll the entire preview back.
create or replace function public.preview_shift_code_change(
  p_code text, p_meaning text, p_start_time time, p_end_time time,
  p_is_working boolean, p_coverage_window text,
  p_original_code text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_plan jsonb;
  v_batch uuid := gen_random_uuid();
begin
  begin
    v_plan := public.apply_shift_code_change(p_code, p_meaning, p_start_time,
      p_end_time, p_is_working, p_coverage_window, p_original_code, v_batch);
    raise exception 'preview rollback' using errcode = 'P9001';
  exception when sqlstate 'P9001' then null;
  end;
  perform set_config('app.shift_code_change_batch', '', true);
  return coalesce(v_plan, '[]'::jsonb);
end;
$$;

create or replace function public.commit_shift_code_change(
  p_code text, p_meaning text, p_start_time time, p_end_time time,
  p_is_working boolean, p_coverage_window text, p_original_code text,
  p_expected_plan jsonb
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_plan jsonb;
  v_batch uuid := gen_random_uuid();
begin
  v_plan := public.apply_shift_code_change(p_code, p_meaning, p_start_time,
    p_end_time, p_is_working, p_coverage_window, p_original_code, v_batch);
  if p_expected_plan is distinct from v_plan then
    raise exception 'The Schedule changed since preview; review the batch again';
  end if;
  perform set_config('app.shift_code_change_batch', '', true);
  if exists (select 1 from public.calendar_invitation_outbox
      where batch_id = v_batch and superseded_at is null) then
    perform public.post_calendar_invitation_delivery(v_batch);
  end if;
end;
$$;

-- Older clients may still call save_shift_code. Keep harmless edits working,
-- but require the review flow for any edit that affects a released Schedule.
create or replace function public.save_shift_code(
  p_code text, p_meaning text, p_start_time time, p_end_time time,
  p_is_working boolean, p_coverage_window text,
  p_original_code text default null
) returns void language plpgsql security definer set search_path = '' as $$
declare v_plan jsonb;
begin
  v_plan := public.preview_shift_code_change(p_code, p_meaning, p_start_time,
    p_end_time, p_is_working, p_coverage_window, p_original_code);
  if v_plan <> '[]'::jsonb then
    raise exception 'Review the Calendar invitation batch in Unit settings first';
  end if;
  perform public.commit_shift_code_change(p_code, p_meaning, p_start_time,
    p_end_time, p_is_working, p_coverage_window, p_original_code, v_plan);
end;
$$;

revoke all on function public.preview_shift_code_change(
  text,text,time,time,boolean,text,text),
  public.commit_shift_code_change(
    text,text,time,time,boolean,text,text,jsonb),
  public.save_shift_code(text,text,time,time,boolean,text,text)
  from public, anon;
grant execute on function public.preview_shift_code_change(
  text,text,time,time,boolean,text,text),
  public.commit_shift_code_change(
    text,text,time,time,boolean,text,text,jsonb),
  public.save_shift_code(text,text,time,time,boolean,text,text)
  to authenticated;
