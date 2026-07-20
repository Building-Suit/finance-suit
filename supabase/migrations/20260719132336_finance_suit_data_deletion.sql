-- Atomically delete one user's Finance Suit product data while preserving the
-- shared Supabase Auth identity and every legacy `public` schema record.
create or replace function app_core.delete_finance_suit_data(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_user_id is null then
    raise exception 'user_id_required';
  end if;

  -- Break the circular salary-period/transaction references before deleting
  -- either side. The transaction remains atomic, so partial deletion cannot be
  -- observed if a later statement fails.
  update app_salary.salary_periods
    set paid_transaction_id = null
    where user_id = p_user_id;
  update app_finance.financial_transactions
    set salary_period_id = null
    where user_id = p_user_id;

  delete from app_finance.held_amounts where user_id = p_user_id;
  delete from app_finance.transaction_macro_items where user_id = p_user_id;
  delete from app_finance.transaction_macros where user_id = p_user_id;
  delete from app_finance.financial_transactions where user_id = p_user_id;
  delete from app_salary.salary_periods where user_id = p_user_id;
  delete from app_finance.transaction_categories where user_id = p_user_id;
  delete from app_finance.accounts where user_id = p_user_id;

  delete from app_work.work_entries where user_id = p_user_id;
  delete from app_work.official_holidays where user_id = p_user_id;

  delete from app_salary.salary_adjustments where user_id = p_user_id;
  delete from app_salary.salary_settings where user_id = p_user_id;

  delete from app_core.user_preferences where user_id = p_user_id;
  delete from app_core.profiles where id = p_user_id;
end;
$$;

comment on function app_core.delete_finance_suit_data(uuid) is
  'Deletes Finance Suit product data only; preserves shared Auth and public legacy data.';

revoke all on function app_core.delete_finance_suit_data(uuid) from public;
revoke all on function app_core.delete_finance_suit_data(uuid) from anon;
revoke all on function app_core.delete_finance_suit_data(uuid) from authenticated;
grant execute on function app_core.delete_finance_suit_data(uuid) to service_role;

notify pgrst, 'reload schema';
