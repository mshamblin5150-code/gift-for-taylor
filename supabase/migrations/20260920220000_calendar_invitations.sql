-- Calendar invitations are an alternative to feed subscriptions. Keep an
-- immutable delivery record so a removed shift can still be cancelled.
alter table public.staff_members add column calendar_channel text not null
  default 'invitations' check (calendar_channel in ('invitations', 'feed'));

-- Existing feed subscribers keep their chosen channel on upgrade.
update public.staff_members member set calendar_channel = 'feed'
where exists (select 1 from public.calendar_feed_tokens token
  where token.staff_member_id = member.id and token.revoked_at is null);

create table public.calendar_invitation_outbox (
  id uuid primary key default gen_random_uuid(),
  staff_member_id uuid not null references public.staff_members(id),
  work_date date not null,
  recipient text not null,
  method text not null check (method in ('REQUEST', 'CANCEL')),
  shift_code text not null,
  starts_at timestamptz,
  ends_at timestamptz,
  sequence integer not null check (sequence >= 0),
  last_modified timestamptz not null default clock_timestamp(),
  sent_at timestamptz,
  superseded_at timestamptz,
  unique (staff_member_id, work_date, sequence),
  check ((starts_at is null) = (ends_at is null))
);
create index calendar_invitation_outbox_pending
  on public.calendar_invitation_outbox (last_modified)
  where sent_at is null and superseded_at is null;
alter table public.calendar_invitation_outbox enable row level security;
revoke all on public.calendar_invitation_outbox from public, anon, authenticated;
grant select on public.calendar_invitation_outbox to service_role;

