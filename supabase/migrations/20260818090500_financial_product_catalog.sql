-- Global, versioned Credit Card / BNPL product reference catalog.
--
-- This schema stores public product facts only. It is deliberately isolated
-- from user accounts and from save_credit_facility, which remains the sole
-- Credit Card / BNPL account-creation path.

create type app_finance.catalog_product_status as enum ('active', 'retired');
create type app_finance.catalog_research_status as enum (
  'resolved', 'ambiguous', 'insufficient_information', 'error'
);
create type app_finance.catalog_queue_reason as enum (
  'new_product', 'stale', 'user_requested', 'conflicting_sources',
  'missing_fields', 'source_changed', 'manual_review', 'initial_seed'
);
create type app_finance.catalog_queue_status as enum (
  'queued', 'leased', 'completed', 'failed'
);
create type app_finance.catalog_run_type as enum (
  'heartbeat', 'seed', 'curator', 'manual'
);
create type app_finance.catalog_run_status as enum (
  'running', 'completed', 'failed'
);

create table app_finance.catalog_configuration (
  singleton boolean primary key default true check (singleton),
  freshness_window interval not null default interval '30 days'
    check (freshness_window between interval '1 day' and interval '365 days'),
  curator_batch_size integer not null default 5
    check (curator_batch_size between 1 and 50),
  lease_duration interval not null default interval '30 minutes'
    check (lease_duration between interval '1 minute' and interval '24 hours'),
  max_attempts integer not null default 3 check (max_attempts between 1 and 20),
  enqueue_rate_limit_per_hour integer not null default 20
    check (enqueue_rate_limit_per_hour between 1 and 1000),
  updated_at timestamptz not null default now()
);

insert into app_finance.catalog_configuration (singleton) values (true);

create trigger trg_catalog_configuration_updated_at
  before update on app_finance.catalog_configuration
  for each row execute function app_private.set_updated_at();

create table app_finance.financial_product_catalog (
  id uuid primary key default gen_random_uuid(),
  account_type app_finance.account_type not null
    check (account_type in ('credit_card', 'bnpl')),
  country_code text not null check (country_code ~ '^[A-Z]{2}$'),
  issuer_name text not null check (char_length(issuer_name) between 1 and 160),
  official_website text check (
    official_website is null or
    (char_length(official_website) <= 500 and official_website ~* '^https?://')
  ),
  product_name text not null check (char_length(product_name) between 1 and 160),
  tier text check (tier is null or char_length(tier) between 1 and 120),
  network text check (
    network is null or network in ('visa', 'mastercard', 'other', 'unknown')
  ),
  currency_code text check (currency_code is null or currency_code ~ '^[A-Z]{3}$'),
  status app_finance.catalog_product_status not null default 'active',
  identity_key text not null,
  last_checked_at timestamptz,
  last_changed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index financial_product_catalog_identity_key
  on app_finance.financial_product_catalog (identity_key);
create index financial_product_catalog_search_idx
  on app_finance.financial_product_catalog
  (account_type, country_code, lower(issuer_name), lower(product_name));

create table app_finance.financial_product_catalog_versions (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references app_finance.financial_product_catalog (id),
  version_number integer not null check (version_number > 0),
  contract_version text not null,
  research_status app_finance.catalog_research_status not null,
  research_payload jsonb not null check (jsonb_typeof(research_payload) = 'object'),
  content_hash text not null check (content_hash ~ '^[0-9a-f]{64}$'),
  effective_from date,
  effective_until date,
  verified_at timestamptz not null,
  superseded_at timestamptz,
  created_at timestamptz not null default now(),
  unique (product_id, version_number),
  check (effective_until is null or effective_from is null or effective_until >= effective_from)
);

create unique index financial_product_catalog_current_version_key
  on app_finance.financial_product_catalog_versions (product_id)
  where superseded_at is null;

create table app_finance.financial_product_catalog_sources (
  id uuid primary key default gen_random_uuid(),
  version_id uuid not null references app_finance.financial_product_catalog_versions (id),
  source_identifier text not null check (char_length(source_identifier) between 1 and 160),
  url text not null check (char_length(url) <= 2000 and url ~* '^https?://'),
  title text not null check (char_length(title) between 1 and 500),
  official_domain boolean not null default false,
  published_date date,
  effective_date date,
  content_hash text check (content_hash is null or content_hash ~ '^[0-9a-f]{64}$'),
  checked_at timestamptz not null,
  created_at timestamptz not null default now(),
  unique (version_id, source_identifier),
  unique (version_id, url)
);

create table app_finance.catalog_research_queue (
  id uuid primary key default gen_random_uuid(),
  product_id uuid references app_finance.financial_product_catalog (id),
  account_type app_finance.account_type not null
    check (account_type in ('credit_card', 'bnpl')),
  country_code text not null check (country_code ~ '^[A-Z]{2}$'),
  issuer_name text not null check (char_length(issuer_name) between 1 and 160),
  official_website text check (
    official_website is null or
    (char_length(official_website) <= 500 and official_website ~* '^https?://')
  ),
  product_name text not null check (char_length(product_name) between 1 and 160),
  tier text check (tier is null or char_length(tier) between 1 and 120),
  network text check (
    network is null or network in ('visa', 'mastercard', 'other', 'unknown')
  ),
  currency_code text check (currency_code is null or currency_code ~ '^[A-Z]{3}$'),
  identity_key text not null,
  work_key text not null,
  reason app_finance.catalog_queue_reason not null,
  priority integer not null default 0 check (priority between -1000 and 1000),
  status app_finance.catalog_queue_status not null default 'queued',
  attempts integer not null default 0 check (attempts >= 0),
  available_at timestamptz not null default now(),
  leased_at timestamptz,
  lease_expires_at timestamptz,
  last_error text check (last_error is null or char_length(last_error) <= 500),
  requested_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (status = 'leased' and leased_at is not null and lease_expires_at is not null)
    or status <> 'leased'
  )
);

