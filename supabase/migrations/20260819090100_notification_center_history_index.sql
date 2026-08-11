-- Notification Center reads only the authenticated user's delivered history
-- in newest-first keyset order. This partial index matches that exact access
-- path without expanding the pending-delivery worker indexes.
create index if not exists idx_notification_outbox_history_sent
  on app_core.notification_outbox (user_id, created_at desc, id desc)
  where status = 'sent';
