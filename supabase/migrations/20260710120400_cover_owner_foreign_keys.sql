-- Cover owner-aware foreign keys in FK column order for planner efficiency.

create index idx_work_entries_holiday_owner_fk
  on app_work.work_entries (holiday_id, user_id)
  where holiday_id is not null;

create index idx_salary_periods_destination_owner_fk
  on app_salary.salary_periods (destination_account_id, user_id)
  where destination_account_id is not null;

create index idx_salary_periods_paid_transaction_fk
  on app_salary.salary_periods (paid_transaction_id)
  where paid_transaction_id is not null;

create index idx_tx_source_owner_fk
  on app_finance.financial_transactions (source_account_id, user_id)
  where source_account_id is not null;

create index idx_tx_destination_owner_fk
  on app_finance.financial_transactions (destination_account_id, user_id)
  where destination_account_id is not null;

create index idx_tx_category_owner_fk
  on app_finance.financial_transactions (category_id, user_id)
  where category_id is not null;

create index idx_tx_salary_period_owner_fk
  on app_finance.financial_transactions (salary_period_id, user_id)
  where salary_period_id is not null;
