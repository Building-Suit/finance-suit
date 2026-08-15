-- Dry-run and post-migration verification for the item-level statement
-- allocation backfill shipped in 20260825090000_selectable_payment_allocations.
--
-- Run the DRY RUN section against production BEFORE applying the migration;
-- if mapped/unmappable sums disagree with expectations, stop and investigate.
-- Run the VERIFICATION section after applying it; every query must return
-- ok = true (or zero rows where stated). The backfill adds detail rows only —
-- no balance, payment amount, or statement total may change.

-- ---------------------------------------------------------------------------
-- DRY RUN (pre-migration)
-- ---------------------------------------------------------------------------

-- Scope: cycles considered, legacy rows, and the legacy amount that will be
-- replayed into item allocations vs. left indeterminate.
select
  count(distinct sa.cycle_id) as statement_cycles_considered,
  count(*) as legacy_allocation_rows,
  sum(sa.amount_minor) as legacy_allocation_sum_minor,
  count(*) filter (where mappable.ok) as mappable_rows,
  sum(sa.amount_minor) filter (where mappable.ok) as mappable_sum_minor,
  count(*) filter (where not mappable.ok) as unmappable_rows,
  sum(sa.amount_minor) filter (where not mappable.ok) as unmappable_sum_minor
from app_finance.credit_card_statement_allocations sa
cross join lateral (
  select coalesce((
    select sum(x.amount_minor)
    from app_finance.credit_card_statement_allocations x
    where x.cycle_id = sa.cycle_id
  ), 0) <= coalesce((
    select sum(si.amount_minor)
    from app_finance.credit_card_statement_items si
    where si.cycle_id = sa.cycle_id
  ), 0) as ok
) mappable;

-- Financial baseline to capture before the migration (compare after).
select
  (select count(*) from app_finance.credit_card_statement_allocations)
    as cycle_allocation_count,
  (select coalesce(sum(amount_minor), 0)
    from app_finance.credit_card_statement_allocations)
    as cycle_allocation_sum,
  (select count(*) from app_finance.installment_payment_allocations)
    as installment_allocation_count,
  (select coalesce(sum(amount_minor), 0)
    from app_finance.installment_payment_allocations)
    as installment_allocation_sum,
  (select coalesce(sum(t.amount_minor), 0)
    from app_finance.financial_transactions t
    join app_finance.accounts a on a.id = t.destination_account_id
    where t.transaction_kind = 'transfer'
      and app_finance.account_role(a.account_type) = 'liability')
    as facility_payment_total;

-- ---------------------------------------------------------------------------
-- VERIFICATION (post-migration)
-- ---------------------------------------------------------------------------

-- 1. Every backfilled (payment, cycle) pair matches its legacy aggregate
--    exactly. Must return zero rows.
select sa.payment_transaction_id, sa.cycle_id, sa.amount_minor,
  sum(ia.amount_minor) as inferred_sum
from app_finance.credit_card_statement_allocations sa
join app_finance.credit_card_statement_items si on si.cycle_id = sa.cycle_id
join app_finance.credit_card_statement_item_allocations ia
  on ia.statement_item_id = si.id
  and ia.payment_transaction_id = sa.payment_transaction_id
group by sa.payment_transaction_id, sa.cycle_id, sa.amount_minor
having sum(ia.amount_minor) <> sa.amount_minor;

-- 2. No item is over-allocated. Must return zero rows.
select ia.statement_item_id, si.amount_minor, sum(ia.amount_minor) as paid
from app_finance.credit_card_statement_item_allocations ia
join app_finance.credit_card_statement_items si
  on si.id = ia.statement_item_id
group by ia.statement_item_id, si.amount_minor
having sum(ia.amount_minor) > si.amount_minor;

-- 3. Legacy aggregates are untouched: re-run the pre-migration baseline
--    query above — every figure must be identical, because the backfill
--    writes only the new item-allocation table.

-- 4. Statement summaries unchanged: paid state still comes exclusively from
--    the cycle-level table, so total_paid_minor per cycle must equal the
--    cycle allocation sums. Must return zero rows.
select y.id
from app_finance.credit_card_statement_summaries y
join lateral (
  select coalesce(sum(x.amount_minor), 0) as paid
  from app_finance.credit_card_statement_allocations x
  where x.cycle_id = y.id
) pa on true
where y.card_charges_paid_minor <> pa.paid;
