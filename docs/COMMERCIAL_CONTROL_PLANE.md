# Finance Suit commercial control plane

Finance Suit commercial state is stored in Supabase under `app_commercial`.
The canonical subject is `auth.users.id`, the same id used by
`app_core.profiles`.

## Plans and prices

| Plan | Initial price | Notes |
| --- | ---: | --- |
| `free` | `0 EGP` | Permanent baseline. Trial or Pro expiry never locks the app or deletes finance data. |
| `pro` monthly | `6000` minor units | Google Play product `finance_suit_pro`, base plan `pro-monthly-egp`. |
| `pro` yearly | `60000` minor units | Google Play product `finance_suit_pro`, base plan `pro-yearly-egp`. |

Published prices live in `app_commercial.plan_prices`; UI reads the catalog
instead of hardcoding display prices. Price changes should be drafted,
validated against Google Play, then published only when provider sync is true.

## Entitlement resolution

`app_commercial.resolve_effective_entitlement()` returns one effective result:

1. Active complimentary Super Admin Pro grant.
2. Active verified paid Pro subscription.
3. Open Early Access (a server-generated effective entitlement, not a grant).
4. Active timed Early Access or promotional grant.
5. Active standard trial grant.
6. Free.

Grants store `starts_at` and `ends_at`. Changing a campaign duration affects
future grants only. Expiration is timestamp-based; no scheduled job is required
for correctness.

## Monetization modes

`app_commercial.monetization_state` holds one validated, server-controlled
mode. It starts as `open_early_access`:

```text
OPEN EARLY ACCESS
       │ admin explicitly starts monetization
       ▼
TIMED EARLY ACCESS
       │ launch campaign completes / protected admin transition
       ▼
    PAID LIVE
```

Open Early Access resolves all eligible users to Pro with no expiration and
does not mutate their historical 90-day grants. `Start Monetization Cycle` is
a protected, audited and idempotent operation: it captures server time, opens
the configured 90-day timed campaign, and creates one launch grant per user.

An `admin_grant` with `ends_at = NULL` is permanent complimentary Pro. It is
independent from Google Play and remains effective in every mode until ended.
Finite complimentary grants use an authoritative `ends_at` timestamp.

## Early Access and trials

`early_access_2026` is active by default and grants Pro for 90 days. The
migration backfills existing `app_core.profiles` from the migration time.
`standard_pro_trial` is configured for 30 days and is used when Early Access is
disabled.

## RLS and admin security

Normal authenticated users can read the public catalog and their own grants and
subscriptions. They cannot write grants, subscriptions, pricing, campaigns, or
admin tables.

Commercial RLS policies use `app_private.is_commercial_admin(...)`. The private
schema grants authenticated callers only `USAGE` plus `EXECUTE` on that helper;
the helper can evaluate only the caller's own `auth.uid()`. Do not revoke that
narrow grant or ordinary entitlement reads will fail during policy evaluation.

Super Admins are stored in `app_commercial.platform_admins`. Do not hardcode an
email or UUID in app code. Bootstrap the first admin with a secure SQL command:

```sql
insert into app_commercial.platform_admins (user_id, role, status)
values ('<AUTH_USER_ID>', 'super_admin', 'active');
```

Verify:

```sql
select * from app_commercial.platform_admins where user_id = '<AUTH_USER_ID>';
```

Revoke:

```sql
update app_commercial.platform_admins
set status = 'revoked'
where user_id = '<AUTH_USER_ID>';
```

Admin mutations go through the `commercial-admin` Edge Function, which validates
the caller's JWT, checks `platform_admins`, performs the privileged mutation
server-side, and writes `app_commercial.audit_log`.

Billing-test access never grants Pro. Its admin action accepts an optional
operator reason and records a canonical audit reason when the admin portal does
not supply one.

## Google Play setup

Manual external setup still required:

1. In Play Console, create subscription product `finance_suit_pro`.
2. Create monthly base plan `pro-monthly-egp`, priced at EGP 60.00.
3. Create yearly base plan `pro-yearly-egp`, priced at EGP 600.00.
4. Configure license testers and test payment instruments.
5. Create a Google Cloud service account with Android Publisher API access.
6. Store its JSON in the Edge Function secret
   `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`.
7. Set `GOOGLE_PLAY_PACKAGE_NAME=com.buildingsuit.finance`.
8. Configure authenticated Pub/Sub RTDN delivery to `google-play-rtdn` as
   described below.
9. Mark provider sync as `synced` only after Play Console and Supabase config
   match.

Secrets must never be committed or exposed to Flutter/admin browser bundles.

## Edge Functions

| Function | Purpose |
| --- | --- |
| `google-play-billing` | Verifies/restores a purchase token with Android Publisher API, stores normalized subscription state, and returns effective entitlement. |
| `google-play-rtdn` | Stores append-only RTDN events idempotently and updates matched subscription lifecycle status. |
| `commercial-admin` | Super Admin overview, user/grant lifecycle, campaign changes, protected monetization start, audit log, and app configuration actions. |

## Google Play RTDN — Authenticated Pub/Sub Push

The production lifecycle is:

```text
Google Play
    ↓
Cloud Pub/Sub topic
    ↓
Authenticated push subscription (payload unwrapping off)
    ↓
Google-signed OIDC JWT
    ↓
Supabase google-play-rtdn (gateway JWT verification remains false)
    ↓
Cryptographic OIDC verification: Google issuer, exact audience, exact email
    ↓
purchaseToken (hashed for local correlation)
    ↓
Google Android Publisher subscriptionsv2.get
    ↓
Verified SubscriptionPurchaseV2 and shared normalization
    ↓
paid_subscriptions
    ↓
resolve_effective_entitlement()
```

The RTDN notification type is audit context only. The verified Google API
response is authoritative for subscription state. A notification received
before client verification is recorded as `verified_unmatched`; it cannot
create an ownerless or incorrectly owned subscription.

Required Edge Function secrets/configuration:

- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`: Google Android Publisher API service-account JSON.
- `GOOGLE_PLAY_PACKAGE_NAME`: `com.buildingsuit.finance`.
- `GOOGLE_PLAY_RTDN_EXPECTED_AUDIENCE`: exact function URL, for example
  `https://<PROJECT_REF>.supabase.co/functions/v1/google-play-rtdn`.
- `GOOGLE_PLAY_RTDN_PUSH_SERVICE_ACCOUNT_EMAIL`: dedicated Pub/Sub push identity,
  for example `finance-suit-rtdn-push@<GCP_PROJECT_ID>.iam.gserviceaccount.com`.

After deployment, the human operator must manually:

1. Create the dedicated push-auth service account.
2. Grant the required Pub/Sub service-agent token-creator permission.
3. Configure an authenticated push subscription using that identity.
4. Set the audience to the exact Supabase RTDN function URL.
5. Leave Pub/Sub payload unwrapping off.
6. Set the two RTDN OIDC Supabase secrets above.
7. Send a Play Console RTDN Test Notification.
8. Confirm the resulting `google_play` `rtdn_test` billing event before marking RTDN healthy.

These cloud and Play Console steps have not been performed by this repository
change. `GOOGLE_PLAY_RTDN_SHARED_SECRET` and the old custom header are not used.

## Downgrade behavior

Commercial state is separate from finance data. Trial expiration,
subscription cancellation, and grant revocation do not delete accounts,
transactions, salary settings, facilities, installments, recurring rules, or
macros. Feature gates should block unsafe new Pro actions while preserving
read-only visibility where practical.
