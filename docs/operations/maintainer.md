# Maintainer account

The Maintainer is one Supabase Auth user bound by Auth user ID, not by email,
Staff Invite, or a `staff_members` row. The app has no control to create, revoke,
or replace this binding. A database operator with access to the private schema
performs these steps outside the app.

## Provision

1. Create the designer's Auth user with the project's administrative Auth tools.
   Verify that the user can sign in and record the Auth user ID. Do not add the
   person to the Staff list or send a Staff Invite.
2. As a database operator, bind that exact ID:

   ```sql
   insert into private.maintainer_identity (singleton, auth_user_id)
   values (true, '<auth-user-uuid>');
   ```

   The singleton key permits only one Maintainer. The database rejects a user
   already linked to a Staff account and rejects later Staff account links.
3. Sign in as the Maintainer and check that Help shows **Maintainer repairs** and
   the Schedule and Settings show Manager controls. A Unit change asks for a
   3–240 character repair reason and stores it with the Auth actor in
   `maintainer_repair_audit` and, for Settings changes, `unit_setting_audit`.

## Recover or replace credentials

Use the administrative Auth recovery flow for the same Auth user ID when only
credentials have been lost. For a replacement Auth user ID, verify the new user
is not Staff-linked, then change the binding as a database operator:

```sql
update private.maintainer_identity
set auth_user_id = '<replacement-auth-user-uuid>'
where singleton;
```

The old ID immediately loses Maintainer authorization, including with an
unexpired token. Revoke old sessions through the administrative Auth tools and
retire that Auth user after checking its historical audit references. Audit rows
retain the actual Auth user ID that performed each change. Neither Manager nor
Administrator can perform these steps with app credentials.
