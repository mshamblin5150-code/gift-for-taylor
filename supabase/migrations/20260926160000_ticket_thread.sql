-- A Ticket question stays private between its sender and the Maintainer.
create type public.ticket_thread_author as enum ('maintainer', 'sender');

alter table public.tickets
  add column question_count integer not null default 0
    check (question_count >= 0),
  add column latest_reply_at timestamptz,
  add column reply_seen_at timestamptz,
  add constraint ticket_reply_marker check (
    (latest_reply_at is null and reply_seen_at is null)
    or (latest_reply_at is not null
      and (reply_seen_at is null or reply_seen_at >= latest_reply_at))
  );

grant select (question_count, latest_reply_at, reply_seen_at)
  on public.tickets to authenticated;

create table public.ticket_thread_entries (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.tickets(id) on delete cascade,
  author public.ticket_thread_author not null,
  text text not null check (char_length(trim(text)) between 1 and 1000),
  suggested_answer text check (
    suggested_answer is null
    or char_length(trim(suggested_answer)) between 1 and 500
  ),
  reply_to_id uuid references public.ticket_thread_entries(id),
  accepted_suggestion boolean,
  created_at timestamptz not null default clock_timestamp(),
  constraint ticket_thread_entry_shape check (
    (author = 'maintainer' and reply_to_id is null
      and accepted_suggestion is null)
    or (author = 'sender' and reply_to_id is not null
      and suggested_answer is null and accepted_suggestion is not null)
  )
);

create index ticket_thread_in_order
  on public.ticket_thread_entries(ticket_id, created_at, id);

alter table public.ticket_thread_entries enable row level security;
revoke all on public.ticket_thread_entries from public, anon, authenticated;
grant select (
  id, ticket_id, author, text, suggested_answer, reply_to_id,
  accepted_suggestion, created_at
) on public.ticket_thread_entries to authenticated;

create policy "Sender reads own Ticket thread"
on public.ticket_thread_entries for select to authenticated
using (exists (
  select 1 from public.tickets ticket
  where ticket.id = ticket_id
    and ticket.sender_id = public.current_staff_member_id()
));

create policy "Maintainer reads every Ticket thread"
on public.ticket_thread_entries for select to authenticated
using (public.is_maintainer());

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
    'maintainer_repair', 'ticket_closed', 'ticket_question'
  )
);

create function public.ask_ticket_question(
  p_ticket_id uuid,
  p_question text,
  p_suggested_answer text default null
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
      message = 'Only the Maintainer can ask Ticket questions';
  end if;
  if p_question is null
      or char_length(trim(p_question)) not between 1 and 1000
      or (p_suggested_answer is not null
        and char_length(trim(p_suggested_answer)) not between 1 and 500) then
    raise exception using errcode = 'P2841',
      message = 'Ticket question text is invalid';
  end if;

  select * into v_ticket from public.tickets
  where id = p_ticket_id for update;
  if not found then
    raise exception using errcode = 'P2834', message = 'Ticket not found';
  end if;
  if v_ticket.state <> 'seen' then
    raise exception using errcode = 'P2842',
      message = 'This Ticket is not ready for another question';
  end if;

  insert into public.ticket_thread_entries(
    ticket_id, author, text, suggested_answer
  ) values (
    p_ticket_id, 'maintainer', trim(p_question),
    nullif(trim(p_suggested_answer), '')
  );
  update public.tickets
  set state = 'waiting_on_sender', question_count = question_count + 1
  where id = p_ticket_id returning * into v_ticket;

  insert into public.staff_notices(
    staff_member_id, kind, title, body
  ) values (
    v_ticket.sender_id, 'ticket_question', 'A Ticket needs your answer',
    'The Maintainer asked a question about your Ticket. Open My tickets to answer.'
  );
  return v_ticket;
end;
$$;

revoke all on function public.ask_ticket_question(uuid, text, text) from public;
grant execute on function public.ask_ticket_question(uuid, text, text)
  to authenticated;

create function public.answer_ticket_question(
  p_ticket_id uuid,
  p_question_id uuid,
  p_answer text,
  p_accept_suggestion boolean
)
returns public.tickets
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_ticket public.tickets%rowtype;
  v_question public.ticket_thread_entries%rowtype;
  v_answer text;
  v_now timestamptz := clock_timestamp();
begin
  select * into v_ticket from public.tickets
  where id = p_ticket_id for update;
  if not found or v_ticket.sender_id is distinct from
      public.current_staff_member_id() then
    raise exception using errcode = '42501',
      message = 'Only the sender can answer this Ticket';
  end if;
  if v_ticket.state <> 'waiting_on_sender' then
    raise exception using errcode = 'P2844',
      message = 'This Ticket is not waiting for an answer';
  end if;

  select * into v_question from public.ticket_thread_entries
  where id = p_question_id and ticket_id = p_ticket_id
    and author = 'maintainer'
  order by created_at desc, id desc limit 1;
  if not found or p_question_id is distinct from (
    select id from public.ticket_thread_entries
    where ticket_id = p_ticket_id and author = 'maintainer'
    order by created_at desc, id desc limit 1
  ) then
    raise exception using errcode = 'P2844',
      message = 'This Ticket question is no longer waiting for an answer';
  end if;

  if p_accept_suggestion then
    if v_question.suggested_answer is null then
      raise exception using errcode = 'P2843',
        message = 'This question has no suggested answer';
    end if;
    v_answer := v_question.suggested_answer;
  else
    if p_answer is null or char_length(trim(p_answer)) not between 1 and 1000 then
      raise exception using errcode = 'P2843',
        message = 'Ticket answer text is invalid';
    end if;
    v_answer := trim(p_answer);
  end if;

  insert into public.ticket_thread_entries(
    ticket_id, author, text, reply_to_id, accepted_suggestion
  ) values (
    p_ticket_id, 'sender', v_answer, p_question_id, p_accept_suggestion
  );
  update public.tickets
  set state = 'seen', latest_reply_at = v_now, reply_seen_at = null
  where id = p_ticket_id returning * into v_ticket;
  return v_ticket;
end;
$$;

revoke all on function public.answer_ticket_question(uuid, uuid, text, boolean)
  from public;
grant execute on function public.answer_ticket_question(uuid, uuid, text, boolean)
  to authenticated;

create or replace function public.open_ticket_for_maintainer(p_ticket_id uuid)
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
      then auth.uid() else seen_by_auth_user_id end,
    reply_seen_at = case when latest_reply_at is not null
      and reply_seen_at is null then clock_timestamp() else reply_seen_at end
  where id = p_ticket_id
  returning * into v_ticket;

  if not found then
    raise exception using errcode = 'P2834', message = 'Ticket not found';
  end if;
  return v_ticket;
end;
$$;
