# Notifications

Finance Suit has one notification subsystem. Every user-facing notification —
in-app or push — is created through a single authoritative path and is
represented by exactly one logical row per user.

```text
Finance domain event  (statement due, payment recorded, transfer received, ...)
        |
        v
app_private.create_notification            <- the only creation path
        |  validates the event key against the catalog
        |  evaluates the recipient's in-app preference
        |  inserts idempotently on (user_id, dedupe_key)
        |
        +--> app_core.notifications         one logical notification per user
        |         |
        |         +--> Supabase Realtime --> Notification Center + unread badge
        |
        +--> push preference evaluation
                  |
                  v
             app_core.notification_outbox   one delivery row per enabled device
                  |
                  v
             notification-worker (Edge Function)
                  |  atomic claim with lease, bounded retry, token retirement
                  v
                 FCM HTTP v1 --> Android
```

## Why the logical/delivery split exists

Before `20260828090000_app_wide_notifications.sql` a notification *was* an
outbox row, and an outbox row is a per-device push delivery record. That
conflated three things:

- a user with two phones saw every notification twice in the Notification
  Center;
- a user with no registered device (push denied, fresh install) had no
  notification history at all;
- history only appeared once FCM accepted the message, so a push outage
  silently swallowed the in-app record too.

`app_core.notifications` is now the logical notification and
`app_core.notification_outbox` is purely its per-device delivery queue,
linked by `notification_outbox.notification_id`.

## Event contract

`app_core.notification_event_catalog` is the single event-key contract.
`create_notification` refuses any key that is not in it, so a feature cannot
invent a string. Keys are stable machine identifiers; the Flutter client
localizes them at render time and never displays a raw key.

### Event matrix

| Feature | Event key | Trigger | Recipient | In-app | Push | Scheduled | Default preference | Destination | Dedupe key |
|---|---|---|---|---|---|---|---|---|---|
| Credit card | `credit_card.statement_due_soon` | worker: `due_on` is `reminder_lead_days` away | statement owner | yes | yes | cron, 5 min | `due_reminders_enabled` + `due_push_enabled` | `/money/facilities/{account}` | `event:statement:due_on` |
| Credit card | `credit_card.statement_due_today` | worker: `due_on` is today | statement owner | yes | yes | cron, 5 min | same | `/money/facilities/{account}` | `event:statement:due_on` |
| Credit card | `credit_card.statement_overdue` | worker: one day past `due_on` | statement owner | yes | yes | cron, 5 min | `overdue_reminders_enabled` + `overdue_push_enabled` | `/money/facilities/{account}` | `event:statement:due_on` |
| Installments | `installment.due_soon` / `.due_today` / `.overdue` | worker, per due row | plan owner | yes | yes | cron, 5 min | due / overdue | `/money/facilities/{account}` | `event:due_id:due_on` |
| BNPL | `bnpl.due_soon` / `.due_today` / `.overdue` | worker, per due row on a BNPL facility | plan owner | yes | yes | cron, 5 min | due / overdue | `/money/facilities/{account}` | `event:due_id:due_on` |
| Facilities | `facility.payment_recorded` | worker: transfer into a facility in the last 24h | payer | yes | yes | cron, 5 min | `payment_confirmations_enabled` + `payment_push_enabled` | `/money/facilities/{account}` | `event:payment_id` |
| Network | `network.add_request_received` | `request_network_add` trigger | target user | yes | yes | event-driven | `network_enabled` + `network_push_enabled` | `/money/network` | `event:request_id` |
| Network | `network.add_request_accepted` | `accept_network_add_request` | requester | yes | yes | event-driven | network | `/money/network` | `event:request_id` |
| Network | `network.transfer_received` | transfer created | receiver | yes | yes | event-driven | network | `/money/network` | `event:transfer_id` |
| Network | `network.transfer_accepted` / `.transfer_declined` | receiver decides | sender | yes | yes | event-driven | network | `/money/network` | `event:transfer_id` |
| Responsibility | `installment_link.request_received` | link requested | responsible user | yes | yes | event-driven | network | `/money/linked/{link}` | `event:link_id` |
| Responsibility | `installment_link.accepted` / `.declined` | responsible user decides | plan owner | yes | yes | event-driven | network | `/money` | `event:link_id` |
| Diagnostics | `system.developer_test` | Settings → send test notification | self | yes | yes | manual | `system_push_enabled` | `/home` | `event:second` |

