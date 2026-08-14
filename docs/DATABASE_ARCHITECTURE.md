# Database Architecture

## Financial product catalog v2

The global financial-product catalog is public reference data for Credit Card
and BNPL products. It never represents a customer's facility and cannot create
or update an account. `app_finance.save_credit_facility` remains the only
authoritative Credit Card / BNPL account-creation path.

### Identity and market layers

Catalog identity is normalized without destroying the historical v1 rows:

- `catalog_issuers` is one issuer/provider, independent of country.
- `catalog_canonical_products` is one branded Credit Card or BNPL program
  beneath an issuer.
- `catalog_issuer_markets` is the issuer's presence in one ISO 3166-1 alpha-2
  country.
- `financial_product_catalog` is the country-specific product-market variant.
  Its historical name is retained for app compatibility and it now references
  the canonical product.
- `financial_product_catalog_versions` and
  `financial_product_catalog_sources` retain immutable public product terms and
  their provenance.
- `catalog_issuer_market_versions` and
  `catalog_issuer_market_sources` version only rules whose source establishes
  issuer-wide scope in that country.
- `catalog_version_verifications` records freshness checks even when normalized
  content is unchanged.
- `catalog_research_queue` supplies transactional, expiring, retry-bounded
  leases. Discovery candidates deduplicate by normalized account type, country,
  issuer, product, tier, network, and currency.

The same product in two countries is two market variants. The same product
name from two issuers is two canonical products. An issuer's headquarters is
never used to infer product availability.

### Public catalog versus private account data

Contract `finance-card-catalog-v2` covers sourced public identity, product
metadata, official appearance, payment-cycle rules, grace semantics,
minimum-payment formulas, fees, purchase interest, installment programs, BNPL
terms, eligibility requirements, advertised public limits, rewards, benefits,
and digital features.

Private or derived values are forbidden: PAN/card numbers, last four digits,
CVV/CVC, PIN, OTP, credentials, a customer's approved limit, balances,
transactions, statement data, current due, notes, personal eligibility
decisions, and customer-specific rates. The legacy
`accountForm.creditLimitMinor` key remains only as the exact unknown wrapper so
old Flutter parsing cannot mistake an advertised maximum for a personal limit.

Official catalog appearance is also separate from
`credit_facility_settings.color_hex`. Catalog color can be declared by an
official source or explicitly marked as derived from an official asset. The
user's selected account color remains authoritative and catalog refresh never
overwrites it.

### Payment-cycle semantics and inheritance

Payment dates remain rules rather than fabricated day numbers. Supported due
rules include fixed day, days after statement, statement-defined,
issuer-assigned, customer-assigned, and variable. Only a verified exact
`fixed_day_of_month` rule is eligible to initialize `defaultDueDay`.

Statement cycles are modeled independently. Grace periods distinguish exact,
"up to", range, none, and unknown. An advertised maximum can never initialize
exact account grace days. Minimum-payment formulas preserve method, percentage
basis, fixed/floor components, and statement inclusions.

Resolution precedence is:

1. a sourced product-market override;
2. a sourced issuer-market default;
3. explicit unknown.

`not_applicable` is an explicit product override and does not fall through.
Rules are never inherited merely because two products share an issuer.

### Provenance and immutable history

Every non-unknown researched claim references one or more sources. Verified
claims require at least one official-domain source. Sources preserve ID, URL,
title, publisher, source type, official status, publication/revision/effective
dates, checked time, and an optional content hash; copied page bodies are not
stored.

Content hashing recursively removes volatile verification timestamps and sorts
JSON arrays. Property order, source order, and a fresh checked timestamp do not
create a fake business-data version. Changed content creates a new version and
supersedes, but never rewrites, the prior version. Unchanged content records a
new immutable verification event and updates market freshness.

### Discovery, leasing, and approved RPC boundary

The scheduled global curator may execute only:

```sql
select app_finance.catalog_status_summary();
select app_finance.get_catalog_research_contract();
select app_finance.enqueue_due_catalog_research();
select * from app_finance.enqueue_catalog_discovery_candidates('[...]'::jsonb, 0);
select * from app_finance.get_catalog_research_work(25);
select * from app_finance.upsert_catalog_research_result('{...}'::jsonb);
select app_finance.fail_catalog_research_work('queue-id'::uuid, 'sanitized reason');
```

Discovery accepts batches of 1–50 public identity objects. Leasing defaults to
25 and hard-clamps at 50, uses `FOR UPDATE SKIP LOCKED`, expires abandoned work,
increments attempts, and enforces the existing maximum-attempt policy.
`upsert_catalog_research_result(jsonb)` is the sole scheduled-agent write path.
The database, not the agent, resolves issuer/canonical/market identity and
decides between a changed version and unchanged verification.

Legacy app-user `catalog_search` and `enqueue_catalog_research` remain during
the Flutter transition. Legacy automation enqueue, alias resolution, heartbeat,
and direct catalog search are deliberately outside the scheduled v2 service-role
surface.

All catalog tables have RLS enabled and no client write policies. Direct table
privileges are revoked from `anon`, `authenticated`, and `service_role`; narrow
functions use explicit empty `search_path`, bounded inputs, validated JSON, and
no user-controlled SQL identifiers. Flutter must never carry a service-role
key.

The field-by-field ownership decision is recorded in
`FINANCIAL_PRODUCT_CATALOG_COVERAGE_MATRIX.md`. The temporary Flutter adapter and
the required Prompt 2 changes are recorded in
`FINANCIAL_PRODUCT_CATALOG_V2_APP_HANDOFF.md`.
