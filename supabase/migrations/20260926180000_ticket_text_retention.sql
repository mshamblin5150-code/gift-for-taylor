-- Ticket prose is temporary. Metadata remains after the private words are gone.
create type public.ticket_text_removal as enum ('maintainer', 'retention');

alter table public.tickets
  add column text_removal public.ticket_text_removal;
alter table public.ticket_thread_entries
  add column text_removal public.ticket_text_removal;

grant select (text_removal) on public.tickets,
  public.ticket_thread_entries to authenticated;

create function public.erase_expired_ticket_text()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_ticket_ids uuid[];
begin
  select array_agg(ticket.id) into v_ticket_ids
  from public.tickets ticket
  where ticket.state in ('done', 'wont_do')
    and ticket.closed_at <= clock_timestamp() - interval '90 days'
    and (
      ticket.text_removal is distinct from 'retention'
      or exists (
        select 1 from public.ticket_thread_entries entry
        where entry.ticket_id = ticket.id
          and (
            entry.text_removal is distinct from 'retention'
            or entry.suggested_answer is not null
          )
      )
    );

  if v_ticket_ids is null then
    return 0;
  end if;

  update public.tickets
  set text = 'Text erased 90 days after closing',
    text_removal = 'retention'
  where id = any(v_ticket_ids);

  update public.ticket_thread_entries
  set text = 'Text erased 90 days after closing',
    suggested_answer = null,
    text_removal = 'retention'
  where ticket_id = any(v_ticket_ids);

  return cardinality(v_ticket_ids);
end;
$$;
revoke all on function public.erase_expired_ticket_text()
  from public, anon, authenticated, service_role;

create function public.redact_ticket_text(p_ticket_id uuid)
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
      message = 'Only the Maintainer can redact Ticket text';
  end if;

  update public.tickets
  set text = 'Text removed by the Maintainer',
    text_removal = 'maintainer'
  where id = p_ticket_id
  returning * into v_ticket;
  if not found then
    raise exception using errcode = 'P2834', message = 'Ticket not found';
  end if;
  return v_ticket;
end;
$$;

create function public.redact_ticket_thread_entry(p_entry_id uuid)
returns public.ticket_thread_entries
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare v_entry public.ticket_thread_entries%rowtype;
begin
  if not public.is_maintainer() then
    raise exception using errcode = '42501',
      message = 'Only the Maintainer can redact Ticket thread text';
  end if;

  update public.ticket_thread_entries
  set text = 'Text removed by the Maintainer',
    suggested_answer = null,
    text_removal = 'maintainer'
  where id = p_entry_id
  returning * into v_entry;
  if not found then
    raise exception using errcode = 'P2845',
      message = 'Ticket thread message not found';
  end if;
  return v_entry;
end;
$$;

revoke all on function public.redact_ticket_text(uuid),
  public.redact_ticket_thread_entry(uuid) from public;
grant execute on function public.redact_ticket_text(uuid),
  public.redact_ticket_thread_entry(uuid) to authenticated;

select cron.schedule(
  'erase-expired-ticket-text',
  '17 3 * * *',
  'select public.erase_expired_ticket_text()'
);
