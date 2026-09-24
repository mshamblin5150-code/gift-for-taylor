-- 20260919220000_administrator_handover.sql is recorded in the hosted
-- schema_migrations but never ran there. Its functions survive only because
-- 20260921010000 replaced them; the two statements nothing later recreates
-- were simply lost. Manager handover died on the first of them with SQLSTATE
-- 23514, which carries no refusal code, so the page could only say "Try
-- again". Restore both, forward, from that migration.

-- Every access change logs this kind, not only handover: assign_administrator
-- and set_staff_access_grants do too. Re-assert the whole list rather than the
-- one missing member, so the statement is correct wherever else it drifted.
alter table public.staff_changes drop constraint if exists staff_changes_kind_check;
alter table public.staff_changes add constraint staff_changes_kind_check
  check (kind in ('last_day', 'reactivated', 'section', 'job_role',
    'name', 'cell_number', 'access_role'));

-- Without this the unit can lose its last active Manager: a Last day, a
-- deactivation or a delete on the Manager row all pass unguarded. It matters
-- most right after a handover, when there is exactly one.
create or replace function public.keep_active_manager()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.active and old.role = 'manager'
      and (tg_op = 'DELETE' or not new.active or new.role <> 'manager') then
    perform pg_advisory_xact_lock(810081);
    if not exists (
      select 1 from public.staff_members member
      where member.id <> old.id and member.active and member.role = 'manager'
    ) then
      raise exception 'The unit needs an active Manager';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function public.keep_active_manager() from public;
drop trigger if exists keep_active_manager on public.staff_members;
create trigger keep_active_manager before update or delete on public.staff_members
for each row execute function public.keep_active_manager();
