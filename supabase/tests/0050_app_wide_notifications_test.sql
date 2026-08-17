begin;
create extension if not exists pgtap with schema extensions;

select plan(23);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000081',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'appwide-notif-a@test.local', '', now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
), (
  '00000000-0000-0000-0000-000000000082',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'appwide-notif-b@test.local', '', now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);

set local role service_role;

-- User A has two devices; user B has none. The whole point of the logical
-- notification table is that both users still get exactly one history row.
insert into app_core.push_devices (
  id, user_id, fcm_token, platform, timezone, is_enabled
) values (
  '00000000-0000-0000-0000-000000008101',
  '00000000-0000-0000-0000-000000000081',
  'appwide-notif-a-phone', 'android', 'Africa/Cairo', true
), (
  '00000000-0000-0000-0000-000000008102',
  '00000000-0000-0000-0000-000000000081',
  'appwide-notif-a-tablet', 'android', 'Africa/Cairo', true
);

insert into app_core.user_preferences (user_id, timezone, locale)
values ('00000000-0000-0000-0000-000000000081', 'Europe/Berlin', 'ar')
on conflict (user_id) do update
  set timezone = excluded.timezone, locale = excluded.locale;

-- ---------------------------------------------------------------------------
-- Logical notification vs device delivery
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_private.create_notification(
      '00000000-0000-0000-0000-000000000081',
      'credit_card.statement_due_today',
      'credit_card.statement_due_today:stmt-1:2026-08-17',
      '{"type":"credit_card_statement_due",
        "account_id":"00000000-0000-0000-0000-0000000081aa"}'::jsonb,
      null,
      '00000000-0000-0000-0000-0000000081bb',
      '/money/facilities/00000000-0000-0000-0000-0000000081aa'
    )$$,
  'the authoritative creation path accepts a catalogued event'
);

select results_eq(
  $$select count(*)::integer from app_core.notifications
    where user_id = '00000000-0000-0000-0000-000000000081'$$,
  $$values (1)$$,
  'two devices produce exactly one Notification Center row'
);

select results_eq(
  $$select count(*)::integer from app_core.notification_outbox
    where notification_id is not null$$,
  $$values (2)$$,
  'each enabled device gets its own delivery row'
);

-- ---------------------------------------------------------------------------
-- Idempotency: repeated scheduler runs must not duplicate
-- ---------------------------------------------------------------------------

select results_eq(
  $$with runs as (
      select app_private.create_notification(
        '00000000-0000-0000-0000-000000000081',
        'credit_card.statement_due_today',
        'credit_card.statement_due_today:stmt-1:2026-08-17'
      ) as id
      from generate_series(1, 3)
    ) select count(distinct id)::integer from runs$$,
  $$values (1)$$,
  'three scheduler runs resolve to one logical notification'
);

select results_eq(
  $$select count(*)::integer from app_core.notification_outbox
    where notification_id is not null$$,
  $$values (2)$$,
  'repeated creation does not fan out duplicate deliveries'
);

select throws_ok(
  $$select app_private.create_notification(
      '00000000-0000-0000-0000-000000000081', 'not.catalogued', 'x'
    )$$,
  null, null,
  'an uncatalogued event key is rejected instead of silently invented'
);

-- ---------------------------------------------------------------------------
-- A user with no push device still has in-app history
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_private.create_notification(
      '00000000-0000-0000-0000-000000000082',
      'network.transfer_received',
      'network.transfer_received:00000000-0000-0000-0000-0000000082cc',
      '{"type":"network_transfer_pending"}'::jsonb,
      null, '00000000-0000-0000-0000-0000000082cc', '/money/network'
    )$$,
  'a user with no registered device can still be notified'
);

select results_eq(
  $$select count(*)::integer from app_core.notifications
    where user_id = '00000000-0000-0000-0000-000000000082'$$,
  $$values (1)$$,
  'in-app history does not depend on push registration'
);

select results_eq(
  $$select count(*)::integer from app_core.notification_outbox
    where user_id = '00000000-0000-0000-0000-000000000082'$$,
  $$values (0)$$,
  'no device means no delivery row to strand in the queue'
);

-- ---------------------------------------------------------------------------
-- Preferences are enforced on the authoritative path
-- ---------------------------------------------------------------------------

insert into app_core.notification_preferences (user_id, due_reminders_enabled)
values ('00000000-0000-0000-0000-000000000081', false)
on conflict (user_id) do update set due_reminders_enabled = false;