create function public.queue_calendar_invitation(
  p_staff_member_id uuid, p_work_date date, p_method text,
  p_shift_code text, p_starts_at timestamptz, p_ends_at timestamptz
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_recipient text;
  v_sequence integer;
begin
  perform pg_advisory_xact_lock(hashtext(p_staff_member_id::text || ':' || p_work_date::text));
  select account.personal_email into v_recipient
  from public.staff_accounts account
  where account.staff_member_id = p_staff_member_id
    and account.accepted_invite_at is not null and account.revoked_at is null;
  if v_recipient is null then return; end if;

  -- A cancelled request that has not left the outbox need not be delivered.
  update public.calendar_invitation_outbox
    set superseded_at = clock_timestamp()
    where staff_member_id = p_staff_member_id and work_date = p_work_date
      and sent_at is null and superseded_at is null;
  select coalesce(max(sequence) + 1, 0) into v_sequence
  from public.calendar_invitation_outbox
  where staff_member_id = p_staff_member_id and work_date = p_work_date;
  insert into public.calendar_invitation_outbox
    (staff_member_id, work_date, recipient, method, shift_code,
     starts_at, ends_at, sequence)
  values (p_staff_member_id, p_work_date, v_recipient, p_method,
    p_shift_code, p_starts_at, p_ends_at, v_sequence);
end;
$$;
revoke all on function public.queue_calendar_invitation(uuid,date,text,text,timestamptz,timestamptz)
  from public, anon, authenticated;

create function public.queue_calendar_cell(
  p_staff_member_id uuid, p_work_date date, p_shift_code text,
  p_method text default 'REQUEST'
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_start time;
  v_end time;
begin
  select code.start_time, code.end_time into v_start, v_end
  from public.shift_codes code where code.code = upper(trim(p_shift_code));
  perform public.queue_calendar_invitation(p_staff_member_id, p_work_date,
    p_method, p_shift_code,
    case when v_start is not null then
      (p_work_date + v_start) at time zone 'America/New_York' end,
    case when v_end is not null then
      (p_work_date + v_end + case when v_end <= v_start
        then interval '1 day' else interval '0 day' end)
        at time zone 'America/New_York' end);
end;
$$;
revoke all on function public.queue_calendar_cell(uuid,date,text,text)
  from public, anon, authenticated;

create function public.calendar_cell_changed()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_released boolean;
  v_active boolean;
  v_channel text;
begin
  if tg_op = 'UPDATE' and new.shift_code is not distinct from old.shift_code then
    return new;
  end if;
  select month.release_state = 'released', member.active, member.calendar_channel
    into v_released, v_active, v_channel
  from public.schedule_months month
  join public.staff_members member on member.id = new.staff_member_id
  where month.id = new.schedule_month_id;
  if not v_released or not v_active or v_channel <> 'invitations' then return new; end if;
  if public.is_working_shift(new.shift_code) then
    perform public.queue_calendar_cell(new.staff_member_id, new.work_date,
      new.shift_code);
  elsif tg_op = 'UPDATE' and public.is_working_shift(old.shift_code) then
    perform public.queue_calendar_cell(new.staff_member_id, new.work_date,
      old.shift_code, 'CANCEL');
  end if;
  return new;
end;
$$;
create trigger calendar_cell_changed after insert or update on public.schedule_cells
  for each row execute function public.calendar_cell_changed();

-- Editing the Shift code legend changes the feed's interpretation of saved
-- cells. Invitations must follow that same interpretation.
create function public.calendar_shift_code_changed()
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
create trigger calendar_shift_code_changed
  after update of is_working, start_time, end_time on public.shift_codes
  for each row execute function public.calendar_shift_code_changed();

create function public.calendar_month_released()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_cell record;
begin
  if old.release_state = 'unpublished' and new.release_state = 'released' then
    for v_cell in
      select cell.staff_member_id, cell.work_date, cell.shift_code
      from public.schedule_cells cell
      join public.staff_members member on member.id = cell.staff_member_id
      where cell.schedule_month_id = new.id and member.active
        and member.calendar_channel = 'invitations'
        and public.is_working_shift(cell.shift_code)
    loop
      perform public.queue_calendar_cell(v_cell.staff_member_id,
        v_cell.work_date, v_cell.shift_code);
    end loop;
  end if;
  return new;
end;
$$;
create trigger calendar_month_released after update of release_state
  on public.schedule_months for each row execute function public.calendar_month_released();

create function public.queue_current_calendar_shifts(p_staff_member_id uuid,
  p_method text) returns void language plpgsql security definer set search_path = '' as $$
declare v_cell record;
begin
  for v_cell in
    select cell.work_date, cell.shift_code from public.schedule_cells cell
    join public.schedule_months month on month.id = cell.schedule_month_id
    where cell.staff_member_id = p_staff_member_id
      and month.release_state = 'released'
      and public.is_working_shift(cell.shift_code)
  loop
    perform public.queue_calendar_cell(p_staff_member_id, v_cell.work_date,
      v_cell.shift_code, p_method);
  end loop;
end;
$$;
revoke all on function public.queue_current_calendar_shifts(uuid,text)
  from public, anon, authenticated;

-- The first Calendar subscription switches channels. Later subscriptions are
-- independent links for the same Staff member.
create or replace function public.create_calendar_subscription(p_name text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_staff_member_id uuid := public.current_staff_member_id();
  v_token text := encode(extensions.gen_random_bytes(32), 'hex');
  v_id uuid;
begin
  if v_staff_member_id is null or not exists (
    select 1 from public.staff_accounts account
    join public.staff_members member on member.id = account.staff_member_id
    where account.staff_member_id = v_staff_member_id
      and account.auth_user_id = auth.uid() and account.revoked_at is null
      and member.active
  ) then
    raise exception 'Only active Staff members can create a Calendar subscription';
  end if;
  if p_name is null or length(trim(p_name)) not between 1 and 80 then
    raise exception 'Calendar subscription name must be 1 to 80 characters';
  end if;
  if (select calendar_channel from public.staff_members where id = v_staff_member_id)
    = 'invitations' then
    perform public.queue_current_calendar_shifts(v_staff_member_id, 'CANCEL');
    update public.staff_members set calendar_channel = 'feed'
      where id = v_staff_member_id;
  end if;
  insert into public.calendar_feed_tokens (staff_member_id, name, token_hash)
  values (v_staff_member_id, trim(p_name),
    encode(sha256(decode(v_token, 'hex')), 'hex'))
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'token', v_token);
end;
$$;

create or replace function public.revoke_calendar_subscription(p_id uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_staff_member_id uuid := public.current_staff_member_id();
begin
  update public.calendar_feed_tokens token set revoked_at = now()
  where token.id = p_id and token.revoked_at is null
    and token.staff_member_id = v_staff_member_id
    and exists (select 1 from public.staff_accounts account
      where account.staff_member_id = token.staff_member_id
        and account.auth_user_id = auth.uid() and account.revoked_at is null);
  if not found then raise exception 'Calendar subscription not found'; end if;
  if not exists (select 1 from public.calendar_feed_tokens
      where staff_member_id = v_staff_member_id and revoked_at is null) then
    update public.staff_members set calendar_channel = 'invitations'
      where id = v_staff_member_id and calendar_channel = 'feed';
    perform public.queue_current_calendar_shifts(v_staff_member_id, 'REQUEST');
  end if;
end;
$$;

create function public.use_calendar_invitations()
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_staff_member_id uuid := public.current_staff_member_id();
begin
  if v_staff_member_id is null then
    raise exception 'Only active Staff members can use Calendar invitations';
  end if;
  update public.calendar_feed_tokens set revoked_at = now()
    where staff_member_id = v_staff_member_id and revoked_at is null;
  update public.staff_members set calendar_channel = 'invitations'
    where id = v_staff_member_id and calendar_channel = 'feed';
  if found then
    perform public.queue_current_calendar_shifts(v_staff_member_id, 'REQUEST');
  end if;
end;
$$;
revoke all on function public.use_calendar_invitations() from public, anon;
grant execute on function public.use_calendar_invitations() to authenticated;

create function public.my_calendar_channel()
returns text language sql stable security definer set search_path = '' as $$
  select member.calendar_channel from public.staff_members member
  where member.id = public.current_staff_member_id()
$$;
revoke all on function public.my_calendar_channel() from public, anon;
grant execute on function public.my_calendar_channel() to authenticated;

create function public.calendar_account_ready()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (select member.active and member.calendar_channel = 'invitations'
      from public.staff_members member where member.id = new.staff_member_id) then
    perform public.queue_current_calendar_shifts(new.staff_member_id, 'REQUEST');
  end if;
  return new;
end;
$$;
create trigger calendar_account_ready after insert on public.staff_accounts
  for each row execute function public.calendar_account_ready();
create trigger calendar_account_reactivated after update of revoked_at
  on public.staff_accounts for each row
  when (old.revoked_at is not null and new.revoked_at is null)
  execute function public.calendar_account_ready();

create function public.calendar_member_deactivated()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.active and not new.active and old.calendar_channel = 'invitations' then
    perform public.queue_current_calendar_shifts(new.id, 'CANCEL');
  end if;
  return new;
end;
$$;
create trigger calendar_member_deactivated after update of active on public.staff_members
  for each row execute function public.calendar_member_deactivated();

-- Privileged delivery endpoint re-reads a queued row; clients cannot enumerate
-- addresses or mark mail as sent.
create function public.calendar_invitation_to_send(p_id uuid)
returns setof public.calendar_invitation_outbox
language sql stable security definer set search_path = '' as $$
  select event.* from public.calendar_invitation_outbox event
  where event.id = p_id and event.sent_at is null and event.superseded_at is null
$$;
revoke all on function public.calendar_invitation_to_send(uuid)
  from public, anon, authenticated;
grant execute on function public.calendar_invitation_to_send(uuid) to service_role;

create function public.calendar_invitation_sent(p_id uuid)
returns void language sql volatile security definer set search_path = '' as $$
  update public.calendar_invitation_outbox set sent_at = clock_timestamp()
  where id = p_id and sent_at is null and superseded_at is null
$$;
revoke all on function public.calendar_invitation_sent(uuid)
  from public, anon, authenticated;
grant execute on function public.calendar_invitation_sent(uuid) to service_role;

-- Existing released months need an initial invitation for Staff who have not
-- chosen a feed. Rows remain pending until the delivery webhook is configured.
do $$ declare v_member record; begin
  for v_member in select member.id from public.staff_members member
    join public.staff_accounts account on account.staff_member_id = member.id
    where member.active and member.calendar_channel = 'invitations'
      and account.revoked_at is null
  loop
    perform public.queue_current_calendar_shifts(v_member.id, 'REQUEST');
  end loop;
end $$;
