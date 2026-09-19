-- One durable notice table drives both the in-app feed and the push webhook.
alter table public.staff_notices drop constraint staff_notices_kind_check;
alter table public.staff_notices add constraint staff_notices_kind_check check (kind in (
  'month_release', 'schedule_change', 'open_shift_pickup', 'open_shift_posted',
  'request_submitted', 'request_decided', 'swap_proposed', 'swap_accepted',
  'swap_declined', 'swap_approved', 'test'
));

alter table public.staff_notices add column push_eligible boolean not null default true;

-- Preserve unread state and timestamps for notices created before this migration.
insert into public.staff_notices(id, staff_member_id, kind, title, body, created_at, read_at, push_eligible)
select old.id, old.staff_member_id, old.kind,
  case old.kind when 'request_submitted' then 'Request off submitted'
    else 'Request off decided' end,
  case old.kind when 'request_submitted' then
    requester.display_name || ' submitted a Request off.'
    else 'Your Request off was ' || request.decision || '.' end,
  old.created_at, old.read_at, false
from public.in_app_notices old
join public.requests_off request on request.id = old.request_off_id
join public.staff_members requester on requester.id = request.staff_member_id;

-- Existing Request off functions insert into this compatibility view. It has no
-- stored rows: the insert trigger writes the same staff_notices feed as every
-- other event. The view can be removed when those functions are next revised.
drop table public.in_app_notices;
create view public.in_app_notices with (security_invoker = true) as
select id, staff_member_id, null::uuid as request_off_id, kind, created_at, read_at
from public.staff_notices where kind in ('request_submitted', 'request_decided');
revoke all on public.in_app_notices from public, anon, authenticated;

create function public.forward_request_notice()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_request public.requests_off%rowtype;
  v_name text;
begin
  if new.staff_member_id = public.current_staff_member_id() then return new; end if;
  select * into v_request from public.requests_off where id = new.request_off_id;
  select display_name into v_name from public.staff_members where id = v_request.staff_member_id;
  insert into public.staff_notices(staff_member_id, kind, title, body)
  values (new.staff_member_id, new.kind,
    case new.kind when 'request_submitted' then 'Request off submitted'
      else 'Request off decided' end,
    case new.kind when 'request_submitted' then v_name || ' submitted a Request off.'
      else 'Your Request off was ' || v_request.decision || '.' end);
  return new;
end;
$$;
create trigger forward_request_notice instead of insert on public.in_app_notices
for each row execute function public.forward_request_notice();

create or replace function public.acknowledge_request_off_notices()
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if public.current_staff_member_id() is null then
    raise exception 'Not on the Staff list';
  end if;
  update public.staff_notices set read_at = clock_timestamp()
  where staff_member_id = public.current_staff_member_id()
    and kind in ('request_submitted', 'request_decided') and read_at is null;
end;
$$;

-- The test endpoint was useful during setup but should no longer create real notices.
drop function public.send_test_push();

create function public.notice_swap()
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
  where recipient.active and recipient.id <> v_actor and (
    recipient.id in (new.requester_id, new.colleague_id)
    or (new.status = 'accepted' and recipient.role = 'manager')
  );
  return new;
end;
$$;
create trigger notice_swap after insert or update on public.swaps
for each row execute function public.notice_swap();

create function public.notice_open_shift(p_short public.short_shifts, p_actor uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_role public.job_role;
begin
  select role.job_role into v_role from public.staff_job_roles role
  where role.staff_member_id = p_short.staff_member_id
    and role.effective_from <= p_short.work_date
  order by role.effective_from desc limit 1;
  if v_role is null then return; end if;
  insert into public.staff_notices(staff_member_id, kind, title, body, month_start)
  select distinct member.id, 'open_shift_posted', 'Open shift posted',
    p_short.shift_code || ' on ' || p_short.work_date::text || ' is open for pickup.',
    date_trunc('month', p_short.work_date)::date
  from public.staff_members member
  join public.staff_accounts account on account.staff_member_id = member.id
  join public.staff_job_roles role on role.staff_member_id = member.id
  join public.staff_section_assignments assignment on assignment.staff_member_id = member.id
  where member.active and member.role = 'staff_member' and member.id <> p_actor
    and member.id <> p_short.staff_member_id
    and account.accepted_invite_at is not null and account.revoked_at is null
    and role.effective_from <= p_short.work_date
    and (role.effective_through is null or role.effective_through >= p_short.work_date)
    and assignment.effective_from <= p_short.work_date
    and (assignment.effective_through is null or assignment.effective_through >= p_short.work_date)
    and (role.job_role = v_role or
      (role.job_role in ('rn', 'lpn') and v_role in ('rn', 'lpn')))
    and not exists (select 1 from public.schedule_cells cell
      where cell.staff_member_id = member.id and cell.work_date = p_short.work_date
        and cell.shift_code not in ('', 'X'));
end;
$$;
revoke all on function public.notice_open_shift(public.short_shifts, uuid) from public;

create function public.notice_new_open_shift()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.schedule_months month
    where month.id = new.schedule_month_id and month.release_state = 'released') then
    perform public.notice_open_shift(new, public.current_staff_member_id());
  end if;
  return new;
end;
$$;
create trigger notice_new_open_shift after insert on public.short_shifts
for each row execute function public.notice_new_open_shift();

create or replace function public.notice_month_release()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_short public.short_shifts%rowtype;
begin
  if new.release_state = 'released' and old.release_state = 'unpublished' then
    insert into public.staff_notices (staff_member_id, kind, title, body, month_start)
    select member.id, 'month_release', 'Schedule released',
      to_char(new.month_start, 'FMMonth YYYY') || ' is ready to view.', new.month_start
    from public.staff_members member
    where member.active and member.id is distinct from new.released_by_staff_member_id;
    for v_short in select * from public.short_shifts
      where schedule_month_id = new.id and filled_at is null loop
      perform public.notice_open_shift(v_short, new.released_by_staff_member_id);
    end loop;
  end if;
  return new;
end;
$$;

create or replace function public.notice_schedule_change()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.staff_notices (staff_member_id, kind, title, body, month_start)
  select distinct changed.staff_member_id, 'schedule_change',
    'Your Schedule changed',
    'One or more shifts changed. Open the Schedule for details.',
    month.month_start
  from new_rows changed
  join old_rows previous on previous.id = changed.id
  join public.schedule_months month on month.id = changed.schedule_month_id
  join public.staff_members member on member.id = changed.staff_member_id
  where previous.announced_at is null and changed.announced_at is not null
    and changed.push_eligible and month.release_state = 'released'
    and member.active and changed.staff_member_id <> changed.changed_by_staff_member_id;
  return null;
end;
$$;
