-- Finance Suit global financial-product catalog v2.
--
-- This migration is intentionally ordered after the existing future-dated
-- catalog migrations. It was scaffolded with `supabase migration new` and
-- re-versioned only so a clean replay cannot run it before catalog v1 exists.

-- The foreign-currency recurring migration intentionally extended this RPC,
-- but CREATE OR REPLACE cannot replace a function after its arity changes.
-- Remove the obsolete overload so 13-argument callers resolve to the new
-- 14-argument function through its final default, then restore least privilege.
drop function if exists app_finance.save_recurring_rule(
  text,
  app_finance.recurring_rule_kind,
  bigint,
  app_finance.recurring_frequency,
  smallint,
  date,
  smallint,
  uuid,
  uuid,
  uuid,
  text,
  uuid,
  boolean
);
revoke all on function app_finance.save_recurring_rule(
  text,
  app_finance.recurring_rule_kind,
  bigint,
  app_finance.recurring_frequency,
  smallint,
  date,
  smallint,
  uuid,
  uuid,
  uuid,
  text,
  uuid,
  boolean,
  boolean
) from public, anon;
grant execute on function app_finance.save_recurring_rule(
  text,
  app_finance.recurring_rule_kind,
  bigint,
  app_finance.recurring_frequency,
  smallint,
  date,
  smallint,
  uuid,
  uuid,
  uuid,
  text,
  uuid,
  boolean,
  boolean
) to authenticated;

-- ---------------------------------------------------------------------------
-- Global issuer -> canonical product -> country-market identity
-- ---------------------------------------------------------------------------

create type app_finance.catalog_issuer_kind as enum (
  'bank', 'card_issuer', 'fintech_provider', 'other'
);

