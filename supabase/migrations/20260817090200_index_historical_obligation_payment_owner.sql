create index idx_historical_obligations_payment_owner
  on app_finance.historical_facility_obligations (
    settled_by_transaction_id, user_id
  );
