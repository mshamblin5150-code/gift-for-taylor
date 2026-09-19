alter table public.short_shifts drop constraint short_shifts_reason_check;
alter table public.short_shifts add constraint short_shifts_reason_check
  check (reason in ('last_day', 'request_off'));

create table public.requests_off (
  id uuid primary key default gen_random_uuid(),
  staff_member_id uuid not null references public.staff_members(id),
  reason text,
  submitted_at timestamptz not null default clock_timestamp(),
  email_confirmed_at timestamptz,
  decision text not null default 'pending' check (decision in ('pending', 'approved', 'declined')),
  decision_reason text,
  decided_by_staff_member_id uuid references public.staff_members(id),
  decided_at timestamptz,
  check ((decision = 'pending') = (decided_at is null and decided_by_staff_member_id is null))
);

create table public.request_off_dates (
  request_off_id uuid not null references public.requests_off(id),
  work_date date not null,
  primary key (request_off_id, work_date)
);

create table public.in_app_notices (
  id uuid primary key default gen_random_uuid(),
  staff_member_id uuid not null references public.staff_members(id),
  request_off_id uuid not null references public.requests_off(id),
  kind text not null check (kind in ('request_submitted', 'request_decided')),
  created_at timestamptz not null default clock_timestamp(),
  read_at timestamptz
);

create index requests_off_pending on public.requests_off (submitted_at) where decision = 'pending';
create index requests_off_by_staff on public.requests_off (staff_member_id, submitted_at desc);

alter table public.requests_off enable row level security;
alter table public.request_off_dates enable row level security;
alter table public.in_app_notices enable row level security;
revoke all on public.requests_off, public.request_off_dates, public.in_app_notices from public, anon, authenticated;
grant select on public.requests_off, public.request_off_dates, public.in_app_notices to authenticated;

create policy "requester and Manager read Requests off"
on public.requests_off for select using (
  public.current_staff_role() = 'manager'
  or staff_member_id = public.current_staff_member_id()
);
create policy "visible Request off dates"
on public.request_off_dates for select using (
  exists (select 1 from public.requests_off request where request.id = request_off_id)
);
create policy "recipient reads their notices"
on public.in_app_notices for select using (
  staff_member_id = public.current_staff_member_id()
);

create function public.submit_request_off(p_dates date[], p_reason text)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_staff_id uuid := public.current_staff_member_id();
  v_name text;
  v_manager_email text;
  v_id uuid;
  v_dates date[];
begin
  if v_staff_id is null then raise exception 'Not on the Staff list'; end if;
  select array_agg(distinct day order by day) into v_dates
  from unnest(p_dates) as days(day) where day is not null;
  if coalesce(array_length(v_dates, 1), 0) = 0 then
    raise exception 'Choose at least one day';
  end if;
  select display_name into v_name from public.staff_members where id = v_staff_id;
  select account.personal_email into v_manager_email
  from public.staff_members manager
  join public.staff_accounts account on account.staff_member_id = manager.id
  where manager.role = 'manager' and manager.active and account.revoked_at is null
  order by manager.created_at limit 1;
  if v_manager_email is null then raise exception 'Manager email is unavailable'; end if;
  insert into public.requests_off(staff_member_id, reason)
  values (v_staff_id, nullif(trim(p_reason), '')) returning id into v_id;
  insert into public.request_off_dates(request_off_id, work_date)
  select v_id, day from unnest(v_dates) as days(day);
  insert into public.in_app_notices(staff_member_id, request_off_id, kind)
  select manager.id, v_id, 'request_submitted'
  from public.staff_members manager where manager.role = 'manager' and manager.active;
  return jsonb_build_object('request_id', v_id, 'manager_email', v_manager_email, 'staff_name', v_name);
end;
$$;

create function public.confirm_request_off_email(p_request_id uuid)
returns void language plpgsql volatile security definer set search_path = ''
as $$
begin
  update public.requests_off set email_confirmed_at = coalesce(email_confirmed_at, clock_timestamp())
  where id = p_request_id and staff_member_id = public.current_staff_member_id();
  if not found then raise exception 'Request off not found'; end if;
end;
$$;

create function public.acknowledge_request_off_notices()
returns void language plpgsql volatile security definer set search_path = ''
as $$
begin
  if public.current_staff_member_id() is null then
    raise exception 'Not on the Staff list';
  end if;
  update public.in_app_notices set read_at = clock_timestamp()
  where staff_member_id = public.current_staff_member_id() and read_at is null;
