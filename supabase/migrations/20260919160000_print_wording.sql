-- One setting for the unit, independent of any Schedule month.
create table public.print_wording (
  id boolean primary key default true check (id),
  tooltip_style text not null default 'bookPage'
    check (tooltip_style in ('bookPage', 'schedule', 'binder')),
  title_style text not null default 'hospital'
    check (title_style in ('hospital', 'emergencyRoom', 'er')),
  notice_style text not null default 'subjectToChange'
    check (notice_style in ('subjectToChange', 'checkForChanges', 'none'))
);

insert into public.print_wording (id) values (true);

alter table public.print_wording enable row level security;
grant select on public.print_wording to authenticated;
create policy "staff can read print wording"
on public.print_wording for select
using (public.is_active_staff_member());

create function public.set_print_wording(
  p_tooltip_style text,
  p_title_style text,
  p_notice_style text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public.current_staff_role() is distinct from 'manager'::public.staff_role then
    raise exception 'Only the Manager can change print wording';
  end if;

  update public.print_wording
  set tooltip_style = p_tooltip_style,
      title_style = p_title_style,
      notice_style = p_notice_style
  where id = true;
end;
$$;

revoke all on function public.set_print_wording(text, text, text) from public;
grant execute on function public.set_print_wording(text, text, text) to authenticated;
