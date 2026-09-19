-- A notice is the durable in-app record. The database webhook on INSERT sends
-- the same notice as web push to the recipient's opted-in devices.
create table public.staff_notices (
  id uuid primary key default gen_random_uuid(),
  staff_member_id uuid not null references public.staff_members(id),
  kind text not null check (kind in ('month_release', 'schedule_change', 'test')),
  title text not null,
  body text not null,
  month_start date,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index staff_notices_recipient on public.staff_notices
  (staff_member_id, created_at desc);

create table public.push_subscriptions (
  endpoint text primary key,
  staff_member_id uuid not null references public.staff_members(id),
  subscription jsonb not null,
  created_at timestamptz not null default now(),
  check (length(endpoint) <= 2048),
  check (subscription->>'endpoint' = endpoint)
);

create index push_subscriptions_recipient on public.push_subscriptions
  (staff_member_id);

alter table public.staff_notices enable row level security;
alter table public.push_subscriptions enable row level security;
grant select on public.staff_notices to authenticated;

create policy "staff read their notices" on public.staff_notices for select
using (staff_member_id = public.current_staff_member_id());

create function public.register_push_subscription(p_subscription jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_staff_id uuid := public.current_staff_member_id();
  v_endpoint text := p_subscription->>'endpoint';
begin
  if v_staff_id is null then
    raise exception 'Only active Staff can allow push';
  end if;
  if v_endpoint is null or length(v_endpoint) > 2048
    or v_endpoint !~ '^https://'
    or p_subscription->'keys'->>'p256dh' is null
    or p_subscription->'keys'->>'auth' is null then
    raise exception 'Invalid push subscription';
  end if;
  insert into public.push_subscriptions (endpoint, staff_member_id, subscription)
  values (v_endpoint, v_staff_id, p_subscription)
  on conflict (endpoint) do update set
    staff_member_id = excluded.staff_member_id,
    subscription = excluded.subscription;
end;
$$;

create function public.remove_push_subscription(p_endpoint text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from public.push_subscriptions
  where endpoint = p_endpoint
    and staff_member_id = public.current_staff_member_id();
end;
$$;

create function public.send_test_push()
returns void language plpgsql security definer set search_path = '' as $$
declare v_staff_id uuid := public.current_staff_member_id();
begin
  if v_staff_id is null then
    raise exception 'Only active Staff can test push';
  end if;
  if not exists (select 1 from public.push_subscriptions where staff_member_id = v_staff_id) then
    raise exception 'Allow notifications first';
  end if;
  insert into public.staff_notices (staff_member_id, kind, title, body)
  values (v_staff_id, 'test', 'ER Schedule test', 'Notifications are working.');
end;
$$;

create function public.mark_staff_notice_read(p_notice_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.staff_notices set read_at = coalesce(read_at, now())
  where id = p_notice_id and staff_member_id = public.current_staff_member_id();
end;
$$;

revoke all on function public.register_push_subscription(jsonb) from public;
revoke all on function public.remove_push_subscription(text) from public;
revoke all on function public.send_test_push() from public;
revoke all on function public.mark_staff_notice_read(uuid) from public;
grant execute on function public.register_push_subscription(jsonb),
  public.remove_push_subscription(text), public.send_test_push(),
  public.mark_staff_notice_read(uuid) to authenticated;

create function public.notice_month_release()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.release_state = 'released' and old.release_state = 'unpublished' then
    insert into public.staff_notices (staff_member_id, kind, title, body, month_start)
    select member.id, 'month_release', 'Schedule released',
      to_char(new.month_start, 'FMMonth YYYY') || ' is ready to view.', new.month_start
    from public.staff_members member
    where member.active;
  end if;
  return new;
end;
$$;

create trigger notice_month_release after update of release_state
on public.schedule_months for each row execute function public.notice_month_release();

-- Capture whether an edit was made to a live month when it is saved. Comparing
-- timestamps later is unreliable when release and edits share a transaction.
alter table public.schedule_changes add column push_eligible boolean not null default false;

create function public.set_change_push_eligibility()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  new.push_eligible := exists (
    select 1 from public.schedule_months month
    where month.id = new.schedule_month_id and month.release_state = 'released'
  );
  return new;
end;
$$;

create trigger set_change_push_eligibility before insert on public.schedule_changes
for each row execute function public.set_change_push_eligibility();

create function public.notice_schedule_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_month_start date;
begin
  select month.month_start into v_month_start from public.schedule_months month
  where month.id = new.schedule_month_id and month.release_state = 'released';
  if old.announced_at is null and new.announced_at is not null
    and new.push_eligible and v_month_start is not null and exists (
    select 1 from public.staff_members member
    where member.id = new.staff_member_id and member.active
  ) then
    insert into public.staff_notices (staff_member_id, kind, title, body, month_start)
    values (new.staff_member_id, 'schedule_change', 'Your Schedule changed',
      'A shift on ' || to_char(new.work_date, 'FMMonth FMDD') || ' changed. Open the Schedule for details.',
      v_month_start);
  end if;
  return new;
end;
$$;

create trigger notice_schedule_change after update of announced_at on public.schedule_changes
for each row execute function public.notice_schedule_change();
