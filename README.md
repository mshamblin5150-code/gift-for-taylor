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

## Deploying

Pushing to `main`, or running the workflow by hand, deploys the `send-push`,
`calendar-feed`, and `send-calendar-invitation` Edge Functions, applies pending migrations to the hosted
project, and then publishes the web app to GitHub Pages. `send-push` deploys
first so migrations that insert historical Notices cannot trigger pushes to
Staff phones. The app only goes live once deployment and migration succeed.

After a migration run, and once each night, the `schema-drift` job compares
table triggers and constraints in the hosted `public` and `private` schemas
with a fresh local database built from the migrations. Drift fails that
monitoring job and opens or updates one `Hosted schema drift detected` issue;
it does not block the Pages deployment. Deliberate hosted-only objects must be
listed with a reason in `scripts/schema_drift_allowlist.json`. The database
webhook trigger `send_push_on_notice` is the only current exception.

The three compile-time values above are repository *variables*
(`SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `VAPID_PUBLIC_KEY`), since they
ship inside the web app. Set `SUPABASE_PROJECT_REF` as a repository variable
to the project ref in `SUPABASE_URL`. The workflow also needs two repository
*secrets*: `SUPABASE_ACCESS_TOKEN` for named Edge Function deployment and
`SUPABASE_DB_URL` for migrations. The latter is the project's **session pooler**
connection string, from Connect in the Supabase dashboard.

It must be the pooler URL, not the direct one. `db.<ref>.supabase.co` publishes
an AAAA record and no A record, and GitHub's runners are IPv4-only. Percent-
encode the password if it contains `@ / ? # [ ] %` or a space.

Migrations use the connection string, which reaches only this database. The
access token is supplied only to the Edge Function steps. It is never used for
`supabase config push`.

A superseded run queues rather than cancelling, so a second push cannot
interrupt a migration midway.

Only the three named Edge Functions and migrations are applied. Never run
`supabase config push` against the project: it writes `config.toml` over the
hosted settings, Auth included.

To apply migrations by hand, or to see what is outstanding:

```powershell
supabase link --project-ref <project-ref>
supabase migration list --linked
supabase db push --linked
```

## Web push

Create one VAPID key pair (`npx web-push generate-vapid-keys`) and keep its
private key out of source control. Build the app with the public key above.
Set the Edge Function secrets `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`,
`VAPID_SUBJECT` (a `mailto:` address), and `PUSH_WEBHOOK_SECRET` using
`supabase secrets set`. CI deploys `send-push` before migrations.
Use the same public key in the web build and Edge Function. Do not use a
localhost URL for `VAPID_SUBJECT`; Safari rejects it.
That order lets historical Request off notices move into the shared feed
without new pushes.

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

## Calendar invitations and feed

Calendar invitations are the default for active Staff members with a personal
email. A Month release sends one message per Staff member, carrying one
`VEVENT` per working shift. Subsequent Schedule changes queue a separate
`REQUEST` or a `CANCEL` for the changed shift. The
`calendar_invitation_outbox` retains each sequence and delivery state. The
delivery function sends iMIP mail using the same Resend SMTP provider as Auth.
Set `RESEND_SMTP_PASSWORD` to a Resend API key allowed to send from the verified
`axion.healthcare` domain, and set a random `CALENDAR_WEBHOOK_SECRET`, using
`supabase secrets set`. The sender is `no-reply@axion.healthcare`; Staff can save
its contact card from **My calendar**.

Store the same `CALENDAR_WEBHOOK_SECRET` value in database Vault under the name
`calendar_webhook_secret`. The installed database triggers call the function
once per Month release batch and once for each later single-shift row; do not
create a second Dashboard webhook. The function rejects requests without this
header and accepts the batch or row `id` in the webhook body. It atomically
claims only that delivery before sending, so concurrent calls cannot deliver it
twice and no call can drain unrelated rows. A five-minute scheduled sweep
retries only known failures or stale claims that never reached SMTP, capped at
three total attempts.
An uncertain send is held for investigation instead of risking duplicate mail.
The trigger URL points at the production Supabase project; change it for another
project.
The Maintainer can open an investigation Repair and read **Undelivered
invitations** in Settings without database or dashboard access. Each entry shows
the Staff member, shift, attempt count, failure time, SMTP status and provider
reply. Monitor the `retry-calendar-invitation-deliveries` Cron job separately;
later invitations never retry old rows.
The webhook and SMTP secret must be configured before Staff can receive mail.

Staff can switch to the Calendar feed in **My calendar**. Switching queues
`CANCEL` for their invitations and creates a private feed link. Switching back
revokes every subscription link and queues current working shifts as
invitations. Use only the `webcal://` link shown in the app when subscribing.

### Calendar feed

CI deploys the Calendar feed Edge Function alongside the database migrations.
To deploy it by hand:

```powershell
supabase functions deploy calendar-feed --no-verify-jwt
```

The function uses Supabase's `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`
environment values. Each signed-in Staff member opens **My calendar** and
creates a named link for each place they subscribe, such as iPhone or Google.
The page shows when each subscription last checked in and can revoke it without
affecting the others. The page detects the platform and shows one setup path,
with a way to choose another device. Android Staff members must sign in on a
computer and add the HTTPS URL through Google Calendar's **From URL** screen;
the Android app cannot add a subscription. The page offers a `webcal://`
subscription action and a copyable HTTPS URL for apps that require pasting,
such as new Outlook. Opening an HTTPS ICS URL in a browser can import a static
copy rather than subscribe. The hosted Supabase feed host redirects HTTP to
HTTPS with a 301. Keep links private because calendar apps read them without
signing in.

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
4. The Manager opens that month in the app and proofreads it against the printed
   Schedule page it was transcribed from, taps any misread cell to correct it
   (each correction goes into the change log), and taps **Confirm month**.
   Confirming releases the month.

## Print the book page

On a phone or office computer, open the month in the app and tap the printer icon.
On a phone, tap **Open printable page**, then **Print this page** in the new tab
or use the browser's Print option. On a computer, the print dialog opens directly.
The print preview shows only the book page, laid out like the printed Schedule
and fitted to one page. It requests landscape, but also fits when a phone's
print dialog uses portrait. Choose the printer and print. The page
shows the live month, including changes not yet announced, with each person in
the Section they're in that month. For a very large Staff list, the app warns
that one-page printing will make the text small.

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

Client Schedule logic lives in `packages/schedule_rules`; plain reads and writes
use the store interfaces directly. The `packages/schedule_rules_testing` package
provides in-memory stores for Dart and widget tests. Database policy tests
exercise a real local Supabase/Postgres stack.

See [the version-one data model](docs/data-model-v1.md) for the full planned
schema and its staged rollout.
