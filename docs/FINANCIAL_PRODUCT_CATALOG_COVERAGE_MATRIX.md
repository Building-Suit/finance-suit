# Financial Product Catalog Coverage Matrix

This matrix is the design input for `finance-card-catalog-v2`. It classifies
every financially relevant Credit Card / BNPL field currently used by Finance
Suit before deciding whether the value belongs in the public catalog.

Classification:

- **A — issuer-market catalog**: public rule shared by an issuer/provider in a
  specific country.
- **B — product-market catalog**: public fact for one product in one country.
- **C — user/account instance**: private value belonging to one customer's
  facility or plan.
- **D — derived**: calculated by Finance Suit from private ledger data and
  account configuration.
- **E — unsupported/not persisted**: not safely or usefully persisted yet.

## Identity, market, and presentation

| Field or concept | Class | Catalog v2 treatment |
| --- | --- | --- |
| Issuer/provider legal or public name | A | Normalized issuer identity with aliases and provenance. |
| Issuer/provider kind | A | Bank, card issuer, fintech provider, or other. |
| Issuer headquarters | E | Not used to infer availability; may be added later as descriptive metadata. |
| Canonical branded product name | B | Canonical product identity beneath an issuer. |
| Product country | B | Required ISO 3166-1 alpha-2 market identity. |
| Product currency | B | ISO 4217 when known; null means unknown. |
| Tier and card network | B | Product identity discriminators; unknown remains null. |
| Product availability, launch, discontinuation | B | Effective-dated researched values. |
| Official product/application/support URLs | B | Researched metadata with sources. |
| Official description | B | Bounded summary, never a copied page body. |
| Official color and official card asset | B | Appearance facts with declared/derived/unknown source method. |
| `credit_facility_settings.color_hex` | C | User-selected display preference; never overwritten by catalog refresh. |
| Suggested initial account color | B | Safe autofill only from sufficiently verified catalog appearance. |
| Account name | C | User-owned; catalog may suggest a default name only. |
| Last four digits, PAN, CVV/CVC, PIN, OTP | C | Forbidden from every catalog payload and RPC. |

## Credit, balances, statements, and dates

| Field or concept | Class | Catalog v2 treatment |
| --- | --- | --- |
| Advertised minimum/maximum possible limit | B | Public-limit rule, clearly distinct from an approved limit. |
| Actual `credit_limit_minor` | C | Forbidden from catalog and never catalog-autofilled. |
| Opening owed, outstanding, available credit, utilization | D | Calculated from the user's ledger and actual limit. |
| Statement balance, minimum due, due amount, overdue amount | D | Calculated per user statement; forbidden from catalog. |
| Actual generated statement/due dates | D | Generated from user/account cycle state. |
| Fixed public payment day | A or B | Explicit `fixed_day_of_month` rule at issuer-market or product-market scope. |
| Days after statement | A or B | Explicit relative rule; never converted to a fabricated fixed day. |
| Issuer/customer assigned or variable due date | A or B | Explicit rule type; not autofilled as an exact day. |
| Public statement cycle rule | A or B | Fixed, selectable, assigned, end-of-month, relative, variable, or unknown. |
| User's actual statement and installment due day | C | Stored on the facility; catalog may initialize only exact compatible rules. |
| Reminder lead days | C | User preference; not catalog data. |
| Statement items and payment allocations | C | Private ledger data; forbidden from catalog. |

## Minimum payment, grace, and interest

| Field or concept | Class | Catalog v2 treatment |
| --- | --- | --- |
| Minimum-payment formula and basis | A or B | Structured rule with percentage/fixed/greater-of components and inclusions. |
| User's calculated minimum due | D | Derived from the statement and account rule. |
| Exact grace days | A or B | Exact only when the source establishes an exact contractual value. |
| Advertised “up to N days” | A or B | Maximum/advertised semantic; never treated as exact account days. |
| Grace eligibility and exclusions | A or B | Purchases, cash, installments, and paid-in-full conditions are explicit. |
| Purchase APR/monthly rate | A or B | Stored only in the published period; no invented conversion. |
| Accrual method and interest start | A or B | Structured product rule compatible with the rules engine. |
| Interest actually charged | D | Derived or bank-posted user ledger entry; never catalog data. |
| Customer-specific promotional rate | C | Private account override; forbidden from global catalog. |

