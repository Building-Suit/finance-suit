# Database

Schema changes live in `supabase/migrations`.

The app does not create product tables, views, or RPCs in the default Supabase
schema. Module schemas are:

- `app_core`: `profiles`, `user_preferences`, backward-compatible onboarding
  RPCs
- `app_finance`: `accounts`, `transaction_categories`,
  `financial_transactions`, recurring `income_sources`, percentage
  `income_source_allocations`, approval-based `income_occurrences`, account
  balance views, and atomic transfer/income RPCs
- `app_work`: `official_holidays`, `work_entries`
- `app_salary`: `salary_settings`, `salary_adjustments`, `salary_periods`,
  salary payment RPC
- `app_reports`: read-only history/report views and RPCs
- `app_private`: trigger/helper functions that are not exposed to clients

Important derived objects:

- `app_finance.account_flows`
- `app_finance.account_balances`
- `app_reports.history_items`
- `app_reports.cash_flow_summary`
- `app_reports.finance_series`
- `app_reports.amounts_by_category`
- `app_reports.income_amounts_by_category`
- `app_reports.account_balance_history`
- `app_reports.work_summary`
- `app_reports.work_minutes_series`
- `app_reports.salary_comparison_report`
- `app_reports.salary_period_work_report`

All user-owned tables have RLS policies tied to `auth.uid()`.

`transaction_categories.parent_category_id` is nullable. Existing rows remain
top-level categories and transactions continue to reference the same
`category_id`; new children are restricted to one level, the same owner, and
the same category kind.

Recurring income is materialized as pending occurrences. Materialization alone
never creates a financial transaction. `accept_income_occurrence` atomically
creates the income transaction, percentage-based transfer allocations, and an
accepted decision. The primary account keeps the integer rounding remainder.
Salary occurrences additionally link the existing finalized salary period.
Existing configured salary users receive a backfilled automation source, and
salary settings stay synchronized with that source in both directions.
