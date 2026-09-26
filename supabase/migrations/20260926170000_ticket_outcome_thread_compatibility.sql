-- Keep Ticket outcome privacy and reopening valid across the private thread.
alter table public.tickets
  drop constraint ticket_prior_close_is_reopened,
  add constraint ticket_prior_close_is_reopened check (
    closed_at is null or state in ('done', 'wont_do')
      or (state in ('seen', 'waiting_on_sender') and reopened_at is not null)
  );

drop function public.answer_ticket_question(uuid, uuid, text, boolean);

create function public.answer_ticket_question(
  p_ticket_id uuid,
  p_question_id uuid,
  p_answer text,
  p_accept_suggestion boolean
)
returns jsonb
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
  return private.sender_ticket(v_ticket);
end;
$$;

revoke all on function public.answer_ticket_question(uuid, uuid, text, boolean)
  from public;
grant execute on function public.answer_ticket_question(uuid, uuid, text, boolean)
  to authenticated;
