-- The statement-cycle tables shipped without row level security, which the
-- production schema verification rightly rejects (RLS is mandatory for all
-- private tables). Enable it with the standard owner policies. Write access
-- is doubly guarded: these policies scope rows to their owner, and the
-- protect_installment_rows triggers keep even the owner's direct writes out
-- so only the facility RPCs can mutate statement data.

alter table app_finance.credit_card_statement_cycles
  enable row level security;
drop policy if exists credit_card_statement_cycles_select
  on app_finance.credit_card_statement_cycles;
create policy credit_card_statement_cycles_select
  on app_finance.credit_card_statement_cycles
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists credit_card_statement_cycles_insert
  on app_finance.credit_card_statement_cycles;
create policy credit_card_statement_cycles_insert
  on app_finance.credit_card_statement_cycles
  for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists credit_card_statement_cycles_delete
  on app_finance.credit_card_statement_cycles;
create policy credit_card_statement_cycles_delete
  on app_finance.credit_card_statement_cycles
  for delete to authenticated using ((select auth.uid()) = user_id);

alter table app_finance.credit_card_statement_items
  enable row level security;
drop policy if exists credit_card_statement_items_select
  on app_finance.credit_card_statement_items;
create policy credit_card_statement_items_select
  on app_finance.credit_card_statement_items
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists credit_card_statement_items_insert
  on app_finance.credit_card_statement_items;
create policy credit_card_statement_items_insert
  on app_finance.credit_card_statement_items
  for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists credit_card_statement_items_delete
  on app_finance.credit_card_statement_items;
create policy credit_card_statement_items_delete
  on app_finance.credit_card_statement_items
  for delete to authenticated using ((select auth.uid()) = user_id);

alter table app_finance.credit_card_statement_allocations
  enable row level security;
drop policy if exists credit_card_statement_allocations_select
  on app_finance.credit_card_statement_allocations;
create policy credit_card_statement_allocations_select
  on app_finance.credit_card_statement_allocations
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists credit_card_statement_allocations_insert
  on app_finance.credit_card_statement_allocations;
create policy credit_card_statement_allocations_insert
  on app_finance.credit_card_statement_allocations
  for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists credit_card_statement_allocations_delete
  on app_finance.credit_card_statement_allocations;
create policy credit_card_statement_allocations_delete
  on app_finance.credit_card_statement_allocations
  for delete to authenticated using ((select auth.uid()) = user_id);

notify pgrst, 'reload schema';
