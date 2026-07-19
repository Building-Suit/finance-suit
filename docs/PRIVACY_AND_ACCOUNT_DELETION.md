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

Theme, locale, and home-report range choices also use on-device
SharedPreferences. The account-deletion flow clears those values after the
server confirms deletion.

The current dependency and platform-manifest audit found no advertising,
analytics, crash-reporting, bank-sync, payment, location, contacts, media,
camera, microphone, health, or device-id integration. Android requests only
the Internet permission. Re-audit this file and the Play Data Safety form
before adding a new SDK or permission.

## In-app deletion design

1. The user opens **Settings > Delete account**.
2. The user reviews the warning, enters the current password, acknowledges
   permanent deletion, and confirms again.
3. The Flutter client reauthenticates with Supabase Auth.
4. The client invokes the `delete-account` Edge Function with its bearer JWT.
5. The function independently validates the JWT with Supabase Auth, requires a
   sign-in no more than five minutes old, and derives the user id from that
   verified account. It never accepts a caller-supplied user id.
6. The server-side Supabase client hard-deletes that Auth user. Every Finance
   Suit product table has an ownership foreign key to `auth.users` with
   `ON DELETE CASCADE`; `supabase/tests/0008_account_deletion_test.sql` covers
   every current product table.
7. The app removes the local session and SharedPreferences values.

The Edge Function intentionally has gateway `verify_jwt = false` and performs
explicit `auth.admin.getUser` validation. This supports both legacy symmetric
JWTs and current asymmetric signing keys while keeping authorization inside
the function. `SUPABASE_SERVICE_ROLE_KEY` is an automatically provisioned Edge
Function secret and must never be passed to Flutter or GitHub build defines.

## Deployment

Deploy the backend before releasing an app build that exposes the delete UI:

```bash
supabase functions deploy delete-account --project-ref kedjrbwnznvfqlzszawa
```

Then test deletion with a dedicated disposable user containing data in every
feature. Verify the user disappears from **Supabase Dashboard > Authentication
> Users** and no owned rows remain.

## Legal documents

Canonical in-app English and Arabic documents are in `assets/legal`. Public,
static Google Play pages are in `legal`:

- `privacy-policy.html`
- `terms.html`
- `delete-account.html`

Replace `{{DEVELOPER_NAME}}` and `{{PRIVACY_EMAIL}}` before publishing the
static pages. Builds may supply the same values with:

```text
--dart-define=LEGAL_DEVELOPER_NAME=...
--dart-define=PRIVACY_CONTACT_EMAIL=...
```

A custom domain is not required. Host these pages at any stable public HTTPS
location that needs no login and is accessible to Google reviewers. The
privacy and delete-account URLs are then entered in Play Console.

The legal text is tailored to the audited codebase, but it is not a substitute
for advice from a lawyer in the developer's jurisdiction.
