begin;
create extension if not exists pgtap with schema extensions;

select plan(5);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000071',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'notification-owner-a@test.local', '', now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
), (
  '00000000-0000-0000-0000-000000000072',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'notification-owner-b@test.local', '', now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);

set local role service_role;

insert into app_core.push_devices (
  id, user_id, fcm_token, platform, timezone, is_enabled
) values (
  '00000000-0000-0000-0000-000000007101',
  '00000000-0000-0000-0000-000000000071',
  'notification-center-a', 'android', 'Africa/Cairo', true
), (
  '00000000-0000-0000-0000-000000007201',
  '00000000-0000-0000-0000-000000000072',
  'notification-center-b', 'android', 'Africa/Cairo', true
);

insert into app_core.notification_outbox (
  id, user_id, device_id, obligation_type, obligation_id, reminder_kind,
  scheduled_local_date, status, sent_at, next_attempt_at, payload_snapshot
) values (
  '00000000-0000-0000-0000-000000007111',
  '00000000-0000-0000-0000-000000000071',
  '00000000-0000-0000-0000-000000007101',
  'general', '00000000-0000-0000-0000-000000007112', 'due_today',
  current_date, 'sent', now(), now(), '{}'::jsonb
), (
  '00000000-0000-0000-0000-000000007211',
  '00000000-0000-0000-0000-000000000072',
  '00000000-0000-0000-0000-000000007201',
  'general', '00000000-0000-0000-0000-000000007212', 'due_today',
  current_date, 'sent', now(), now(), '{}'::jsonb
);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000071","role":"authenticated"}';

select results_eq(
  $$select count(*)::integer from app_core.notification_outbox$$,
  $$values (1)$$,
  'users see only their own notification history'
);

select lives_ok(
  $$update app_core.notification_outbox set read_at = now()
    where id = '00000000-0000-0000-0000-000000007111'$$,
  'users can mark their own delivered notification as read'
);

select results_eq(
  $$select count(*)::integer from app_core.notification_outbox
    where id = '00000000-0000-0000-0000-000000007111'
      and read_at is not null$$,
  $$values (1)$$,
  'read state persists for the owning user'
);

select results_eq(
  $$with changed as (
      update app_core.notification_outbox set read_at = now()
      where id = '00000000-0000-0000-0000-000000007211'
      returning id
    ) select count(*)::integer from changed$$,
  $$values (0)$$,
  'users cannot update another user notification'
);

select throws_ok(
  $$update app_core.notification_outbox set status = 'failed'
    where id = '00000000-0000-0000-0000-000000007111'$$,
  '42501', null,
  'authenticated clients cannot mutate delivery-owned columns'
);

select * from finish();
rollback;
