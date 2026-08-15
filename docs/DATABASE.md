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
  balance views, atomic transfer/income/facility RPCs, and the
  Finance Suit Network tables (`network_add_requests`,
  `network_connections`, `network_transfers`)
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

Global Credit Card / BNPL reference data lives in the versioned financial
product catalog v2. Issuers, canonical products, issuer-country markets, and
country-specific product variants are separate, while legacy immutable catalog
history remains readable. It is RLS-locked against direct client access and is
separate from user facilities; see `docs/DATABASE_ARCHITECTURE.md` for its
storage, 25/50-item curator leasing, discovery RPC, provenance rules, and exact
scheduled-task boundary. `docs/FINANCIAL_PRODUCT_CATALOG_COVERAGE_MATRIX.md`
defines which fields are public, private, derived, or unsupported.

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
keeps treating them normally. Home also asks
`app_reports.cash_flow_summary_v3(start, end, exclude_hidden => true)` so
its cash-flow figures cover exactly the accounts it lists; Reports call
the same function without the flag and keep counting everything.

`credit_facility_summaries.upcoming_due_minor` sums every unpaid
installment and statement falling due between today and one month out, so
a card can state what it will actually ask for rather than only its
earliest single due.

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
`notification-worker` Edge Function materializes, claims, sends, retries,
and suppresses rows in `app_core.notification_outbox` (select-only for
clients) whose unique key makes each notification exactly-once per device,
obligation, kind, and local date. See
`docs/NOTIFICATIONS_FCM.md` for the activation guide.

Recurring income is materialized as pending occurrences. Materialization alone
never creates a financial transaction. `accept_income_occurrence` atomically
creates the income transaction, percentage-based transfer allocations, and an
accepted decision. The primary account keeps the integer rounding remainder.
Salary occurrences additionally link the existing finalized salary period.
Existing configured salary users receive a backfilled automation source, and
salary settings stay synchronized with that source in both directions.

Finance Suit Network: users connect through `network_add_requests` (one
pending request per unordered user pair) into `network_connections`, which
store two private directional aliases — what A calls B and what B calls A.
The alias columns are not client-readable; `list_network_contacts` resolves
the caller's side server-side. A connected person is a transfer destination
identity, never an `accounts` row, so nothing about assets, balances, or
reports changes by connecting. A network transfer
(`network_transfers`) starts `pending` with zero ledger impact, and
`reject_network_transfer` keeps it that way. `accept_network_transfer` is the
only path that books money: it locks the shared row, revalidates the sender's
funds and account state, and atomically creates two one-sided `transfer` rows
— source-only on the sender, destination-only on the receiver — linked by
`financial_transactions.network_transfer_id` and marked
`is_network_transfer`. Those rows are blocked from the generic editors by a
trigger, are transfers (never expense or income) in every report, and each
side of the shared record exposes only that party's own account. Connecting
changes no RLS on any private table; both parties see the shared request,
connection, and transfer rows only.

Automations reach the network through `destination_network_connection_id` on
`recurring_rules` and `income_source_allocations`, and
`extra_work_destination_network_connection_id` on `income_sources` (exactly
one destination per rule; balance rollover keeps its own-savings semantics).
Approving a recurring occurrence or accepting an income occurrence that
routes to a contact creates the pending network transfer once — deterministic
idempotency keys (`recurring:<occurrence>`, `income:<occurrence>:<allocation>`,
`extra-work:<occurrence>`) make retries reuse it — and the sender's balance
moves only when the receiver accepts into their own matching-currency asset
account. A removed connection blocks new transfers and pending acceptances
and surfaces `network_destination_unavailable` instead of rerouting.

Installment responsibility: `installment_responsibility_links` lets an owner
link one active plan to the person who reimburses them — a private
`custom_name` (accepted immediately, no account needed) or a network contact
derived from an active `network_connections` row, who must accept first.
Linking never moves money and never transfers the facility liability: the
plan, its dues, and `pay_credit_facility` stay entirely the owner's. A
network request stores a server-built sanitized `request_snapshot` (terms,
remaining schedule aggregates, a `terms_fingerprint` of the remaining dues)
as consent evidence; acceptance re-verifies the fingerprint so materially
changed terms (restructures) can never be accepted silently, and an accepted
link whose terms later change blocks new reimbursements until re-consent.
Responsibility starts at `responsibility_from_sequence` — the first unpaid,
non-presettled due — so paid history is never reassigned, and one live link
per plan is enforced by a partial unique index. Unlink soft-removes
(`removed_at`); history rows and reimbursements stay. The linked user reads
only the narrow RPC DTOs (`get_shared_installment_link_details`,
`list_my_linked_installments`) — plan, due, account, and transaction RLS is
not broadened at all.

Reimbursements (`installment_reimbursements`) are per-due, capped across all
links so a reassigned plan can never collect the same due twice, and are
always transfers, never income. A network reimbursement rides the existing
network transfer rail (`origin_kind = 'installment_reimbursement'`): pending
moves nothing, the owner's acceptance books the two one-sided legs, and a
trigger settles the reimbursement row server-side. A custom reimbursement is
recorded by the owner through `record_custom_installment_reimbursement`,
which books a protected one-sided destination-only transfer inflow
(`is_reimbursement_inflow`) into one of the owner's asset accounts. Neither
path touches `installment_payment_allocations` or the facility outstanding —
paying the bank remains a separate, explicit facility payment.
