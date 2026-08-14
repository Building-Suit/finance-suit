# Financial Product Catalog v2 — Flutter Handoff

This is the exact Prompt 2 integration boundary. Prompt 1 changes the Supabase
contract and preserves a narrow compatibility adapter; it does not implement
the complete catalog-driven account editor.

## Read path

Use authenticated `app_finance.catalog_browse(account_type, country, query)`
for the picker. Each row keeps the existing identity/version columns and
returns a `finance-card-catalog-v2` `research_payload` plus normalized sources.
Use `catalog_resolved_public_configuration(product_id)` when the form needs the
effective product-override/issuer-default payment configuration.

Do not read normalized catalog tables directly. Do not expose or ship the
service-role key.

## Model changes required

Replace the legacy account-form-only DTO with v2 models for:

- issuer, canonical product, and country-market identity;
- official appearance and its source method;
- payment due rule, statement cycle rule, grace semantics, and minimum-payment
  formula;
- complete fee rules and purchase-interest rules;
- installment programs, conversion, and early-settlement terms;
- first-class BNPL terms;
- public eligibility and advertised public limits;
- rewards, bounded benefits, and extensible digital features;
- source provenance and public-source conflicts.

The existing `CardResearchResult` adapter temporarily understands v2 `fees`,
nested `installments.tenors`, and `publicationDate`. It intentionally filters
fee/tenor enum values the current form cannot represent and intentionally does
not turn v2 public-source conflicts into the old user-versus-official conflict
UI.

## Form behavior

The user chooses issuer/provider, then product, then country variant when
needed. Populate fields only when the contract marks the claim semantically
eligible and the client supports that exact rule:

- fixed due day only from verified `fixed_day_of_month`;
- statement day only from a verified exact fixed/end-of-month rule;
- grace days only from `semantics: exact`, never `up_to` or `range`;
- minimum-payment fields only from a complete exact formula;
- FX markup and interest without converting the published rate period;
- official color only from verified official appearance or a clearly marked
  derivation from an official asset.

Never autofill a customer's approved limit, last four digits, balances, current
due, customer-assigned dates, notes, approval outcome, or customer-specific
rate. Advertised limit fields are explanatory product facts, not account
values.

Once the user accepts or edits the form, persist through
`save_credit_facility`. The created facility becomes user-owned. Later catalog
refreshes must never overwrite it automatically, including its display color.

## UI changes required

- Add country-aware issuer/product search and an explicit stale/last-verified
  state.
- Show sources and unresolved/conflicting public claims before acceptance.
- Render rule semantics rather than reducing every rule to an integer day.
- Distinguish official appearance from the editable account color.
- Add all catalog fee types and calculation states to the rules UI before
  importing filtered v2 fees into an account.
- Add first-class BNPL terms rather than forcing BNPL into Credit Card labels.
- Keep a fallback/manual form when no fresh catalog result exists; unknown is a
  visible absence of knowledge, never zero or false.

## Contract discovery

Prompt 2 should read `get_catalog_research_contract()` rather than copying enum
lists from prose. The returned v2 object documents required sections, exact
unknown wrapper, enums, source/conflict shapes, discovery identity, result
envelope, autofill eligibility, and queue limits.
