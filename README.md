# Finance Suit

Private Flutter application for personal salary estimation, work tracking, account balances, and cash-flow reporting.

## Current Status

As of 2026-07-10:

- Phases 1-7 are implemented in the Flutter/Supabase codebase.
- Phase 7 salary tests are present and passing.
- Phase 8 dashboard, unified history, server-backed reports, charts, and tests are implemented.
- Phase 9 realtime invalidation and local performance seed support are implemented.
- Final QA commands are documented in [docs/TESTING.md](docs/TESTING.md).

## Stack

- Flutter 3.41.6 / Dart 3.11.4
- Material 3
- Shared Suit visual language: navy/gold role tokens, Manrope, IBM Plex Sans
  Arabic, and free Hugeicons Stroke Rounded glyphs
- Riverpod
- go_router
- Supabase Auth, PostgreSQL, RLS, Realtime
- fl_chart

## Product Identity

Finance Suit is a standalone product with its own finance-ledger `F` mark. It
uses the shared Suit visual system as the finance portal in the Building Suit
product family. Its permanent Android application ID is
`com.buildingsuit.finance`.

## Google Play delivery

Google Play builds use signed Android App Bundles for smaller device-specific
downloads. The `test` branch delivers to Internal Testing, while version tags
on `main` are delivered to Production by an explicit manual workflow run. See
[docs/GOOGLE_PLAY_DELIVERY.md](docs/GOOGLE_PLAY_DELIVERY.md) for signing,
Play Console, service-account, and rollout setup.

## Local Setup

1. Copy `config/development.example.json` to a local untracked config file and fill Supabase URL and anon key.
2. Start Supabase locally with `supabase start`.
3. Apply migrations with `supabase migration up --local` or reset local dev data with `supabase db reset`.
4. Run Flutter with:

```bash
flutter run --dart-define-from-file=config/development.example.json
```

## Verification

```bash
flutter analyze
flutter test
supabase test db
flutter build apk --debug --dart-define-from-file=config/development.example.json
```

Production email delivery requires external Resend/Supabase SMTP setup. See [docs/RESEND_SETUP.md](docs/RESEND_SETUP.md).
