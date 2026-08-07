-- New values on existing Credit Card enums for accurate CIB-style fees.
-- PostgreSQL forbids using a value added by ALTER TYPE ... ADD VALUE inside
-- the same transaction that added it, so these additions live alone here;
-- the functions that consume them follow in the next migration file,
-- matching the 20260815090000_credit_card_rule_enum_values.sql precedent.

-- Foreign-fee condition observed on real EGP statements: the markup line
-- appears only when a foreign merchant bills in the card's home currency
-- (a genuinely foreign-currency purchase carries its markup inside the
-- exchange rate instead). None of the four existing conditions can say
-- "merchant outside home AND currency does not differ".
alter type app_finance.foreign_apply_when add value if not exists
  'foreign_merchant_home_currency';

-- Egyptian stamp duty is charged quarterly on the highest debit balance
-- the account reached during the quarter — a running-balance peak, which
-- highest_statement_due_lookback (a statement figure) cannot reproduce.
alter type app_finance.fee_percent_basis add value if not exists
  'highest_daily_balance_lookback';

notify pgrst, 'reload schema';
