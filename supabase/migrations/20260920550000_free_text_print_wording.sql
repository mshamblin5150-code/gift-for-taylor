-- Keep the wording of existing enum-backed rows exactly as printed before.
alter table public.print_wording
  add column tooltip text,
  add column title text,
  add column notice text;

update public.print_wording set
  tooltip = case tooltip_style
    when 'bookPage' then 'Print the book page'
    when 'schedule' then 'Print Schedule'
    when 'binder' then 'Print for the Schedule book'
  end,
  title = case title_style
    when 'hospital' then 'Welch Community Hospital - Emergency Room Schedule'
    when 'emergencyRoom' then 'Emergency Room Schedule'
    when 'er' then 'ER Schedule'
  end,
  notice = case notice_style
    when 'subjectToChange' then 'Schedule subject to change'
    when 'checkForChanges' then 'Check for Schedule changes'
    when 'none' then ''
  end;

alter table public.print_wording
  alter column tooltip set default 'Print the book page',
  alter column title set default 'Welch Community Hospital - Emergency Room Schedule',
  alter column notice set default 'Schedule subject to change',
  alter column tooltip set not null,
  alter column title set not null,
  alter column notice set not null,
  add constraint print_wording_tooltip_length check (length(trim(tooltip)) between 1 and 80),
  add constraint print_wording_title_length check (length(trim(title)) between 1 and 80),
  add constraint print_wording_notice_length check (length(notice) <= 80);

drop function public.set_print_wording(text, text, text);

alter table public.print_wording
  drop column tooltip_style,
  drop column title_style,
  drop column notice_style;

create function public.set_print_wording(
  p_tooltip text,
  p_title text,
  p_notice text
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
  set tooltip = p_tooltip,
      title = p_title,
      notice = p_notice
  where id = true;
end;
$$;

revoke all on function public.set_print_wording(text, text, text) from public;
grant execute on function public.set_print_wording(text, text, text) to authenticated;
