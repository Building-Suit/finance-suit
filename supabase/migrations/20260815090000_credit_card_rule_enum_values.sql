-- New values on existing Credit Card enums for the versioned rules engine
-- (section: generic bank-agnostic fee/charge rules). PostgreSQL forbids
-- using a value added by ALTER TYPE ... ADD VALUE inside the same
-- transaction that added it, so these additions live alone in this
-- migration; the tables/functions that consume them follow in the next
-- migration file, matching the existing
-- 20260804090000_credit_facility_account_types.sql precedent.

alter type app_finance.card_fee_type add value if not exists
  'international_cash_advance';
alter type app_finance.card_fee_type add value if not exists 'wallet_fee';
alter type app_finance.card_fee_type add value if not exists 'statement_fee';
alter type app_finance.card_fee_type add value if not exists
  'early_settlement';

alter type app_finance.fee_percent_basis add value if not exists
  'transaction_amount';
alter type app_finance.fee_percent_basis add value if not exists
  'highest_statement_due_lookback';
alter type app_finance.fee_percent_basis add value if not exists
  'remaining_principal';
alter type app_finance.fee_percent_basis add value if not exists
  'remaining_outstanding';

alter type app_finance.fee_frequency add value if not exists
  'per_transaction';

alter type app_finance.plan_pricing_method add value if not exists
  'card_tenor_default';

notify pgrst, 'reload schema';
