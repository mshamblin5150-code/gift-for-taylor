-- The secret is returned only at creation or reset. The database keeps its hash.
create table public.calendar_feed_tokens (
  staff_member_id uuid primary key references public.staff_members(id),
  token_hash text not null unique,
  rotated_at timestamptz not null default now(),
  revoked_at timestamptz
);

alter table public.calendar_feed_tokens enable row level security;
revoke all on public.calendar_feed_tokens from public, anon, authenticated;

create function public.has_calendar_feed()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.calendar_feed_tokens token
    where token.staff_member_id = public.current_staff_member_id()
      and token.revoked_at is null
  )
$$;
revoke all on function public.has_calendar_feed() from public;
grant execute on function public.has_calendar_feed() to authenticated;

create function public.reset_calendar_feed()
returns text
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_staff_member_id uuid := public.current_staff_member_id();
  v_token text := encode(extensions.gen_random_bytes(32), 'hex');
begin
  if v_staff_member_id is null or not exists (
    select 1 from public.staff_accounts account
    where account.staff_member_id = v_staff_member_id
      and account.auth_user_id = auth.uid()
      and account.revoked_at is null
  ) then
    raise exception 'Only active Staff members can reset a Calendar feed';
  end if;
  insert into public.calendar_feed_tokens (staff_member_id, token_hash)
  values (v_staff_member_id, encode(sha256(decode(v_token, 'hex')), 'hex'))
  on conflict (staff_member_id) do update
  set token_hash = excluded.token_hash,
      rotated_at = now(),
      revoked_at = null;
  return v_token;
end;
$$;
revoke all on function public.reset_calendar_feed() from public;
grant execute on function public.reset_calendar_feed() to authenticated;

create function public.calendar_feed_owner(p_token text)
returns uuid
language sql stable security definer set search_path = ''
as $$
  select member.id
  from public.calendar_feed_tokens token
  join public.staff_members member on member.id = token.staff_member_id
  where p_token ~ '^[0-9a-f]{64}$'
    and token.token_hash = encode(sha256(decode(p_token, 'hex')), 'hex')
    and token.revoked_at is null
    and member.active
$$;
revoke all on function public.calendar_feed_owner(text) from public, anon, authenticated;
grant execute on function public.calendar_feed_owner(text) to service_role;

-- Called only by the Edge Function with its service key. No caller supplies a
-- Staff id: the token selects its owner, and only released months are exposed.
create function public.calendar_feed_events(p_token text)
returns table (
  staff_member_id uuid,
  work_date date,
  shift_code text,
  starts_at timestamptz,
  ends_at timestamptz
)
language sql stable security definer set search_path = ''
as $$
  select member.id, cell.work_date, cell.shift_code,
    case when legend.start_time is not null then
      (cell.work_date + legend.start_time) at time zone 'America/New_York'
    end,
    case when legend.end_time is not null then
      (cell.work_date + legend.end_time +
        case when legend.end_time <= legend.start_time
          then interval '1 day' else interval '0 day' end)
        at time zone 'America/New_York'
    end
  from public.calendar_feed_tokens token
  join public.staff_members member on member.id = token.staff_member_id
  join public.schedule_cells cell on cell.staff_member_id = member.id
  join public.schedule_months month on month.id = cell.schedule_month_id
  left join (values
    ('16D', time '07:00', time '23:00'),
    ('7A',  time '07:00', time '19:00'),
    ('D',   time '07:00', time '15:00'),
    ('MM',  time '11:00', time '19:00'),
    ('11A', time '11:00', time '23:00'),
    ('3P',  time '15:00', time '03:00'),
    ('7P',  time '19:00', time '07:00'),
    ('ME',  time '19:00', time '03:00'),
    ('N',   time '23:00', time '07:00')
  ) as legend(code, start_time, end_time)
    on legend.code = upper(trim(cell.shift_code))
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

-- Deactivation immediately revokes the old URL. Reactivation requires a fresh
-- Invite and a newly generated feed URL.
create function public.revoke_calendar_feed_on_deactivation()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if old.active and not new.active then
    update public.calendar_feed_tokens
    set revoked_at = now()
    where staff_member_id = new.id and revoked_at is null;
  end if;
  return new;
end;
$$;
revoke all on function public.revoke_calendar_feed_on_deactivation() from public;
create trigger revoke_calendar_feed_on_deactivation
after update of active on public.staff_members
for each row execute function public.revoke_calendar_feed_on_deactivation();