Features that deliberately do **not** notify, and why:

- **Recurring rules and income occurrences** — materialization is silent by
  design; an occurrence appearing is not a user decision point. Their *dues*
  already notify through the installment and statement rows.
- **Ordinary transactions, categories, macros, held amounts** — user-initiated
  and immediately visible; a notification would be spam.
- **Salary periods and work entries** — no due-date or approval workflow that
  the user could miss exists in the current schema.
- **Subscription / trial state** — the commercial control plane has no
  expiry-approaching event yet. When one exists it belongs in the catalog as
  a `system` (or `security`) event; the pipeline needs no change.
- **Security and device events** — the catalog reserves the `security`
  category, which is always written in-app (`is_critical`), but Supabase Auth
  does not currently emit a new-device signal Finance Suit can subscribe to.

## Preferences

`app_core.notification_preferences` holds one row per user and is
channel-aware:

- the category switches (`due_reminders_enabled`, `overdue_reminders_enabled`,
  `payment_confirmations_enabled`, `network_enabled`) decide whether the
  notification exists at all — a disabled category creates no row anywhere;
- the `*_push_enabled` switches decide only whether enabled devices are
  targeted, so a user can keep in-app history while silencing their phone;
- `show_amounts` controls whether an amount reaches the *pre-rendered push
  text*. It is off by default.

Enforcement lives on the authoritative path
(`app_private.notification_channel_allowed`), not in the Flutter UI. The
worker re-checks device state and obligation state before sending, so a
preference change between enqueue and send still suppresses the push.

Events flagged `is_critical` in the catalog are always recorded in-app; only
their push channel is user-controlled. Settings states this explicitly rather
than offering a switch that does nothing.

## Money privacy

Two different rules, deliberately:

- **Lock screen.** `compose()` in the Edge Function only ever reads
  `amount_text`, which the worker populates only when `show_amounts` is on.
  The FCM `data` block carries routing keys — event key, notification id,
  route, entity and account ids — and never an amount or a device token.
- **Inside the app.** The logical payload carries `amount_minor` and
  `currency_code`, and the Notification Center renders them through
  `AppMoneyText`/`ProtectedMoney`, the app's existing money-privacy control.
  There is no second privacy system.

## Scheduling

Reminder timing uses the user's own timezone from
`app_core.user_preferences.timezone` (falling back to their most recently
seen device, then `Africa/Cairo`), resolved by
`app_core.notification_user_context`. Egypt is a fallback, not a constant.

Due reminders dedupe on the **due instance**
(`event_key:entity_id:due_on`), not on the day the scheduler ran:

- rerunning the scheduler any number of times produces one notification;
- moving a due date produces a new logical reminder for the new instance;
- paying, completing or cancelling the obligation makes the queued delivery
  ineligible, and the worker suppresses it before sending;
- each recurring occurrence is its own row, so each gets its own reminder;
- restarts and worker retries change nothing.

## Delivery

`app_core.claim_notification_outbox(batch_size, lease_seconds, max_attempts)`
claims work atomically with `FOR UPDATE SKIP LOCKED`. It also reclaims rows a
crashed worker left in `sending` once their lease expires, so nothing becomes
a permanent zombie. `app_core.reap_notification_outbox` retires deliveries
past the attempt budget and runs before every claim.

Retries are bounded (1, 5, 15, 60 minutes, then failed). FCM `UNREGISTERED`,
`INVALID_ARGUMENT` and 404 retire the device registration instead of retrying
forever. Errors stored in the row and written to logs are sanitized status
codes; full FCM tokens, authorization headers and service-account material
are never logged.

