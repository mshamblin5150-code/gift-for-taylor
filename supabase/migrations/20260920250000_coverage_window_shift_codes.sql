alter table public.shift_codes
  add column coverage_window text
    check (coverage_window in ('day', 'night')),
  add constraint shift_code_window_requires_hours
    check (start_time is not null or coverage_window is null);

-- A shift belongs to the first anchor it covers. Both comparisons work for
-- ordinary hours and for shifts crossing midnight.
create function public.coverage_window_for_hours(p_start time, p_end time)
returns text language sql immutable set search_path = '' as $$
  select case
    when p_start is null or p_end is null or p_start = p_end then null
    when (p_start < p_end and p_start <= time '13:00' and time '13:00' < p_end)
      or (p_start > p_end and (p_start <= time '13:00' or time '13:00' < p_end))
      then 'day'
    when (p_start < p_end and p_start <= time '02:00' and time '02:00' < p_end)
      or (p_start > p_end and (p_start <= time '02:00' or time '02:00' < p_end))
      then 'night'
  end
$$;

update public.shift_codes
set coverage_window = public.coverage_window_for_hours(start_time, end_time)
where start_time is not null;

-- Preserve an existing hosted meaning, but correct the working flag everywhere.
insert into public.shift_codes(code, meaning, is_working, display_order)
values ('C/I', 'Called in', false, 17)
on conflict (code) do update
  set meaning = coalesce(public.shift_codes.meaning, excluded.meaning),
      is_working = false,
      start_time = null,
      end_time = null,
      coverage_window = null,
      active = true;

do $$
declare v_code text;
begin
  foreach v_code in array array['4P', '9-7', '7-5'] loop
    if public.shift_code_in_use(v_code) then
      update public.shift_codes set active = false where code = v_code;
    else
      delete from public.shift_codes where code = v_code;
    end if;
  end loop;
end;
$$;

drop function public.save_shift_code(text, text, time, time, boolean, text);
create function public.save_shift_code(
  p_code text, p_meaning text, p_start_time time, p_end_time time,
  p_is_working boolean, p_coverage_window text, p_original_code text default null
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
    or (p_start_time is null) <> (p_end_time is null)
    or (p_coverage_window is not null and p_coverage_window not in ('day', 'night'))
    or (p_start_time is null and p_coverage_window is not null) then
    raise exception 'Invalid Shift code, hours or Coverage window';
  end if;
  if p_original_code is not null and v_code <> p_original_code then
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
  insert into public.shift_codes(
    code, meaning, start_time, end_time, is_working, coverage_window, display_order)
  values (v_code, nullif(trim(p_meaning), ''), p_start_time, p_end_time,
    p_is_working,
    coalesce(p_coverage_window, public.coverage_window_for_hours(p_start_time, p_end_time)),
    coalesce(v_order, (select display_order from public.shift_codes where code = p_original_code),
      (select coalesce(max(display_order), 0) + 1 from public.shift_codes)))
  on conflict (code) do update set meaning = excluded.meaning,
    start_time = excluded.start_time, end_time = excluded.end_time,
    is_working = excluded.is_working, coverage_window = excluded.coverage_window,
    active = true;
end;
$$;

revoke all on function public.save_shift_code(text,text,time,time,boolean,text,text)
  from public, anon;
grant execute on function public.save_shift_code(text,text,time,time,boolean,text,text)
  to authenticated;
