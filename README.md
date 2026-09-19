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
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-key>
```

Deploy the contents of `build/web` over HTTPS. In Safari on iPhone, use Share,
then **Add to Home Screen**. The web manifest and Apple web-app metadata make the
installed app open in standalone mode.

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
   person in page order. Section names must match the `sections` table exactly.
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

## Verify

```powershell
flutter analyze
flutter test
dart test packages/schedule_rules/test
supabase start
supabase test db
flutter build web --release
```

The schedule rules live behind the `ScheduleRules` interface in
`packages/schedule_rules`. Its in-memory database stand-in keeps domain behavior
tests independent of Flutter and the network. Database policy tests exercise a
real local Supabase/Postgres stack.

See [the version-one data model](docs/data-model-v1.md) for the full planned
schema and its staged rollout.
