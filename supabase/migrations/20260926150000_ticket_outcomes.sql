-- A Maintainer closes a Ticket with an answer; its sender may reopen for 14 days.
alter table public.tickets
  add column github_issue_number bigint,
  add column github_issue_url text,
  add column github_linked_at timestamptz,
  add column github_linked_by_auth_user_id uuid references auth.users(id),
  add column close_reason text,
  add column closed_at timestamptz,
  add column closed_by_auth_user_id uuid references auth.users(id),
  add column reopened_at timestamptz,
  add column reopen_note text,
  add constraint ticket_github_issue_record check (
    (github_issue_number is null and github_issue_url is null
      and github_linked_at is null and github_linked_by_auth_user_id is null)
    or (github_issue_number > 0
      and github_issue_url =
        'https://github.com/mshamblin5150-code/gift-for-taylor/issues/'
        || github_issue_number::text
      and github_linked_at is not null
      and github_linked_by_auth_user_id is not null)
  ),
  add constraint ticket_close_record check (
    (close_reason is null and closed_at is null
      and closed_by_auth_user_id is null)
    or (char_length(trim(close_reason)) between 1 and 1000
      and closed_at is not null and closed_by_auth_user_id is not null)
  ),
  add constraint ticket_closed_state_has_record check (
    state not in ('done', 'wont_do') or closed_at is not null
  ),
  add constraint ticket_prior_close_is_reopened check (
    closed_at is null or state in ('done', 'wont_do')
      or (state = 'seen' and reopened_at is not null)
  ),
  add constraint ticket_reopen_record check (
    (reopened_at is null and reopen_note is null)
    or (reopened_at is not null
      and char_length(trim(reopen_note)) between 1 and 500)
  );

grant select (close_reason, closed_at, reopened_at, reopen_note)
  on public.tickets to authenticated;

create function private.ticket_reopen_until(p_ticket public.tickets)
returns timestamptz
language sql
immutable
set search_path = ''
as $$
  select case when p_ticket.closed_at is null then null
    else p_ticket.closed_at + interval '14 days' end
$$;

