-- A Ticket is private between its sending Staff member and the Maintainer.
create type public.ticket_kind as enum ('problem', 'idea', 'question');
create type public.ticket_state as enum (
  'sent', 'seen', 'waiting_on_sender', 'done', 'wont_do'
);

create table public.tickets (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.staff_members(id),
  sender_display_name text not null,
  kind public.ticket_kind not null,
  text text not null,
  state public.ticket_state not null default 'sent',
  screen_context text not null,
  schedule_month date,
  release_id text not null,
  device_context text not null,
  context_captured_at timestamptz not null,
  created_at timestamptz not null default clock_timestamp(),
  seen_at timestamptz,
  seen_by_auth_user_id uuid references auth.users(id),
  constraint ticket_text_length check (
    char_length(trim(text)) between 1 and 2000
  ),
  constraint ticket_screen_context_length check (
    char_length(trim(screen_context)) between 1 and 100
  ),
  constraint ticket_release_length check (
    char_length(trim(release_id)) between 1 and 120
  ),
  constraint ticket_device_context_length check (
    char_length(trim(device_context)) between 1 and 500
  ),
  constraint ticket_month_is_month_start check (
    schedule_month is null or schedule_month = date_trunc('month', schedule_month)::date
  ),
  constraint ticket_seen_record check (
    (state = 'sent' and seen_at is null and seen_by_auth_user_id is null)
    or (state <> 'sent' and seen_at is not null
      and seen_by_auth_user_id is not null)
  )
);

create index tickets_by_sender
  on public.tickets(sender_id, created_at desc, id);
create index tickets_newest_first
  on public.tickets(created_at desc, id);

alter table public.tickets enable row level security;
revoke all on public.tickets from public, anon, authenticated;
grant select (
  id, sender_id, sender_display_name, kind, text, state, screen_context,
  schedule_month, release_id, device_context, context_captured_at,
  created_at, seen_at
) on public.tickets to authenticated;

create policy "Sender reads own Tickets"
on public.tickets for select to authenticated
using (sender_id = public.current_staff_member_id());

create policy "Maintainer reads every Ticket"
on public.tickets for select to authenticated
using (public.is_maintainer());

create function public.put_in_ticket(
  p_kind public.ticket_kind,
  p_text text,
  p_screen_context text,
  p_schedule_month date,
  p_release_id text,
  p_device_context text,
  p_context_captured_at timestamptz
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_sender_id uuid := public.current_staff_member_id();
  v_sender_name text;
  v_ticket_id uuid;
begin
  if v_sender_id is null then
    raise exception using errcode = 'P2831',
      message = 'A current Staff account is required';
  end if;
  if p_text is null or char_length(trim(p_text)) not between 1 and 2000 then
    raise exception using errcode = 'P2832',
      message = 'Ticket text must be between 1 and 2000 characters';
  end if;
  if p_screen_context is null
      or char_length(trim(p_screen_context)) not between 1 and 100
      or p_release_id is null
      or char_length(trim(p_release_id)) not between 1 and 120
      or p_device_context is null
      or char_length(trim(p_device_context)) not between 1 and 500
      or p_context_captured_at is null
      or (p_schedule_month is not null
        and p_schedule_month <> date_trunc('month', p_schedule_month)::date) then
    raise exception using errcode = 'P2833',
      message = 'Ticket context is incomplete';
  end if;

  select display_name into strict v_sender_name
  from public.staff_members where id = v_sender_id;

  insert into public.tickets(
    sender_id, sender_display_name, kind, text, screen_context,
    schedule_month, release_id, device_context, context_captured_at
  ) values (
    v_sender_id, v_sender_name, p_kind, trim(p_text),
    trim(p_screen_context), p_schedule_month, trim(p_release_id),
    trim(p_device_context), p_context_captured_at
  ) returning id into v_ticket_id;
  return v_ticket_id;
end;
$$;

revoke all on function public.put_in_ticket(
  public.ticket_kind, text, text, date, text, text, timestamptz
) from public;
grant execute on function public.put_in_ticket(
  public.ticket_kind, text, text, date, text, text, timestamptz
) to authenticated;

create function public.open_ticket_for_maintainer(p_ticket_id uuid)
returns public.tickets
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare v_ticket public.tickets%rowtype;
begin
  if not public.is_maintainer() then
    raise exception using errcode = '42501',
      message = 'Only the Maintainer can open Tickets';
  end if;

  update public.tickets
  set state = case when state = 'sent'
      then 'seen'::public.ticket_state else state end,
    seen_at = case when state = 'sent' then clock_timestamp() else seen_at end,
    seen_by_auth_user_id = case when state = 'sent'
      then auth.uid() else seen_by_auth_user_id end
  where id = p_ticket_id
  returning * into v_ticket;

  if not found then
    raise exception using errcode = 'P2834', message = 'Ticket not found';
  end if;
  return v_ticket;
end;
$$;

revoke all on function public.open_ticket_for_maintainer(uuid) from public;
grant execute on function public.open_ticket_for_maintainer(uuid)
  to authenticated;
