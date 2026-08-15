-- New network transfer origin for installment reimbursements. PostgreSQL
-- forbids using a value added by ALTER TYPE ... ADD VALUE inside the same
-- transaction that added it, so this addition lives alone in this migration;
-- the tables and functions that consume it follow in the next migration
-- file, matching the 20260815090000_credit_card_rule_enum_values.sql
-- precedent.

alter type app_finance.network_transfer_origin add value if not exists
  'installment_reimbursement';

notify pgrst, 'reload schema';