select is(
  (select app_private.create_notification(
    '00000000-0000-0000-0000-000000000081', 'installment.due_today',
    'installment.due_today:off:2026-08-17'
  )),
  null,
  'a disabled category creates no notification at all'
);

update app_core.notification_preferences
  set due_reminders_enabled = true, due_push_enabled = false
  where user_id = '00000000-0000-0000-0000-000000000081';

-- Created in its own statement: a function called inside the asserted query
-- would not be visible to that same query's snapshot.
create temporary table push_off_notification on commit drop as
select app_private.create_notification(
  '00000000-0000-0000-0000-000000000081', 'installment.due_today',
  'installment.due_today:pushoff:2026-08-17'
) as id;

select results_eq(
  $$select
      (select count(*)::integer from app_core.notifications
         where id = (select id from push_off_notification)),
      (select count(*)::integer from app_core.notification_outbox
         where notification_id = (select id from push_off_notification))$$,
  $$values (1, 0)$$,
  'disabling only the push channel keeps in-app history and sends nothing'
);

update app_core.notification_preferences
  set due_push_enabled = true
  where user_id = '00000000-0000-0000-0000-000000000081';

-- ---------------------------------------------------------------------------
-- Timezone comes from the user, not from whichever device registered last
-- ---------------------------------------------------------------------------

select results_eq(
  $$select timezone, locale from app_core.notification_user_context(
      array['00000000-0000-0000-0000-000000000081'::uuid]
    )$$,
  $$values ('Europe/Berlin', 'ar')$$,
  'scheduling context follows the user preference over the device record'
);

-- ---------------------------------------------------------------------------
-- Worker claim: atomic, lease-recoverable, attempt-bounded
-- ---------------------------------------------------------------------------

update app_core.notification_outbox
  set status = 'pending', attempt_count = 0, next_attempt_at = now(),
      last_attempt_at = null, sent_at = null, permanently_failed_at = null
  where notification_id is not null;

select results_eq(
  $$select count(*)::integer from app_core.claim_notification_outbox(50)$$,
  $$values (2)$$,
  'a worker claims the pending batch'
);

select results_eq(
  $$select count(*)::integer from app_core.claim_notification_outbox(50)$$,
  $$values (0)$$,
  'a second overlapping worker cannot claim the same rows'
);

select results_eq(
  $$select count(*)::integer
    from app_core.claim_notification_outbox(50, 600)$$,
  $$values (0)$$,
  'a claim held inside its lease is not stolen'
);

update app_core.notification_outbox
  set last_attempt_at = now() - interval '30 minutes'
  where notification_id is not null;

select results_eq(
  $$select count(*)::integer
    from app_core.claim_notification_outbox(50, 600)$$,
  $$values (2)$$,
  'a crashed worker''s rows become claimable once the lease expires'
);

update app_core.notification_outbox
  set attempt_count = 9, last_attempt_at = now() - interval '30 minutes'
  where notification_id is not null;

select results_eq(
  $$select app_core.reap_notification_outbox(5, 600)$$,
  $$values (2)$$,
  'deliveries past the attempt budget are retired'
);

select results_eq(
  $$select count(*)::integer from app_core.notification_outbox
    where status = 'sending'$$,
  $$values (0)$$,
  'no delivery is left permanently in sending'
);

-- ---------------------------------------------------------------------------
-- Client-facing security and read state
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000081","role":"authenticated"}';

select results_eq(
  $$select count(*)::integer from app_core.notifications$$,
  $$values (2)$$,
  'a user reads only their own notifications'
);

select throws_ok(
  $$insert into app_core.notifications
      (user_id, event_key, category, dedupe_key)
    values ('00000000-0000-0000-0000-000000000081',
            'system.developer_test', 'system', 'forged')$$,
  '42501', null,
  'a client cannot author its own notification'
);

select throws_ok(
  $$select app_core.enqueue_notification(
      '00000000-0000-0000-0000-000000000082', 'system.developer_test', 'forged'
    )$$,
  '42501', null,
  'a client cannot enqueue a privileged notification for another user'
);

select results_eq(
  $$select app_core.mark_notifications_read()$$,
  $$values (0)$$,
  'mark all read clears the authoritative unread count in one statement'
);

select results_eq(
  $$select count(*)::integer from app_core.notifications
    where user_id = '00000000-0000-0000-0000-000000000082'
      and read_at is not null$$,
  $$values (0)$$,
  'marking all read never touches another user read state'
);

select * from finish();
rollback;
