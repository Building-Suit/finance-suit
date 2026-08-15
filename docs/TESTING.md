# Testing

Flutter:

```bash
dart format lib test
flutter analyze
flutter test
```

Supabase:

```bash
supabase migration up --local
supabase test db
```

Build:

```bash
flutter build apk --debug --dart-define-from-file=config/development.example.json
```

On 2026-07-10 this build command was attempted with local Supabase dart-defines and was blocked because the environment has no Android SDK / `ANDROID_HOME`.

Current tested coverage includes money/date/validation, salary calculation, salary estimate snapshots, history model/query behavior, report model parsing, schema/RLS/business rules, phase 8 history/report SQL, credit-facility installment plans (schedule rounding, month-end dates, payment allocation, reversal, and liability guard rails in both Flutter and pgTAP), and the Finance Suit Network (connection lifecycle, directional alias privacy, pending/accepted/rejected transfer accounting, cross-user RLS isolation, and recurring/income-allocation network destinations in both Flutter and pgTAP), and installment responsibility linking (custom/network link lifecycle, consent snapshots and stale-terms blocking, responsibility start at the first unpaid due, reimbursement accounting that never touches the facility liability or income, per-due overpayment caps across reassignment, and three-user RLS isolation in both Flutter and pgTAP).
