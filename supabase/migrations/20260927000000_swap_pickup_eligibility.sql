-- A receiver may take a shift only when their effective-dated Job role matches
-- the giver's (with RN/LPN interchangeable) and they have a Section that day.
-- Day conflicts remain the caller's responsibility because a Swap may offer
-- the receiver's existing cell as part of the same exchange.
create function public.can_take_shift(
  p_from_staff_member_id uuid,
  p_to_staff_member_id uuid,
  p_work_date date
)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.staff_job_roles from_role
    join public.staff_job_roles to_role on true
    where from_role.staff_member_id = p_from_staff_member_id
      and from_role.effective_from <= p_work_date
      and (from_role.effective_through is null
        or from_role.effective_through >= p_work_date)
      and to_role.staff_member_id = p_to_staff_member_id
      and to_role.effective_from <= p_work_date
      and (to_role.effective_through is null
        or to_role.effective_through >= p_work_date)
      and (to_role.job_role = from_role.job_role
        or (to_role.job_role in ('rn', 'lpn')
          and from_role.job_role in ('rn', 'lpn')))
  ) and exists (
    select 1 from public.staff_section_assignments assignment
    where assignment.staff_member_id = p_to_staff_member_id
      and assignment.effective_from <= p_work_date
      and (assignment.effective_through is null
        or assignment.effective_through >= p_work_date)
  );
$$;
revoke all on function public.can_take_shift(uuid, uuid, date) from public;

-- The Swap dialog asks SQL which candidate days pass the pickup rule. The
-- signed-in requester must be one of the two people being compared.
create function public.eligible_swap_dates(
  p_from_staff_member_id uuid,
  p_to_staff_member_id uuid,
  p_dates date[]
)
returns date[] language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(day order by day), array[]::date[])
  from unnest(p_dates) day
  where public.current_staff_member_id() in (
      p_from_staff_member_id, p_to_staff_member_id)
    and coalesce(cardinality(p_dates), 0) between 1 and 31
    and public.can_take_shift(
      p_from_staff_member_id, p_to_staff_member_id, day
    );
$$;
revoke all on function public.eligible_swap_dates(uuid, uuid, date[])
  from public;
grant execute on function public.eligible_swap_dates(uuid, uuid, date[])
  to authenticated;

create function public.validate_swap_shift_eligibility()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_swap public.swaps%rowtype;
  v_from uuid;
  v_to uuid;
begin
  select * into v_swap from public.swaps where id = new.swap_id;
  v_from := case new.side
    when 'requester' then v_swap.requester_id else v_swap.colleague_id end;
  v_to := case new.side
    when 'requester' then v_swap.colleague_id else v_swap.requester_id end;
  if not public.can_take_shift(v_from, v_to, new.work_date) then
    raise exception using errcode = 'P2831',
      message = format(
        'A Staff member cannot work the offered shift on %s', new.work_date
      );
  end if;
  return new;
end;
$$;
create trigger validate_swap_shift_eligibility
before insert on public.swap_shifts
for each row execute function public.validate_swap_shift_eligibility();
revoke all on function public.validate_swap_shift_eligibility() from public;

create function public.recheck_swap_eligibility_before_approval()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'approved' and old.status = 'accepted' and exists (
    select 1 from public.swap_shifts shift
    where shift.swap_id = new.id
      and not public.can_take_shift(
        case shift.side when 'requester' then new.requester_id
          else new.colleague_id end,
        case shift.side when 'requester' then new.colleague_id
          else new.requester_id end,
        shift.work_date
      )
  ) then
    raise exception using errcode = 'P2831',
      message = 'A Staff member can no longer work one of the offered shifts';
  end if;
  return new;
end;
$$;
create trigger recheck_swap_eligibility_before_approval
before update of status on public.swaps
for each row execute function public.recheck_swap_eligibility_before_approval();
revoke all on function public.recheck_swap_eligibility_before_approval()
  from public;

create or replace function public.giveaway_colleague_eligible(
  p_giver_id uuid, p_colleague_id uuid, p_work_date date
)
returns boolean language sql stable security definer set search_path = '' as $$
  select p_colleague_id is distinct from p_giver_id
    and exists (
      select 1 from public.staff_members member
      join public.staff_accounts account
        on account.staff_member_id = member.id
      where member.id = p_colleague_id and member.active
        and account.accepted_invite_at is not null
        and account.revoked_at is null
    )
    and public.can_take_shift(p_giver_id, p_colleague_id, p_work_date)
    and not public.staff_member_has_day_conflict(
      p_colleague_id, p_work_date
    );
$$;
