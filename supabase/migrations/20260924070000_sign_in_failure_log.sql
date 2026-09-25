create table private.sign_in_failures (
  id bigint generated always as identity primary key,
  happened_at timestamptz not null default statement_timestamp(),
  error_code text,
  status_code text,
  error_message text not null,
  constraint sign_in_failure_error_code_length
    check (error_code is null or char_length(error_code) <= 120),
  constraint sign_in_failure_status_code_length
    check (status_code is null or char_length(status_code) <= 16),
  constraint sign_in_failure_message_length
    check (char_length(error_message) between 1 and 1000)
);

alter table private.sign_in_failures enable row level security;
revoke all on private.sign_in_failures from public, anon, authenticated;

create function public.record_sign_in_failure(
  p_error_code text,
  p_status_code text,
  p_error_message text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from private.sign_in_failures
  where happened_at < statement_timestamp() - interval '30 days';

  insert into private.sign_in_failures(error_code, status_code, error_message)
  values (
    nullif(left(btrim(p_error_code), 120), ''),
    nullif(left(btrim(p_status_code), 16), ''),
    coalesce(nullif(left(btrim(p_error_message), 1000), ''),
      'Unknown provider failure')
  );
end;
$$;
revoke all on function public.record_sign_in_failure(text, text, text)
  from public;
grant execute on function public.record_sign_in_failure(text, text, text)
  to anon, authenticated;

create function public.read_sign_in_failures()
returns table (
  happened_at timestamptz,
  error_code text,
  status_code text,
  error_message text
)
language plpgsql
security definer
stable
set search_path = ''
as $$
begin
  if not public.is_maintainer() then
    raise exception 'Only the Maintainer can read sign-in failures'
      using errcode = '42501';
  end if;

  return query
  select failure.happened_at, failure.error_code, failure.status_code,
    failure.error_message
  from private.sign_in_failures failure
  where failure.happened_at >= statement_timestamp() - interval '30 days'
  order by failure.happened_at desc
  limit 100;
end;
$$;
revoke all on function public.read_sign_in_failures() from public;
grant execute on function public.read_sign_in_failures() to authenticated;
