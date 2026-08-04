# Realtime

Supabase Realtime is used as an invalidation signal, not as an aggregate patching mechanism.

Flutter subscribes in `realtimeInvalidationProvider` while the authenticated shell is mounted.

Subscribed tables:

- `financial_transactions`
- `accounts`
- `transaction_categories`
- `credit_facility_settings`
- `installment_plans`
- `installment_dues`
- `installment_payment_allocations`
- `work_entries`
- `official_holidays`
- `salary_periods`
- `salary_adjustments`
- `salary_settings`

Each subscription is filtered by `user_id = auth.uid()`. Changes are debounced for 450 ms, then affected providers are invalidated and re-fetched.

Known risk: delete payload filtering depends on Supabase Realtime delete payload behavior. Aggregates remain correct after manual refresh because server-side RLS and queries are authoritative.
