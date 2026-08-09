# Database Architecture

## Financial product catalog

The global financial product catalog is public reference data for Credit Card
and BNPL products. It does not represent a user's facility and cannot create an
account. `app_finance.save_credit_facility` remains the only authoritative
Credit Card / BNPL account-creation path.

The catalog is stored in four layers:

- `financial_product_catalog` holds one normalized, case/whitespace-insensitive
  identity per global product.
- `financial_product_catalog_versions` holds immutable, content-hashed research
  versions. A changed result supersedes the current version; an unchanged check
  updates only the product's `last_checked_at`.
- `financial_product_catalog_sources` stores deduplicated source provenance for
  each version.
- `catalog_research_queue` and `catalog_research_runs` provide atomic leases,
  retry state, and sanitized curator/heartbeat audit records.

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

`upsert_catalog_research_result` is the sole curator result-write interface. It
checks `finance-card-catalog-v1`, validates the existing AI research enums and
source references, requires official provenance for verified values, computes
the content hash inside Postgres, and atomically completes the leased work. It
cannot call or mutate accounts, balances, transactions, statements,
installments, or `save_credit_facility`.

The catalog rejects PAN/card numbers, CVV/CVC, PIN, OTP, passwords, authentication
tokens, provider keys, user notes, personal limits and balances, transactions,
statements, and personal due amounts. `user_provided` is not a valid global
catalog field status; `creditLimitMinor` must be absent or explicitly
unknown/null.

### Scheduled Task operations

Connected Scheduled Tasks use only these SQL forms. They must never issue direct
DML or DDL:

```sql
select app_finance.record_catalog_automation_heartbeat('task-name');
select app_finance.catalog_status_summary();
select app_finance.get_catalog_research_contract();
select app_finance.enqueue_catalog_research_automation(
  'credit_card', 'EG', 'Issuer', 'Product',
  p_reason => 'initial_seed'
);
select app_finance.enqueue_due_catalog_research();
select app_finance.get_catalog_research_work(5);
select app_finance.upsert_catalog_research_result('{...}'::jsonb);
select app_finance.fail_catalog_research_work('queue-uuid'::uuid, 'sanitized error');
```