create table app_finance.catalog_issuers (
  id uuid primary key default gen_random_uuid(),
  canonical_name text not null check (char_length(canonical_name) between 1 and 160),
  normalized_name text not null,
  issuer_kind app_finance.catalog_issuer_kind not null default 'other',
  official_website text check (
    official_website is null or
    (char_length(official_website) <= 500 and official_website ~* '^https?://')
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (normalized_name)
);

create table app_finance.catalog_canonical_products (
  id uuid primary key default gen_random_uuid(),
  issuer_id uuid not null references app_finance.catalog_issuers (id),
  account_type app_finance.account_type not null
    check (account_type in ('credit_card', 'bnpl')),
  canonical_name text not null check (char_length(canonical_name) between 1 and 160),
  normalized_name text not null,
  tier text,
  network text,
  identity_key text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (identity_key)
);

create index catalog_canonical_products_issuer_idx
  on app_finance.catalog_canonical_products (issuer_id, account_type);

create table app_finance.catalog_issuer_markets (
  id uuid primary key default gen_random_uuid(),
  issuer_id uuid not null references app_finance.catalog_issuers (id),
  country_code text not null check (country_code ~ '^[A-Z]{2}$'),
  created_at timestamptz not null default now(),
  unique (issuer_id, country_code)
);

create table app_finance.catalog_issuer_market_versions (
  id uuid primary key default gen_random_uuid(),
  issuer_market_id uuid not null
    references app_finance.catalog_issuer_markets (id),
  version_number integer not null check (version_number > 0),
  contract_version text not null,
  rules_payload jsonb not null check (jsonb_typeof(rules_payload) = 'object'),
  content_hash text not null check (content_hash ~ '^[0-9a-f]{64}$'),
  effective_from date,
  effective_until date,
  verified_at timestamptz not null,
  superseded_at timestamptz,
  created_at timestamptz not null default now(),
  unique (issuer_market_id, version_number),
  check (
    effective_until is null or effective_from is null
    or effective_until >= effective_from
  )
);

create unique index catalog_issuer_market_current_version_key
  on app_finance.catalog_issuer_market_versions (issuer_market_id)
  where superseded_at is null;

create table app_finance.catalog_issuer_market_sources (
  id uuid primary key default gen_random_uuid(),
  version_id uuid not null
    references app_finance.catalog_issuer_market_versions (id),
  source_identifier text not null check (char_length(source_identifier) between 1 and 160),
  url text not null check (char_length(url) <= 2000 and url ~* '^https?://'),
  title text not null check (char_length(title) between 1 and 500),
  publisher text check (publisher is null or char_length(publisher) <= 200),
  official_domain boolean not null default false,
  source_type text not null,
  published_date date,
  revision_date date,
  effective_date date,
  checked_at timestamptz not null,
  created_at timestamptz not null default now(),
  unique (version_id, source_identifier),
  unique (version_id, url)
);

create table app_finance.catalog_version_verifications (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null
    references app_finance.financial_product_catalog (id),
  version_id uuid not null
    references app_finance.financial_product_catalog_versions (id),
  verified_at timestamptz not null default now(),
  source_checks jsonb not null default '[]'::jsonb
    check (jsonb_typeof(source_checks) = 'array'),
  created_at timestamptz not null default now()
);

create index catalog_version_verifications_product_idx
  on app_finance.catalog_version_verifications
  (product_id, verified_at desc);

alter table app_finance.financial_product_catalog
  add column canonical_product_id uuid
    references app_finance.catalog_canonical_products (id);

alter table app_finance.financial_product_catalog_sources
  add column publisher text
    check (publisher is null or char_length(publisher) <= 200),
  add column revision_date date,
  add column source_type text;

alter table app_finance.catalog_configuration
  add column curator_max_batch_size integer not null default 50
    check (curator_max_batch_size between 50 and 100);

update app_finance.catalog_configuration
set curator_batch_size = 25,
    curator_max_batch_size = 50,
    updated_at = now()
where singleton;

alter table app_finance.financial_product_catalog
  drop constraint if exists financial_product_catalog_network_check;
alter table app_finance.financial_product_catalog
  add constraint financial_product_catalog_network_check check (
    network is null or network in (
      'visa', 'mastercard', 'american_express', 'discover', 'jcb',
      'unionpay', 'mada', 'rupay', 'other', 'unknown'
    )
  );

alter table app_finance.catalog_research_queue
  drop constraint if exists catalog_research_queue_network_check;
alter table app_finance.catalog_research_queue
  add constraint catalog_research_queue_network_check check (
    network is null or network in (
      'visa', 'mastercard', 'american_express', 'discover', 'jcb',
      'unionpay', 'mada', 'rupay', 'other', 'unknown'
    )
  );

create or replace function app_private.catalog_canonical_product_key(
  p_issuer_id uuid,
  p_account_type app_finance.account_type,
  p_product_name text,
  p_tier text,
  p_network text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select p_issuer_id::text || '|' || p_account_type::text || '|' ||
    app_private.catalog_normalize_text(p_product_name) || '|' ||
    app_private.catalog_normalize_text(p_tier) || '|' ||
    app_private.catalog_normalize_text(p_network);
$$;

insert into app_finance.catalog_issuers (
  canonical_name, normalized_name, issuer_kind
)
select distinct on (app_private.catalog_normalize_text(p.issuer_name))
  p.issuer_name,
  app_private.catalog_normalize_text(p.issuer_name),
  case when p.account_type = 'bnpl'
    then 'fintech_provider'::app_finance.catalog_issuer_kind
    else 'bank'::app_finance.catalog_issuer_kind end
from app_finance.financial_product_catalog p
order by app_private.catalog_normalize_text(p.issuer_name), p.created_at, p.id;

insert into app_finance.catalog_canonical_products (
  issuer_id, account_type, canonical_name, normalized_name, tier, network,
  identity_key
)
select distinct on (
  app_private.catalog_canonical_product_key(
    i.id, p.account_type, p.product_name, p.tier, p.network
  )
)
  i.id,
  p.account_type,
  p.product_name,
  app_private.catalog_normalize_text(p.product_name),
  p.tier,
  p.network,
  app_private.catalog_canonical_product_key(
    i.id, p.account_type, p.product_name, p.tier, p.network
  )
from app_finance.financial_product_catalog p
join app_finance.catalog_issuers i
  on i.normalized_name = app_private.catalog_normalize_text(p.issuer_name)
order by app_private.catalog_canonical_product_key(
  i.id, p.account_type, p.product_name, p.tier, p.network
), p.created_at, p.id;

update app_finance.financial_product_catalog p
set canonical_product_id = cp.id
from app_finance.catalog_issuers i
join app_finance.catalog_canonical_products cp on cp.issuer_id = i.id
where i.normalized_name = app_private.catalog_normalize_text(p.issuer_name)
  and cp.identity_key = app_private.catalog_canonical_product_key(
    i.id, p.account_type, p.product_name, p.tier, p.network
  );

alter table app_finance.financial_product_catalog
  alter column canonical_product_id set not null;

insert into app_finance.catalog_issuer_markets (issuer_id, country_code)
select distinct cp.issuer_id, p.country_code
from app_finance.financial_product_catalog p
join app_finance.catalog_canonical_products cp
  on cp.id = p.canonical_product_id
on conflict (issuer_id, country_code) do nothing;

create or replace function app_private.set_catalog_issuer_identity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.canonical_name := regexp_replace(
    btrim(new.canonical_name), '[[:space:]]+', ' ', 'g'
  );
  new.normalized_name := app_private.catalog_normalize_text(new.canonical_name);
  new.official_website := nullif(btrim(new.official_website), '');
  return new;
end;
$$;

create trigger trg_catalog_issuer_identity
  before insert or update of canonical_name, official_website
  on app_finance.catalog_issuers
  for each row execute function app_private.set_catalog_issuer_identity();

create trigger trg_catalog_issuers_updated_at
  before update on app_finance.catalog_issuers
  for each row execute function app_private.set_updated_at();

create or replace function app_private.set_catalog_canonical_product_identity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.canonical_name := regexp_replace(
    btrim(new.canonical_name), '[[:space:]]+', ' ', 'g'
  );
  new.normalized_name := app_private.catalog_normalize_text(new.canonical_name);
  new.tier := nullif(regexp_replace(btrim(new.tier), '[[:space:]]+', ' ', 'g'), '');
  new.network := nullif(lower(btrim(new.network)), '');
  new.identity_key := app_private.catalog_canonical_product_key(
    new.issuer_id, new.account_type, new.canonical_name, new.tier, new.network
  );
  return new;
end;
$$;

create trigger trg_catalog_canonical_product_identity
  before insert or update of issuer_id, account_type, canonical_name, tier, network
  on app_finance.catalog_canonical_products
  for each row execute function app_private.set_catalog_canonical_product_identity();

create trigger trg_catalog_canonical_products_updated_at
  before update on app_finance.catalog_canonical_products
  for each row execute function app_private.set_updated_at();

create or replace function app_private.resolve_catalog_market_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_issuer_id uuid;
  v_canonical_id uuid;
begin
  insert into app_finance.catalog_issuers (
    canonical_name, normalized_name, issuer_kind
  ) values (
    new.issuer_name,
    app_private.catalog_normalize_text(new.issuer_name),
    case when new.account_type = 'bnpl'
      then 'fintech_provider'::app_finance.catalog_issuer_kind
      else 'bank'::app_finance.catalog_issuer_kind end
  )
  on conflict (normalized_name) do update
    set canonical_name = app_finance.catalog_issuers.canonical_name
  returning id into v_issuer_id;

  insert into app_finance.catalog_canonical_products (
    issuer_id, account_type, canonical_name, normalized_name, tier, network,
    identity_key
  ) values (
    v_issuer_id,
    new.account_type,
    new.product_name,
    app_private.catalog_normalize_text(new.product_name),
    new.tier,
    new.network,
    app_private.catalog_canonical_product_key(
      v_issuer_id, new.account_type, new.product_name, new.tier, new.network
    )
  )
  on conflict (identity_key) do update
    set canonical_name = app_finance.catalog_canonical_products.canonical_name
  returning id into v_canonical_id;

  insert into app_finance.catalog_issuer_markets (issuer_id, country_code)
  values (v_issuer_id, upper(btrim(new.country_code)))
  on conflict (issuer_id, country_code) do nothing;

  new.canonical_product_id := v_canonical_id;
  return new;
end;
$$;

create trigger trg_financial_product_catalog_resolve_identity
  before insert or update of account_type, country_code, issuer_name,
    product_name, tier, network
  on app_finance.financial_product_catalog
  for each row execute function app_private.resolve_catalog_market_identity();

comment on table app_finance.financial_product_catalog is
  'Country-specific market variants. Historical name retained for compatible app RPCs.';
comment on column app_finance.financial_product_catalog.canonical_product_id is
  'Links a country-market variant to its global canonical branded product.';

-- ---------------------------------------------------------------------------
-- Canonical JSON, unknown semantics, provenance, and immutability
-- ---------------------------------------------------------------------------

create or replace function app_private.catalog_normalize_jsonb(p_value jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case jsonb_typeof(p_value)
    when 'object' then coalesce((
      select jsonb_object_agg(e.key, app_private.catalog_normalize_jsonb(e.value))
      from jsonb_each(p_value - array[
        'checkedAt', 'verifiedAt', 'researchedAt', 'lastVerifiedDate'
      ]::text[]) e
    ), '{}'::jsonb)
    when 'array' then coalesce((
      select jsonb_agg(n.value order by n.value::text)
      from (
        select app_private.catalog_normalize_jsonb(a.value) value
        from jsonb_array_elements(p_value) a
      ) n
    ), '[]'::jsonb)
    else p_value
  end;
$$;

create or replace function app_private.catalog_payload_hash(p_value jsonb)
returns text
language sql
immutable
set search_path = ''
as $$
  select encode(
    extensions.digest(
      convert_to(app_private.catalog_normalize_jsonb(p_value)::text, 'UTF8'),
      'sha256'
    ),
    'hex'
  );
$$;

create or replace function app_private.catalog_unknown_value()
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select '{"value":null,"status":"unknown","confidence":null,"sourceIds":[]}'::jsonb;
$$;

create or replace function app_private.assert_catalog_v2_public_payload(
  p_research jsonb
)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_required_sections constant text[] := array[
    'product', 'accountForm', 'appearance', 'paymentCycle', 'fees',
    'purchaseInterest', 'installments', 'bnpl', 'eligibility',
    'publicLimits', 'rewards', 'benefits', 'digitalFeatures',
    'issuerMarketDefaults', 'sources', 'conflicts', 'unresolvedFields',
    'unsupportedFindings'
  ];
  v_required_product constant text[] := array[
    'issuerName', 'productName', 'tier', 'network', 'currencyCode',
    'officialProductUrl', 'officialApplicationUrl', 'issuerSupportUrl',
    'officialDescription', 'availabilityStatus', 'launchDate',
    'discontinuedDate'
  ];
  v_required_account_form constant text[] := array[
    'suggestedName', 'creditLimitMinor', 'defaultDueDay', 'statementDay',
    'gracePeriodDays', 'minPaymentMethod', 'minPaymentFixedMinor',
    'minPaymentBasisPoints', 'minPaymentPercentageBasis',
    'minPaymentIncludeInstallmentDues', 'minPaymentIncludeBankFees',
    'minPaymentIncludeOverdue', 'minPaymentFixedFloorMinor',
    'installmentDueDay', 'fxMarkupBasisPoints', 'colorHex'
  ];
  v_required_appearance constant text[] := array[
    'officialColorName', 'primaryColorHex', 'secondaryColorHex',
    'accentColorHexes', 'officialCardImageUrl', 'appearanceSourceMethod'
  ];
  v_required_payment constant text[] := array[
    'paymentDueRule', 'statementCycleRule', 'gracePeriod', 'minimumPayment'
  ];
  v_required_bnpl constant text[] := array[
    'repaymentFrequency', 'firstPaymentTiming', 'downPaymentRule',
    'publicSpendingLimits', 'merchantRestrictions', 'earlySettlementRule',
    'eligibilityNotes', 'virtualCardAvailable', 'physicalCardAvailable'
  ];
  v_required_eligibility constant text[] := array[
    'minimumAge', 'maximumAge', 'employmentRequirement', 'residency',
    'nationalityRestrictions', 'minimumIncomeMinor', 'incomeCurrency',
    'salaryTransferRequired', 'relationshipRequirement',
    'depositOrCollateralRequirement', 'secured', 'creditCriteriaNotes'
  ];
  v_required_limits constant text[] := array[
    'advertisedMinimumLimitMinor', 'advertisedMaximumLimitMinor',
    'purchaseLimitRule', 'cashWithdrawalRule', 'contactlessLimitRule'
  ];
  v_required_rewards constant text[] := array[
    'pointsRule', 'cashbackRule', 'milesRule', 'welcomeBonus',
    'redemptionNotes'
  ];
  v_required_digital constant text[] := array[
    'features', 'supportedWallets'
  ];
  v_required_issuer_defaults constant text[] := array[
    'paymentDueRule', 'statementCycleRule', 'gracePeriod',
    'minimumPayment', 'fxMarkupRule', 'eligibility'
  ];
  v_collection jsonb;
  v_required text[];
  v_name text;
  v_node jsonb;
  v_key text;
  v_source_ids text[];
  v_due_rule jsonb;
  v_statement_rule jsonb;
  v_grace_rule jsonb;
begin
  if jsonb_typeof(p_research) <> 'object'
    or not (p_research ?& v_required_sections)
    or exists (
      select 1 from jsonb_object_keys(p_research) k
      where k <> all(v_required_sections)
    ) then
    raise exception 'catalog v2 research sections are incomplete or unknown'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from app_private.catalog_json_nodes(p_research) n
    cross join lateral jsonb_object_keys(
      case when jsonb_typeof(n) = 'object' then n else '{}'::jsonb end
    ) k
    where lower(regexp_replace(k, '[_-]', '', 'g')) in (
      'pan', 'cardnumber', 'fullcardnumber', 'lastfourdigits', 'cvv', 'cvc',
      'pin', 'otp', 'password', 'usernotes', 'uservalue', 'approvedlimit',
      'creditlimitminor', 'currentbalance', 'outstandingbalance',
      'availablecredit', 'transaction', 'transactions', 'transactionhistory',
      'statementdata', 'statementbalance', 'currentdueamount',
      'personaldueamount', 'personaldue', 'authtoken', 'accesstoken',
      'providerapikey', 'servicerolekey', 'apikey'
    ) and not (
      lower(regexp_replace(k, '[_-]', '', 'g')) = 'creditlimitminor'
      and n = p_research -> 'accountForm'
    )
  ) then
    raise exception 'private or account-instance data is forbidden in the global catalog'
      using errcode = '22023';
  end if;

  if p_research::text ~ '([0-9][ -]?){13,19}'
    or p_research::text ~ 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
    or p_research::text ~ '(sb_secret_|sk-[A-Za-z0-9_-]{16,}|AIza[A-Za-z0-9_-]{20,})'
    or p_research::text ~ '"status"[[:space:]]*:[[:space:]]*"user_provided"' then
    raise exception 'credential-like, card-number-like, or user-provided content is forbidden'
      using errcode = '22023';
  end if;

  foreach v_name in array array[
    'product', 'accountForm', 'appearance', 'paymentCycle', 'bnpl',
    'eligibility', 'publicLimits', 'rewards', 'digitalFeatures',
    'issuerMarketDefaults'
  ] loop
    v_collection := p_research -> v_name;
    if jsonb_typeof(v_collection) <> 'object' then
      raise exception 'catalog v2 section % must be an object', v_name
        using errcode = '22023';
    end if;
    v_required := case v_name
      when 'product' then v_required_product
      when 'accountForm' then v_required_account_form
      when 'appearance' then v_required_appearance
      when 'paymentCycle' then v_required_payment
      when 'bnpl' then v_required_bnpl
      when 'eligibility' then v_required_eligibility
      when 'publicLimits' then v_required_limits
      when 'rewards' then v_required_rewards
      when 'digitalFeatures' then v_required_digital
      else v_required_issuer_defaults
    end;
    if not (v_collection ?& v_required)
      or exists (
        select 1 from jsonb_object_keys(v_collection) k
        where k <> all(v_required)
      ) then
      raise exception 'catalog v2 section % has incomplete or unknown fields', v_name
        using errcode = '22023';
    end if;
    for v_key, v_node in select key, value from jsonb_each(v_collection)
    loop
      if jsonb_typeof(v_node) <> 'object'
        or not (v_node ?& array['value', 'status', 'confidence', 'sourceIds'])
        or (select count(*) from jsonb_object_keys(v_node)) <> 4
        or jsonb_typeof(v_node -> 'sourceIds') <> 'array'
        or exists (
          select 1 from jsonb_array_elements(v_node -> 'sourceIds') s
          where jsonb_typeof(s) <> 'string'
        ) then
        raise exception 'malformed researched wrapper %.%', v_name, v_key
          using errcode = '22023';
      end if;
    end loop;
  end loop;

  if jsonb_typeof(p_research -> 'fees') <> 'array'
    or jsonb_array_length(p_research -> 'fees') > 100
    or jsonb_typeof(p_research -> 'benefits') <> 'array'
    or jsonb_array_length(p_research -> 'benefits') > 100
    or jsonb_typeof(p_research -> 'conflicts') <> 'array'
    or jsonb_array_length(p_research -> 'conflicts') > 50
    or jsonb_typeof(p_research -> 'sources') <> 'array'
    or jsonb_array_length(p_research -> 'sources') > 100
    or jsonb_typeof(p_research -> 'unresolvedFields') <> 'array'
    or jsonb_typeof(p_research -> 'unsupportedFindings') <> 'array'
    or jsonb_typeof(p_research #> '{purchaseInterest,rule}') <> 'object'
    or jsonb_typeof(p_research #> '{installments,tenors}') <> 'array'
    or jsonb_typeof(p_research #> '{installments,earlySettlementRule}') <> 'object'
    or jsonb_typeof(p_research #> '{installments,conversionRule}') <> 'object' then
    raise exception 'catalog v2 collection shape or bound is invalid'
      using errcode = '22023';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_research -> 'sources') s
    where jsonb_typeof(s) <> 'object'
      or not (s ?& array[
        'id', 'url', 'title', 'publisher', 'officialDomain', 'publicationDate',
        'revisionDate', 'effectiveDate', 'checkedAt', 'sourceType'
      ])
      or exists (
        select 1 from jsonb_object_keys(s) k
        where k not in (
          'id', 'url', 'title', 'publisher', 'officialDomain',
          'publicationDate', 'revisionDate', 'effectiveDate', 'checkedAt',
          'sourceType', 'contentHash'
        )
      )
      or coalesce(s ->> 'id', '') = ''
      or coalesce(s ->> 'url', '') !~* '^https?://'
      or coalesce(s ->> 'title', '') = ''
      or jsonb_typeof(s -> 'officialDomain') <> 'boolean'
      or s ->> 'sourceType' not in (
        'official_product_page', 'tariff_pdf', 'terms', 'faq', 'regulator',
        'official_card_asset', 'secondary_source'
      )
      or coalesce(s ->> 'checkedAt', '') !~
        '^\d{4}-\d{2}-\d{2}([T ][0-9:.+-]+Z?)?$'
  ) then
    raise exception 'malformed catalog v2 source provenance'
      using errcode = '22023';
  end if;

  if (select count(*) from jsonb_array_elements(p_research -> 'sources')) <>
    (select count(distinct s ->> 'id')
     from jsonb_array_elements(p_research -> 'sources') s) then
    raise exception 'duplicate catalog v2 source identifiers'
      using errcode = '22023';
  end if;

  select coalesce(array_agg(s ->> 'id'), '{}'::text[])
  into v_source_ids
  from jsonb_array_elements(p_research -> 'sources') s;

  for v_node in
    select n from app_private.catalog_json_nodes(p_research) n
    where jsonb_typeof(n) = 'object'
      and n ? 'status'
      and not (n ? 'competingValues')
  loop
    if v_node ->> 'status' not in (
      'verified', 'probable', 'conflicting', 'unknown', 'not_applicable'
    ) or not (v_node ? 'sourceIds')
      or jsonb_typeof(v_node -> 'sourceIds') <> 'array' then
      raise exception 'invalid catalog v2 claim status or provenance shape'
        using errcode = '22023';
    end if;
    if v_node ->> 'status' in ('verified', 'probable', 'conflicting')
      and coalesce(v_node ->> 'confidence', '') not in ('high', 'medium', 'low') then
      raise exception 'researched catalog v2 claims require confidence'
        using errcode = '22023';
    end if;
    if v_node ? 'value' and v_node ->> 'status' in ('unknown', 'not_applicable')
      and (
        v_node -> 'value' <> 'null'::jsonb
        or v_node -> 'confidence' <> 'null'::jsonb
        or jsonb_array_length(v_node -> 'sourceIds') <> 0
      ) then
      raise exception 'unknown and not-applicable values must use the exact empty wrapper'
        using errcode = '22023';
    end if;
    if v_node ->> 'status' in ('verified', 'probable', 'conflicting')
      and jsonb_array_length(v_node -> 'sourceIds') = 0 then
      raise exception 'researched catalog v2 claims require source provenance'
        using errcode = '22023';
    end if;
    if exists (
      select 1 from jsonb_array_elements_text(v_node -> 'sourceIds') sid
      where sid <> all(v_source_ids)
    ) then
      raise exception 'catalog v2 claim references an unknown source identifier'
        using errcode = '22023';
    end if;
    if v_node ->> 'status' = 'verified' and not exists (
      select 1
      from jsonb_array_elements_text(v_node -> 'sourceIds') sid
      join jsonb_array_elements(p_research -> 'sources') s
        on s ->> 'id' = sid
      where (s ->> 'officialDomain')::boolean
    ) then
      raise exception 'verified catalog v2 claims require official provenance'
        using errcode = '22023';
    end if;
  end loop;

  if p_research #> '{accountForm,creditLimitMinor}' <>
    app_private.catalog_unknown_value() then
    raise exception 'personal credit limit is forbidden in the global catalog'
      using errcode = '22023';
  end if;

  if p_research #>> '{product,issuerName,status}' in ('unknown', 'not_applicable')
    or p_research #>> '{product,productName,status}' in ('unknown', 'not_applicable')
    or jsonb_typeof(p_research #> '{product,issuerName,value}') <> 'string'
    or jsonb_typeof(p_research #> '{product,productName,value}') <> 'string' then
    raise exception 'resolved issuer and product identity values are required'
      using errcode = '22023';
  end if;

  if p_research #>> '{product,currencyCode,status}' not in ('unknown', 'not_applicable')
    and p_research #>> '{product,currencyCode,value}' !~ '^[A-Z]{3}$' then
    raise exception 'catalog currency must be ISO 4217'
      using errcode = '22023';
  end if;

  if p_research #>> '{appearance,primaryColorHex,status}' not in ('unknown', 'not_applicable')
    and p_research #>> '{appearance,primaryColorHex,value}' !~ '^#[0-9A-Fa-f]{6}$' then
    raise exception 'catalog primary color must be a six-digit hex color'
      using errcode = '22023';
  end if;
  if p_research #>> '{appearance,appearanceSourceMethod,status}' not in ('unknown', 'not_applicable')
    and p_research #>> '{appearance,appearanceSourceMethod,value}' not in (
      'official_declared', 'derived_from_official_asset', 'unknown'
    ) then
    raise exception 'invalid catalog appearance source method'
      using errcode = '22023';
  end if;

  v_due_rule := p_research #> '{paymentCycle,paymentDueRule,value}';
  if v_due_rule <> 'null'::jsonb and (
    jsonb_typeof(v_due_rule) <> 'object'
    or v_due_rule ->> 'type' not in (
      'fixed_day_of_month', 'days_after_statement', 'statement_defined',
      'customer_assigned', 'issuer_assigned', 'variable', 'unknown'
    )
  ) then
    raise exception 'invalid payment due rule'
      using errcode = '22023';
  end if;

  v_statement_rule := p_research #> '{paymentCycle,statementCycleRule,value}';
  if v_statement_rule <> 'null'::jsonb and (
    jsonb_typeof(v_statement_rule) <> 'object'
    or v_statement_rule ->> 'type' not in (
      'fixed_day_of_month', 'selectable_day', 'issuer_assigned',
      'end_of_month', 'relative_cycle', 'customer_assigned', 'variable',
      'unknown'
    )
  ) then
    raise exception 'invalid statement cycle rule'
      using errcode = '22023';
  end if;

  v_grace_rule := p_research #> '{paymentCycle,gracePeriod,value}';
  if v_grace_rule <> 'null'::jsonb and jsonb_typeof(v_grace_rule) <> 'object' then
    raise exception 'invalid grace period rule'
      using errcode = '22023';
  end if;

  if p_research #>> '{accountForm,defaultDueDay,status}' not in ('unknown', 'not_applicable')
    and (
      v_due_rule ->> 'type' <> 'fixed_day_of_month'
      or (p_research #>> '{accountForm,defaultDueDay,value}')::integer
        is distinct from (v_due_rule ->> 'fixedDay')::integer
    ) then
    raise exception 'defaultDueDay autofill requires an exact fixed payment rule'
      using errcode = '22023';
  end if;

  if p_research #>> '{accountForm,gracePeriodDays,status}' not in ('unknown', 'not_applicable')
    and (
      v_grace_rule ->> 'semantics' <> 'exact'
      or (p_research #>> '{accountForm,gracePeriodDays,value}')::integer
        is distinct from (v_grace_rule ->> 'exactDays')::integer
    ) then
    raise exception 'gracePeriodDays autofill requires exact grace semantics'
      using errcode = '22023';
  end if;

  if p_research #>> '{accountForm,statementDay,status}' not in ('unknown', 'not_applicable')
    and not (
      (v_statement_rule ->> 'type' = 'fixed_day_of_month'
        and (p_research #>> '{accountForm,statementDay,value}')::integer
          is not distinct from (v_statement_rule ->> 'fixedDay')::integer)
      or (v_statement_rule ->> 'type' = 'end_of_month'
        and (p_research #>> '{accountForm,statementDay,value}')::integer = 31)
    ) then
    raise exception 'statementDay autofill requires an exact statement cycle rule'
      using errcode = '22023';
  end if;

  if p_research #>> '{accountForm,colorHex,status}' not in ('unknown', 'not_applicable')
    and (
      p_research #>> '{appearance,primaryColorHex,status}' in ('unknown', 'not_applicable')
      or lower(p_research #>> '{accountForm,colorHex,value}')
        is distinct from lower(p_research #>> '{appearance,primaryColorHex,value}')
    ) then
    raise exception 'colorHex autofill requires the exact catalog appearance color'
      using errcode = '22023';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_research -> 'fees') f
    where jsonb_typeof(f) <> 'object'
      or not (f ?& array[
        'feeType', 'calculationType', 'frequency', 'trigger',
        'fixedAmountMinor', 'percentBasisPoints', 'percentBasis',
        'minimumMinor', 'maximumMinor', 'lookbackCycles', 'conditions',
        'effectiveFrom', 'effectiveUntil', 'exclusions', 'status',
        'confidence', 'sourceIds'
      ])
      or f ->> 'feeType' not in (
        'annual_membership', 'issuance', 'renewal', 'supplementary_card',
        'replacement', 'administration', 'insurance', 'stamp_tax',
        'foreign_transaction', 'cash_advance', 'international_cash_advance',
        'wallet_fee', 'statement_fee', 'late_payment', 'over_limit',
        'installment_conversion', 'early_settlement', 'processing', 'other'
      )
      or f ->> 'calculationType' not in (
        'fixed', 'percentage', 'fixed_plus_percentage', 'unknown',
        'not_applicable', 'conflicting'
      )
  ) then
    raise exception 'invalid catalog v2 fee rule'
      using errcode = '22023';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_research #> '{installments,tenors}') t
    where jsonb_typeof(t) <> 'object'
      or not (t ?& array[
        'fromMonths', 'toMonths', 'rateBasisPoints', 'ratePeriod',
        'interestMethod', 'conversionFee', 'processingFee',
        'minimumPurchaseMinor', 'maximumPurchaseMinor',
        'eligibleMerchantsOrCategories', 'installmentDueRule',
        'effectiveFrom', 'effectiveUntil', 'status', 'confidence', 'sourceIds'
      ])
      or (t ->> 'fromMonths')::integer < 1
      or (t ->> 'toMonths')::integer < (t ->> 'fromMonths')::integer
      or t ->> 'ratePeriod' not in ('monthly', 'annual', 'unknown', 'not_applicable')
      or t ->> 'interestMethod' not in ('flat', 'reducing', 'unknown', 'not_applicable')
  ) then
    raise exception 'invalid catalog v2 installment tenor rule'
      using errcode = '22023';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_research -> 'conflicts') c
    where jsonb_typeof(c) <> 'object'
      or not (c ?& array['field', 'status', 'competingValues'])
      or c ->> 'status' <> 'conflicting'
      or jsonb_typeof(c -> 'competingValues') <> 'array'
      or jsonb_array_length(c -> 'competingValues') < 2
      or exists (
        select 1 from jsonb_array_elements(c -> 'competingValues') v
        where jsonb_typeof(v) <> 'object'
          or not (v ?& array[
            'value', 'sourceIds', 'effectiveFrom', 'effectiveUntil', 'confidence'
          ])
          or jsonb_typeof(v -> 'sourceIds') <> 'array'
          or coalesce(v ->> 'confidence', '') not in ('high', 'medium', 'low')
          or exists (
            select 1 from jsonb_array_elements_text(v -> 'sourceIds') sid
            where sid <> all(v_source_ids)
          )
      )
  ) then
    raise exception 'invalid catalog v2 conflict representation'
      using errcode = '22023';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_research -> 'benefits') b
    where jsonb_typeof(b) <> 'object'
      or not (b ?& array[
        'type', 'title', 'description', 'status', 'confidence', 'sourceIds'
      ])
      or jsonb_typeof(b -> 'sourceIds') <> 'array'
  ) then
    raise exception 'invalid catalog v2 benefit claim'
      using errcode = '22023';
  end if;
end;
$$;

-- Keep legacy history readable while validating each newly inserted version
-- against the contract version it declares.
create or replace function app_private.validate_catalog_version_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.contract_version = 'finance-card-catalog-v2' then
    perform app_private.assert_catalog_v2_public_payload(new.research_payload);
  else
    perform app_private.assert_catalog_public_payload(new.research_payload);
  end if;
  return new;
end;
$$;

create or replace function app_private.protect_catalog_immutable_row()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'catalog historical records are immutable' using errcode = '55000';
end;
$$;

create or replace function app_private.protect_catalog_issuer_market_version()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'catalog issuer-market versions are immutable' using errcode = '55000';
  end if;
  if (to_jsonb(new) - array['superseded_at', 'effective_until']::text[])
     is distinct from
     (to_jsonb(old) - array['superseded_at', 'effective_until']::text[]) then
    raise exception 'catalog issuer-market version payloads are immutable'
      using errcode = '55000';
  end if;
  if old.superseded_at is not null and new is distinct from old then
    raise exception 'a superseded issuer-market version cannot be changed'
      using errcode = '55000';
  end if;
  return new;
end;
$$;

create trigger trg_catalog_issuer_market_versions_immutable
  before update or delete on app_finance.catalog_issuer_market_versions
  for each row execute function app_private.protect_catalog_issuer_market_version();

create trigger trg_catalog_issuer_market_sources_immutable
  before update or delete on app_finance.catalog_issuer_market_sources
  for each row execute function app_private.protect_catalog_immutable_row();

create trigger trg_catalog_version_verifications_immutable
  before update or delete on app_finance.catalog_version_verifications
  for each row execute function app_private.protect_catalog_immutable_row();

-- ---------------------------------------------------------------------------
-- Self-describing finance-card-catalog-v2 contract
-- ---------------------------------------------------------------------------

create or replace function app_private.catalog_contract_v2()
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'contractVersion', 'finance-card-catalog-v2',
    'identityArchitecture', jsonb_build_object(
      'levels', jsonb_build_array('issuer', 'canonicalProduct', 'countryMarketVariant'),
      'countryStandard', 'ISO 3166-1 alpha-2',
      'currencyStandard', 'ISO 4217',
      'marketRequired', true,
      'availabilityNeverDerivedFromIssuerHeadquarters', true,
      'accountTypes', jsonb_build_array('credit_card', 'bnpl'),
      'issuerKinds', jsonb_build_array('bank', 'card_issuer', 'fintech_provider', 'other'),
      'networks', jsonb_build_array(
        'visa', 'mastercard', 'american_express', 'discover', 'jcb',
        'unionpay', 'mada', 'rupay', 'other', 'unknown'
      )
    ),
    'productIdentity', jsonb_build_object(
      'required', jsonb_build_array(
        'accountType', 'countryCode', 'issuerName', 'productName'
      ),
      'optional', jsonb_build_array(
        'officialUrl', 'tier', 'network', 'currencyCode'
      ),
      'normalization', jsonb_build_array(
        'trim whitespace', 'collapse internal whitespace',
        'case-insensitive issuer/product identity',
        'uppercase country/currency', 'lowercase network'
      )
    ),
    'researchStatuses', jsonb_build_array(
      'resolved', 'ambiguous', 'insufficient_information', 'error'
    ),
    'fieldStatuses', jsonb_build_array(
      'verified', 'probable', 'conflicting', 'unknown', 'not_applicable'
    ),
    'confidenceLevels', jsonb_build_array('high', 'medium', 'low'),
    'unknownSemantics', jsonb_build_object(
      'exactWrapper', app_private.catalog_unknown_value(),
      'rules', jsonb_build_array(
        'unknown is never 0, empty string, false, a fake date, or a guessed average',
        'not_applicable uses the same empty wrapper with status not_applicable',
        'verified claims require an official-domain source',
        'the global curator must never submit user_provided'
      )
    ),
    'valueShape', jsonb_build_object(
      'required', jsonb_build_array('value', 'status', 'confidence', 'sourceIds'),
      'additionalProperties', false
    ),
    'researchPayload', jsonb_build_object(
      'requiredSections', jsonb_build_array(
        'product', 'accountForm', 'appearance', 'paymentCycle', 'fees',
        'purchaseInterest', 'installments', 'bnpl', 'eligibility',
        'publicLimits', 'rewards', 'benefits', 'digitalFeatures',
        'issuerMarketDefaults', 'sources', 'conflicts', 'unresolvedFields',
        'unsupportedFindings'
      ),
      'allPropertiesExact', true
    ),
    'productFields', jsonb_build_object(
      'requiredWrappers', jsonb_build_array(
        'issuerName', 'productName', 'tier', 'network', 'currencyCode',
        'officialProductUrl', 'officialApplicationUrl', 'issuerSupportUrl',
        'officialDescription', 'availabilityStatus', 'launchDate',
        'discontinuedDate'
      ),
      'availabilityStatuses', jsonb_build_array(
        'active', 'temporarily_unavailable', 'discontinued', 'unknown'
      )
    ),
    'appearanceShape', jsonb_build_object(
      'requiredWrappers', jsonb_build_array(
        'officialColorName', 'primaryColorHex', 'secondaryColorHex',
        'accentColorHexes', 'officialCardImageUrl', 'appearanceSourceMethod'
      ),
      'sourceMethods', jsonb_build_array(
        'official_declared', 'derived_from_official_asset', 'unknown'
      ),
      'derivedColorRule',
        'A visually estimated hex must use derived_from_official_asset, never official_declared',
      'accountColorSeparate', true
    ),
    'paymentCycleShape', jsonb_build_object(
      'requiredWrappers', jsonb_build_array(
        'paymentDueRule', 'statementCycleRule', 'gracePeriod', 'minimumPayment'
      ),
      'paymentDueRule', jsonb_build_object(
        'types', jsonb_build_array(
          'fixed_day_of_month', 'days_after_statement', 'statement_defined',
          'customer_assigned', 'issuer_assigned', 'variable', 'unknown'
        ),
        'fields', jsonb_build_array(
          'type', 'fixedDay', 'daysAfterStatement', 'minimumDaysAfterStatement',
          'maximumDaysAfterStatement', 'description', 'effectiveFrom',
          'effectiveUntil'
        )
      ),
      'statementCycleRule', jsonb_build_object(
        'types', jsonb_build_array(
          'fixed_day_of_month', 'selectable_day', 'issuer_assigned',
          'end_of_month', 'relative_cycle', 'customer_assigned', 'variable',
          'unknown'
        ),
        'fields', jsonb_build_array(
          'type', 'fixedDay', 'selectableDays', 'relativeDays', 'description',
          'effectiveFrom', 'effectiveUntil'
        )
      ),
      'gracePeriod', jsonb_build_object(
        'semantics', jsonb_build_array('exact', 'up_to', 'range', 'none', 'unknown'),
        'fields', jsonb_build_array(
          'semantics', 'exactDays', 'advertisedMaximumDays', 'minimumDays',
          'maximumDays', 'interestFree', 'requiresPreviousBalancePaidInFull',
          'appliesToPurchases', 'excludesCashAdvances',
          'appliesToInstallments', 'interestStartBehavior', 'notes'
        )
      ),
      'minimumPayment', jsonb_build_object(
        'methods', jsonb_build_array('full', 'fixed', 'percent', 'greater_of'),
        'fields', jsonb_build_array(
          'method', 'fixedAmountMinor', 'percentageBasisPoints',
          'percentageBasis', 'minimumFloorMinor', 'includesInstallments',
          'includesFees', 'includesOverdue', 'description'
        )
      ),
      'precedence', jsonb_build_array(
        'product_market_override', 'issuer_market_default', 'unknown'
      )
    ),
    'accountFormAutofill', jsonb_build_object(
      'requiredWrappers', jsonb_build_array(
        'suggestedName', 'creditLimitMinor', 'defaultDueDay', 'statementDay',
        'gracePeriodDays', 'minPaymentMethod', 'minPaymentFixedMinor',
        'minPaymentBasisPoints', 'minPaymentPercentageBasis',
        'minPaymentIncludeInstallmentDues', 'minPaymentIncludeBankFees',
        'minPaymentIncludeOverdue', 'minPaymentFixedFloorMinor',
        'installmentDueDay', 'fxMarkupBasisPoints', 'colorHex'
      ),
      'eligibility', jsonb_build_object(
        'suggestedName', 'verified_or_probable_identity',
        'creditLimitMinor', 'never',
        'defaultDueDay', 'verified exact fixed_day_of_month only',
        'statementDay', 'verified exact fixed day or end_of_month only',
        'gracePeriodDays', 'verified exact semantics only; never up_to or range',
        'minimumPaymentFields', 'verified semantically exact formula only',
        'fxMarkupBasisPoints', 'verified exact published rate only',
        'colorHex', 'verified official color or clearly marked official-asset derivation'
      ),
      'neverAutofill', jsonb_build_array(
        'actual credit limit', 'last four digits', 'current balance',
        'current due amount', 'customer-assigned statement date', 'notes'
      )
    ),
    'feeRuleShape', jsonb_build_object(
      'required', jsonb_build_array(
        'feeType', 'calculationType', 'frequency', 'trigger',
        'fixedAmountMinor', 'percentBasisPoints', 'percentBasis',
        'minimumMinor', 'maximumMinor', 'lookbackCycles', 'conditions',
        'effectiveFrom', 'effectiveUntil', 'exclusions', 'status',
        'confidence', 'sourceIds'
      ),
      'feeTypes', jsonb_build_array(
        'annual_membership', 'issuance', 'renewal', 'supplementary_card',
        'replacement', 'administration', 'insurance', 'stamp_tax',
        'foreign_transaction', 'cash_advance', 'international_cash_advance',
        'wallet_fee', 'statement_fee', 'late_payment', 'over_limit',
        'installment_conversion', 'early_settlement', 'processing', 'other'
      ),
      'calculationTypes', jsonb_build_array(
        'fixed', 'percentage', 'fixed_plus_percentage', 'unknown',
        'not_applicable', 'conflicting'
      ),
      'percentBases', jsonb_build_array(
        'statement_balance', 'outstanding_balance', 'credit_limit',
        'transaction_amount', 'highest_statement_due_lookback',
        'highest_daily_balance_lookback', 'remaining_principal',
        'remaining_outstanding'
      )
    ),
    'purchaseInterestShape', jsonb_build_object(
      'required', jsonb_build_array('rule'),
      'ruleFields', jsonb_build_array(
        'rateBasisPoints', 'ratePeriod', 'aprBasisPoints', 'interestMethod',
        'accrualMethod', 'interestStartRule', 'graceEligible', 'effectiveFrom',
        'effectiveUntil', 'notes'
      ),
      'ratePeriods', jsonb_build_array('daily', 'monthly', 'annual'),
      'conversionForbidden', true
    ),
    'installmentShape', jsonb_build_object(
      'required', jsonb_build_array('tenors', 'earlySettlementRule', 'conversionRule'),
      'tenorRequired', jsonb_build_array(
        'fromMonths', 'toMonths', 'rateBasisPoints', 'ratePeriod',
        'interestMethod', 'conversionFee', 'processingFee',
        'minimumPurchaseMinor', 'maximumPurchaseMinor',
        'eligibleMerchantsOrCategories', 'installmentDueRule',
        'effectiveFrom', 'effectiveUntil', 'status', 'confidence', 'sourceIds'
      )
    ),
    'bnplShape', jsonb_build_object(
      'firstClassProductType', true,
      'requiredWrappers', jsonb_build_array(
        'repaymentFrequency', 'firstPaymentTiming', 'downPaymentRule',
        'publicSpendingLimits', 'merchantRestrictions', 'earlySettlementRule',
        'eligibilityNotes', 'virtualCardAvailable', 'physicalCardAvailable'
      )
    ),
    'eligibilityShape', jsonb_build_object(
      'requiredWrappers', jsonb_build_array(
        'minimumAge', 'maximumAge', 'employmentRequirement', 'residency',
        'nationalityRestrictions', 'minimumIncomeMinor', 'incomeCurrency',
        'salaryTransferRequired', 'relationshipRequirement',
        'depositOrCollateralRequirement', 'secured', 'creditCriteriaNotes'
      ),
      'neverApprovalPrediction', true
    ),
    'publicLimitsShape', jsonb_build_object(
      'requiredWrappers', jsonb_build_array(
        'advertisedMinimumLimitMinor', 'advertisedMaximumLimitMinor',
        'purchaseLimitRule', 'cashWithdrawalRule', 'contactlessLimitRule'
      ),
      'actualApprovedLimitForbidden', true
    ),
    'rewardsAndBenefitsShape', jsonb_build_object(
      'rewardWrappers', jsonb_build_array(
        'pointsRule', 'cashbackRule', 'milesRule', 'welcomeBonus',
        'redemptionNotes'
      ),
      'benefitClaimRequired', jsonb_build_array(
        'type', 'title', 'description', 'status', 'confidence', 'sourceIds'
      )
    ),
    'digitalFeaturesShape', jsonb_build_object(
      'requiredWrappers', jsonb_build_array('features', 'supportedWallets'),
      'knownFeatureExamples', jsonb_build_array(
        'apple_pay', 'google_pay', 'samsung_wallet', 'contactless',
        'virtual_card', 'physical_card', 'supplementary_cards', 'card_controls'
      ),
      'extensibleIdentifiers', true
    ),
    'issuerMarketDefaultsShape', jsonb_build_object(
      'requiredWrappers', jsonb_build_array(
        'paymentDueRule', 'statementCycleRule', 'gracePeriod',
        'minimumPayment', 'fxMarkupRule', 'eligibility'
      ),
      'scopeMustBeEstablishedBySource', true,
      'productOverrideWins', true
    ),
    'sourceShape', jsonb_build_object(
      'required', jsonb_build_array(
        'id', 'url', 'title', 'publisher', 'officialDomain',
        'publicationDate', 'revisionDate', 'effectiveDate', 'checkedAt',
        'sourceType'
      ),
      'optional', jsonb_build_array('contentHash'),
      'sourceTypes', jsonb_build_array(
        'official_product_page', 'tariff_pdf', 'terms', 'faq', 'regulator',
        'official_card_asset', 'secondary_source'
      ),
      'pageBodiesForbidden', true
    ),
    'conflictShape', jsonb_build_object(
      'required', jsonb_build_array('field', 'status', 'competingValues'),
      'status', 'conflicting',
      'competingValueRequired', jsonb_build_array(
        'value', 'sourceIds', 'effectiveFrom', 'effectiveUntil', 'confidence'
      ),
      'minimumCompetingValues', 2
    ),
    'discoveryCandidateShape', jsonb_build_object(
      'batchArgument', 'jsonb array',
      'required', jsonb_build_array(
        'accountType', 'countryCode', 'issuerName', 'productName'
      ),
      'optional', jsonb_build_array(
        'tier', 'network', 'currencyCode', 'officialUrl'
      ),
      'publicIdentityOnly', true
    ),
    'writeEnvelope', jsonb_build_object(
      'required', jsonb_build_array(
        'contractVersion', 'queueItemId', 'productIdentity',
        'researchStatus', 'research'
      ),
      'optional', jsonb_build_array('effectiveFrom')
    ),
    'resultPayload', jsonb_build_object(
      'contractVersion', 'finance-card-catalog-v2',
      'identity', 'productIdentity',
      'status', 'researchStatus',
      'data', 'researchPayload',
      'writer', 'app_finance.upsert_catalog_research_result(jsonb)',
      'unchangedVerificationCreatesNewVersion', false
    ),
    'queue', jsonb_build_object(
      'defaultLeaseBatch', 25,
      'hardMaximumLeaseBatch', 50,
      'transactionalSkipLocked', true,
      'leaseExpiryRecovery', true,
      'maximumAttempts', 3
    ),
    'forbiddenPrivateFields', jsonb_build_array(
      'actualCreditLimit', 'lastFourDigits', 'pan', 'cardNumber', 'cvv',
      'cvc', 'pin', 'otp', 'password', 'userNotes', 'currentBalance',
      'outstandingBalance', 'availableCredit', 'transactions',
      'statementData', 'currentDueAmount', 'personalEligibilityDecision',
      'customerSpecificRate', 'authToken', 'providerApiKey'
    )
  );
$$;

create or replace function app_finance.get_catalog_research_contract()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select app_private.catalog_contract_v2();
$$;

-- ---------------------------------------------------------------------------
-- Bounded global discovery and 25/50-item transactional leasing
-- ---------------------------------------------------------------------------

create or replace function app_private.enqueue_catalog_research_common(
  p_account_type app_finance.account_type,
  p_country_code text,
  p_issuer_name text,
  p_product_name text,
  p_tier text,
  p_network text,
  p_currency_code text,
  p_official_website text,
  p_reason app_finance.catalog_queue_reason,
  p_priority integer,
  p_requested_by uuid
)
returns table (
  queue_item_id uuid,
  queue_status app_finance.catalog_queue_status
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_identity text;
  v_product_id uuid;
  v_work_key text;
  v_id uuid;
  v_status app_finance.catalog_queue_status;
begin
  if p_account_type not in ('credit_card', 'bnpl')
    or upper(btrim(coalesce(p_country_code, ''))) !~ '^[A-Z]{2}$'
    or char_length(btrim(coalesce(p_issuer_name, ''))) not between 1 and 160
    or char_length(btrim(coalesce(p_product_name, ''))) not between 1 and 160
    or (p_tier is not null and char_length(btrim(p_tier)) > 120)
    or (p_currency_code is not null
      and upper(btrim(p_currency_code)) !~ '^[A-Z]{3}$')
    or (p_network is not null and lower(btrim(p_network)) not in (
      'visa', 'mastercard', 'american_express', 'discover', 'jcb',
      'unionpay', 'mada', 'rupay', 'other', 'unknown'
    ))
    or (p_official_website is not null and (
      char_length(btrim(p_official_website)) > 500
      or btrim(p_official_website) !~* '^https?://'
    )) then
    raise exception 'invalid public product identity' using errcode = '22023';
  end if;

  v_identity := app_private.catalog_identity_key(
    p_account_type, p_country_code, p_issuer_name, p_product_name,
    p_tier, p_network, p_currency_code
  );

  select p.id into v_product_id
  from app_finance.financial_product_catalog p
  where p.identity_key = v_identity;

  v_work_key := case when v_product_id is null
    then 'identity:' || v_identity
    else 'product:' || v_product_id::text end;

  select q.id, q.status into v_id, v_status
  from app_finance.catalog_research_queue q
  where q.work_key = v_work_key and q.status in ('queued', 'leased')
  order by q.created_at, q.id
  limit 1;

  if v_id is null then
    begin
      insert into app_finance.catalog_research_queue (
        product_id, account_type, country_code, issuer_name, official_website,
        product_name, tier, network, currency_code, identity_key, work_key,
        reason, priority, requested_by
      ) values (
        v_product_id,
        p_account_type,
        upper(btrim(p_country_code)),
        regexp_replace(btrim(p_issuer_name), '[[:space:]]+', ' ', 'g'),
        nullif(btrim(p_official_website), ''),
        regexp_replace(btrim(p_product_name), '[[:space:]]+', ' ', 'g'),
        nullif(regexp_replace(btrim(p_tier), '[[:space:]]+', ' ', 'g'), ''),
        nullif(lower(btrim(p_network)), ''),
        nullif(upper(btrim(p_currency_code)), ''),
        v_identity,
        v_work_key,
        p_reason,
        greatest(-1000, least(1000, coalesce(p_priority, 0))),
        p_requested_by
      )
      returning id, status into v_id, v_status;
    exception when unique_violation then
      select q.id, q.status into v_id, v_status
      from app_finance.catalog_research_queue q
      where q.work_key = v_work_key and q.status in ('queued', 'leased')
      order by q.created_at, q.id
      limit 1;
    end;
  end if;

  return query select v_id, v_status;
end;
$$;

create or replace function app_finance.enqueue_catalog_discovery_candidates(
  p_candidates jsonb,
  p_priority integer default 0
)
returns table (
  candidate_index integer,
  queue_item_id uuid,
  queue_status app_finance.catalog_queue_status
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_candidate jsonb;
  v_index integer := 0;
  v_result record;
begin
  if jsonb_typeof(p_candidates) <> 'array'
    or jsonb_array_length(p_candidates) < 1
    or jsonb_array_length(p_candidates) > 50 then
    raise exception 'discovery candidates must be a JSON array containing 1 to 50 items'
      using errcode = '22023';
  end if;

  for v_candidate in select value from jsonb_array_elements(p_candidates)
  loop
    v_index := v_index + 1;
    if jsonb_typeof(v_candidate) <> 'object'
      or not (v_candidate ?& array[
        'accountType', 'countryCode', 'issuerName', 'productName'
      ])
      or exists (
        select 1 from jsonb_object_keys(v_candidate) k
        where k not in (
          'accountType', 'countryCode', 'issuerName', 'productName',
          'tier', 'network', 'currencyCode', 'officialUrl'
        )
      ) then
      raise exception 'invalid discovery candidate at index %', v_index
        using errcode = '22023';
    end if;

    if exists (
      select 1
      from app_private.catalog_json_nodes(v_candidate) n
      cross join lateral jsonb_object_keys(
        case when jsonb_typeof(n) = 'object' then n else '{}'::jsonb end
      ) k
      where lower(regexp_replace(k, '[_-]', '', 'g')) in (
        'pan', 'cardnumber', 'lastfourdigits', 'cvv', 'cvc', 'pin', 'otp',
        'password', 'creditlimit', 'balance', 'dueamount', 'usernotes',
        'transaction', 'statement', 'authtoken', 'apikey'
      )
    ) then
      raise exception 'private data is forbidden in discovery candidates'
        using errcode = '22023';
    end if;

    begin
      select * into v_result
      from app_private.enqueue_catalog_research_common(
        (v_candidate ->> 'accountType')::app_finance.account_type,
        v_candidate ->> 'countryCode',
        v_candidate ->> 'issuerName',
        v_candidate ->> 'productName',
        v_candidate ->> 'tier',
        v_candidate ->> 'network',
        v_candidate ->> 'currencyCode',
        v_candidate ->> 'officialUrl',
        'new_product',
        p_priority,
        null
      );
    exception when invalid_text_representation then
      raise exception 'invalid discovery candidate at index %', v_index
        using errcode = '22023';
    end;

    candidate_index := v_index;
    queue_item_id := v_result.queue_item_id;
    queue_status := v_result.queue_status;
    return next;
  end loop;
end;
$$;

create or replace function app_finance.get_catalog_research_work(
  p_limit integer default 25
)
returns table (
  queue_item_id uuid,
  reason app_finance.catalog_queue_reason,
  priority integer,
  attempt integer,
  leased_at timestamptz,
  lease_expires_at timestamptz,
  product_identity jsonb,
  contract_version text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limit integer;
  v_lease interval;
begin
  select least(
      greatest(coalesce(p_limit, c.curator_batch_size), 1),
      c.curator_max_batch_size
    ),
    c.lease_duration
  into v_limit, v_lease
  from app_finance.catalog_configuration c
  where c.singleton;

  return query
  with candidates as (
    select q.id
    from app_finance.catalog_research_queue q
    cross join app_finance.catalog_configuration cfg
    where q.available_at <= now()
      and q.attempts < cfg.max_attempts
      and (
        q.status = 'queued'
        or (q.status = 'leased' and q.lease_expires_at <= now())
      )
    order by q.priority desc, q.available_at, q.created_at, q.id
    for update of q skip locked
    limit v_limit
  ), leased as (
    update app_finance.catalog_research_queue q
    set status = 'leased',
        leased_at = now(),
        lease_expires_at = now() + v_lease,
        attempts = q.attempts + 1,
        last_error = null
    from candidates c
    where q.id = c.id
    returning q.*
  )
  select
    l.id,
    l.reason,
    l.priority,
    l.attempts,
    l.leased_at,
    l.lease_expires_at,
    jsonb_build_object(
      'accountType', l.account_type,
      'countryCode', l.country_code,
      'issuerName', l.issuer_name,
      'officialUrl', l.official_website,
      'productName', l.product_name,
      'tier', l.tier,
      'network', l.network,
      'currencyCode', l.currency_code
    ),
    'finance-card-catalog-v2'::text
  from leased l
  order by l.priority desc, l.created_at, l.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- The sole scheduled-agent research-result writer
-- ---------------------------------------------------------------------------

create or replace function app_finance.upsert_catalog_research_result(
  p_payload jsonb
)
returns table (
  product_id uuid,
  version_id uuid,
  changed boolean,
  version_number integer,
  queue_status app_finance.catalog_queue_status
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_queue app_finance.catalog_research_queue%rowtype;
  v_identity jsonb;
  v_research jsonb;
  v_research_status app_finance.catalog_research_status;
  v_account_type app_finance.account_type;
  v_country_code text;
  v_issuer_name text;
  v_product_name text;
  v_tier text;
  v_network text;
  v_currency_code text;
  v_official_url text;
  v_identity_key text;
  v_product_id uuid;
  v_version_id uuid;
  v_version_number integer;
  v_current app_finance.financial_product_catalog_versions%rowtype;
  v_hash text;
  v_now timestamptz := now();
  v_source jsonb;
  v_changed boolean := false;
  v_alias_id uuid;
  v_issuer_market_id uuid;
  v_issuer_market_current app_finance.catalog_issuer_market_versions%rowtype;
  v_issuer_market_version_id uuid;
  v_issuer_market_hash text;
  v_issuer_defaults jsonb;
begin
  if jsonb_typeof(p_payload) <> 'object'
    or not (p_payload ?& array[
      'contractVersion', 'queueItemId', 'productIdentity',
      'researchStatus', 'research'
    ])
    or exists (
      select 1 from jsonb_object_keys(p_payload) k
      where k not in (
        'contractVersion', 'queueItemId', 'productIdentity',
        'researchStatus', 'research', 'effectiveFrom'
      )
    ) then
    raise exception 'malformed catalog v2 write envelope' using errcode = '22023';
  end if;

  if p_payload ->> 'contractVersion' <> 'finance-card-catalog-v2' then
    raise exception 'unsupported catalog research contract version'
      using errcode = '22023';
  end if;
  if coalesce(p_payload ->> 'queueItemId', '') !~*
    '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception 'valid queueItemId is required' using errcode = '22023';
  end if;

  select * into v_queue
  from app_finance.catalog_research_queue q
  where q.id = (p_payload ->> 'queueItemId')::uuid
  for update;
  if not found or v_queue.status <> 'leased' then
    raise exception 'queue item is not leased' using errcode = '55000';
  end if;
  if v_queue.lease_expires_at <= v_now then
    raise exception 'queue item lease has expired' using errcode = '55000';
  end if;

  v_identity := p_payload -> 'productIdentity';
  v_research := p_payload -> 'research';
  if jsonb_typeof(v_identity) <> 'object'
    or jsonb_typeof(v_research) <> 'object'
    or not (v_identity ?& array[
      'accountType', 'countryCode', 'issuerName', 'productName'
    ])
    or exists (
      select 1 from jsonb_object_keys(v_identity) k
      where k not in (
        'accountType', 'countryCode', 'issuerName', 'productName',
        'tier', 'network', 'currencyCode', 'officialUrl'
      )
    ) then
    raise exception 'invalid catalog v2 product identity'
      using errcode = '22023';
  end if;

  begin
    v_account_type := (v_identity ->> 'accountType')::app_finance.account_type;
    v_research_status :=
      (p_payload ->> 'researchStatus')::app_finance.catalog_research_status;
  exception when invalid_text_representation then
    raise exception 'invalid catalog v2 enum value' using errcode = '22023';
  end;

  v_country_code := upper(btrim(coalesce(v_identity ->> 'countryCode', '')));
  v_issuer_name := regexp_replace(
    btrim(coalesce(v_identity ->> 'issuerName', '')), '[[:space:]]+', ' ', 'g'
  );
  v_product_name := regexp_replace(
    btrim(coalesce(v_identity ->> 'productName', '')), '[[:space:]]+', ' ', 'g'
  );
  v_tier := nullif(
    regexp_replace(btrim(v_identity ->> 'tier'), '[[:space:]]+', ' ', 'g'), ''
  );
  v_network := nullif(lower(btrim(v_identity ->> 'network')), '');
  v_currency_code := nullif(upper(btrim(v_identity ->> 'currencyCode')), '');
  v_official_url := nullif(btrim(v_identity ->> 'officialUrl'), '');

  if v_account_type not in ('credit_card', 'bnpl')
    or v_country_code !~ '^[A-Z]{2}$'
    or char_length(v_issuer_name) not between 1 and 160
    or char_length(v_product_name) not between 1 and 160
    or (v_tier is not null and char_length(v_tier) > 120)
    or (v_currency_code is not null and v_currency_code !~ '^[A-Z]{3}$')
    or (v_network is not null and v_network not in (
      'visa', 'mastercard', 'american_express', 'discover', 'jcb',
      'unionpay', 'mada', 'rupay', 'other', 'unknown'
    ))
    or (v_official_url is not null and (
      char_length(v_official_url) > 500 or v_official_url !~* '^https?://'
    )) then
    raise exception 'invalid public product identity' using errcode = '22023';
  end if;

  if v_account_type <> v_queue.account_type
    or v_country_code <> v_queue.country_code then
    raise exception 'researched market must match the leased account type and country'
      using errcode = '22023';
  end if;

  perform app_private.assert_catalog_v2_public_payload(v_research);

  if app_private.catalog_normalize_text(
      v_research #>> '{product,issuerName,value}'
    ) <> app_private.catalog_normalize_text(v_issuer_name)
    or app_private.catalog_normalize_text(
      v_research #>> '{product,productName,value}'
    ) <> app_private.catalog_normalize_text(v_product_name) then
    raise exception 'researched identity wrappers must match productIdentity'
      using errcode = '22023';
  end if;

  if v_research_status <> 'resolved' then
    update app_finance.catalog_research_queue q
    set status = 'completed',
        leased_at = null,
        lease_expires_at = null,
        last_error = null
    where q.id = v_queue.id;
    insert into app_finance.catalog_research_runs (
      task_name, run_type, status, completed_at, item_count,
      completed_count, summary
    ) values (
      'catalog-curator-v2', 'curator', 'completed', v_now, 1, 1,
      jsonb_build_object(
        'researchStatus', v_research_status,
        'queueItemId', v_queue.id
      )
    );
    return query select
      null::uuid,
      null::uuid,
      false,
      null::integer,
      'completed'::app_finance.catalog_queue_status;
    return;
  end if;

  v_identity_key := app_private.catalog_identity_key(
    v_account_type, v_country_code, v_issuer_name, v_product_name,
    v_tier, v_network, v_currency_code
  );

  if v_queue.product_id is not null then
    v_product_id := v_queue.product_id;
    if v_identity_key <> (
      select p.identity_key
      from app_finance.financial_product_catalog p
      where p.id = v_product_id
    ) then
      raise exception 'refresh work cannot change an existing market identity'
        using errcode = '22023';
    end if;
  else
    select p.id into v_product_id
    from app_finance.financial_product_catalog p
    where p.identity_key = v_identity_key;

    if v_product_id is null then
      insert into app_finance.financial_product_catalog (
        account_type, country_code, issuer_name, official_website,
        product_name, tier, network, currency_code, identity_key,
        status, last_checked_at, last_changed_at
      ) values (
        v_account_type, v_country_code, v_issuer_name, v_official_url,
        v_product_name, v_tier, v_network, v_currency_code, v_identity_key,
        'active', v_now, v_now
      )
      returning id into v_product_id;
    end if;

    if v_queue.identity_key <> v_identity_key then
      insert into app_finance.financial_product_catalog_aliases (
        product_id, account_type, country_code, issuer_alias, product_alias,
        normalized_issuer_alias, normalized_product_alias
      ) values (
        v_product_id, v_queue.account_type, v_queue.country_code,
        v_queue.issuer_name, v_queue.product_name, 'pending', 'pending'
      )
      on conflict (
        account_type, country_code, normalized_issuer_alias,
        normalized_product_alias
      ) do nothing
      returning id into v_alias_id;

      if v_alias_id is null and not exists (
        select 1
        from app_finance.financial_product_catalog_aliases a
        where a.account_type = v_queue.account_type
          and a.country_code = v_queue.country_code
          and a.normalized_issuer_alias =
            app_private.catalog_normalize_text(v_queue.issuer_name)
          and a.normalized_product_alias =
            app_private.catalog_normalize_text(v_queue.product_name)
          and a.product_id = v_product_id
      ) then
        raise exception 'discovery alias already maps to another canonical product'
          using errcode = '23505';
      end if;
    end if;
  end if;

  v_hash := app_private.catalog_payload_hash(v_research);
  select * into v_current
  from app_finance.financial_product_catalog_versions cv
  where cv.product_id = v_product_id and cv.superseded_at is null
  order by cv.version_number desc
  limit 1
  for update;

  if v_current.id is not null and v_current.content_hash = v_hash then
    update app_finance.financial_product_catalog p
    set last_checked_at = v_now
    where p.id = v_product_id;
    v_version_id := v_current.id;
    v_version_number := v_current.version_number;
  else
    v_changed := true;
    if v_current.id is not null then
      update app_finance.financial_product_catalog_versions cv
      set superseded_at = v_now,
          effective_until = greatest(
            v_current.effective_from,
            coalesce(
              nullif(p_payload ->> 'effectiveFrom', '')::date - 1,
              current_date
            )
          )
      where cv.id = v_current.id;
    end if;

    select coalesce(max(cv.version_number), 0) + 1
    into v_version_number
    from app_finance.financial_product_catalog_versions cv
    where cv.product_id = v_product_id;

    insert into app_finance.financial_product_catalog_versions (
      product_id, version_number, contract_version, research_status,
      research_payload, content_hash, effective_from, verified_at
    ) values (
      v_product_id,
      v_version_number,
      'finance-card-catalog-v2',
      v_research_status,
      v_research,
      v_hash,
      nullif(p_payload ->> 'effectiveFrom', '')::date,
      v_now
    )
    returning id into v_version_id;

    for v_source in
      select value from jsonb_array_elements(v_research -> 'sources')
    loop
      insert into app_finance.financial_product_catalog_sources (
        version_id, source_identifier, url, title, publisher,
        official_domain, source_type, published_date, revision_date,
        effective_date, content_hash, checked_at
      ) values (
        v_version_id,
        v_source ->> 'id',
        v_source ->> 'url',
        v_source ->> 'title',
        nullif(v_source ->> 'publisher', ''),
        (v_source ->> 'officialDomain')::boolean,
        v_source ->> 'sourceType',
        nullif(v_source ->> 'publicationDate', '')::date,
        nullif(v_source ->> 'revisionDate', '')::date,
        nullif(v_source ->> 'effectiveDate', '')::date,
        nullif(v_source ->> 'contentHash', ''),
        (v_source ->> 'checkedAt')::timestamptz
      );
    end loop;

    update app_finance.financial_product_catalog p
    set last_checked_at = v_now,
        last_changed_at = v_now,
        official_website = coalesce(v_official_url, p.official_website)
    where p.id = v_product_id;
  end if;

  insert into app_finance.catalog_version_verifications (
    product_id, version_id, verified_at, source_checks
  ) values (
    v_product_id,
    v_version_id,
    v_now,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'sourceId', s ->> 'id',
        'checkedAt', s ->> 'checkedAt'
      ) order by s ->> 'id')
      from jsonb_array_elements(v_research -> 'sources') s
    ), '[]'::jsonb)
  );

  select im.id into v_issuer_market_id
  from app_finance.financial_product_catalog p
  join app_finance.catalog_canonical_products cp
    on cp.id = p.canonical_product_id
  join app_finance.catalog_issuer_markets im
    on im.issuer_id = cp.issuer_id and im.country_code = p.country_code
  where p.id = v_product_id;

  v_issuer_defaults := v_research -> 'issuerMarketDefaults';
  v_issuer_market_hash := app_private.catalog_payload_hash(v_issuer_defaults);
  select * into v_issuer_market_current
  from app_finance.catalog_issuer_market_versions imv
  where imv.issuer_market_id = v_issuer_market_id
    and imv.superseded_at is null
  order by imv.version_number desc
  limit 1
  for update;

  if v_issuer_market_current.id is null
    or v_issuer_market_current.content_hash <> v_issuer_market_hash then
    if v_issuer_market_current.id is not null then
      update app_finance.catalog_issuer_market_versions imv
      set superseded_at = v_now,
          effective_until = greatest(
            v_issuer_market_current.effective_from,
            coalesce(
              nullif(p_payload ->> 'effectiveFrom', '')::date - 1,
              current_date
            )
          )
      where imv.id = v_issuer_market_current.id;
    end if;

    insert into app_finance.catalog_issuer_market_versions (
      issuer_market_id, version_number, contract_version, rules_payload,
      content_hash, effective_from, verified_at
    )
    select
      v_issuer_market_id,
      coalesce(max(imv.version_number), 0) + 1,
      'finance-card-catalog-v2',
      v_issuer_defaults,
      v_issuer_market_hash,
      nullif(p_payload ->> 'effectiveFrom', '')::date,
      v_now
    from app_finance.catalog_issuer_market_versions imv
    where imv.issuer_market_id = v_issuer_market_id
    returning id into v_issuer_market_version_id;

    for v_source in
      select value from jsonb_array_elements(v_research -> 'sources')
    loop
      insert into app_finance.catalog_issuer_market_sources (
        version_id, source_identifier, url, title, publisher,
        official_domain, source_type, published_date, revision_date,
        effective_date, checked_at
      ) values (
        v_issuer_market_version_id,
        v_source ->> 'id',
        v_source ->> 'url',
        v_source ->> 'title',
        nullif(v_source ->> 'publisher', ''),
        (v_source ->> 'officialDomain')::boolean,
        v_source ->> 'sourceType',
        nullif(v_source ->> 'publicationDate', '')::date,
        nullif(v_source ->> 'revisionDate', '')::date,
        nullif(v_source ->> 'effectiveDate', '')::date,
        (v_source ->> 'checkedAt')::timestamptz
      );
    end loop;
  end if;

  update app_finance.catalog_research_queue q
  set product_id = v_product_id,
      status = 'completed',
      leased_at = null,
      lease_expires_at = null,
      last_error = null
  where q.id = v_queue.id;

  insert into app_finance.catalog_research_runs (
    task_name, run_type, status, completed_at, item_count,
    completed_count, changed_count, summary
  ) values (
    'catalog-curator-v2', 'curator', 'completed', v_now, 1, 1,
    case when v_changed then 1 else 0 end,
    jsonb_build_object(
      'queueItemId', v_queue.id,
      'productId', v_product_id,
      'versionNumber', v_version_number
    )
  );

  return query select
    v_product_id,
    v_version_id,
    v_changed,
    v_version_number,
    'completed'::app_finance.catalog_queue_status;
end;
$$;

-- Product-market claims override issuer-market defaults. An explicit
-- not_applicable is an override; only unknown falls through.
create or replace function app_private.catalog_prefer_product_claim(
  p_product_claim jsonb,
  p_issuer_claim jsonb
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case
    when jsonb_typeof(p_product_claim) = 'object'
      and p_product_claim ->> 'status' <> 'unknown'
      then p_product_claim
    when jsonb_typeof(p_issuer_claim) = 'object'
      then p_issuer_claim
    else app_private.catalog_unknown_value()
  end;
$$;

create or replace function app_finance.catalog_resolved_public_configuration(
  p_catalog_product_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with market as (
    select
      p.id,
      p.canonical_product_id,
      p.country_code,
      pv.research_payload,
      im.id issuer_market_id
    from app_finance.financial_product_catalog p
    join app_finance.catalog_canonical_products cp
      on cp.id = p.canonical_product_id
    join app_finance.catalog_issuer_markets im
      on im.issuer_id = cp.issuer_id and im.country_code = p.country_code
    join lateral (
      select v.research_payload
      from app_finance.financial_product_catalog_versions v
      where v.product_id = p.id and v.superseded_at is null
      order by v.version_number desc
      limit 1
    ) pv on true
    where p.id = p_catalog_product_id and p.status = 'active'
  ), issuer_defaults as (
    select m.*, coalesce(iv.rules_payload, '{}'::jsonb) rules_payload
    from market m
    left join lateral (
      select v.rules_payload
      from app_finance.catalog_issuer_market_versions v
      where v.issuer_market_id = m.issuer_market_id
        and v.superseded_at is null
      order by v.version_number desc
      limit 1
    ) iv on true
  )
  select jsonb_build_object(
    'paymentDueRule', app_private.catalog_prefer_product_claim(
      d.research_payload #> '{paymentCycle,paymentDueRule}',
      d.rules_payload -> 'paymentDueRule'
    ),
    'statementCycleRule', app_private.catalog_prefer_product_claim(
      d.research_payload #> '{paymentCycle,statementCycleRule}',
      d.rules_payload -> 'statementCycleRule'
    ),
    'gracePeriod', app_private.catalog_prefer_product_claim(
      d.research_payload #> '{paymentCycle,gracePeriod}',
      d.rules_payload -> 'gracePeriod'
    ),
    'minimumPayment', app_private.catalog_prefer_product_claim(
      d.research_payload #> '{paymentCycle,minimumPayment}',
      d.rules_payload -> 'minimumPayment'
    ),
    'fxMarkupRule', app_private.catalog_prefer_product_claim(
      d.research_payload #> '{accountForm,fxMarkupBasisPoints}',
      d.rules_payload -> 'fxMarkupRule'
    ),
    'eligibility', case
      when exists (
        select 1
        from jsonb_each(d.research_payload -> 'eligibility') claim
        where claim.value ->> 'status' <> 'unknown'
      ) then d.research_payload -> 'eligibility'
      when jsonb_typeof(d.rules_payload -> 'eligibility') = 'object'
        then d.rules_payload -> 'eligibility'
      else '{}'::jsonb
    end
  )
  from issuer_defaults d
  where (select auth.uid()) is not null;
$$;

create or replace function app_finance.catalog_status_summary()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with cfg as (
    select * from app_finance.catalog_configuration where singleton
  ), current_versions as (
    select p.id, p.account_type, p.country_code, p.last_checked_at,
      v.contract_version, v.research_payload
    from app_finance.financial_product_catalog p
    left join lateral (
      select cv.contract_version, cv.research_payload
      from app_finance.financial_product_catalog_versions cv
      where cv.product_id = p.id and cv.superseded_at is null
      order by cv.version_number desc
      limit 1
    ) v on true
    where p.status = 'active'
  ), coverage as (
    select
      count(*) filter (
        where contract_version = 'finance-card-catalog-v2'
          and research_payload #>> '{appearance,primaryColorHex,status}'
            not in ('unknown', 'not_applicable')
      ) appearance,
      count(*) filter (
        where contract_version = 'finance-card-catalog-v2'
          and research_payload #>> '{paymentCycle,paymentDueRule,status}'
            not in ('unknown', 'not_applicable')
      ) payment_cycle,
      count(*) filter (
        where contract_version = 'finance-card-catalog-v2'
          and jsonb_array_length(research_payload -> 'fees') > 0
      ) fees,
      count(*) filter (
        where contract_version = 'finance-card-catalog-v2'
          and research_payload #>> '{eligibility,minimumAge,status}'
            not in ('unknown', 'not_applicable')
      ) eligibility,
      count(*) filter (
        where contract_version = 'finance-card-catalog-v2'
          and research_payload #>> '{rewards,pointsRule,status}'
            not in ('unknown', 'not_applicable')
      ) rewards,
      count(*) total
    from current_versions
  )
  select jsonb_build_object(
    'contractVersion', 'finance-card-catalog-v2',
    'issuersProviders', (select count(*) from app_finance.catalog_issuers),
    'canonicalProducts', (
      select count(*) from app_finance.catalog_canonical_products
    ),
    'productMarketVariants', (select count(*) from current_versions),
    'countriesCovered', (
      select count(distinct country_code) from current_versions
    ),
    'creditCards', (
      select count(*) from current_versions where account_type = 'credit_card'
    ),
    'bnplProducts', (
      select count(*) from current_versions where account_type = 'bnpl'
    ),
    'staleWork', (
      select count(*) from current_versions c, cfg
      where c.last_checked_at is null
        or c.last_checked_at < now() - cfg.freshness_window
    ),
    'queuedDiscoveryWork', (
      select count(*) from app_finance.catalog_research_queue
      where status = 'queued' and reason in ('new_product', 'initial_seed')
    ),
    'queuedWork', (
      select count(*) from app_finance.catalog_research_queue
      where status = 'queued'
    ),
    'leasedWork', (
      select count(*) from app_finance.catalog_research_queue
      where status = 'leased'
    ),
    'failedWork', (
      select count(*) from app_finance.catalog_research_queue
      where status = 'failed'
    ),
    'fieldsMissingResearch', jsonb_build_object(
      'appearance', greatest(coverage.total - coverage.appearance, 0),
      'paymentCycle', greatest(coverage.total - coverage.payment_cycle, 0),
      'fees', greatest(coverage.total - coverage.fees, 0),
      'eligibility', greatest(coverage.total - coverage.eligibility, 0),
      'rewards', greatest(coverage.total - coverage.rewards, 0)
    ),
    'coveragePercentages', jsonb_build_object(
      'appearance', case when coverage.total = 0 then 0
        else round(coverage.appearance * 100.0 / coverage.total, 1) end,
      'paymentCycle', case when coverage.total = 0 then 0
        else round(coverage.payment_cycle * 100.0 / coverage.total, 1) end,
      'fees', case when coverage.total = 0 then 0
        else round(coverage.fees * 100.0 / coverage.total, 1) end,
      'eligibility', case when coverage.total = 0 then 0
        else round(coverage.eligibility * 100.0 / coverage.total, 1) end,
      'rewards', case when coverage.total = 0 then 0
        else round(coverage.rewards * 100.0 / coverage.total, 1) end
    ),
    'batch', jsonb_build_object(
      'default', cfg.curator_batch_size,
      'maximum', cfg.curator_max_batch_size
    )
  )
  from cfg cross join coverage;
$$;

create or replace function app_finance.catalog_browse(
  p_account_type app_finance.account_type,
  p_country_code text default null,
  p_query text default null
)
returns table (
  catalog_product_id uuid,
  catalog_version_id uuid,
  account_type app_finance.account_type,
  country_code text,
  issuer_name text,
  official_website text,
  product_name text,
  tier text,
  network text,
  currency_code text,
  version_number integer,
  research_payload jsonb,
  sources jsonb,
  verified_at timestamptz,
  is_fresh boolean,
  age_days integer,
  match_quality integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    p.id,
    v.id,
    p.account_type,
    p.country_code,
    p.issuer_name,
    p.official_website,
    p.product_name,
    p.tier,
    p.network,
    p.currency_code,
    v.version_number,
    v.research_payload,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.source_identifier,
        'url', s.url,
        'title', s.title,
        'publisher', s.publisher,
        'officialDomain', s.official_domain,
        'publishedDate', s.published_date,
        'publicationDate', s.published_date,
        'revisionDate', s.revision_date,
        'effectiveDate', s.effective_date,
        'contentHash', s.content_hash,
        'checkedAt', s.checked_at,
        'sourceType', s.source_type
      ) order by s.source_identifier)
      from app_finance.financial_product_catalog_sources s
      where s.version_id = v.id
    ), '[]'::jsonb),
    v.verified_at,
    p.last_checked_at >= now() - cfg.freshness_window,
    greatest(
      0,
      floor(extract(epoch from (now() - p.last_checked_at)) / 86400)
    )::integer,
    100
  from app_finance.financial_product_catalog p
  cross join app_finance.catalog_configuration cfg
  join lateral (
    select candidate.*
    from app_finance.financial_product_catalog_versions candidate
    where candidate.product_id = p.id
      and candidate.superseded_at is null
    order by candidate.version_number desc
    limit 1
  ) v on true
  where (select auth.uid()) is not null
    and p.status = 'active'
    and p.account_type = p_account_type
    and (
      nullif(upper(btrim(coalesce(p_country_code, ''))), '') is null
      or p.country_code = upper(btrim(p_country_code))
    )
    and (
      nullif(app_private.catalog_normalize_text(p_query), '') is null
      or app_private.catalog_normalize_text(p.issuer_name)
          like '%' || app_private.catalog_normalize_text(p_query) || '%'
      or app_private.catalog_normalize_text(p.product_name)
          like '%' || app_private.catalog_normalize_text(p_query) || '%'
    )
  order by p.issuer_name, p.product_name, p.tier, p.country_code;
$$;

alter table app_finance.catalog_configuration
  add constraint catalog_configuration_batch_bounds
  check (curator_batch_size <= curator_max_batch_size);

-- ---------------------------------------------------------------------------
-- RLS and least-privilege RPC surface
-- ---------------------------------------------------------------------------

alter table app_finance.catalog_issuers enable row level security;
alter table app_finance.catalog_canonical_products enable row level security;
alter table app_finance.catalog_issuer_markets enable row level security;
alter table app_finance.catalog_issuer_market_versions enable row level security;
alter table app_finance.catalog_issuer_market_sources enable row level security;
alter table app_finance.catalog_version_verifications enable row level security;

revoke all on table app_finance.catalog_issuers
  from public, anon, authenticated, service_role;
revoke all on table app_finance.catalog_canonical_products
  from public, anon, authenticated, service_role;
revoke all on table app_finance.catalog_issuer_markets
  from public, anon, authenticated, service_role;
revoke all on table app_finance.catalog_issuer_market_versions
  from public, anon, authenticated, service_role;
revoke all on table app_finance.catalog_issuer_market_sources
  from public, anon, authenticated, service_role;
revoke all on table app_finance.catalog_version_verifications
  from public, anon, authenticated, service_role;
revoke all on table app_finance.financial_product_catalog_aliases
  from service_role;

revoke execute on function app_private.catalog_canonical_product_key(
  uuid, app_finance.account_type, text, text, text
) from public, anon, authenticated, service_role;
revoke execute on function app_private.set_catalog_issuer_identity()
  from public, anon, authenticated, service_role;
revoke execute on function app_private.set_catalog_canonical_product_identity()
  from public, anon, authenticated, service_role;
revoke execute on function app_private.resolve_catalog_market_identity()
  from public, anon, authenticated, service_role;
revoke execute on function app_private.catalog_normalize_jsonb(jsonb)
  from public, anon, authenticated, service_role;
revoke execute on function app_private.catalog_payload_hash(jsonb)
  from public, anon, authenticated, service_role;
revoke execute on function app_private.catalog_unknown_value()
  from public, anon, authenticated, service_role;
revoke execute on function app_private.assert_catalog_v2_public_payload(jsonb)
  from public, anon, authenticated, service_role;
revoke execute on function app_private.protect_catalog_immutable_row()
  from public, anon, authenticated, service_role;
revoke execute on function app_private.protect_catalog_issuer_market_version()
  from public, anon, authenticated, service_role;
revoke execute on function app_private.catalog_contract_v2()
  from public, anon, authenticated, service_role;
revoke execute on function app_private.catalog_prefer_product_claim(jsonb, jsonb)
  from public, anon, authenticated, service_role;

-- The invoker-rights contract function composes this read-only constant.
grant execute on function app_private.catalog_contract_v2()
  to authenticated, service_role;

revoke execute on function app_finance.get_catalog_research_contract()
  from public, anon;
grant execute on function app_finance.get_catalog_research_contract()
  to authenticated, service_role;

revoke execute on function app_finance.enqueue_catalog_discovery_candidates(
  jsonb, integer
) from public, anon, authenticated;
grant execute on function app_finance.enqueue_catalog_discovery_candidates(
  jsonb, integer
) to service_role;

revoke execute on function app_finance.get_catalog_research_work(integer)
  from public, anon, authenticated;
grant execute on function app_finance.get_catalog_research_work(integer)
  to service_role;

revoke execute on function app_finance.upsert_catalog_research_result(jsonb)
  from public, anon, authenticated;
grant execute on function app_finance.upsert_catalog_research_result(jsonb)
  to service_role;

revoke execute on function app_finance.enqueue_due_catalog_research()
  from public, anon, authenticated;
grant execute on function app_finance.enqueue_due_catalog_research()
  to service_role;

revoke execute on function app_finance.fail_catalog_research_work(uuid, text)
  from public, anon, authenticated;
grant execute on function app_finance.fail_catalog_research_work(uuid, text)
  to service_role;

revoke execute on function app_finance.catalog_status_summary()
  from public, anon, authenticated;
grant execute on function app_finance.catalog_status_summary()
  to service_role;

revoke execute on function app_finance.catalog_resolved_public_configuration(uuid)
  from public, anon, service_role;
grant execute on function app_finance.catalog_resolved_public_configuration(uuid)
  to authenticated;

revoke execute on function app_finance.catalog_browse(
  app_finance.account_type, text, text
) from public, anon, service_role;
grant execute on function app_finance.catalog_browse(
  app_finance.account_type, text, text
) to authenticated;

-- These v1 administration helpers are retained for migration compatibility,
-- but the scheduled v2 curator no longer has permission to call them.
revoke execute on function app_finance.enqueue_catalog_research_automation(
  app_finance.account_type, text, text, text, text, text, text, text,
  app_finance.catalog_queue_reason, integer
) from service_role;
revoke execute on function app_finance.resolve_catalog_research_alias(uuid, uuid)
  from service_role;
revoke execute on function app_finance.record_catalog_automation_heartbeat(text)
  from service_role;
revoke execute on function app_finance.catalog_search(
  app_finance.account_type, text, text, text, text, text, text
) from service_role;
revoke execute on function app_finance.enqueue_catalog_research(
  app_finance.account_type, text, text, text, text, text, text, text,
  app_finance.catalog_queue_reason, integer
) from service_role;

notify pgrst, 'reload schema';
