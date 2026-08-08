# Push Notifications (FCM)

Finance Suit sends due reminders and facility payment confirmations through:

```text
Finance obligation
-> app_core.notification_outbox
-> Supabase Edge Function notification-worker
-> FCM HTTP v1
-> Android device
-> Finance Suit notification tap
-> auth/device-lock-safe route
```

Device registration is client initiated after sign-in:

```text
Finance Suit
-> Firebase initialize
-> Android notification permission
-> FCM token
-> app_core.register_push_device(...)
-> app_core.push_devices
```

## Client

- Firebase is initialized from the existing Flutter/Android Firebase config.
  Do not generate or commit replacement Firebase config unless the Firebase
  project itself changes.
- Android uses one high-importance channel:
  `finance_due_reminders`.
- Notification permission is requested only after an authenticated session and
  only once per install. App-level notification preferences remain server
  backed by `app_core.notification_preferences`.
- Settings -> Notifications shows Firebase availability, OS permission, FCM
  token/server registration status, a masked token, and an Enable/Retry action.
- Foreground FCM messages are mirrored to one local notification. Background,
  terminated, and local-notification taps all route through the same handler.
- Taps route to the Money/facility screen when `account_id` is present. The
  app-wide device lock remains wrapped around the router, so notification
  taps cannot bypass biometric/device authentication.
- Logout disables the current token through `app_core.disable_push_device(...)`
  before Supabase sign-out and cancels FCM listeners.

## Database

Migration `20260817090400_complete_fcm_notifications.sql` adds:

- global uniqueness for `app_core.push_devices.fcm_token`;
- `app_core.register_push_device(...)`, which atomically transfers the token
  to the current authenticated user and creates default preferences;
- `app_core.disable_push_device(...)`;
- outbox delivery state columns: `status`, `attempt_count`,
  `last_attempt_at`, `next_attempt_at`, `permanently_failed_at`,
  `fcm_message_id`, `payload_snapshot`;
- `app_core.claim_notification_outbox(batch_size)` using
  `FOR UPDATE SKIP LOCKED`;
- `app_core.enqueue_developer_test_notification(...)`;
- pg_cron/pg_net schedule `finance-notification-worker-every-5-minutes`.

Flutter may register/disable its own device and read/update its preferences.
Only the service-role worker writes, claims, sends, retries, or suppresses
outbox rows.

## Edge Function

Canonical function:

```text
supabase/functions/notification-worker
```

The worker:

- materializes due-soon, due-today, and one initial overdue reminder from
  `app_finance.credit_card_statement_summaries`,
  `app_finance.installment_due_statuses`, and
  `app_finance.credit_facility_summaries`;
- materializes recent facility payment confirmations from successful
  asset-to-facility transfers;
- respects `due_reminders_enabled`, `overdue_reminders_enabled`,
  `payment_confirmations_enabled`, and `show_amounts`;
- stores the final safe payload in `payload_snapshot`;
- claims due rows atomically;
- mints a short-lived Google OAuth token and sends through FCM HTTP v1;
- stores the FCM message id on success;
- retries 429/500/503 with bounded backoff;
- disables invalid/unregistered tokens and does not retry them forever;
- suppresses stale paid/disabled/preference-blocked rows before sending.

The Firebase service-account JSON is never stored in Postgres or shipped to
Flutter. The worker reads only:

```text
FIREBASE_SERVICE_ACCOUNT_JSON_B64
```

If the hosted runtime does not expose a platform service key dictionary, the
worker also reads this custom Edge Function secret:

```text
FINANCE_SUPABASE_SERVICE_ROLE_KEY
```

## Required Secret Setup

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

Create the value locally:

```bash
base64 -w 0 android/app/google-services.json
```

macOS base64 alternative:

```bash
base64 < /path/to/firebase-service-account.json | tr -d '\n'
```

Store cron invocation values in Supabase Vault. Use the production project URL
and the project publishable or anon key:

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

## Developer Test Push

After signing in on a physical Android device and granting notification
permission, verify registration:

```sql
select id, user_id, platform, is_enabled, last_seen_at,
       left(fcm_token, 8) || '...' || right(fcm_token, 6) as masked_token
from app_core.push_devices
order by last_seen_at desc;
```

Enqueue a safe developer test notification for the signed-in user:

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

Check the outbox:

```sql
select status, reminder_kind, sent_at, fcm_message_id, error
from app_core.notification_outbox
order by created_at desc
limit 10;
```

## Production QA

1. Install the Android build that includes the existing
   `android/app/google-services.json`.
2. Sign in as the target user and tap Allow on Android notification
   permission.
3. Open Settings -> Notifications and confirm:
   - System notifications are allowed;
   - This device registration says Device registered.
4. Confirm one enabled `app_core.push_devices` row with a masked token.
5. Send the developer test push through the real outbox + worker + FCM path.
6. Test foreground, background, terminated, and tap behavior.
7. Create or use a real upcoming card/installment/BNPL due fixture.
8. Run the worker and verify due-soon/due-today/overdue behavior.
9. Pay the obligation and verify stale reminders suppress and payment
   confirmation sends.

Connectivity may be smoke-tested from Firebase Console, but production
notifications must use Supabase -> FCM HTTP v1.
