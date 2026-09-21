-- Coverage configuration and one-date overrides join the Settings home audit.
-- Weekday rules already write that audit through audit_weekday_minimum.
create function public.audit_coverage_rule_for_unit()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_actor_name text;
begin
  if new.action = 'weekday_minimum' then return new; end if;
  select display_name into v_actor_name from public.staff_members
    where id = new.actor;
  insert into public.unit_setting_audit(kind, actor_id, actor_name,
    changed_at, before_value, after_value)
  values (case new.action
      when 'coverage_pools' then 'Coverage pools'
      when 'date_minimum' then 'Date Staffing minimum'
      else 'Coverage rule'
    end,
    new.actor, coalesce(v_actor_name, 'Staff member'), new.changed_at,
    coalesce(new.before_value, '{}'::jsonb) ||
      jsonb_build_object('effective_from', new.effective_from),
    coalesce(new.after_value, '{}'::jsonb) ||
      jsonb_build_object('effective_from', new.effective_from));
  return new;
end;
$$;
revoke all on function public.audit_coverage_rule_for_unit() from public;
create trigger audit_coverage_rule_for_unit
  after insert on public.coverage_rule_audit for each row
  execute function public.audit_coverage_rule_for_unit();

insert into public.unit_setting_audit(kind, actor_id, actor_name,
  changed_at, before_value, after_value)
select case audit.action
    when 'coverage_pools' then 'Coverage pools'
    when 'date_minimum' then 'Date Staffing minimum'
    else 'Coverage rule'
  end,
  audit.actor, member.display_name, audit.changed_at,
  coalesce(audit.before_value, '{}'::jsonb) ||
    jsonb_build_object('effective_from', audit.effective_from),
  coalesce(audit.after_value, '{}'::jsonb) ||
    jsonb_build_object('effective_from', audit.effective_from)
from public.coverage_rule_audit audit
join public.staff_members member on member.id = audit.actor
where audit.action <> 'weekday_minimum';