## Client

- `app_core.unread_notification_count()` is the one authoritative badge
  source. The header bell, the Notification Center and any future app-icon
  badge read `notificationUnreadCountProvider`; feature counts never feed it.
- `app_core.mark_notifications_read(ids)` marks one, many, or (with null)
  everything in a single server-side statement and returns the reconciled
  unread count so the badge settles in the same round trip.
- The Notification Center serves cached pages immediately, refreshes stale
  ones in the background, fetches at most 20 rows per page, and guarantees a
  single in-flight next-page request.
- One realtime subscription per signed-in session, owned by the authenticated
  shell (`notificationRealtimeProvider`), keyed by user id so a previous
  account's channel cannot survive a switch.
- The feed cache is keyed by user; signing in as somebody else starts empty.
- Deep links come from the notification's structured `route`, validated
  against an allowlist (`NotificationRoutes.resolve`). A payload is
  addressing, not authorization — the destination screen still loads its
  entity under RLS, and a missing or malformed target simply opens nothing.
- A tap that arrives before the session exists (terminated app) is held and
  replayed once registration resolves the user and the router is ready.

## Device registration

Client initiated after sign-in:

```text
Finance Suit -> Firebase initialize -> Android notification permission
             -> FCM token -> app_core.register_push_device(...)
             -> app_core.push_devices
```

`fcm_token` is globally unique and `register_push_device` atomically
transfers it to the current user, so a token can never belong to two users.
Permission is requested once per install; denial leaves the app fully usable
with in-app notifications and reports push as unavailable. Logout disables the
current token through `app_core.disable_push_device(...)` before sign-out.

## Security

- RLS on `app_core.notifications`: select own rows, update only `read_at` on
  own rows. `insert`/`delete` are revoked from `authenticated` (the schema's
  default privileges would otherwise grant them).
- `app_core.enqueue_notification` refuses to run when `auth.uid()` is
  non-null and is granted to `service_role` only, so a client cannot mint a
  privileged notification for itself or anyone else.
- `app_private.create_notification` and the claim/reap functions are
  service-role only, `security definer` with `set search_path = ''`.
- The Firebase service account and the Supabase service-role key stay in Edge
  Function secrets; neither is in Postgres or in the Flutter client.

## Retention

Read is not delete. Notification history is retained indefinitely for now —
pagination is what keeps the Notification Center scalable, and no destructive
cleanup was invented to reduce row count. Outbox delivery diagnostics are a
separate concern and may get their own cleanup policy later; nothing prunes
them today.

## Database objects

Added by `20260828090000_app_wide_notifications.sql`:

- tables `app_core.notifications`, `app_core.notification_event_catalog`;
- `app_core.notification_outbox.notification_id` plus a partial unique index
  on `(notification_id, device_id)`, and the obligation columns relaxed to
  nullable behind a `notification_outbox_shape` check;
- `app_core.notification_preferences` channel columns;
- `app_private.create_notification`, `app_private.notification_channel_allowed`,
  `app_private.notification_event_key_for`,
  `app_private.notification_route_for`;
- `app_core.enqueue_notification`, `app_core.unread_notification_count`,
  `app_core.mark_notifications_read`, `app_core.notification_user_context`,
  `app_core.reap_notification_outbox`, and a replaced
  `app_core.claim_notification_outbox(integer, integer, integer)`;
- `app_private.enqueue_network_notification` rewired onto the authoritative
  path (same signature, so no call site changed);
- `app_core.notifications` added to the `supabase_realtime` publication;
- a backfill that collapses existing outbox rows into logical notifications,
  preserving their original `created_at` and read state.

## Edge Function

```text
supabase/functions/notification-worker
  index.ts     materialization, claiming, FCM delivery, retry policy
  compose.ts   pure event mapping, localized text, backoff, FCM data block
  compose.test.ts
```

