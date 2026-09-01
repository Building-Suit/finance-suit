# Privacy and account deletion

## Repository audit

Finance Suit sends the following user data to the hosted Supabase project:

- Supabase Auth: email, password credential, display name, user id, sessions,
  and authentication audit metadata
- `app_core`: profile and currency, timezone, locale, week, weekend, history,
  and onboarding preferences
- `app_salary`: salary settings, pay dates, rates, adjustments, periods,
  calculation snapshots, actual amounts, and notes
- `app_work`: work dates, times, durations, rates, holidays, calculated
  amounts, and notes
- `app_finance`: account names/types/currencies/opening balances, categories,
  transactions, counterparties, macros, held amounts, debts, and notes

Theme, locale, home-report range, protected-amount, and app-lock choices also
use on-device SharedPreferences. The account-deletion flow clears those values
after the server confirms deletion.

Quick login is separately opt-in. After a fresh password check and device-owner
authentication, the app stores the user's email and password in
`flutter_secure_storage`: Android Keystore-backed encrypted storage or the iOS
Keychain, restricted to the current device. The credential is used only after
device authentication for a Supabase password sign-in. Disabling quick login,
changing the account email/password, or successful Finance Suit profile
deletion clears it. Android application backup is disabled so this credential
cannot be restored onto another device.

Optional amount protection and app lock invoke Android or iOS device
authentication. The OS evaluates the configured fingerprint, face, PIN,
pattern, password, or passcode and returns only an authentication result. The
app never receives or persists a biometric template or screen-lock secret.

The current dependency and platform-manifest audit found no advertising,
analytics, crash-reporting, bank-sync, payment, location, contacts, media,
camera, microphone, health, or device-id integration. Android requests Internet
and `USE_BIOMETRIC`; iOS declares the required Face ID purpose string. These
device-authentication declarations do not grant Finance Suit access to
biometric templates. Re-audit this file and the Play Data Safety form before
adding a new SDK or permission.

## In-app deletion design

1. The user opens **Settings > Delete account**.
2. The user reviews the warning, enters the current password, acknowledges
   permanent deletion, and confirms again.
3. The Flutter client reauthenticates with Supabase Auth.
4. The client invokes the `delete-account` Edge Function with its bearer JWT.
5. The function independently validates the JWT with Supabase Auth, requires a
   sign-in no more than five minutes old, and derives the user id from that
   verified account. It never accepts a caller-supplied user id.
6. The server-side Supabase client calls the service-role-only
   `app_core.delete_finance_suit_data` database function. It deletes every
   current Finance Suit product row in one transaction and deliberately
   preserves `auth.*` plus the legacy `public` schema.
   `supabase/tests/0008_account_deletion_test.sql` covers every current product
   table and asserts that the shared Auth user and legacy profile remain.
7. The app removes the local session and SharedPreferences values.

The Edge Function intentionally has gateway `verify_jwt = false` and performs
explicit `auth.admin.getUser` validation. This supports both legacy symmetric
JWTs and current asymmetric signing keys while keeping authorization inside
the function. The verified user id is the only id passed to the deletion RPC.
`SUPABASE_SERVICE_ROLE_KEY` is an automatically provisioned Edge Function
secret and must never be passed to Flutter or GitHub build defines.

Finance Suit and the legacy finance tracker share a Supabase Auth identity.
Deleting Finance Suit therefore signs the user out of this device and deletes
the Finance Suit portal profile/data only. Signing in again starts Finance Suit
onboarding as a new portal profile; deleted Finance Suit records are not
restored.

## Deployment

Apply the migration and deploy the backend before releasing an app build that
exposes the delete UI:

```bash
supabase link --project-ref kedjrbwnznvfqlzszawa
supabase db push --linked
supabase functions deploy delete-account --project-ref kedjrbwnznvfqlzszawa
```

For deployment without a local checkout, merge the migration and the Edge
Function to the branch the Supabase GitHub integration tracks. Supabase applies
pending migrations and deploys changed Edge Functions from that branch; confirm
both landed in the Supabase dashboard before releasing the app build.

Then test deletion with a dedicated disposable user containing data in every
feature. Verify the user remains in **Supabase Dashboard > Authentication >
Users**, the corresponding legacy `public.profiles` row remains, and no rows
remain for that user in the Finance Suit schemas.

## Legal documents

Canonical in-app English and Arabic documents are in `assets/legal`. Public,
static Google Play pages are in `legal`:

- `privacy-policy.html`
- `terms.html`
- `delete-account.html`

The current legal publisher is **Tareq Abdelwhap** and the privacy/support
address is **tarekian99@gmail.com**. Builds may override the same values with:

```text
--dart-define=LEGAL_DEVELOPER_NAME=...
--dart-define=PRIVACY_CONTACT_EMAIL=...
```

A custom domain is not required. Host these pages at any stable public HTTPS
location that needs no login and is accessible to Google reviewers. The
privacy and delete-account URLs are then entered in Play Console.

The legal text is tailored to the audited codebase, but it is not a substitute
for advice from a lawyer in the developer's jurisdiction.
