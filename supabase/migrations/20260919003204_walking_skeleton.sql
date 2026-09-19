create type public.staff_role as enum (
  'manager',
  'administrator',
  'night_scheduler',
  'staff_member'
);

create type public.month_release_state as enum ('unpublished', 'released');

create table public.sections (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (length(trim(name)) > 0),
  display_order integer not null check (display_order >= 0),
  created_at timestamptz not null default now()
);

create table public.staff_members (
  id uuid primary key default gen_random_uuid(),
  display_name text not null check (length(trim(display_name)) > 0),
  cell_number text,
  role public.staff_role not null default 'staff_member',
  active boolean not null default true,
  last_day date,
  created_at timestamptz not null default now()
);

create table public.staff_accounts (
  staff_member_id uuid primary key references public.staff_members(id),
  auth_user_id uuid not null unique references auth.users(id) on delete cascade,
  accepted_invite_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table public.schedule_months (
  id uuid primary key default gen_random_uuid(),
  month_start date not null unique check (date_trunc('month', month_start)::date = month_start),
  release_state public.month_release_state not null default 'unpublished',
  released_at timestamptz,
  released_by_staff_member_id uuid references public.staff_members(id),
  created_at timestamptz not null default now(),
  check (
    (release_state = 'released') =
    (released_at is not null and released_by_staff_member_id is not null)
  )
);

create table public.schedule_cells (
  id uuid primary key default gen_random_uuid(),
  schedule_month_id uuid not null references public.schedule_months(id) on delete cascade,
  staff_member_id uuid not null references public.staff_members(id),
  section_id uuid not null references public.sections(id),
  work_date date not null,
  shift_code text not null default '',
  updated_at timestamptz not null default now(),
  unique (schedule_month_id, staff_member_id, work_date)
);

create function public.schedule_cell_date_matches_month()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.schedule_months month
    where month.id = new.schedule_month_id
      and new.work_date >= month.month_start
      and new.work_date < (month.month_start + interval '1 month')
  ) then
    raise exception 'Schedule cell date must belong to its Schedule month'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function public.schedule_cell_date_matches_month() from public;

create trigger schedule_cell_date_matches_month
before insert or update of schedule_month_id, work_date
on public.schedule_cells
for each row execute function public.schedule_cell_date_matches_month();

create function public.current_staff_role()
returns public.staff_role
language sql
stable
security definer
set search_path = ''
as $$
  select member.role
  from public.staff_accounts account
  join public.staff_members member on member.id = account.staff_member_id
  where account.auth_user_id = auth.uid()
    and member.active
    and account.accepted_invite_at is not null
$$;

create function public.is_active_staff_member()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.current_staff_role() is not null
$$;

revoke all on function public.current_staff_role() from public;
revoke all on function public.is_active_staff_member() from public;
grant execute on function public.current_staff_role() to anon, authenticated;
grant execute on function public.is_active_staff_member() to anon, authenticated;

alter table public.sections enable row level security;
alter table public.staff_members enable row level security;
alter table public.staff_accounts enable row level security;
alter table public.schedule_months enable row level security;
alter table public.schedule_cells enable row level security;

grant select on public.sections to anon, authenticated;
grant select on public.staff_members to anon, authenticated;
grant select on public.schedule_months to anon, authenticated;
grant select on public.schedule_cells to anon, authenticated;

create policy "active staff can read Sections"
on public.sections for select
using (public.is_active_staff_member());

create policy "active staff can read the Staff list"
on public.staff_members for select
using (public.is_active_staff_member());

create policy "schedulers can read every month; staff read released months"
on public.schedule_months for select
using (
  public.current_staff_role() in ('manager', 'administrator', 'night_scheduler')
  or (
    public.current_staff_role() = 'staff_member'
    and release_state = 'released'
  )
);

create policy "staff can read cells in visible months"
on public.schedule_cells for select
using (
  exists (
    select 1
    from public.schedule_months month
    where month.id = schedule_month_id
  )
);
