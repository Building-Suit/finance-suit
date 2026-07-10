# Database

Schema changes live in `supabase/migrations`.

The app does not create product tables, views, or RPCs in the default Supabase
schema. Module schemas are:

- `app_core`: `profiles`, `user_preferences`, `complete_onboarding`
- `app_finance`: `accounts`, `transaction_categories`,
  `financial_transactions`, account balance views, transfer RPC
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
