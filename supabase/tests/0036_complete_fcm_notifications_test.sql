begin;
create extension if not exists pgtap with schema extensions;

select plan(13);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000061',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'push-owner-a@test.local', '', now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
), (
  '00000000-0000-0000-0000-000000000062',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'push-owner-b@test.local', '', now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);

select has_function(
  'app_core',
  'register_push_device',
  array['text', 'text', 'text', 'text', 'text'],
  'register_push_device RPC exists'
);
-- Batch size, lease seconds, attempt budget. The lease argument is what lets
-- a crashed worker's `sending` rows become claimable again.
select has_function(
  'app_core',
  'claim_notification_outbox',
  array['integer', 'integer', 'integer'],
  'claim_notification_outbox RPC exists'
);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000061","role":"authenticated"}';

select lives_ok(
  $$select app_core.register_push_device(
    'fake-fcm-token-transfer-0001', 'android', '0.6.0', 'en-EG',
    'Africa/Cairo'
  )$$,
  'authenticated users can register an FCM token through the RPC'
);

select results_eq(
  $$select user_id, platform, is_enabled, timezone
    from app_core.push_devices
    where fcm_token = 'fake-fcm-token-transfer-0001'$$,
  $$values (
    '00000000-0000-0000-0000-000000000061'::uuid,
    'android', true, 'Africa/Cairo'
  )$$,
  'registration stores the current user and IANA timezone'
);

select results_eq(
  $$select count(*)::integer from app_core.notification_preferences
    where user_id = '00000000-0000-0000-0000-000000000061'$$,
  $$values (1)$$,
  'registration creates a default preference row'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000062","role":"authenticated"}';

select lives_ok(
  $$select app_core.register_push_device(
    'fake-fcm-token-transfer-0001', 'android', '0.6.0', 'ar-EG',
    'Africa/Cairo'
  )$$,
  'a new authenticated user can reclaim the same physical token'
);

select results_eq(
  $$select user_id, locale, count(*) over ()::integer
    from app_core.push_devices
    where fcm_token = 'fake-fcm-token-transfer-0001'$$,
  $$values (
    '00000000-0000-0000-0000-000000000062'::uuid,
    'ar-EG', 1
  )$$,
  'one global token row remains and belongs to the latest user'
);

select lives_ok(
  $$select app_core.disable_push_device('fake-fcm-token-transfer-0001')$$,
  'the owning user can disable the current device'
);

select results_eq(
  $$select is_enabled from app_core.push_devices
    where fcm_token = 'fake-fcm-token-transfer-0001'$$,
  $$values (false)$$,
  'disable_push_device turns off the token'
);

select throws_ok(
  $$select app_core.register_push_device(
    'fake-fcm-token-bad-tz-0001', 'android', null, null, 'Not/AZone'
  )$$,
  'P0001', null, 'invalid timezone values are rejected'
);

reset role;
set local role service_role;

update app_core.push_devices
  set is_enabled = true
  where fcm_token = 'fake-fcm-token-transfer-0001';

insert into app_core.notification_outbox (
  user_id, device_id, obligation_type, obligation_id, reminder_kind,
  scheduled_local_date, status, next_attempt_at, payload_snapshot
) select
  user_id, id, 'general', '00000000-0000-0000-0000-00000000f001',
  'due_today', current_date, 'pending', now(),
  '{"type":"developer_test","reminder_kind":"due_today"}'::jsonb
from app_core.push_devices
where fcm_token = 'fake-fcm-token-transfer-0001';

select results_eq(
  $$select status, attempt_count from app_core.notification_outbox
    where obligation_id = '00000000-0000-0000-0000-00000000f001'$$,
  $$values ('pending', 0)$$,
  'new outbox state columns default to pending with zero attempts'
);

select results_eq(
  $$select attempt_count from app_core.claim_notification_outbox(10)
    where obligation_id = '00000000-0000-0000-0000-00000000f001'$$,
  $$values (1)$$,
  'claiming marks rows sending and increments attempts'
);

select results_eq(
  $$select count(*)::integer from app_core.claim_notification_outbox(10)
    where obligation_id = '00000000-0000-0000-0000-00000000f001'$$,
  $$values (0)$$,
  'a second worker cannot claim the same sending row'
);

select * from finish();
rollback;
