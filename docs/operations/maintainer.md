# Maintainer account

The Maintainer is one Supabase Auth user bound by Auth user ID, not by email,
Staff Invite, or a `staff_members` row. The app has no control to create, revoke,
or replace this binding. A database operator with access to the private schema
performs these steps outside the app.

Per ADR-0020 the Maintainer is a hat, not a second account. The binding may
attach to an Auth user that also holds a Staff account, and here it does: the
designer is a nurse on this Schedule. Being on the Staff list is a property of
the Staff row and says nothing about Maintainer authority; wearing the hat puts
nobody on the Schedule.

## Provision

1. Use the designer's existing Auth user — the one their Staff login already
   uses. Record the Auth user ID. Do not create a second Auth user, and do not
   remove them from the Staff list.
2. As a database operator, bind that exact ID:

   ```sql
   insert into private.maintainer_identity (singleton, auth_user_id)
   values (true, '<auth-user-uuid>');
   ```

   The singleton key permits only one Maintainer.
3. Sign in and check that the ordinary app is unchanged — no Manager controls in
   the Schedule or Settings, because the hat is off until a Repair is open. Help
   shows **Maintainer repairs**.
4. Break the glass: open a Repair, choosing a reason and writing the detail.
   Manager views and actions become available, a banner names the Repair, and the
   Manager receives a Notice carrying the reason. Close the Repair and confirm
   Manager controls disappear again. An unclosed Repair lapses after an hour.

Repair records carry the Auth actor and the Repair id in
`maintainer_repair_audit` and, for Settings changes, `unit_setting_audit`.

## Recover or replace credentials

Use the administrative Auth recovery flow for the same Auth user ID when only
credentials have been lost. For a replacement Auth user ID, change the binding as
a database operator:

```sql
update private.maintainer_identity
set auth_user_id = '<replacement-auth-user-uuid>'
where singleton;
```

The old ID immediately loses Maintainer authorization, including with an
unexpired token, and any open Repair on it stops granting authority. Do not
retire that Auth user without checking whether it also carries a Staff account —
under ADR-0020 it usually will, and retiring it would take a nurse off the
Schedule along with the hat. Audit rows retain the actual Auth user ID that
performed each change. Neither Manager nor Administrator can perform these steps
with app credentials.
