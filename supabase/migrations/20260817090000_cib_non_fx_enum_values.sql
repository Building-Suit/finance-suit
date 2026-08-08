-- Canonical non-FX card-interest semantics. Values added to existing enum
-- types must commit before the following migration can use them.

alter type app_finance.card_fee_type add value if not exists
  'purchase_interest';

alter type app_finance.card_rule_trigger add value if not exists
  'statement_interest';

notify pgrst, 'reload schema';