Batch size 50, lease 600s, max 5 attempts, materialization capped at 500
logical notifications per invocation (the cap is logged, never silent).
Reminders are only materialized after 09:00 in the user's local time.

## Required secret setup

Set the Firebase service account as a base64-encoded Edge Function secret:

```bash
base64 -w 0 /path/to/firebase-service-account.json > /tmp/firebase-sa.b64

supabase secrets set \
  FIREBASE_SERVICE_ACCOUNT_JSON_B64="$(cat /tmp/firebase-sa.b64)" \
  --project-ref kedjrbwnznvfqlzszawa
```

Set the service-role fallback with a non-reserved name. Get this value from
Supabase Dashboard -> Project Settings -> API -> service_role/secret key:

```bash
supabase secrets set \
  FINANCE_SUPABASE_SERVICE_ROLE_KEY="YOUR_SUPABASE_SERVICE_ROLE_KEY" \
  --project-ref kedjrbwnznvfqlzszawa
```

For Google Play builds, add this GitHub Actions secret in the `play-test` and
`play-production` environments. Its value is the base64-encoded
`android/app/google-services.json`:

```text
FIREBASE_ANDROID_GOOGLE_SERVICES_JSON_BASE64
```

Store cron invocation values in Supabase Vault:

```sql
select vault.create_secret(
  'https://kedjrbwnznvfqlzszawa.supabase.co',
  'project_url',
  'Finance Suit production project URL for cron edge invocation'
);

select vault.create_secret(
  'YOUR_SUPABASE_PUBLISHABLE_OR_ANON_KEY',
  'publishable_key',
  'Finance Suit cron edge invocation key'
);
```

Verify Firebase Cloud Messaging API (V1) is enabled for the Firebase project.

## Deploy

```bash
supabase db push --project-ref kedjrbwnznvfqlzszawa
supabase functions deploy notification-worker --project-ref kedjrbwnznvfqlzszawa
```

## Developer test push

After signing in on a physical Android device and granting notification
permission, verify registration:

```sql
select id, user_id, platform, is_enabled, last_seen_at,
       left(fcm_token, 8) || '...' || right(fcm_token, 6) as masked_token
from app_core.push_devices
order by last_seen_at desc;
```

Enqueue a safe developer test notification:

```sql
select app_core.enqueue_developer_test_notification(
  'USER_ID_FROM_PUSH_DEVICES'::uuid
);
```

Invoke the worker:

```bash
curl -X POST \
  -H "Authorization: Bearer YOUR_SUPABASE_PUBLISHABLE_OR_ANON_KEY" \
  -H "apikey: YOUR_SUPABASE_PUBLISHABLE_OR_ANON_KEY" \
  https://kedjrbwnznvfqlzszawa.supabase.co/functions/v1/notification-worker
```

Inspect both layers:

```sql
select event_key, created_at, read_at, route
from app_core.notifications order by created_at desc limit 10;

select o.status, o.attempt_count, o.sent_at, o.fcm_message_id, o.error
from app_core.notification_outbox o order by o.created_at desc limit 10;
```

## Production QA

1. Install the Android build that includes `android/app/google-services.json`.
2. Sign in and tap Allow on the Android notification permission.
3. Settings → Notifications: confirm the category switches, the phone-alert
   switches, and that the security row explains it cannot be silenced in-app.
4. Confirm one enabled `app_core.push_devices` row with a masked token.
5. Send a test notification and confirm it appears both on the phone and in
   the Notification Center.
6. Test foreground, background, terminated, and tap-to-route behaviour.
7. Sign in on a second device and confirm the Notification Center still shows
   **one** row per notification.
8. Deny notification permission on a device and confirm in-app notifications
   still arrive.
9. Create a real upcoming card/installment/BNPL due, run the worker twice in a
   row, and confirm exactly one reminder.
10. Pay the obligation and verify the stale reminder suppresses and the
    payment confirmation sends.
11. Turn off a category and confirm nothing is created; turn its push switch
    off only and confirm the in-app row still appears with no phone alert.
