# Architecture

The app uses feature-first Flutter structure:

- `lib/core`: shared money/date/result/errors/validation/Supabase utilities.
- `lib/app`: routing, shell, theme, app bootstrap.
- `lib/features/auth`: Supabase auth flows.
- `lib/features/onboarding`: first-run profile, salary, account setup.
- `lib/features/finance`: accounts, categories, transactions, transfers.
- `lib/features/network`: Finance Suit Network — user search, add requests,
  private aliases, and pending cross-user transfers.
- `lib/features/work`: work entries and official holidays.
- `lib/features/salary`: settings, salary math, periods, payments.
- `lib/features/dashboard`: home dashboard.
- `lib/features/history`: unified business-date history.
- `lib/features/reports`: server-backed report aggregates and charts.

Repositories isolate Supabase calls. Widgets consume providers and do not build SQL queries directly. Salary formulas are pure domain code and are covered by unit tests.