create unique index catalog_research_queue_outstanding_work_key
  on app_finance.catalog_research_queue (work_key)
  where status in ('queued', 'leased');
create index catalog_research_queue_lease_idx
  on app_finance.catalog_research_queue
  (status, available_at, lease_expires_at, priority desc, created_at);
create index catalog_research_queue_requested_by_idx
  on app_finance.catalog_research_queue (requested_by, created_at desc)
  where requested_by is not null;

create table app_finance.catalog_research_runs (
  id uuid primary key default gen_random_uuid(),
  task_name text not null check (char_length(task_name) between 1 and 160),
  run_type app_finance.catalog_run_type not null,
  status app_finance.catalog_run_status not null,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  item_count integer not null default 0 check (item_count >= 0),
  completed_count integer not null default 0 check (completed_count >= 0),
  changed_count integer not null default 0 check (changed_count >= 0),
  failed_count integer not null default 0 check (failed_count >= 0),
  summary jsonb not null default '{}'::jsonb check (jsonb_typeof(summary) = 'object'),
  created_at timestamptz not null default now(),
  check ((status = 'running' and completed_at is null) or status <> 'running')
);

create or replace function app_private.catalog_normalize_text(p_value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select lower(regexp_replace(btrim(coalesce(p_value, '')), '[[:space:]]+', ' ', 'g'));
$$;

create or replace function app_private.catalog_identity_key(
  p_account_type app_finance.account_type,
  p_country_code text,
  p_issuer_name text,
  p_product_name text,
  p_tier text,
  p_network text,
  p_currency_code text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select p_account_type::text || '|' || upper(btrim(p_country_code)) || '|' ||
    app_private.catalog_normalize_text(p_issuer_name) || '|' ||
    app_private.catalog_normalize_text(p_product_name) || '|' ||
    app_private.catalog_normalize_text(p_tier) || '|' ||
    app_private.catalog_normalize_text(p_network) || '|' ||
    upper(btrim(coalesce(p_currency_code, '')));
$$;

create or replace function app_private.set_catalog_identity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.country_code := upper(btrim(new.country_code));
  new.issuer_name := regexp_replace(btrim(new.issuer_name), '[[:space:]]+', ' ', 'g');
  new.product_name := regexp_replace(btrim(new.product_name), '[[:space:]]+', ' ', 'g');
  new.tier := nullif(regexp_replace(btrim(new.tier), '[[:space:]]+', ' ', 'g'), '');
  new.network := nullif(lower(btrim(new.network)), '');
  new.currency_code := nullif(upper(btrim(new.currency_code)), '');
  new.official_website := nullif(btrim(new.official_website), '');
  new.identity_key := app_private.catalog_identity_key(
    new.account_type, new.country_code, new.issuer_name, new.product_name,
    new.tier, new.network, new.currency_code
  );
  if tg_table_name = 'catalog_research_queue' then
    new.work_key := case when new.product_id is not null
      then 'product:' || new.product_id::text
      else 'identity:' || new.identity_key end;
  end if;
  return new;
end;
$$;

create trigger trg_financial_product_catalog_identity
  before insert or update of account_type, country_code, issuer_name,
    product_name, tier, network, currency_code, official_website
  on app_finance.financial_product_catalog
  for each row execute function app_private.set_catalog_identity();
create trigger trg_financial_product_catalog_updated_at
  before update on app_finance.financial_product_catalog
  for each row execute function app_private.set_updated_at();
create trigger trg_catalog_research_queue_identity
  before insert or update of product_id, account_type, country_code,
    issuer_name, product_name, tier, network, currency_code, official_website
  on app_finance.catalog_research_queue
  for each row execute function app_private.set_catalog_identity();
create trigger trg_catalog_research_queue_updated_at
  before update on app_finance.catalog_research_queue
  for each row execute function app_private.set_updated_at();

create or replace function app_private.protect_catalog_version()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'catalog versions are immutable' using errcode = '55000';
  end if;
  if (to_jsonb(new) - array['superseded_at', 'effective_until']::text[])
     is distinct from
     (to_jsonb(old) - array['superseded_at', 'effective_until']::text[]) then
    raise exception 'catalog version payloads are immutable' using errcode = '55000';
  end if;
  if old.superseded_at is not null and new.superseded_at is distinct from old.superseded_at then
    raise exception 'a superseded catalog version cannot be changed' using errcode = '55000';
  end if;
  return new;
end;
$$;

create trigger trg_financial_product_catalog_versions_immutable
  before update or delete on app_finance.financial_product_catalog_versions
  for each row execute function app_private.protect_catalog_version();

create or replace function app_private.catalog_json_nodes(p_value jsonb)
returns setof jsonb
language sql
immutable
set search_path = ''
as $$
  with recursive nodes(value) as (
    select p_value
    union all
    select child.value
    from nodes n
    cross join lateral (
      select e.value
      from jsonb_each(case when jsonb_typeof(n.value) = 'object' then n.value else '{}'::jsonb end) e
      union all
      select a.value
      from jsonb_array_elements(case when jsonb_typeof(n.value) = 'array' then n.value else '[]'::jsonb end) a
    ) child
  )
  select value from nodes;
$$;

create or replace function app_finance.get_catalog_research_contract()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'contractVersion', 'finance-card-catalog-v1',
    'productIdentity', jsonb_build_object(
      'required', jsonb_build_array('accountType','countryCode','issuerName','productName'),
      'optional', jsonb_build_array('officialWebsite','tier','network','currencyCode'),
      'accountTypes', jsonb_build_array('credit_card','bnpl'),
      'networks', jsonb_build_array('visa','mastercard','other','unknown')
    ),
    'researchStatuses', jsonb_build_array('resolved','ambiguous','insufficient_information','error'),
    'fieldStatuses', jsonb_build_array('verified','probable','conflicting','unknown','not_applicable'),
    'confidenceLevels', jsonb_build_array('high','medium','low'),
    'accountFormFields', jsonb_build_array(
      'suggestedName','creditLimitMinor','defaultDueDay','statementDay',
      'minPaymentMethod','minPaymentFixedMinor','minPaymentBasisPoints'
    ),
    'valueShape', jsonb_build_object(
      'required', jsonb_build_array('value','status','confidence','sourceIds'),
      'creditLimitRule', 'creditLimitMinor must be absent or {value:null,status:unknown,confidence:null,sourceIds:[]}'
    ),
    'enums', jsonb_build_object(
      'cardFeeType', jsonb_build_array(
        'annual_membership','insurance','administration','stamp_tax',
        'foreign_transaction','cash_advance','international_cash_advance',
        'wallet_fee','statement_fee','early_settlement','late_payment',
        'over_limit','installment_conversion','other'
      ),
      'calculationType', jsonb_build_array('fixed','percentage','fixed_plus_percentage'),
      'feeFrequency', jsonb_build_array('once','monthly','quarterly','annually','per_transaction'),
      'percentBasis', jsonb_build_array(
        'statement_balance','outstanding_balance','credit_limit','transaction_amount',
        'highest_statement_due_lookback','remaining_principal','remaining_outstanding'
      ),
      'minPaymentMethod', jsonb_build_array('full','fixed','percent','greater_of'),
      'interestMethod', jsonb_build_array('flat','reducing'),
      'ratePeriod', jsonb_build_array('monthly','annual')
    ),
    'feeRuleShape', jsonb_build_object(
      'required', jsonb_build_array(
        'feeType','calculationType','frequency','fixedAmountMinor',
        'percentBasisPoints','percentBasis','minimumMinor','maximumMinor',
        'lookbackCycles','status','confidence','sourceIds'
      )
    ),
    'installmentTenorShape', jsonb_build_object(
      'required', jsonb_build_array(
        'fromMonths','toMonths','ratePercentBasisPoints','method','period','status','sourceIds'
      )
    ),
    'sourceShape', jsonb_build_object(
      'required', jsonb_build_array('id','url','title','officialDomain','publishedDate','effectiveDate'),
      'optional', jsonb_build_array('contentHash')
    ),
    'unsupportedFindingShape', jsonb_build_object(
      'required', jsonb_build_array('description','note')
    ),
    'researchPayload', jsonb_build_object(
      'required', jsonb_build_array(
        'product','accountForm','rules','installmentTenors','sources',
        'unresolvedRequiredFields','conflicts','unsupportedFindings'
      )
    ),
    'sourceRequirements', jsonb_build_array(
      'Every sourceIds entry must reference sources[].id',
      'Every verified value or rule must cite at least one officialDomain source',
      'Tariff and rule values should prefer current official issuer/company sources'
    ),
    'forbiddenPrivateFields', jsonb_build_array(
      'pan','cardNumber','fullCardNumber','cvv','cvc','pin','otp','password',
      'userNotes','outstandingBalance','transactionHistory','statementData',
      'personalDueAmount','authToken','providerApiKey'
    ),
    'writeEnvelope', jsonb_build_object(
      'required', jsonb_build_array(
        'contractVersion','queueItemId','productIdentity','researchStatus','research'
      )
    )
  );
$$;

create or replace function app_finance.catalog_search(
  p_account_type app_finance.account_type,
  p_country_code text,
  p_issuer_name text,
  p_product_name text,
  p_tier text default null,
  p_network text default null,
  p_currency_code text default null
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
  with input as (
    select
      app_private.catalog_normalize_text(p_issuer_name) issuer,
      app_private.catalog_normalize_text(p_product_name) product,
      app_private.catalog_normalize_text(p_tier) tier,
      app_private.catalog_normalize_text(p_network) network,
      upper(btrim(coalesce(p_currency_code, ''))) currency
  ), candidates as (
    select p.*, v.id version_id, v.version_number, v.research_payload,
      v.verified_at,
      coalesce(
        (select jsonb_agg(jsonb_build_object(
          'id', s.source_identifier, 'url', s.url, 'title', s.title,
          'officialDomain', s.official_domain, 'publishedDate', s.published_date,
          'effectiveDate', s.effective_date, 'contentHash', s.content_hash,
          'checkedAt', s.checked_at
        ) order by s.source_identifier)
        from app_finance.financial_product_catalog_sources s
        where s.version_id = v.id), '[]'::jsonb
      ) source_payload,
      (case when app_private.catalog_normalize_text(p.issuer_name) = i.issuer then 40
            when app_private.catalog_normalize_text(p.issuer_name) like '%' || i.issuer || '%' then 20 else 0 end
       + case when app_private.catalog_normalize_text(p.product_name) = i.product then 40
              when app_private.catalog_normalize_text(p.product_name) like '%' || i.product || '%' then 20 else 0 end
       + case when i.tier = '' then 0 when app_private.catalog_normalize_text(p.tier) = i.tier then 8 else 0 end
       + case when i.network = '' then 0 when app_private.catalog_normalize_text(p.network) = i.network then 6 else 0 end
       + case when i.currency = '' then 0 when coalesce(p.currency_code, '') = i.currency then 6 else 0 end
      ) score
    from app_finance.financial_product_catalog p
    cross join input i
    join lateral (
      select cv.* from app_finance.financial_product_catalog_versions cv
      where cv.product_id = p.id and cv.superseded_at is null
      order by cv.version_number desc limit 1
    ) v on true
    where p.status = 'active'
      and p.account_type = p_account_type
      and p.country_code = upper(btrim(p_country_code))
      and i.issuer <> ''
      and i.product <> ''
      and (
        app_private.catalog_normalize_text(p.issuer_name) = i.issuer
        or app_private.catalog_normalize_text(p.issuer_name) like '%' || i.issuer || '%'
        or i.issuer like '%' || app_private.catalog_normalize_text(p.issuer_name) || '%'
      )
      and (
        app_private.catalog_normalize_text(p.product_name) = i.product
        or app_private.catalog_normalize_text(p.product_name) like '%' || i.product || '%'
        or i.product like '%' || app_private.catalog_normalize_text(p.product_name) || '%'
      )
  )
  select c.id, c.version_id, c.account_type, c.country_code, c.issuer_name,
    c.official_website, c.product_name, c.tier, c.network, c.currency_code,
    c.version_number, c.research_payload, c.source_payload, c.verified_at,
    c.last_checked_at >= now() - cfg.freshness_window,
    greatest(0, floor(extract(epoch from (now() - c.last_checked_at)) / 86400))::integer,
    c.score
  from candidates c
  cross join app_finance.catalog_configuration cfg
  order by c.score desc, c.identity_key, c.version_number desc
  limit 5;
$$;

create or replace function app_finance.enqueue_catalog_research(
  p_account_type app_finance.account_type,
  p_country_code text,
  p_issuer_name text,
  p_product_name text,
  p_tier text default null,
  p_network text default null,
  p_currency_code text default null,
  p_official_website text default null,
  p_reason app_finance.catalog_queue_reason default 'user_requested',
  p_priority integer default 0
)
returns table (queue_item_id uuid, queue_status app_finance.catalog_queue_status)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_identity text;
  v_product_id uuid;
  v_work_key text;
  v_id uuid;
  v_status app_finance.catalog_queue_status;
  v_limit integer;
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if p_account_type not in ('credit_card', 'bnpl')
    or upper(btrim(coalesce(p_country_code, ''))) !~ '^[A-Z]{2}$'
    or char_length(btrim(coalesce(p_issuer_name, ''))) not between 1 and 160
    or char_length(btrim(coalesce(p_product_name, ''))) not between 1 and 160
    or (p_currency_code is not null and upper(btrim(p_currency_code)) !~ '^[A-Z]{3}$')
    or (p_network is not null and lower(btrim(p_network)) not in ('visa','mastercard','other','unknown'))
    or (p_official_website is not null and btrim(p_official_website) !~* '^https?://') then
    raise exception 'invalid public product identity' using errcode = '22023';
  end if;
  if p_reason not in ('new_product', 'stale', 'user_requested', 'missing_fields') then
    raise exception 'authenticated callers cannot use this queue reason' using errcode = '42501';
  end if;

  select enqueue_rate_limit_per_hour into v_limit
  from app_finance.catalog_configuration where singleton;
  if (select count(*) from app_finance.catalog_research_queue
      where requested_by = v_user_id and created_at >= now() - interval '1 hour') >= v_limit then
    raise exception 'catalog enqueue rate limit exceeded' using errcode = 'P0001';
  end if;

  v_identity := app_private.catalog_identity_key(
    p_account_type, p_country_code, p_issuer_name, p_product_name,
    p_tier, p_network, p_currency_code
  );
  select id into v_product_id from app_finance.financial_product_catalog
    where identity_key = v_identity;
  v_work_key := case when v_product_id is null then 'identity:' || v_identity
                     else 'product:' || v_product_id::text end;

  select id, status into v_id, v_status
  from app_finance.catalog_research_queue
  where work_key = v_work_key and status in ('queued', 'leased')
  order by created_at limit 1;

  if v_id is null then
    begin
      insert into app_finance.catalog_research_queue (
        product_id, account_type, country_code, issuer_name, official_website,
        product_name, tier, network, currency_code, identity_key, work_key,
        reason, priority, requested_by
      ) values (
        v_product_id, p_account_type, upper(btrim(p_country_code)), btrim(p_issuer_name),
        nullif(btrim(p_official_website), ''), btrim(p_product_name), nullif(btrim(p_tier), ''),
        nullif(lower(btrim(p_network)), ''), nullif(upper(btrim(p_currency_code)), ''),
        v_identity, v_work_key, p_reason, greatest(-1000, least(1000, p_priority)), v_user_id
      ) returning id, status into v_id, v_status;
    exception when unique_violation then
      select id, status into v_id, v_status
      from app_finance.catalog_research_queue
      where work_key = v_work_key and status in ('queued', 'leased')
      order by created_at limit 1;
    end;
  end if;
  return query select v_id, v_status;
end;
$$;

create or replace function app_finance.enqueue_due_catalog_research()
returns table (queued_count integer, already_outstanding_count integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_queued integer := 0;
  v_existing integer := 0;
  v_row record;
begin
  for v_row in
    select p.* from app_finance.financial_product_catalog p
    cross join app_finance.catalog_configuration cfg
    where p.status = 'active'
      and (p.last_checked_at is null or p.last_checked_at < now() - cfg.freshness_window)
  loop
    begin
      insert into app_finance.catalog_research_queue (
        product_id, account_type, country_code, issuer_name, official_website,
        product_name, tier, network, currency_code, identity_key, work_key,
        reason, priority
      ) values (
        v_row.id, v_row.account_type, v_row.country_code, v_row.issuer_name,
        v_row.official_website, v_row.product_name, v_row.tier, v_row.network,
        v_row.currency_code, v_row.identity_key, 'product:' || v_row.id::text,
        'stale', 100
      );
      v_queued := v_queued + 1;
    exception when unique_violation then
      v_existing := v_existing + 1;
    end;
  end loop;
  return query select v_queued, v_existing;
end;
$$;

create or replace function app_finance.get_catalog_research_work(p_limit integer default 5)
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
  select least(greatest(coalesce(p_limit, curator_batch_size), 1), curator_batch_size),
    lease_duration into v_limit, v_lease
  from app_finance.catalog_configuration where singleton;

  return query
  with candidates as (
    select q.id
    from app_finance.catalog_research_queue q
    cross join app_finance.catalog_configuration cfg
    where q.available_at <= now()
      and q.attempts < cfg.max_attempts
      and (q.status = 'queued' or (q.status = 'leased' and q.lease_expires_at <= now()))
    order by q.priority desc, q.available_at, q.created_at, q.id
    for update of q skip locked
    limit v_limit
  ), leased as (
    update app_finance.catalog_research_queue q
    set status = 'leased', leased_at = now(), lease_expires_at = now() + v_lease,
      attempts = q.attempts + 1, last_error = null
    from candidates c where q.id = c.id
    returning q.*
  )
  select l.id, l.reason, l.priority, l.attempts, l.leased_at, l.lease_expires_at,
    jsonb_build_object(
      'accountType', l.account_type, 'countryCode', l.country_code,
      'issuerName', l.issuer_name, 'officialWebsite', l.official_website,
      'productName', l.product_name, 'tier', l.tier, 'network', l.network,
      'currencyCode', l.currency_code
    ), 'finance-card-catalog-v1'::text
  from leased l
  order by l.priority desc, l.created_at, l.id;
end;
$$;

create or replace function app_finance.upsert_catalog_research_result(p_payload jsonb)
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
  v_research jsonb;
  v_identity jsonb;
  v_research_status app_finance.catalog_research_status;
  v_product_id uuid;
  v_version_id uuid;
  v_version_number integer;
  v_current app_finance.financial_product_catalog_versions%rowtype;
  v_hash text;
  v_now timestamptz := now();
  v_source jsonb;
  v_source_ids text[];
  v_node jsonb;
  v_key text;
  v_changed boolean := false;
begin
  if jsonb_typeof(p_payload) <> 'object' then
    raise exception 'payload must be a JSON object' using errcode = '22023';
  end if;
  if p_payload ->> 'contractVersion' <> 'finance-card-catalog-v1' then
    raise exception 'unsupported catalog research contract version' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_object_keys(p_payload) k
    where k not in ('contractVersion','queueItemId','productIdentity','researchStatus','research','effectiveFrom')
  ) then
    raise exception 'unknown top-level payload field' using errcode = '22023';
  end if;
  if (p_payload ->> 'queueItemId') is null
    or (p_payload ->> 'queueItemId') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception 'valid queueItemId is required' using errcode = '22023';
  end if;
  select * into v_queue from app_finance.catalog_research_queue
    where id = (p_payload ->> 'queueItemId')::uuid for update;
  if not found or v_queue.status <> 'leased' then
    raise exception 'queue item is not leased' using errcode = '55000';
  end if;

  v_identity := p_payload -> 'productIdentity';
  v_research := p_payload -> 'research';
  if v_identity is null or v_research is null
    or jsonb_typeof(v_identity) <> 'object' or jsonb_typeof(v_research) <> 'object' then
    raise exception 'productIdentity and research objects are required' using errcode = '22023';
  end if;
  if app_private.catalog_identity_key(
      (v_identity ->> 'accountType')::app_finance.account_type,
      v_identity ->> 'countryCode', v_identity ->> 'issuerName',
      v_identity ->> 'productName', v_identity ->> 'tier',
      v_identity ->> 'network', v_identity ->> 'currencyCode'
    ) <> v_queue.identity_key then
    raise exception 'payload product identity does not match leased work' using errcode = '22023';
  end if;

  begin
    v_research_status := (p_payload ->> 'researchStatus')::app_finance.catalog_research_status;
  exception when invalid_text_representation then
    raise exception 'invalid research status' using errcode = '22023';
  end;

  if exists (
    select 1 from jsonb_object_keys(v_research) k
    where k not in ('product','accountForm','rules','installmentTenors','sources',
                    'unresolvedRequiredFields','conflicts','unsupportedFindings')
  ) or not (v_research ?& array['product','accountForm','rules','installmentTenors','sources',
                                'unresolvedRequiredFields','conflicts','unsupportedFindings']) then
    raise exception 'malformed research payload' using errcode = '22023';
  end if;
  if jsonb_typeof(v_research -> 'product') <> 'object'
    or jsonb_typeof(v_research -> 'accountForm') <> 'object'
    or jsonb_typeof(v_research -> 'rules') <> 'array'
    or jsonb_typeof(v_research -> 'installmentTenors') <> 'array'
    or jsonb_typeof(v_research -> 'sources') <> 'array'
    or jsonb_typeof(v_research -> 'unresolvedRequiredFields') <> 'array'
    or jsonb_typeof(v_research -> 'conflicts') <> 'array'
    or jsonb_typeof(v_research -> 'unsupportedFindings') <> 'array' then
    raise exception 'malformed research collection shape' using errcode = '22023';
  end if;

  for v_node in select * from app_private.catalog_json_nodes(p_payload)
  loop
    if jsonb_typeof(v_node) = 'object' then
      for v_key in select jsonb_object_keys(v_node)
      loop
        if lower(regexp_replace(v_key, '[_-]', '', 'g')) in (
          'pan','cardnumber','fullcardnumber','cvv','cvc','pin','otp','password',
          'usernotes','outstandingbalance','transactionhistory','statementdata',
          'personaldueamount','authtoken','providerapikey','apikey'
        ) then
          raise exception 'forbidden private field in catalog payload: %', v_key using errcode = '22023';
        end if;
      end loop;
    end if;
  end loop;

  if v_research #> '{accountForm,creditLimitMinor}' is not null
    and not (
      v_research #>> '{accountForm,creditLimitMinor,status}' = 'unknown'
      and v_research #> '{accountForm,creditLimitMinor,value}' = 'null'::jsonb
      and coalesce(jsonb_array_length(v_research #> '{accountForm,creditLimitMinor,sourceIds}'), 0) = 0
    ) then
    raise exception 'personal credit limit is forbidden in the global catalog' using errcode = '22023';
  end if;

  for v_node in select * from app_private.catalog_json_nodes(v_research)
  loop
    if jsonb_typeof(v_node) = 'object' and v_node ? 'status' then
      if v_node ->> 'status' = 'user_provided' then
        raise exception 'user_provided field status is forbidden in the global catalog' using errcode = '22023';
      end if;
      if v_node ->> 'status' not in ('verified','probable','conflicting','unknown','not_applicable') then
        raise exception 'invalid catalog field status' using errcode = '22023';
      end if;
      if not (v_node ? 'sourceIds') or jsonb_typeof(v_node -> 'sourceIds') <> 'array' then
        raise exception 'researched values require a sourceIds array' using errcode = '22023';
      end if;
    end if;
  end loop;

  if exists (
    select 1 from jsonb_array_elements(v_research -> 'sources') s
    where jsonb_typeof(s) <> 'object'
      or coalesce(s ->> 'id','') = '' or coalesce(s ->> 'url','') !~* '^https?://'
      or coalesce(s ->> 'title','') = '' or jsonb_typeof(s -> 'officialDomain') <> 'boolean'
  ) then
    raise exception 'malformed source provenance' using errcode = '22023';
  end if;
  if (select count(*) from jsonb_array_elements(v_research -> 'sources')) <>
     (select count(distinct s ->> 'id') from jsonb_array_elements(v_research -> 'sources') s) then
    raise exception 'duplicate source identifiers' using errcode = '22023';
  end if;
  select coalesce(array_agg(s ->> 'id'), '{}'::text[]) into v_source_ids
  from jsonb_array_elements(v_research -> 'sources') s;

  for v_node in
    select n from app_private.catalog_json_nodes(v_research) n
    where jsonb_typeof(n) = 'object' and n ? 'sourceIds'
  loop
    if exists (
      select 1 from jsonb_array_elements_text(v_node -> 'sourceIds') sid
      where sid <> all(v_source_ids)
    ) then
      raise exception 'research field references an unknown source identifier' using errcode = '22023';
    end if;
    if v_node ->> 'status' = 'verified' and not exists (
      select 1
      from jsonb_array_elements_text(v_node -> 'sourceIds') sid
      join jsonb_array_elements(v_research -> 'sources') s on s ->> 'id' = sid
      where (s ->> 'officialDomain')::boolean
    ) then
      raise exception 'verified catalog values require official source provenance' using errcode = '22023';
    end if;
  end loop;

  if exists (
    select 1 from jsonb_array_elements(v_research -> 'rules') r
    where r ->> 'feeType' not in (
      'annual_membership','insurance','administration','stamp_tax','foreign_transaction',
      'cash_advance','international_cash_advance','wallet_fee','statement_fee',
      'early_settlement','late_payment','over_limit','installment_conversion','other'
    ) or r ->> 'calculationType' not in ('fixed','percentage','fixed_plus_percentage')
      or r ->> 'frequency' not in ('once','monthly','quarterly','annually','per_transaction')
      or (r -> 'percentBasis' <> 'null'::jsonb and r ->> 'percentBasis' not in (
        'statement_balance','outstanding_balance','credit_limit','transaction_amount',
        'highest_statement_due_lookback','remaining_principal','remaining_outstanding'))
  ) then
    raise exception 'unknown fee rule enum value' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_research -> 'installmentTenors') t
    where t ->> 'method' not in ('flat','reducing')
      or t ->> 'period' not in ('monthly','annual')
      or (t ->> 'fromMonths')::integer < 1
      or (t ->> 'toMonths')::integer < (t ->> 'fromMonths')::integer
  ) then
    raise exception 'unknown installment tenor enum or range' using errcode = '22023';
  end if;

  if v_research_status <> 'resolved' then
    update app_finance.catalog_research_queue set status = 'completed', leased_at = null,
      lease_expires_at = null, last_error = null where id = v_queue.id;
    insert into app_finance.catalog_research_runs (
      task_name, run_type, status, completed_at, item_count, completed_count, summary
    ) values (
      'catalog-curator', 'curator', 'completed', v_now, 1, 1,
      jsonb_build_object('researchStatus', v_research_status, 'queueItemId', v_queue.id)
    );
    return query select null::uuid, null::uuid, false, null::integer, 'completed'::app_finance.catalog_queue_status;
    return;
  end if;

  v_hash := encode(extensions.digest(convert_to(v_research::text, 'UTF8'), 'sha256'), 'hex');
  select * into v_current
  from app_finance.financial_product_catalog_versions cv
  where cv.product_id = v_queue.product_id and cv.superseded_at is null
  order by cv.version_number desc limit 1 for update;

  v_product_id := v_queue.product_id;
  if v_product_id is null then
    insert into app_finance.financial_product_catalog (
      account_type, country_code, issuer_name, official_website, product_name,
      tier, network, currency_code, identity_key, status, last_checked_at,
      last_changed_at
    ) values (
      v_queue.account_type, v_queue.country_code, v_queue.issuer_name,
      v_queue.official_website, v_queue.product_name, v_queue.tier,
      v_queue.network, v_queue.currency_code, v_queue.identity_key, 'active',
      v_now, v_now
    ) on conflict (identity_key) do update set last_checked_at = v_now
    returning id into v_product_id;
    update app_finance.catalog_research_queue set product_id = v_product_id where id = v_queue.id;
    select * into v_current
    from app_finance.financial_product_catalog_versions cv
    where cv.product_id = v_product_id and cv.superseded_at is null
    order by cv.version_number desc limit 1 for update;
  end if;

  if v_current.id is not null and v_current.content_hash = v_hash then
    update app_finance.financial_product_catalog
      set last_checked_at = v_now where id = v_product_id;
    v_version_id := v_current.id;
    v_version_number := v_current.version_number;
  else
    v_changed := true;
    if v_current.id is not null then
      update app_finance.financial_product_catalog_versions
      set superseded_at = v_now, effective_until = coalesce(
        ((p_payload ->> 'effectiveFrom')::date - 1), current_date
      ) where id = v_current.id;
    end if;
    select coalesce(max(cv.version_number), 0) + 1 into v_version_number
    from app_finance.financial_product_catalog_versions cv
    where cv.product_id = v_product_id;
    insert into app_finance.financial_product_catalog_versions (
      product_id, version_number, contract_version, research_status,
      research_payload, content_hash, effective_from, verified_at
    ) values (
      v_product_id, v_version_number, 'finance-card-catalog-v1',
      v_research_status, v_research, v_hash,
      nullif(p_payload ->> 'effectiveFrom', '')::date, v_now
    ) returning id into v_version_id;

    for v_source in select * from jsonb_array_elements(v_research -> 'sources')
    loop
      insert into app_finance.financial_product_catalog_sources (
        version_id, source_identifier, url, title, official_domain,
        published_date, effective_date, content_hash, checked_at
      ) values (
        v_version_id, v_source ->> 'id', v_source ->> 'url', v_source ->> 'title',
        (v_source ->> 'officialDomain')::boolean,
        nullif(v_source ->> 'publishedDate', '')::date,
        nullif(v_source ->> 'effectiveDate', '')::date,
        nullif(v_source ->> 'contentHash', ''), v_now
      );
    end loop;
    update app_finance.financial_product_catalog
      set last_checked_at = v_now, last_changed_at = v_now where id = v_product_id;
  end if;

  update app_finance.catalog_research_queue set status = 'completed', leased_at = null,
    lease_expires_at = null, last_error = null where id = v_queue.id;
  insert into app_finance.catalog_research_runs (
    task_name, run_type, status, completed_at, item_count, completed_count,
    changed_count, summary
  ) values (
    'catalog-curator', 'curator', 'completed', v_now, 1, 1,
    case when v_changed then 1 else 0 end,
    jsonb_build_object('queueItemId', v_queue.id, 'productId', v_product_id,
                       'versionNumber', v_version_number)
  );
  return query select v_product_id, v_version_id, v_changed, v_version_number,
    'completed'::app_finance.catalog_queue_status;
end;
$$;

create or replace function app_finance.fail_catalog_research_work(
  p_queue_item_id uuid,
  p_error text
)
returns table (
  queue_item_id uuid,
  queue_status app_finance.catalog_queue_status,
  attempts integer,
  available_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_queue app_finance.catalog_research_queue%rowtype;
  v_max integer;
  v_error text;
begin
  select * into v_queue from app_finance.catalog_research_queue
    where id = p_queue_item_id for update;
  if not found or v_queue.status <> 'leased' then
    raise exception 'queue item is not leased' using errcode = '55000';
  end if;
  select max_attempts into v_max from app_finance.catalog_configuration where singleton;
  v_error := left(
    regexp_replace(
      regexp_replace(
        regexp_replace(coalesce(p_error, 'research failed'),
          '([0-9][ -]?){13,19}', '[redacted]', 'g'),
        '(cvv|cvc|pin|otp)[[:space:]:=#-]*[0-9]{3,8}',
        '\1 [redacted]', 'gi'
      ),
      '[[:cntrl:]]', ' ', 'g'
    ),
    500
  );
  update app_finance.catalog_research_queue q
  set status = case when q.attempts >= v_max then 'failed'::app_finance.catalog_queue_status
                    else 'queued'::app_finance.catalog_queue_status end,
      available_at = case when q.attempts >= v_max then q.available_at
                          else now() + make_interval(mins => least(60, q.attempts * 5)) end,
      leased_at = null, lease_expires_at = null, last_error = v_error
  where q.id = p_queue_item_id
  returning q.* into v_queue;
  insert into app_finance.catalog_research_runs (
    task_name, run_type, status, completed_at, item_count, failed_count, summary
  ) values (
    'catalog-curator', 'curator', 'failed', now(), 1, 1,
    jsonb_build_object('queueItemId', p_queue_item_id, 'willRetry', v_queue.status = 'queued')
  );
  return query select v_queue.id, v_queue.status, v_queue.attempts, v_queue.available_at;
end;
$$;

create or replace function app_finance.record_catalog_automation_heartbeat(p_task_name text)
returns table (run_id uuid, recorded_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_now timestamptz := now();
begin
  if char_length(btrim(coalesce(p_task_name, ''))) not between 1 and 160 then
    raise exception 'invalid task name' using errcode = '22023';
  end if;
  insert into app_finance.catalog_research_runs (
    task_name, run_type, status, started_at, completed_at, summary
  ) values (btrim(p_task_name), 'heartbeat', 'completed', v_now, v_now, '{}'::jsonb)
  returning id into v_id;
  return query select v_id, v_now;
end;
$$;

create or replace function app_finance.catalog_status_summary()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'activeProducts', (select count(*) from app_finance.financial_product_catalog where status = 'active'),
    'staleProducts', (select count(*) from app_finance.financial_product_catalog p
      where p.status = 'active' and (p.last_checked_at is null or p.last_checked_at < now() - cfg.freshness_window)),
    'queued', (select count(*) from app_finance.catalog_research_queue where status = 'queued'),
    'leased', (select count(*) from app_finance.catalog_research_queue where status = 'leased'),
    'failed', (select count(*) from app_finance.catalog_research_queue where status = 'failed'),
    'lastSuccessfulCuratorRun', (select max(completed_at) from app_finance.catalog_research_runs
      where run_type = 'curator' and status = 'completed'),
    'lastHeartbeat', (select max(completed_at) from app_finance.catalog_research_runs
      where run_type = 'heartbeat' and status = 'completed'),
    'contractVersion', 'finance-card-catalog-v1'
  ) from app_finance.catalog_configuration cfg where cfg.singleton;
$$;

alter table app_finance.catalog_configuration enable row level security;
alter table app_finance.financial_product_catalog enable row level security;
alter table app_finance.financial_product_catalog_versions enable row level security;
alter table app_finance.financial_product_catalog_sources enable row level security;
alter table app_finance.catalog_research_queue enable row level security;
alter table app_finance.catalog_research_runs enable row level security;

revoke all on table app_finance.catalog_configuration from public, anon, authenticated, service_role;
revoke all on table app_finance.financial_product_catalog from public, anon, authenticated, service_role;
revoke all on table app_finance.financial_product_catalog_versions from public, anon, authenticated, service_role;
revoke all on table app_finance.financial_product_catalog_sources from public, anon, authenticated, service_role;
revoke all on table app_finance.catalog_research_queue from public, anon, authenticated, service_role;
revoke all on table app_finance.catalog_research_runs from public, anon, authenticated, service_role;

revoke execute on function app_finance.get_catalog_research_contract() from public, anon, authenticated;
revoke execute on function app_finance.catalog_search(
  app_finance.account_type,text,text,text,text,text,text
) from public, anon, authenticated;
revoke execute on function app_finance.enqueue_catalog_research(
  app_finance.account_type,text,text,text,text,text,text,text,
  app_finance.catalog_queue_reason,integer
) from public, anon, authenticated;
revoke execute on function app_finance.enqueue_due_catalog_research() from public, anon, authenticated;
revoke execute on function app_finance.get_catalog_research_work(integer) from public, anon, authenticated;
revoke execute on function app_finance.upsert_catalog_research_result(jsonb) from public, anon, authenticated;
revoke execute on function app_finance.fail_catalog_research_work(uuid,text) from public, anon, authenticated;
revoke execute on function app_finance.record_catalog_automation_heartbeat(text) from public, anon, authenticated;
revoke execute on function app_finance.catalog_status_summary() from public, anon, authenticated;

grant execute on function app_finance.get_catalog_research_contract() to authenticated, service_role;
grant execute on function app_finance.catalog_search(
  app_finance.account_type,text,text,text,text,text,text
) to authenticated, service_role;
grant execute on function app_finance.enqueue_catalog_research(
  app_finance.account_type,text,text,text,text,text,text,text,
  app_finance.catalog_queue_reason,integer
) to authenticated, service_role;
grant execute on function app_finance.enqueue_due_catalog_research() to service_role;
grant execute on function app_finance.get_catalog_research_work(integer) to service_role;
grant execute on function app_finance.upsert_catalog_research_result(jsonb) to service_role;
grant execute on function app_finance.fail_catalog_research_work(uuid,text) to service_role;
grant execute on function app_finance.record_catalog_automation_heartbeat(text) to service_role;
grant execute on function app_finance.catalog_status_summary() to service_role;

notify pgrst, 'reload schema';
