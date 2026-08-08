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

1. Active paid Pro subscription.
2. Active Super Admin grant.
3. Active Early Access or promotional grant.
4. Active standard trial grant.
5. Free.

Grants store `starts_at` and `ends_at`. Changing a campaign duration affects
future grants only. Expiration is timestamp-based; no scheduled job is required
for correctness.

## Early Access and trials

`early_access_2026` is active by default and grants Pro for 90 days. The
migration backfills existing `app_core.profiles` from the migration time.
`standard_pro_trial` is configured for 30 days and is used when Early Access is
disabled.

## RLS and admin security

Normal authenticated users can read the public catalog and their own grants and
subscriptions. They cannot write grants, subscriptions, pricing, campaigns, or
admin tables.

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
8. Configure Pub/Sub RTDN delivery to `google-play-rtdn`.
9. Set `GOOGLE_PLAY_RTDN_SHARED_SECRET` and send it as
   `x-finance-suit-rtdn-secret` if using the simple shared-secret guard.
10. Mark provider sync as `synced` only after Play Console and Supabase config
    match.

Secrets must never be committed or exposed to Flutter/admin browser bundles.

## Edge Functions

| Function | Purpose |
| --- | --- |
| `google-play-billing` | Verifies/restores a purchase token with Android Publisher API, stores normalized subscription state, and returns effective entitlement. |
| `google-play-rtdn` | Stores append-only RTDN events idempotently and updates matched subscription lifecycle status. |
| `commercial-admin` | Super Admin overview, campaign changes, app config changes, and manual temporary Pro grants with audit logging. |

## Downgrade behavior

Commercial state is separate from finance data. Trial expiration,
subscription cancellation, and grant revocation do not delete accounts,
transactions, salary settings, facilities, installments, recurring rules, or
macros. Feature gates should block unsafe new Pro actions while preserving
read-only visibility where practical.