end;
$$;

create function public.decide_request_off(p_request_id uuid, p_decision text, p_reason text)
returns void language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_request public.requests_off%rowtype;
  v_day date;
  v_month_id uuid;
  v_section_id uuid;
  v_old_code text;
begin
  if public.current_staff_role() <> 'manager' or public.current_staff_role() is null then
    raise exception 'Only the Manager can decide Requests off';
  end if;
  if p_decision not in ('approved', 'declined') or p_decision is null then
    raise exception 'Choose approve or decline';
  end if;
  select * into v_request from public.requests_off where id = p_request_id for update;
  if not found then raise exception 'Request off not found'; end if;
  if v_request.decision <> 'pending' then raise exception 'Already decided'; end if;

  if p_decision = 'approved' then
    -- Validate every day first. A failure rolls back the entire decision.
    for v_day in select work_date from public.request_off_dates
      where request_off_id = p_request_id order by work_date loop
      if not exists (
        select 1 from public.staff_section_assignments assignment
        where assignment.staff_member_id = v_request.staff_member_id
          and assignment.effective_from <= v_day
          and (assignment.effective_through is null or assignment.effective_through >= v_day)
      ) then raise exception 'Staff member is not on the Schedule for that day'; end if;
    end loop;

    for v_day in select work_date from public.request_off_dates
      where request_off_id = p_request_id order by work_date loop
      select id into v_month_id from public.schedule_months
      where month_start = date_trunc('month', v_day)::date;
      if v_month_id is null then raise exception 'That Schedule month has not been started'; end if;
      select assignment.section_id into v_section_id
      from public.staff_section_assignments assignment
      where assignment.staff_member_id = v_request.staff_member_id
        and assignment.effective_from <= v_day
        and (assignment.effective_through is null or assignment.effective_through >= v_day)
      order by assignment.effective_from desc limit 1;
      perform pg_advisory_xact_lock(hashtext(v_request.staff_member_id::text || ':' || v_day::text));
      select shift_code into v_old_code from public.schedule_cells
      where schedule_month_id = v_month_id and staff_member_id = v_request.staff_member_id
        and work_date = v_day for update;
      v_old_code := coalesce(v_old_code, '');
      if v_old_code = 'R/O' then continue; end if;
      insert into public.schedule_cells(schedule_month_id, staff_member_id, section_id, work_date, shift_code)
      values (v_month_id, v_request.staff_member_id, v_section_id, v_day, 'R/O')
      on conflict (schedule_month_id, staff_member_id, work_date) do update
      set shift_code = 'R/O', section_id = excluded.section_id, updated_at = now();
      insert into public.schedule_changes(schedule_month_id, staff_member_id, section_id,
        work_date, old_shift_code, new_shift_code, changed_by_staff_member_id)
      values (v_month_id, v_request.staff_member_id, v_section_id, v_day,
        v_old_code, 'R/O', public.current_staff_member_id());
      if public.is_working_shift(v_old_code) then
        insert into public.short_shifts(schedule_month_id, section_id, work_date,
          shift_code, staff_member_id, reason)
        values (v_month_id, v_section_id, v_day, v_old_code,
          v_request.staff_member_id, 'request_off');
      end if;
    end loop;
  end if;

  update public.requests_off set decision = p_decision,
    decision_reason = nullif(trim(p_reason), ''),
    decided_by_staff_member_id = public.current_staff_member_id(),
    decided_at = clock_timestamp() where id = p_request_id;
  insert into public.in_app_notices(staff_member_id, request_off_id, kind)
  values (v_request.staff_member_id, p_request_id, 'request_decided');
end;
$$;

revoke all on function public.submit_request_off(date[], text) from public;
revoke all on function public.confirm_request_off_email(uuid) from public;
revoke all on function public.acknowledge_request_off_notices() from public;
revoke all on function public.decide_request_off(uuid, text, text) from public;
grant execute on function public.submit_request_off(date[], text) to authenticated;
grant execute on function public.confirm_request_off_email(uuid) to authenticated;
grant execute on function public.acknowledge_request_off_notices() to authenticated;
grant execute on function public.decide_request_off(uuid, text, text) to authenticated;
