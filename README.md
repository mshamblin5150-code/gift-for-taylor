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
explicit sign-out. Before production use, create the Manager's `staff_members` and
`staff_accounts` rows in the Supabase dashboard; no Staff names belong in source
control.

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
