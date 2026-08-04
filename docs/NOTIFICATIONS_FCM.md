# Push Notifications (FCM) — Owner Setup Guide

Finance Suit reminds you about installment dues and credit-card statement
due dates through Firebase Cloud Messaging (FCM). Everything in the app and
database is already wired; this guide is the **one-time activation
checklist** you (the project owner) walk through to turn notifications on.

## How the system works

```
pg_cron (hourly) ──▶ Edge Function send-due-reminders ──▶ FCM v1 API ──▶ device
                        │
                        ├─ reads app_finance dues + statement cycles
                        ├─ honors app_core.notification_preferences
                        ├─ honors each card's "Remind me X days before"
                        └─ writes app_core.notification_outbox (exactly-once)
```

- **What gets sent**: a lead reminder (your per-card "Remind me X days
  before" setting), a due-tomorrow reminder, a due-today reminder, and
  overdue nags on days 1, 2, 3, 5, 7, 10, 14, 21, 30, 45, 60 after the due
  date. One notification per device, obligation, kind, and day — re-running
  the sender never duplicates.
- **Privacy**: notification text contains the plan/card name and date only.
  Amounts appear **only** if you enable *Settings → Notifications → Show
  amounts in notifications* (off by default), so balances never show on a
  lock screen unless you asked for that.
- **Client side**: the app registers the device token into
  `app_core.push_devices` after sign-in (and asks for the Android 13+
  notification permission). Without Firebase config files the app builds
  and runs normally with push disabled.

## Step 1 — Create the Firebase project

1. Go to <https://console.firebase.google.com> and **Add project**
   (e.g. `finance-suit`). Google Analytics is not needed — disable it.
2. Inside the project: **Project settings → General → Your apps →
   Add app → Android**.
   - Android package name: `com.buildingsuit.finance`
     (must match `applicationId` in `android/app/build.gradle.kts`).
   - App nickname: anything, e.g. `Finance Suit`.
   - SHA-1: optional for FCM; you can add your Play App Signing SHA-1
     later from Play Console → App integrity.
3. Download **`google-services.json`**.

## Step 2 — Put the client config in the app

1. Copy the downloaded file to **`android/app/google-services.json`**.
   - It is already in `.gitignore` — **never commit it**.
   - CI builds without the file still succeed (push simply stays off in
     those builds), so store a copy of the file with your keystore backups.
2. For your local/release builds that should have push, that one file is
   all the client needs. Rebuild the app; on first sign-in it will ask for
   notification permission and register the device.

> For Play releases built in GitHub Actions you will later want to inject
> the file from a secret (base64) before the build step, the same pattern
> used for the keystore. Until then, sideloaded/dev builds registered from
> your phone work fine.

## Step 3 — Enable the FCM v1 API and get a service account

1. In Firebase **Project settings → Cloud Messaging**, confirm
   **Firebase Cloud Messaging API (V1)** shows *Enabled*. If not, click
   through to Google Cloud Console and enable
   `fcm.googleapis.com` for the project.
2. Go to **Project settings → Service accounts → Generate new private
   key**. This downloads a JSON file (contains `project_id`,
   `client_email`, `private_key`).
   - This key can send notifications as your project. Treat it like a
     password: it lives **only** in Supabase secrets, never in the app,
     never in git.

## Step 4 — Store the key as a Supabase secret and deploy the sender

From the repo root, logged into the Supabase CLI against the production
project:

```bash
# The whole JSON file becomes one secret value.
supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat /path/to/service-account.json)"

# Deploy the sender function.
supabase functions deploy send-due-reminders
```

(Both also run automatically for future deploys if you add the function to
your existing deploy workflow, mirroring `delete-account`.)

## Step 5 — Schedule the sender with pg_cron

The sender is safe to run hourly: the outbox makes each reminder
exactly-once per day, and hourly runs mean reminders arrive in the morning
of the right day in your timezone regardless of UTC offsets.

Run once in the Supabase SQL editor (Dashboard → SQL). This stores the
service-role key in Vault and schedules the call — replace only
`YOUR-PROJECT-REF`; the key is read from Vault so it never sits in the cron
command:

```sql
select vault.create_secret(
  'YOUR-SERVICE-ROLE-KEY', 'service_role_key', 'used by cron to call edge functions'
);

select cron.schedule(
  'send-due-reminders-hourly',
  '5 * * * *',
  $$
  select net.http_post(
    url := 'https://YOUR-PROJECT-REF.supabase.co/functions/v1/send-due-reminders',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (
        select decrypted_secret from vault.decrypted_secrets
        where name = 'service_role_key'
      )
    ),
    body := '{}'::jsonb
  );
  $$
);
```

To pause or remove the schedule later:

```sql
select cron.unschedule('send-due-reminders-hourly');
```

## Step 6 — Verify end-to-end

1. Build and install the app with `google-services.json` in place.
2. Sign in; accept the notification permission prompt.
3. Check registration:
   `select platform, is_enabled, last_seen_at from app_core.push_devices;`
   → one row for your device.
4. Create a test installment plan whose next due date is tomorrow, then
   invoke the function once by hand:

   ```bash
   curl -X POST \
     -H "Authorization: Bearer YOUR-SERVICE-ROLE-KEY" \
     "https://YOUR-PROJECT-REF.supabase.co/functions/v1/send-due-reminders"
   ```

   The response reports `{"sent":1,...}` and your phone shows
   *“Payment due tomorrow”*.
5. Check the audit trail:
   `select reminder_kind, scheduled_local_date, sent_at, error
    from app_core.notification_outbox order by created_at desc;`
6. Run it a second time — `sent` drops to 0 (`skipped` counts up): the
   outbox idempotency is working.

## Settings the user controls

| Where | What |
| --- | --- |
| Account form → *Remind me before a due date* | Per-card lead time (0–14 days) for the early reminder. |
| Settings → Notifications → Due date reminders | Master switch for lead/tomorrow/today reminders. |
| Settings → Notifications → Overdue alerts | The overdue nag series. |
| Settings → Notifications → Payment confirmations | Reserved for payment-recorded pushes. |
| Settings → Notifications → Show amounts | Includes the remaining amount in the text (off by default). |
| System notification settings | The `Payment reminders` channel can be silenced per-device. |

## Troubleshooting

| Symptom | Check |
| --- | --- |
| No row in `push_devices` | The app was built without `google-services.json`, the permission was denied (re-enable in system settings and reopen the app), or sign-in never completed. |
| `firebase_not_configured` from the function | `FIREBASE_SERVICE_ACCOUNT` secret missing — redo Step 4. |
| `fcm_404` errors in the outbox | Stale token; the sender auto-disables that device and the app re-registers on next launch. |
| Nothing arrives while the app is open | Foreground messages are shown by the app itself on the `Payment reminders` channel — check the channel isn't muted. |
| Reminders arrive at odd hours | The cron runs hourly and each device computes "today" in its own timezone (default `Africa/Cairo`); a reminder fires in the first run after local midnight. If you prefer morning delivery, change the cron to e.g. `0 7 * * *` UTC+offset math for your timezone. |

## Security notes

- The service-account JSON and the service-role key exist **only** as
  Supabase secrets / Vault entries. Neither is ever compiled into the app.
- `google-services.json` is client config (not a secret in the strict
  sense) but stays untracked to keep the repo project-agnostic.
- `app_core.notification_outbox` is select-only for the user (RLS); only
  the service role writes to it.
- FCM tokens identify one app install; they are stored per-user under RLS
  and disabled on sign-out or when FCM reports them stale.
