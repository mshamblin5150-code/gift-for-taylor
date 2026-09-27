-- A Repair may name the private Ticket that prompted it. The Manager-facing
-- surfaces carry only the fact that a Staff Ticket exists, never its contents
-- or sender.
alter table public.maintainer_repairs
  add column ticket_id uuid references public.tickets(id) on delete restrict;

drop function if exists public.current_access();

create function public.current_access()
returns table (
  manager boolean,
  administrator boolean,
  maintainer boolean,
  staff_member_id uuid,
  night_scheduler_section_ids uuid[],
  repair_id uuid,
  repair_reason_category public.maintainer_repair_reason_category,
  repair_detail text,
  repair_opened_at timestamptz,
  repair_expires_at timestamptz,
  repair_seconds_remaining double precision,
  repair_ticket_id uuid
)
language sql stable security definer set search_path = '' as $$
  select
    coalesce(public.current_staff_role() = 'manager', false),
    coalesce(member.role = 'administrator', false),
    public.is_maintainer(),
    member.id,
    coalesce((select array_agg(assignment.section_id order by assignment.section_id)
      from public.night_scheduler_sections assignment
      where assignment.staff_member_id = member.id), '{}'::uuid[]),
    repair.id,
    repair.reason_category,
    repair.detail,
    repair.opened_at,
    repair.expires_at,
    greatest(
      extract(epoch from repair.expires_at - statement_timestamp()), 0),
    (select linked.ticket_id
      from public.maintainer_repairs linked where linked.id = repair.id)
  from (select 1) singleton
  left join public.staff_accounts account on account.auth_user_id = auth.uid()
    and account.accepted_invite_at is not null and account.revoked_at is null
  left join public.staff_members member on member.id = account.staff_member_id
    and member.active
  left join lateral public.current_maintainer_repair() repair on true
$$;
revoke all on function public.current_access() from public;
grant execute on function public.current_access() to authenticated;

drop function public.open_maintainer_repair(
  public.maintainer_repair_reason_category, text);
create function public.open_maintainer_repair(
  p_reason_category public.maintainer_repair_reason_category,
  p_detail text default null,
  p_ticket_id uuid default null
)
returns setof public.maintainer_repairs
language plpgsql volatile security definer set search_path = '' as $$
declare v_detail text := nullif(trim(p_detail), '');
begin
  if not public.is_maintainer() then
    raise exception 'Only the Maintainer can open a Repair';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('maintainer-repair:' || auth.uid()::text, 0));
  if v_detail is not null and length(v_detail) not between 3 and 240 then
    raise exception 'Repair detail must be 3-240 characters';
  end if;
  if p_reason_category = 'something_else' and v_detail is null then
    raise exception 'Something else requires repair detail (3-240 characters)';
  end if;
  if p_ticket_id is not null
      and not exists (select 1 from public.tickets where id = p_ticket_id) then
    raise exception using errcode = 'P2845', message = 'Ticket not found';
  end if;

  update public.maintainer_repairs
  set closed_at = expires_at
  where auth_user_id = auth.uid() and closed_at is null
    and expires_at <= clock_timestamp();
  if private.active_maintainer_repair_id() is not null then
    raise exception 'Close the current Repair before opening another';
  end if;

  return query insert into public.maintainer_repairs(
      auth_user_id, reason_category, detail, ticket_id)
    values (auth.uid(), p_reason_category, v_detail, p_ticket_id)
    returning *;
end;
$$;
revoke all on function public.open_maintainer_repair(
  public.maintainer_repair_reason_category, text, uuid) from public;
grant execute on function public.open_maintainer_repair(
  public.maintainer_repair_reason_category, text, uuid) to authenticated;

create or replace function private.notice_maintainer_repair()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_manager_id uuid;
  v_actor_id uuid;
  v_category text;
  v_body text;
begin
  select member.id into v_manager_id
  from public.staff_members member
  where member.active and member.role = 'manager';

  select account.staff_member_id into v_actor_id
  from public.staff_accounts account
  where account.auth_user_id = new.auth_user_id
    and account.accepted_invite_at is not null
    and account.revoked_at is null;

  if v_manager_id is null or v_manager_id is not distinct from v_actor_id then
    return new;
  end if;

  v_category := private.maintainer_repair_category_label(new.reason_category);
  v_body := coalesce(new.detail, '');
  if new.ticket_id is not null then
    v_body := concat_ws(E'\n\n', nullif(v_body, ''),
      'This Repair was opened because of a Ticket from a Staff member.');
  end if;

  insert into public.staff_notices(
    staff_member_id, kind, title, body, push_eligible)
  values (v_manager_id, 'maintainer_repair', 'Repair: ' || v_category,
    v_body, false);
  return new;
end;
$$;
revoke all on function private.notice_maintainer_repair() from public;
