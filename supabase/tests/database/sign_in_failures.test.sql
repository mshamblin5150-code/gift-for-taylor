begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000003381', 'maintainer-338@example.test'),
  ('00000000-0000-0000-0000-000000003382', 'staff-338@example.test');
insert into private.maintainer_identity(auth_user_id)
values ('00000000-0000-0000-0000-000000003381');

set local role anon;
select lives_ok(
  $$select public.record_sign_in_failure(
    'unexpected_failure', '500', 'mail quota reached')$$,
  'a signed-out client can record the provider reply');
reset role;

select is((select count(*)::integer from private.sign_in_failures), 1,
  'one failed attempt is recorded');
select is((select error_code from private.sign_in_failures),
  'unexpected_failure', 'the provider code is retained');
select is((select status_code from private.sign_in_failures),
  '500', 'the provider status is retained');
select is((select error_message from private.sign_in_failures),
  'mail quota reached', 'the provider reply is retained');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003382","role":"authenticated"}',
  true);
select throws_ok($$select * from public.read_sign_in_failures()$$,
  '42501', 'Only the Maintainer can read sign-in failures',
  'ordinary Staff cannot read sign-in failures');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000003381","role":"authenticated"}',
  true);
select is((select count(*)::integer from public.read_sign_in_failures()), 1,
  'the Maintainer can read the failure without opening a Repair');
select is((select error_message from public.read_sign_in_failures()),
  'mail quota reached', 'the Maintainer sees the provider reply');

select * from finish();
rollback;
