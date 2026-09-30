create or replace function public.open_maintainer_repair(
  p_reason_category public.maintainer_repair_reason_category,
  p_detail text default null,
  p_ticket_id uuid default null
)
returns setof public.maintainer_repairs
language plpgsql volatile security definer set search_path = '' as $$
declare v_detail text := nullif(trim(p_detail), '');
begin
  if not public.is_maintainer() then
    raise exception using errcode = '42501',
      message = 'Only the Maintainer can open a Repair';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('maintainer-repair:' || auth.uid()::text, 0));
  if v_detail is not null and length(v_detail) not between 3 and 240 then
    raise exception using errcode = 'P2851',
      message = 'Repair detail must be 3-240 characters';
  end if;
  if p_reason_category = 'something_else' and v_detail is null then
    raise exception using errcode = 'P2851',
      message = 'Something else requires repair detail (3-240 characters)';
  end if;
  if p_ticket_id is not null
      and not exists (select 1 from public.tickets where id = p_ticket_id) then
    raise exception using errcode = 'P2834', message = 'Ticket not found';
  end if;

  update public.maintainer_repairs
  set closed_at = expires_at
  where auth_user_id = auth.uid() and closed_at is null
    and expires_at <= clock_timestamp();
  if private.active_maintainer_repair_id() is not null then
    raise exception using errcode = 'P2850',
      message = 'Close the current Repair before opening another';
  end if;

  return query insert into public.maintainer_repairs(
      auth_user_id, reason_category, detail, ticket_id)
    values (auth.uid(), p_reason_category, v_detail, p_ticket_id)
    returning *;
end;
$$;

create or replace function public.close_maintainer_repair(
  p_repair_id uuid default null
)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if not public.is_maintainer() then
    raise exception using errcode = '42501',
      message = 'Only the Maintainer can close a Repair';
  end if;
  update public.maintainer_repairs
  set closed_at = least(clock_timestamp(), expires_at)
  where id = coalesce(p_repair_id, (
      select repair.id from public.maintainer_repairs repair
      where repair.auth_user_id = auth.uid() and repair.closed_at is null
      order by repair.opened_at desc limit 1))
    and auth_user_id = auth.uid() and closed_at is null;
end;
$$;