## Fees and penalties

| Field or concept | Class | Catalog v2 treatment |
| --- | --- | --- |
| Annual, issuance, renewal, supplementary, replacement | A or B | Effective-dated fee claims. |
| Administration, insurance, stamp tax | A or B | Effective-dated fee claims. |
| Foreign transaction / FX markup | A or B | Explicit basis, condition, min/max, and source. |
| Domestic/international cash advance and wallet fee | A or B | Explicit trigger and calculation shape. |
| Statement, late, over-limit, installment conversion | A or B | Explicit trigger and calculation shape. |
| Early-settlement fee | A or B | Structured installment/fee rule. |
| Actual fee occurrence/reconciliation | C | User ledger and reconciliation data; forbidden from catalog. |
| Fixed, percentage, fixed + percentage, min/max/lookback | A or B | Reuses Finance Suit rule-engine concepts. |
| Unknown fee | A or B | Unknown claim, never zero. |

## Installments and BNPL

| Field or concept | Class | Catalog v2 treatment |
| --- | --- | --- |
| Public tenor ranges and pricing | A or B | Structured tenor claims with method, period, min purchase, and fees. |
| Installment due rule | A or B | Explicit fixed/relative/assigned/variable rule. |
| Early settlement/cancellation restrictions | A or B | Structured public rules. |
| Merchant/category eligibility | A or B | Bounded public restrictions. |
| User installment purchase price, down payment, plan balance | C | Private plan data; forbidden from catalog. |
| User installment schedule, paid count, reconciliation | C | Private plan data; forbidden from catalog. |
| Remaining principal, future interest, next installment | D | Calculated from the user's immutable plan schedule. |
| BNPL repayment frequency and first payment timing | B | First-class BNPL section. |
| Public BNPL spending/purchase limits | B | Public limits only, never the user's approved limit. |
| Virtual/physical BNPL card availability | B | Extensible public feature flags. |

## Eligibility, rewards, and digital features

| Field or concept | Class | Catalog v2 treatment |
| --- | --- | --- |
| Public age, employment, residency, nationality requirements | A or B | Structured eligibility facts with provenance. |
| Public minimum income and salary-transfer requirement | A or B | Product requirement, never an approval prediction. |
| Relationship, deposit/collateral, secured status | A or B | Structured public requirement. |
| Actual approval or personal eligibility decision | C | Forbidden from catalog. |
| Points, cashback, miles and earning rules | B | Common structured rewards fields. |
| Welcome bonus, lounge, insurance, protection, concierge | B | Bounded benefits claims rather than unbounded marketing text. |
| Apple Pay, Google Pay, Samsung Wallet, local wallets | A or B | Extensible feature identifiers; not one column per wallet. |
| Contactless, virtual/physical card, controls | B | Extensible digital/product features. |

## Provenance, conflicts, and derivation

| Field or concept | Class | Catalog v2 treatment |
| --- | --- | --- |
| Source URL/title/publisher/type/dates | A or B | Immutable version provenance plus verification checks. |
| Official-domain status | A or B | Required for `verified` claims. |
| Conflicting public values | A or B | Competing values, source IDs, effective dates, confidence, conflict status. |
| User-entered conflicting value | C | Kept in the account UI only; forbidden from global research results. |
| Verification timestamp only | D | Updates freshness/check history without creating a product version. |
| Resolved issuer default → product override | D | Product-market override wins, then issuer-market default, then unknown. |

The result is deliberately asymmetric: the catalog can initialize verified
public configuration, but the private facility remains authoritative after
creation. No catalog refresh changes a user's account automatically.
