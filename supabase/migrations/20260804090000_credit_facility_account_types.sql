-- Credit Card and BNPL / finance-company facilities are liability accounts.
-- The new account_type values live alone in this migration because PostgreSQL
-- refuses to use an enum value inside the transaction that added it; the
-- tables, views, and RPCs that consume these values follow in the next
-- migration file.

alter type app_finance.account_type add value if not exists 'credit_card';
alter type app_finance.account_type add value if not exists 'bnpl';

notify pgrst, 'reload schema';
