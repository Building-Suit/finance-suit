# Implementation Checklist

State values: Not started, In progress, Completed, Blocked by external credential, Deferred with justification.

| Phase | State | Evidence |
| --- | --- | --- |
| Phase 1: Scaffold and foundations | Completed | Flutter app, routing shell, Riverpod, theme, localization, errors, money/date/validation utilities. |
| Phase 2: Supabase database | Completed | Migrations under `supabase/migrations`, RLS tests under `supabase/tests`. |
| Phase 3: Authentication | Completed | Supabase auth repository, login/register/reset/confirm screens, route guards, deep-link config. |
| Phase 4: Onboarding and settings | Completed | Onboarding RPC, profile/preferences/salary settings screens and providers. |
| Phase 5: Accounts and finance | Completed | Account management, transactions, allowances, income, transfers, derived balances, tests. |
| Phase 6: Work tracking | Completed | Calendar/list, work entries, overtime, extra day, holiday worked, holiday settings. |
| Phase 7: Salary | Completed | Calculation engine, period derivation, estimates, adjustments, finalization/payment flow, salary tests. |
| Phase 8: Dashboard, history and reports | Completed | Home dashboard, `/history`, `history_items`, server report RPCs, charts, tests. |
| Phase 9: Realtime and performance | Completed | Debounced user-scoped realtime invalidation and `seed_performance_sample`. |
| Phase 10: Final QA | Deferred with justification | Format, analyze, Flutter tests, and Supabase DB tests pass. Android build is blocked in this environment because no Android SDK is installed. |
| Selectable payment allocation | Completed | `20260825090000` migration (item-level statement allocations, `pay_credit_facility_v2`, `facility_due_breakdown`), Pay-screen checklist with Next installment / Minimum payment / Full outstanding presets, persistent Due Breakdown, payment Applied-to detail, pgTAP `0047`, Flutter unit/widget tests. |

## External-Credential Blockers

- Production Resend SMTP credentials: Blocked by external credential.
- Production Supabase project URL/anon key: Blocked by external credential.
- Apple/Google signing: Blocked by external credential.
- Android SDK in this execution environment: Deferred with justification.
