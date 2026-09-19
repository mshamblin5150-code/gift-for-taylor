# ER Schedule

A phone-first Flutter web app for the ER Manager's monthly Schedule. It is a
progressive web app backed by Supabase and contains no patient data.

## Run the app

Install Flutter stable, Supabase CLI, and Docker Desktop. Then start the local
backend and run Flutter with the values printed by `supabase status`:

```powershell
supabase start
flutter run -d chrome `
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<local-publishable-key>
```

The production build uses the same two compile-time settings:

```powershell
flutter build web --release `
  --dart-define=SUPABASE_URL=<project-url> `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-key> `
  --dart-define=VAPID_PUBLIC_KEY=<public-vapid-key>
```

Deploy the contents of `build/web` over HTTPS. In Safari on iPhone, use Share,
then **Add to Home Screen**. The web manifest and Apple web-app metadata make the
installed app open in standalone mode.

## Web push

Create one VAPID key pair (`npx web-push generate-vapid-keys`) and keep its
private key out of source control. Build the app with the public key above.
Set the Edge Function secrets `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`,
`VAPID_SUBJECT` (a `mailto:` address), and `PUSH_WEBHOOK_SECRET` using
`supabase secrets set`, then deploy with `supabase functions deploy send-push`.
Use the same public key in the web build and Edge Function. Do not use a
localhost URL for `VAPID_SUBJECT`; Safari rejects it.
Deploy the updated Edge Function before applying new database migrations so
historical Request off notices move into the shared feed without new pushes.

In Supabase Dashboard, create a Database Webhook for **INSERT** on
`public.staff_notices`, targeting the `send-push` Edge Function. Add the HTTP
header `x-push-secret` with the exact value of `PUSH_WEBHOOK_SECRET`. The
function rejects requests without this header; `verify_jwt = false` is set
because database webhooks do not carry a Staff member's JWT. Keep the service
role key in Supabase's Edge Function environment, never in the web build.

Deploy the app over HTTPS with `push.js` and `push-service-worker.js` at the
same base path as the Flutter app. On iPhone iOS 16.4 or later, add it to the
Home Screen, open it from there, sign in, tap **Notices → Allow notifications**,
then wait for a Schedule event or Request off, Swap, or Open shift notice. Confirm
the device receives the push and the app shows the same notice. Turning
notifications off or signing out unsubscribes that device. A Month release
creates a notice for each active Staff member except the person who released it; a
post-release shift change creates one only for the affected Staff member when
the scheduler marks the text announcement sent.

## Calendar feed

Deploy the Calendar feed Edge Function alongside the database migrations:

```powershell
supabase functions deploy calendar-feed --no-verify-jwt
```

The function uses Supabase's `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`
environment values. Each signed-in Staff member opens **My Calendar feed**, creates
a link, and copies it into their phone calendar's subscription screen. The link
is shown only when created or reset; resetting invalidates the previous one.
Keep the link private because a calendar app reads it without signing in.

Supabase Flutter persists and refreshes the session in browser storage. The app
offers one emailed-code flow for accepting an Invite and signing in, and exposes
explicit sign-out. Before production use, create the Manager's `staff_members`,
`staff_accounts`, and current `staff_section_assignments` rows in the Supabase
dashboard; include the Manager's personal email on the account row. No Staff
names belong in source control.

## Load the first month

The current month is transcribed from photos of the printed book page and
loaded straight into production. Photos, transcripts, and the generated SQL hold
real staff names, so keep them only in the gitignored `private/` folder and never
paste them into an issue.

1. Transcribe the page into `private/first-month.csv`: a header row
   `Section,Name,Cell,1,2,…` through the last day of the month, then one row per
   person in page order. Section names must match the `sections` table exactly,
   and anyone already on the Staff list must be spelled exactly as they are
   there, or the load adds them a second time.
   `Cell` is the number their Invite is texted to. Staff enter their own email
   when they accept, so no email is needed. Leave a blank cell blank and write
   every Shift code as printed.
2. Turn it into one SQL statement:

   ```powershell
   cd packages/schedule_rules
   dart run bin/first_month_sql.dart 2026-10 ../../private/first-month.csv |
     Out-File -Encoding utf8 ../../private/first-month.sql
   ```

3. Paste `private/first-month.sql` into the Supabase dashboard SQL editor and run
   it. The load is all-or-nothing. It adds everyone not already on the Staff
   list (matched by exact name) to the bottom of their Section with their cell
   number. It sends no Invites; send each one from the Staff list with
   **Resend Invite**. Anyone left without a cell number shows "No cell number
   yet" and can't be invited until one is added. The load refuses a month that
   already exists.
4. The Manager opens that month in the app, checks it against her Excel file,
   taps any misread cell to correct it (each correction goes into the change
   log), and taps **Confirm month**. Confirming releases the month.

## Print the book page

On the office computer, open the month in the app and tap the printer icon.
The browser's print dialog shows only the book page, laid out like the printed
Schedule and sized to one landscape page. Choose the printer and print. The page
shows the live month, including changes not yet announced, with each person in
the Section they're in that month.

## Verify

```powershell
flutter analyze
flutter test
dart test packages/schedule_rules/test
supabase start
supabase test db
deno test supabase/functions/calendar-feed/index_test.ts
flutter build web --release
```

The schedule rules live behind the `ScheduleRules` interface in
`packages/schedule_rules`. Its in-memory database stand-in keeps domain behavior
tests independent of Flutter and the network. Database policy tests exercise a
real local Supabase/Postgres stack.

See [the version-one data model](docs/data-model-v1.md) for the full planned
schema and its staged rollout.
