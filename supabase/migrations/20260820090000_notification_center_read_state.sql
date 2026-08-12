-- Persist in-app Notification Center read state independently from push
-- delivery state. Clients may only update their own delivered history.
alter table app_core.notification_outbox
  add column if not exists read_at timestamptz;

-- Existing bootstrap grants allow updates across app_core. Narrow the mobile
-- client's privilege to the single read-state column; delivery fields remain
-- service-owned even when the row passes RLS.
revoke update on table app_core.notification_outbox from authenticated;
grant update (read_at) on table app_core.notification_outbox to authenticated;

drop policy if exists notification_outbox_update_read_state
  on app_core.notification_outbox;
create policy notification_outbox_update_read_state
  on app_core.notification_outbox
  for update to authenticated
  using (
    (select auth.uid()) = user_id
    and status = 'sent'
  )
  with check (
    (select auth.uid()) = user_id
    and status = 'sent'
  );

create index if not exists idx_notification_outbox_unread_sent
  on app_core.notification_outbox (user_id, created_at desc, id desc)
  where status = 'sent' and read_at is null;
