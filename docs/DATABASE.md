# Database

Schema changes live in `supabase/migrations`.

The app does not create product tables, views, or RPCs in the default Supabase
schema. Module schemas are:

- `app_core`: `profiles`, `user_preferences`, backward-compatible onboarding
  RPCs, plus push infrastructure: `push_devices`,
  `notification_preferences`, and the service-role-only
  `notification_outbox` delivery log
- `app_finance`: `accounts`, `transaction_categories`,
  `financial_transactions`, recurring `income_sources`, percentage
  `income_source_allocations`, approval-based `income_occurrences`,
  liability `credit_facility_settings`, `installment_plans`,
  `installment_dues`, `installment_payment_allocations`,
  `installment_plan_revisions`, credit-card statement tables
  (`credit_card_statement_cycles`, `credit_card_statement_items`,
  `credit_card_statement_allocations`), fee rules
  (`credit_card_fee_rules`, `credit_card_fee_charges`), account
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
- `app_finance.credit_card_statement_summaries`
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
(`app_finance.account_role`). Outstanding debt is positive: legacy
`opening_balance_minor` plus charges minus repayments — the create/edit
flows no longer take an opening amount owed, but previously stored values
keep counting. A financed purchase books one expense transaction from the
facility on the purchase date (plus an optional asset-account down
payment and optional cash upfront fees); the monthly `installment_dues`
rows are schedule entries, never transactions, so expenses are counted
exactly once. Imported running plans mark their pre-tracking dues
`is_presettled` and only book the remaining amount. Ordinary card
spending goes through `charge_credit_card`: one expense assigned to the
statement cycle of its business date (`statement_day` is the cycle
CLOSING day; the cycle's payment falls due on the next
`default_due_day`). Recurring card fees are `credit_card_fee_rules`
(managed from the card's detail screen) materialized idempotently by
`apply_credit_card_fees`; the client runs the generator every time the
facility list loads, so due fees book themselves without any scheduler.
Repayments are
transfers created by `pay_credit_facility`, which settles statement dues
and installment dues together (oldest first, statements before
installments on the same day); direct client writes on facility-linked
ledger rows are blocked by triggers and only the facility RPCs
(`save_credit_facility`, `delete_credit_facility`,
`set_credit_facility_status`, `charge_credit_card`,
`apply_credit_card_fees`, `create_installment_plan`,
`update_installment_plan`, `restructure_installment_plan`,
`pay_credit_facility`, `reverse_facility_payment`,
`cancel_installment_plan`) mutate them.

Partial income acceptance: when less money arrives than was owed,
`accept_income_occurrence_partial` books the received part like a normal
acceptance (salary period and splits run on what arrived) and spawns a
linked pending *remainder occurrence*
(`income_occurrences.remainder_of_occurrence_id`) for the shortfall.
The remainder keeps showing as pending income until it is accepted or
skipped to write it off. The schedule uniqueness key applies only to
materialized rows, so remainders never collide with the monthly schedule.

Salaries accepted before partial acceptance existed recorded only what
arrived, so the shortfall left no trace. A one-time
`app_private.backfill_untracked_salary_shortfalls` gives those
acceptances the remainder they would get today — idempotent, salary
sources only, and bounded to the last 62 days so old history is never
reopened.

A salary shortfall is charged to the extra-work pay first.
`accept_income_occurrence` compares what arrived with the finalized
period snapshot (`total_minor`): the missing amount is subtracted from
the period's extra-day, overtime, and holiday pay before anything routes
to `extra_work_destination_account_id`, and only what the extra work
cannot absorb comes off the base salary — the percentage splits still run
on everything received. Accepting the remainder carries the extra-work
pay that was withheld (the chain of remainders is walked to see what it
already routed) and re-applies percentage rules to what is left, while
fixed splits stay once per payment. A partial acceptance plus its
remainder therefore land exactly where one full payment would have.

Accounts carry a `hide_from_home` flag (exposed through
`account_balances`): the Home tab's balance summary skips hidden accounts
while everything else — the Money tab, pickers, transfers, and reports —
keeps treating them normally.

Recurring automation covers every entry kind, not only income:
`recurring_rules` (expense from cash or a credit card, or transfer;
weekly/monthly/quarterly/annual schedules) materialize into
`recurring_occurrences` on read via `materialize_recurring_occurrences`,
idempotent per `(rule_id, scheduled_on)`. Nothing posts silently:
`accept_recurring_occurrence` books the entry through the same paths as
manual ones (plain expense, `charge_credit_card`, or `create_transfer`),
and `skip_recurring_occurrence` / `snooze_recurring_occurrence` mirror
the income decision flow. Categories are hard-deletable through
`delete_transaction_category` only while nothing references them
(transactions, subcategories, plans, fee rules, held amounts, macro
items, income sources, recurring rules); anything in use archives
instead.

Plan progress is displayed bank-style: every payment splits pro rata into
the item's principal share (a fully paid installment credits exactly
`financed_principal / count`) and the bank's interest-and-fees share,
which is shown on its own line and never counts toward the item. The
ledger is unchanged — `total_payable` is genuinely owed — this is purely
how progress is attributed.

Facility lifecycle: `facility_status` (`active`/`frozen`/`closed`) gates
new purchases only; archiving the account hides it from pickers while any
remaining debt stays visible and payable, and `delete_credit_facility`
hard-deletes only a facility with zero history. Plans with no recorded
payments can be fully edited in place (`update_installment_plan`); once
money moved, `restructure_installment_plan` re-spreads only the unpaid
remainder, bumps `revision`, and records an `installment_plan_revisions`
audit row (extra recognized cost books an explicit adjustment expense).

Push notifications: devices register their FCM token in
`app_core.push_devices` (owner RLS); `app_core.notification_preferences`
holds per-user switches with amounts hidden by default; the
`send-due-reminders` Edge Function writes `app_core.notification_outbox`
(select-only for clients) whose unique key makes each reminder
exactly-once per device, obligation, kind, and local date. See
`docs/NOTIFICATIONS_FCM.md` for the activation guide.

Recurring income is materialized as pending occurrences. Materialization alone
never creates a financial transaction. `accept_income_occurrence` atomically
creates the income transaction, percentage-based transfer allocations, and an
accepted decision. The primary account keeps the integer rounding remainder.
Salary occurrences additionally link the existing finalized salary period.
Existing configured salary users receive a backfilled automation source, and
salary settings stay synchronized with that source in both directions.
