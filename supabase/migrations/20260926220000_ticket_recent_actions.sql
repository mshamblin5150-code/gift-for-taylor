alter table public.tickets
  add column recent_actions text[] not null
    default array['Recent actions were not recorded'],
  add column refusal_code text,
  add constraint ticket_recent_actions_small check (
    cardinality(recent_actions) between 1 and 8
    and array_position(recent_actions, null) is null
    and char_length(recent_actions::text) <= 1600
  ),
  add constraint ticket_refusal_code_stable check (
    refusal_code is null or refusal_code ~ '^P[0-9]{4}$'
  );

alter table public.tickets alter column recent_actions drop default;

grant select (recent_actions, refusal_code)
on public.tickets to authenticated;

drop function public.put_in_ticket(
  public.ticket_kind, text, text, date, text, text, timestamptz
);

create function public.put_in_ticket(
  p_kind public.ticket_kind,
  p_text text,
  p_screen_context text,
  p_schedule_month date,
  p_release_id text,
  p_device_context text,
  p_context_captured_at timestamptz,
  p_recent_actions text[],
  p_refusal_code text
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
      or p_recent_actions is null
      or cardinality(p_recent_actions) not between 1 and 8
      or array_position(p_recent_actions, null) is not null
      or char_length(p_recent_actions::text) > 1600
      or (p_refusal_code is not null
        and p_refusal_code !~ '^P[0-9]{4}$')
      or (p_schedule_month is not null
        and p_schedule_month <> date_trunc('month', p_schedule_month)::date) then
    raise exception using errcode = 'P2833',
      message = 'Ticket context is incomplete';
  end if;

  select display_name into strict v_sender_name
  from public.staff_members where id = v_sender_id;

  insert into public.tickets(
    sender_id, sender_display_name, kind, text, screen_context,
    schedule_month, release_id, device_context, context_captured_at,
    recent_actions, refusal_code
  ) values (
    v_sender_id, v_sender_name, p_kind, trim(p_text),
    trim(p_screen_context), p_schedule_month, trim(p_release_id),
    trim(p_device_context), p_context_captured_at,
    p_recent_actions, p_refusal_code
  ) returning id into v_ticket_id;
  return v_ticket_id;
end;
$$;

revoke all on function public.put_in_ticket(
  public.ticket_kind, text, text, date, text, text, timestamptz, text[], text
) from public;
grant execute on function public.put_in_ticket(
  public.ticket_kind, text, text, date, text, text, timestamptz, text[], text
) to authenticated;

-- Keep callers from earlier Ticket migrations working while they adopt the
-- richer context contract. New app code always uses the overload above.
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
language sql
volatile
security definer
set search_path = ''
as $$
  select public.put_in_ticket(
    p_kind,
    p_text,
    p_screen_context,
    p_schedule_month,
    p_release_id,
    p_device_context,
    p_context_captured_at,
    array['Recent actions were not recorded'],
    null
  )
$$;

revoke all on function public.put_in_ticket(
  public.ticket_kind, text, text, date, text, text, timestamptz
) from public;
grant execute on function public.put_in_ticket(
  public.ticket_kind, text, text, date, text, text, timestamptz
) to authenticated;
