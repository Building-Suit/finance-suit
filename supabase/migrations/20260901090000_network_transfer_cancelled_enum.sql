-- A fourth terminal state for network transfers: the sender withdrawing a
-- request the receiver has not answered yet. Until now the only way out of
-- 'pending' was the receiver accepting or rejecting, so a sender who sent the
-- wrong amount to the wrong contact had no way back.
--
-- PostgreSQL forbids using a value added by ALTER TYPE ... ADD VALUE inside
-- the same transaction that added it, so this addition lives alone in this
-- migration; the constraint rewrite and the RPCs that consume it follow in
-- 20260901090100_network_transfer_amendments.sql, matching the existing
-- 20260815090000_credit_card_rule_enum_values.sql precedent.

alter type app_finance.network_transfer_status add value if not exists
  'cancelled';

notify pgrst, 'reload schema';
