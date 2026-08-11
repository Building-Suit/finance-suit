# Database Architecture

## Financial product catalog

The global financial product catalog is public reference data for Credit Card
and BNPL products. It does not represent a user's facility and cannot create an
account. `app_finance.save_credit_facility` remains the only authoritative
Credit Card / BNPL account-creation path.

The catalog is stored in five layers:

- `financial_product_catalog` holds one normalized, case/whitespace-insensitive
  identity per global product.
- `financial_product_catalog_versions` holds immutable, content-hashed research
  versions. A changed result supersedes the current version; an unchanged check
  updates only the product's `last_checked_at`.
- `financial_product_catalog_sources` stores deduplicated source provenance for
  each version.
- `financial_product_catalog_aliases` stores trusted, exact normalized issuer
  and product alias pairs. An alias is scoped to the canonical product's
  account type and country and can map to only one canonical product.
- `catalog_research_queue` and `catalog_research_runs` provide atomic leases,
  retry state, and category-only curator/heartbeat audit records. Raw worker
  errors are never persisted because they may echo user data or credentials.

`catalog_configuration` centralizes the 30-day freshness window, five-item
curator batch, 30-minute lease, three-attempt retry limit, and authenticated
enqueue rate limit. Stale active products are queued for research and are never
presented as freshly verified. Retired products are excluded from automatic
search matches. A later Flutter catalog-first integration may fall back to the
existing `ai-card-research` Edge Function when no fresh result is available;
that app integration is outside this backend migration.

### Approved RPC boundary

Authenticated app users may call only `catalog_search`,
`enqueue_catalog_research`, and `get_catalog_research_contract`. Catalog table
DML is denied. `enqueue_catalog_research` is the app-user path: it requires
`auth.uid()`, rate-limits by user, restricts user-selectable reasons, and records
the caller in `requested_by`. `enqueue_catalog_research_automation` is the
trusted unattended curator/initial-seed path: it has no JWT dependency, records
`requested_by` as null, and is executable only by `service_role` or the database
owner. Both wrappers share the same private identity validation, normalization,
deduplication, and queue insertion helper.

Supabase Management and ChatGPT Scheduled Task SQL executes with
`current_user = postgres` while `auth.uid()` is null. Those callers must use
`enqueue_catalog_research_automation`; they must never use the authenticated
app-user enqueue RPC. Curator, lease, failure, heartbeat, stale-enqueue, and
operational summary RPCs are likewise restricted to trusted automation/database
administration. All functions revoke PostgreSQL's unsafe default `PUBLIC`
execute access, catalog tables have RLS enabled with no client mutation
policies, and Flutter must never carry the service-role key.

`upsert_catalog_research_result` is the sole curator research-result write
interface. It
checks `finance-card-catalog-v1`, validates the existing AI research enums and
source references, requires official provenance for verified values, computes
the content hash inside Postgres, and atomically completes the leased work. It
cannot call or mutate accounts, balances, transactions, statements,
installments, or `save_credit_facility`.

The catalog rejects PAN/card numbers, CVV/CVC, PIN, OTP, passwords, authentication
tokens, provider keys, user notes, personal limits and balances, transactions,
statements, and personal due amounts. `user_provided` is not a valid global
catalog field status. New v1 research must include all five product wrappers
(`issuerName`, `productName`, `tier`, `network`, and `currencyCode`) and all
seven account-form wrappers (`suggestedName`, `creditLimitMinor`,
`defaultDueDay`, `statementDay`, `minPaymentMethod`, `minPaymentFixedMinor`, and
`minPaymentBasisPoints`), even when a value is unknown. `suggestedName` belongs
only to `accountForm`, and `creditLimitMinor` must always be the exact global
unknown wrapper. The contract and validator obtain these lists from one private
definition. Existing immutable versions retain their historical payload shape.

`resolve_catalog_research_alias` is the separate trusted write path for a
leased identity that is an alias of an active canonical product. It derives the
alias from the queue item, verifies account type and country, completes the
lease without creating a product version, and records a sanitized curator run.
Exact alias pairs score confidently in `catalog_search`; canonical matching and
the Flutter acceptance threshold are unchanged. User input is never promoted
automatically.

### Scheduled Task operations

Connected curator Scheduled Tasks use only the following approved SQL surface.
They must
never issue direct DML or DDL:

```sql
select app_finance.catalog_status_summary();
select app_finance.get_catalog_research_contract();
select app_finance.enqueue_due_catalog_research();
select app_finance.enqueue_catalog_research_automation(...);
select app_finance.get_catalog_research_work(5);
select app_finance.resolve_catalog_research_alias('queue-uuid'::uuid, 'product-uuid'::uuid);
select app_finance.upsert_catalog_research_result('{...}'::jsonb);
select app_finance.fail_catalog_research_work('queue-uuid'::uuid, 'provider timeout');
```

`enqueue_catalog_research_automation` is a separate trusted administrative
surface for explicit initial-seed or curator enqueue operations. It is not part
of the recurring Scheduled Task loop. Management SQL may invoke it as
`postgres`; app users, `anon`, and `authenticated` cannot.