create function private.ticket_reopen_verdict(
  p_ticket public.tickets,
  p_at timestamptz
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_ticket.state not in ('done', 'wont_do')
      or p_ticket.closed_at is null then 'unavailable'
    when p_at > private.ticket_reopen_until(p_ticket) then 'expired'
    else 'available'
  end
$$;

create function private.sender_ticket(p_ticket public.tickets)
returns jsonb
language sql
volatile
set search_path = ''
as $$
  select to_jsonb(p_ticket)
    - 'github_issue_number'
    - 'github_issue_url'
    - 'github_linked_at'
    - 'github_linked_by_auth_user_id'
    - 'seen_by_auth_user_id'
    - 'closed_by_auth_user_id'
    || jsonb_build_object(
      'can_reopen', private.ticket_reopen_verdict(
        p_ticket, clock_timestamp()
      ) = 'available',
      'reopen_until', private.ticket_reopen_until(p_ticket)
    )
$$;
revoke all on function private.ticket_reopen_until(public.tickets),
  private.ticket_reopen_verdict(public.tickets, timestamptz),
  private.sender_ticket(public.tickets) from public;

create function public.open_ticket_for_sender(p_ticket_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_ticket public.tickets%rowtype;
begin
  select * into v_ticket from public.tickets
  where id = p_ticket_id
    and sender_id = public.current_staff_member_id();
  if not found then
    raise exception using errcode = 'P2834', message = 'Ticket not found';
  end if;
  return private.sender_ticket(v_ticket);
end;
$$;

alter table public.staff_notices drop constraint staff_notices_kind_check;
alter table public.staff_notices add constraint staff_notices_kind_check check (
  kind in (
    'month_release', 'schedule_change', 'open_shift_pickup',
    'open_shift_posted', 'request_submitted', 'request_decided',
    'swap_proposed', 'swap_accepted', 'swap_declined', 'swap_approved',
    'swap_withdrawn', 'swap_voided', 'giveaway_proposed',
    'giveaway_accepted', 'giveaway_declined', 'giveaway_approved',
    'giveaway_withdrawn', 'giveaway_voided', 'test',
    'floor_critical_call_in', 'call_in_filled', 'open_shift_batch',
    'maintainer_repair', 'ticket_closed'
  )
);

create function public.link_ticket_to_github(
  p_ticket_id uuid,
  p_issue_number bigint,
  p_issue_url text
)
returns public.tickets
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_ticket public.tickets%rowtype;
begin
  if not public.is_maintainer() then
    raise exception using errcode = '42501',
      message = 'Only the Maintainer can link Tickets to GitHub';
  end if;
  if p_issue_number is null or p_issue_number < 1
      or p_issue_url is distinct from
        'https://github.com/mshamblin5150-code/gift-for-taylor/issues/'
        || p_issue_number::text then
    raise exception using errcode = 'P2835',
      message = 'Enter a valid issue URL for this repository';
  end if;

  update public.tickets set
    github_issue_number = p_issue_number,
    github_issue_url = p_issue_url,
    github_linked_at = clock_timestamp(),
    github_linked_by_auth_user_id = auth.uid()
  where id = p_ticket_id
  returning * into v_ticket;
  if not found then
    raise exception using errcode = 'P2834', message = 'Ticket not found';
  end if;
  return v_ticket;
end;
$$;

create function public.close_ticket(
  p_ticket_id uuid,
  p_outcome public.ticket_state,
  p_reason text
)
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
      message = 'Only the Maintainer can close Tickets';
  end if;
  if p_reason is null or char_length(trim(p_reason)) not between 1 and 1000 then
    raise exception using errcode = 'P2836',
      message = 'A closing reason is required';
  end if;
  if p_outcome is null or p_outcome not in ('done', 'wont_do') then
    raise exception using errcode = 'P2837',
      message = 'Close a Ticket as Done or Won''t do';
  end if;

  update public.tickets set
    state = p_outcome,
    seen_at = coalesce(seen_at, clock_timestamp()),
    seen_by_auth_user_id = coalesce(seen_by_auth_user_id, auth.uid()),
    close_reason = trim(p_reason),
    closed_at = clock_timestamp(),
    closed_by_auth_user_id = auth.uid()
  where id = p_ticket_id
    and state not in ('done', 'wont_do')
  returning * into v_ticket;
  if not found then
    raise exception using errcode = 'P2837',
      message = 'This Ticket cannot be closed';
  end if;

  insert into public.staff_notices(staff_member_id, kind, title, body)
  values (
    v_ticket.sender_id,
    'ticket_closed',
    case v_ticket.state
      when 'done' then 'Ticket done'
      else 'Ticket won''t do'
    end,
    v_ticket.close_reason
  );
  return v_ticket;
end;
$$;

create function public.reopen_ticket(p_ticket_id uuid, p_note text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_ticket public.tickets%rowtype;
  v_verdict text;
begin
  if p_note is null or char_length(trim(p_note)) not between 1 and 500 then
    raise exception using errcode = 'P2838',
      message = 'A reopening note is required';
  end if;

  select * into v_ticket from public.tickets
  where id = p_ticket_id
    and sender_id = public.current_staff_member_id();
  if not found then
    raise exception using errcode = 'P2839',
      message = 'This Ticket cannot be reopened';
  end if;

  v_verdict := private.ticket_reopen_verdict(v_ticket, clock_timestamp());
  if v_verdict = 'expired' then
    raise exception using errcode = 'P2840',
      message = 'This Ticket can no longer be reopened';
  elsif v_verdict <> 'available' then
    raise exception using errcode = 'P2839',
      message = 'This Ticket cannot be reopened';
  end if;

  update public.tickets set
    state = 'seen',
    reopened_at = clock_timestamp(),
    reopen_note = trim(p_note)
  where id = p_ticket_id
  returning * into v_ticket;
  return private.sender_ticket(v_ticket);
end;
$$;

revoke all on function public.link_ticket_to_github(uuid, bigint, text),
  public.close_ticket(uuid, public.ticket_state, text),
  public.reopen_ticket(uuid, text),
  public.open_ticket_for_sender(uuid) from public;
grant execute on function public.link_ticket_to_github(uuid, bigint, text),
  public.close_ticket(uuid, public.ticket_state, text),
  public.reopen_ticket(uuid, text),
  public.open_ticket_for_sender(uuid) to authenticated;
