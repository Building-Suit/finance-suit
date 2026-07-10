# Repository Rules

## Required Checks

Before declaring a phase complete, run:

- `dart format lib test`
- `flutter analyze`
- `flutter test`
- `supabase test db` when the local Supabase database is running
- `flutter build apk --debug --dart-define-from-file=config/development.example.json` when local config exists

## Boundaries

- Widgets must not construct raw SQL or contain salary formulas.
- Supabase access belongs in repositories.
- Salary math belongs in pure domain classes.
- Money is always integer minor units; do not use `double` as authoritative money.
- Business dates use `PlainDate`; do not display `created_at` as transaction or work date.
- RLS is mandatory for all private data tables.
- Do not place service-role keys, SMTP credentials, Resend keys, database passwords, or signing secrets in the client.
- Schema changes must be version-controlled Supabase migrations.
- Do not make dashboard-only production changes outside migrations.
- Completed features must not contain placeholder UI.
