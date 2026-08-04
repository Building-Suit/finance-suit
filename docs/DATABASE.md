# Database

Schema changes live in `supabase/migrations`.

The app does not create product tables, views, or RPCs in the default Supabase
schema. Module schemas are:

- `app_core`: `profiles`, `user_preferences`, backward-compatible onboarding
  RPCs
- `app_finance`: `accounts`, `transaction_categories`,
  `financial_transactions`, recurring `income_sources`, percentage
  `income_source_allocations`, approval-based `income_occurrences`,
  liability `credit_facility_settings`, `installment_plans`,
  `installment_dues`, `installment_payment_allocations`, account
  balance views, and atomic transfer/income/facility RPCs
- `app_work`: `official_holidays`, `work_entries`
- `app_salary`: `salary_settings`, `salary_adjustments`, `salary_periods`,
  salary payment RPC
- `app_reports`: read-only history/report views and RPCs
- `app_private`: trigger/helper functions that are not exposed to clients

Important derived objects:

- `app_finance.account_flows`
- `app_finance.account_balances`
- `app_finance.credit_facility_summaries`
- `app_finance.installment_plan_summaries`
- `app_finance.installment_due_statuses`
- `app_reports.history_items`
- `app_reports.debt_summary`
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

Credit cards and BNPL providers are liability accounts
(`app_finance.account_role`). Outstanding debt is positive:
`opening_balance_minor` (opening amount owed) plus charges minus
repayments. A financed purchase books one expense transaction from the
facility on the purchase date (plus an optional asset-account down
payment); the monthly `installment_dues` rows are schedule entries, never
transactions, so expenses are counted exactly once. Repayments are
transfers created by `pay_credit_facility`, which also allocates them to
the oldest unpaid dues; direct client writes on facility-linked ledger
rows are blocked by triggers and only the facility RPCs
(`save_credit_facility`, `create_installment_plan`, `pay_credit_facility`,
`reverse_facility_payment`, `cancel_installment_plan`) mutate them.

Recurring income is materialized as pending occurrences. Materialization alone
never creates a financial transaction. `accept_income_occurrence` atomically
creates the income transaction, percentage-based transfer allocations, and an
accepted decision. The primary account keeps the integer rounding remainder.
Salary occurrences additionally link the existing finalized salary period.
Existing configured salary users receive a backfilled automation source, and
salary settings stay synchronized with that source in both directions.
