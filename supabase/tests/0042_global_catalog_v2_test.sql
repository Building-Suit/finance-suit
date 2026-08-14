begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

create or replace function pg_temp.unknown_value(
  p_status text default 'unknown'
)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'value', null,
    'status', p_status,
    'confidence', null,
    'sourceIds', '[]'::jsonb
  );
$$;

create or replace function pg_temp.verified_value(p_value jsonb)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'value', p_value,
    'status', 'verified',
    'confidence', 'high',
    'sourceIds', jsonb_build_array('official')
  );
$$;

create or replace function pg_temp.wrapper_object(p_fields text[])
returns jsonb
language sql
immutable
as $$
  select coalesce(
    jsonb_object_agg(field_name, pg_temp.unknown_value()),
    '{}'::jsonb
  )
  from unnest(p_fields) field_name;
$$;

create or replace function pg_temp.valid_v2_research(
  p_issuer text default 'Global Test Bank',
  p_product text default 'Atlas Card'
)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'product',
      jsonb_set(
        jsonb_set(
          pg_temp.wrapper_object(array[
            'issuerName', 'productName', 'tier', 'network', 'currencyCode',
            'officialProductUrl', 'officialApplicationUrl',
            'issuerSupportUrl', 'officialDescription', 'availabilityStatus',
            'launchDate', 'discontinuedDate'
          ]),
          '{issuerName}', pg_temp.verified_value(to_jsonb(p_issuer))
        ),
        '{productName}', pg_temp.verified_value(to_jsonb(p_product))
      ),
    'accountForm', pg_temp.wrapper_object(array[
      'suggestedName', 'creditLimitMinor', 'defaultDueDay', 'statementDay',
      'gracePeriodDays', 'minPaymentMethod', 'minPaymentFixedMinor',
      'minPaymentBasisPoints', 'minPaymentPercentageBasis',
      'minPaymentIncludeInstallmentDues', 'minPaymentIncludeBankFees',
      'minPaymentIncludeOverdue', 'minPaymentFixedFloorMinor',
      'installmentDueDay', 'fxMarkupBasisPoints', 'colorHex'
    ]),
    'appearance', pg_temp.wrapper_object(array[
      'officialColorName', 'primaryColorHex', 'secondaryColorHex',
      'accentColorHexes', 'officialCardImageUrl', 'appearanceSourceMethod'
    ]),
    'paymentCycle', pg_temp.wrapper_object(array[
      'paymentDueRule', 'statementCycleRule', 'gracePeriod', 'minimumPayment'
    ]),
    'fees', '[]'::jsonb,
    'purchaseInterest', jsonb_build_object('rule', pg_temp.unknown_value()),
    'installments', jsonb_build_object(
      'tenors', '[]'::jsonb,
      'earlySettlementRule', pg_temp.unknown_value(),
      'conversionRule', pg_temp.unknown_value()
    ),
    'bnpl', pg_temp.wrapper_object(array[
      'repaymentFrequency', 'firstPaymentTiming', 'downPaymentRule',
      'publicSpendingLimits', 'merchantRestrictions', 'earlySettlementRule',
      'eligibilityNotes', 'virtualCardAvailable', 'physicalCardAvailable'
    ]),
    'eligibility', pg_temp.wrapper_object(array[
      'minimumAge', 'maximumAge', 'employmentRequirement', 'residency',
      'nationalityRestrictions', 'minimumIncomeMinor', 'incomeCurrency',
      'salaryTransferRequired', 'relationshipRequirement',
      'depositOrCollateralRequirement', 'secured', 'creditCriteriaNotes'
    ]),
    'publicLimits', pg_temp.wrapper_object(array[
      'advertisedMinimumLimitMinor', 'advertisedMaximumLimitMinor',
      'purchaseLimitRule', 'cashWithdrawalRule', 'contactlessLimitRule'
    ]),
    'rewards', pg_temp.wrapper_object(array[
      'pointsRule', 'cashbackRule', 'milesRule', 'welcomeBonus',
      'redemptionNotes'
    ]),
    'benefits', '[]'::jsonb,
    'digitalFeatures', pg_temp.wrapper_object(array[
      'features', 'supportedWallets'
    ]),
    'issuerMarketDefaults', pg_temp.wrapper_object(array[
      'paymentDueRule', 'statementCycleRule', 'gracePeriod',
      'minimumPayment', 'fxMarkupRule', 'eligibility'
    ]),
    'sources', jsonb_build_array(jsonb_build_object(
      'id', 'official',
      'url', 'https://global-test.example/products/atlas',
      'title', 'Official product terms',
      'publisher', p_issuer,
      'officialDomain', true,
      'publicationDate', '2026-08-01',
      'revisionDate', null,
      'effectiveDate', '2026-08-01',
      'checkedAt', '2026-08-14T00:00:00Z',
      'sourceType', 'official_product_page'
    )),
    'conflicts', '[]'::jsonb,
    'unresolvedFields', '[]'::jsonb,
    'unsupportedFindings', '[]'::jsonb
  );
$$;

create or replace function pg_temp.write_envelope(
  p_queue_id uuid,
  p_research jsonb
)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'contractVersion', 'finance-card-catalog-v2',
    'queueItemId', q.id,
    'productIdentity', jsonb_build_object(
      'accountType', q.account_type,
      'countryCode', q.country_code,
      'issuerName', q.issuer_name,
      'productName', q.product_name,
      'tier', q.tier,
      'network', q.network,
      'currencyCode', q.currency_code,
      'officialUrl', q.official_website
    ),
    'researchStatus', 'resolved',
    'research', p_research,
    'effectiveFrom', '2026-08-01'
  )
  from app_finance.catalog_research_queue q
  where q.id = p_queue_id;
$$;

-- Contract, identity, country, appearance, and unknown semantics.
select is(
  app_finance.get_catalog_research_contract() ->> 'contractVersion',
  'finance-card-catalog-v2',
  'the scheduled curator contract is v2'
);
select is(
  app_finance.get_catalog_research_contract()
    #>> '{identityArchitecture,countryStandard}',
  'ISO 3166-1 alpha-2',
  'the contract represents countries explicitly'
);
select ok(
  app_finance.get_catalog_research_contract() ? 'resultPayload',
  'the v2 contract describes its result payload'
);
select is(
  app_finance.get_catalog_research_contract()
    #>> '{appearanceShape,accountColorSeparate}',
  'true',
  'official appearance and user-selected account color are distinct'
);
select is(
  pg_temp.unknown_value(),
  '{"value":null,"status":"unknown","confidence":null,"sourceIds":[]}'::jsonb,
  'unknown is represented explicitly rather than as a guessed value'
);
select lives_ok(
  $$select app_private.assert_catalog_v2_public_payload(
      pg_temp.valid_v2_research())$$,
  'a complete all-unknown v2 public payload is valid'
);

-- Discovery is bounded, normalized, global, and duplicate-resistant.
set local role service_role;
create temp table discovery_results as
select * from app_finance.enqueue_catalog_discovery_candidates(
  '[
    {"accountType":"credit_card","countryCode":"EG","issuerName":"Atlas Bank","productName":"World","network":"visa","currencyCode":"EGP"},
    {"accountType":"credit_card","countryCode":"US","issuerName":"Atlas Bank","productName":"World","network":"visa","currencyCode":"USD"},
    {"accountType":"credit_card","countryCode":"EG","issuerName":"Other Bank","productName":"World","network":"visa","currencyCode":"EGP"}
  ]'::jsonb,
  -100
);
select is((select count(*)::integer from discovery_results), 3,
  'discovery candidates enter the queue');
create temp table duplicate_result as
select * from app_finance.enqueue_catalog_discovery_candidates(
  '[{"accountType":"credit_card","countryCode":"eg","issuerName":"  ATLAS   BANK ","productName":" world ","network":"VISA","currencyCode":"egp"}]'::jsonb,
  -100
);
select is(
  (select queue_item_id from duplicate_result),
  (select queue_item_id from discovery_results where candidate_index = 1),
  'normalized duplicate discovery returns the existing work item'
);
set local role postgres;
select is((select count(*)::integer from app_finance.catalog_research_queue), 3,
  'duplicate discovery creates no extra queue row');
select is((select count(distinct identity_key)::integer
  from app_finance.catalog_research_queue where product_name = 'World'), 3,
  'same product names remain distinct across issuers and countries');
select throws_ok(
  $$select * from app_finance.enqueue_catalog_discovery_candidates(
    '[{"accountType":"credit_card","countryCode":"EG","issuerName":"Unsafe","productName":"Card","creditLimitMinor":100000}]'::jsonb)$$,
  'invalid discovery candidate at index 1',
  'discovery rejects fields beyond public identity'
);
select throws_ok(
  $$select * from app_finance.enqueue_catalog_discovery_candidates(
    (select jsonb_agg(jsonb_build_object(
      'accountType','bnpl','countryCode','EG','issuerName','Bounded',
      'productName','Plan ' || n)) from generate_series(1,51) n))$$,
  'discovery candidates must be a JSON array containing 1 to 50 items',
  'discovery input has a hard 50-candidate bound'
);

-- Payment-cycle semantics and exact account-form autofill eligibility.
select lives_ok($$
  select app_private.assert_catalog_v2_public_payload(
    jsonb_set(
      jsonb_set(pg_temp.valid_v2_research(),
        '{paymentCycle,paymentDueRule}',
        pg_temp.verified_value('{"type":"fixed_day_of_month","fixedDay":25}'::jsonb)),
      '{accountForm,defaultDueDay}', pg_temp.verified_value('25'::jsonb)
    )
  )$$, 'an exact fixed payment day can populate defaultDueDay');
select lives_ok($$
  select app_private.assert_catalog_v2_public_payload(
    jsonb_set(pg_temp.valid_v2_research(),
      '{paymentCycle,paymentDueRule}',
      pg_temp.verified_value('{"type":"days_after_statement","daysAfterStatement":21}'::jsonb))
  )$$, 'days-after-statement is represented without inventing a due day');
select lives_ok($$
  select app_private.assert_catalog_v2_public_payload(
    jsonb_set(pg_temp.valid_v2_research(),
      '{paymentCycle,paymentDueRule}',
      pg_temp.verified_value('{"type":"issuer_assigned","description":"Shown on each statement"}'::jsonb))
  )$$, 'issuer-assigned payment dates remain rule-based');
select throws_ok($$
  select app_private.assert_catalog_v2_public_payload(
    jsonb_set(
      jsonb_set(pg_temp.valid_v2_research(),
        '{paymentCycle,paymentDueRule}',
        pg_temp.verified_value('{"type":"issuer_assigned"}'::jsonb)),
      '{accountForm,defaultDueDay}', pg_temp.verified_value('25'::jsonb)
    )
  )$$,
  'defaultDueDay autofill requires an exact fixed payment rule',
  'a non-exact payment rule cannot become a fixed account due day');
select lives_ok($$
  select app_private.assert_catalog_v2_public_payload(
    jsonb_set(
      jsonb_set(pg_temp.valid_v2_research(),
        '{paymentCycle,statementCycleRule}',
        pg_temp.verified_value('{"type":"fixed_day_of_month","fixedDay":18}'::jsonb)),
      '{accountForm,statementDay}', pg_temp.verified_value('18'::jsonb)
    )
  )$$, 'an exact statement day is autofillable');
select lives_ok($$
  select app_private.assert_catalog_v2_public_payload(
    jsonb_set(
      jsonb_set(pg_temp.valid_v2_research(),
        '{paymentCycle,gracePeriod}',
        pg_temp.verified_value('{"semantics":"exact","exactDays":55,"interestFree":true}'::jsonb)),
      '{accountForm,gracePeriodDays}', pg_temp.verified_value('55'::jsonb)
    )
  )$$, 'an exact grace period can populate the account form');
select lives_ok($$
  select app_private.assert_catalog_v2_public_payload(
    jsonb_set(pg_temp.valid_v2_research(),
      '{paymentCycle,gracePeriod}',
      pg_temp.verified_value('{"semantics":"up_to","advertisedMaximumDays":55}'::jsonb))
  )$$, 'an up-to grace claim is represented without an exact account value');
select throws_ok($$
  select app_private.assert_catalog_v2_public_payload(
    jsonb_set(
      jsonb_set(pg_temp.valid_v2_research(),
        '{paymentCycle,gracePeriod}',
        pg_temp.verified_value('{"semantics":"up_to","advertisedMaximumDays":55}'::jsonb)),
      '{accountForm,gracePeriodDays}', pg_temp.verified_value('55'::jsonb)
    )
  )$$,
  'gracePeriodDays autofill requires exact grace semantics',
  'up to N days is never treated as an exact grace period');
select lives_ok($$
  select app_private.assert_catalog_v2_public_payload(
    jsonb_set(pg_temp.valid_v2_research(),
      '{paymentCycle,minimumPayment}',
      pg_temp.verified_value('{"method":"greater_of","fixedAmountMinor":5000,"percentageBasisPoints":500,"percentageBasis":"statement_total","includesInstallments":true,"includesFees":true,"includesOverdue":true}'::jsonb))
  )$$, 'minimum-payment formulas are represented structurally');

-- Appearance, fees, interest, installments, BNPL, eligibility and benefits.
select lives_ok($$
  select app_private.assert_catalog_v2_public_payload(
    jsonb_set(
      jsonb_set(
        jsonb_set(pg_temp.valid_v2_research(),
          '{appearance,primaryColorHex}', pg_temp.verified_value('"#123ABC"'::jsonb)),
        '{appearance,appearanceSourceMethod}',
        pg_temp.verified_value('"derived_from_official_asset"'::jsonb)),
      '{accountForm,colorHex}', pg_temp.verified_value('"#123ABC"'::jsonb)
    )
  )$$, 'official product color can be sourced from an official asset');
select lives_ok($$
  select app_private.assert_catalog_v2_public_payload(
    jsonb_set(pg_temp.valid_v2_research(), '{fees}',
      '[{"feeType":"annual_membership","calculationType":"fixed","frequency":"annually","trigger":"schedule","fixedAmountMinor":75000,"percentBasisPoints":null,"percentBasis":null,"minimumMinor":null,"maximumMinor":null,"lookbackCycles":null,"conditions":{},"effectiveFrom":"2026-01-01","effectiveUntil":null,"exclusions":[],"status":"verified","confidence":"high","sourceIds":["official"]}]'::jsonb)
  )$$, 'comprehensive fee rules are accepted');
select lives_ok($$
  select app_private.assert_catalog_v2_public_payload(
    jsonb_set(pg_temp.valid_v2_research(), '{purchaseInterest,rule}',
      pg_temp.verified_value('{"rateBasisPoints":3450,"ratePeriod":"annual","aprBasisPoints":3450,"interestMethod":"reducing","accrualMethod":"daily","interestStartRule":"purchase_date","graceEligible":true}'::jsonb))
  )$$, 'purchase interest remains a distinct sourced rule');
select lives_ok($$
  select app_private.assert_catalog_v2_public_payload(
    jsonb_set(pg_temp.valid_v2_research(), '{installments,tenors}',
      '[{"fromMonths":3,"toMonths":12,"rateBasisPoints":150,"ratePeriod":"monthly","interestMethod":"flat","conversionFee":null,"processingFee":null,"minimumPurchaseMinor":100000,"maximumPurchaseMinor":null,"eligibleMerchantsOrCategories":[],"installmentDueRule":{"type":"statement_defined"},"effectiveFrom":"2026-01-01","effectiveUntil":null,"status":"verified","confidence":"high","sourceIds":["official"]}]'::jsonb)
  )$$, 'installment tenor programs are represented');
select lives_ok($$
  select app_private.assert_catalog_v2_public_payload(
    jsonb_set(pg_temp.valid_v2_research(), '{installments,earlySettlementRule}',
      pg_temp.verified_value('{"allowed":true,"feeType":"percentage","percentBasisPoints":300,"basis":"remaining_principal"}'::jsonb))
  )$$, 'early-settlement terms are represented separately');
select lives_ok($$
  select app_private.assert_catalog_v2_public_payload(
    jsonb_set(
      jsonb_set(pg_temp.valid_v2_research('Atlas BNPL','Flex'),
        '{bnpl,repaymentFrequency}', pg_temp.verified_value('"monthly"'::jsonb)),
      '{bnpl,firstPaymentTiming}', pg_temp.verified_value('"at_purchase"'::jsonb)
    )
  )$$, 'BNPL-specific public terms are first-class');
select lives_ok($$
  select app_private.assert_catalog_v2_public_payload(
    jsonb_set(pg_temp.valid_v2_research(), '{eligibility,minimumAge}',
      pg_temp.verified_value('21'::jsonb))
  )$$, 'public eligibility requirements are represented without approval predictions');
select lives_ok($$
  select app_private.assert_catalog_v2_public_payload(
    jsonb_set(pg_temp.valid_v2_research(),
      '{publicLimits,advertisedMaximumLimitMinor}',
      pg_temp.verified_value('100000000'::jsonb))
  )$$, 'advertised public limits use a field distinct from a personal limit');
select lives_ok($$
  select app_private.assert_catalog_v2_public_payload(
    jsonb_set(
      jsonb_set(pg_temp.valid_v2_research(), '{rewards,pointsRule}',
        pg_temp.verified_value('{"pointsPerMinor":0.01}'::jsonb)),
      '{benefits}',
      '[{"type":"lounge_access","title":"Airport lounge access","description":"Published eligibility applies","status":"verified","confidence":"high","sourceIds":["official"]}]'::jsonb
    )
  )$$, 'structured rewards and bounded benefits are represented');
select lives_ok($$
  select app_private.assert_catalog_v2_public_payload(
    jsonb_set(pg_temp.valid_v2_research(), '{digitalFeatures,features}',
      pg_temp.verified_value('["contactless","card_controls"]'::jsonb))
  )$$, 'digital features use extensible identifiers');

-- Conflicts, provenance, and private-data rejection.
select lives_ok($$
  select app_private.assert_catalog_v2_public_payload(
    jsonb_set(pg_temp.valid_v2_research(), '{conflicts}',
      '[{"field":"fees.annual_membership","status":"conflicting","competingValues":[{"value":50000,"sourceIds":["official"],"effectiveFrom":"2026-01-01","effectiveUntil":null,"confidence":"high"},{"value":75000,"sourceIds":["official"],"effectiveFrom":"2026-07-01","effectiveUntil":null,"confidence":"medium"}]}]'::jsonb)
  )$$, 'conflicting official claims preserve each competing value');
select throws_ok($$
  select app_private.assert_catalog_v2_public_payload(
    jsonb_set(pg_temp.valid_v2_research(), '{product,tier}',
      '{"value":"Gold","status":"verified","confidence":"high","sourceIds":["missing"]}'::jsonb)
  )$$,
  'catalog v2 claim references an unknown source identifier',
  'every researched claim must reference persisted source provenance');
select throws_ok($$
  select app_private.assert_catalog_v2_public_payload(
    jsonb_set(pg_temp.valid_v2_research(), '{accountForm,creditLimitMinor}',
      pg_temp.verified_value('5000000'::jsonb))
  )$$,
  'personal credit limit is forbidden in the global catalog',
  'a user approved credit limit cannot enter the catalog');
select throws_ok($$
  select app_private.assert_catalog_v2_public_payload(
    jsonb_set(pg_temp.valid_v2_research(), '{unsupportedFindings}',
      '[{"creditLimitMinor":5000000}]'::jsonb)
  )$$,
  'private or account-instance data is forbidden in the global catalog',
  'private fields are rejected even when nested elsewhere');
select throws_ok($$
  select app_private.assert_catalog_v2_public_payload(
    jsonb_set(pg_temp.valid_v2_research(), '{unsupportedFindings}',
      '[{"description":"4111 1111 1111 1111"}]'::jsonb)
  )$$,
  'credential-like, card-number-like, or user-provided content is forbidden',
  'PAN-like content is rejected regardless of its JSON key');

-- Batch leasing: default 25, hard max 50, disjoint leases, and recovery.
set local role service_role;
select * from app_finance.enqueue_catalog_discovery_candidates(
  (select jsonb_agg(jsonb_build_object(
    'accountType', 'bnpl', 'countryCode', 'GB',
    'issuerName', 'Batch Provider', 'productName', 'Plan ' || n,
    'currencyCode', 'GBP'
  )) from generate_series(1,50) n),
  0
);
select * from app_finance.enqueue_catalog_discovery_candidates(
  (select jsonb_agg(jsonb_build_object(
    'accountType', 'bnpl', 'countryCode', 'GB',
    'issuerName', 'Batch Provider', 'productName', 'Extra Plan ' || n,
    'currencyCode', 'GBP'
  )) from generate_series(1,15) n),
  0
);
create temp table lease_default as
select * from app_finance.get_catalog_research_work();
select is((select count(*)::integer from lease_default), 25,
  'the default curator lease is 25 items');
set local role postgres;
update app_finance.catalog_research_queue
set status = 'queued', leased_at = null, lease_expires_at = null
where id in (select queue_item_id from lease_default);
set local role service_role;
create temp table lease_hard_max as
select * from app_finance.get_catalog_research_work(999);
select is((select count(*)::integer from lease_hard_max), 50,
  'the server hard-clamps curator leases to 50, not 5');
set local role postgres;
update app_finance.catalog_research_queue
set status = 'queued', leased_at = null, lease_expires_at = null
where id in (select queue_item_id from lease_hard_max);
set local role service_role;
create temp table lease_worker_a as
select * from app_finance.get_catalog_research_work(25);
create temp table lease_worker_b as
select * from app_finance.get_catalog_research_work(25);
select is((select count(*)::integer from lease_worker_a), 25,
  'the first concurrent-style worker leases 25 rows');
select is((select count(*)::integer from lease_worker_b), 25,
  'the second concurrent-style worker leases another 25 rows');
select is((select count(*)::integer from lease_worker_a a
  join lease_worker_b b using (queue_item_id)), 0,
  'sequential transactions using SKIP LOCKED never share a lease');
set local role postgres;
update app_finance.catalog_research_queue
set lease_expires_at = now() - interval '1 minute', priority = 999
where id = (select queue_item_id from lease_worker_a limit 1);
set local role service_role;
select is((select count(*)::integer
  from app_finance.get_catalog_research_work(1)), 1,
  'expired work is eligible for recovery');

-- Persist one researched market and exercise identity, precedence, history,
-- unchanged verification, and source storage.
set local role postgres;
update app_finance.catalog_research_queue
set status = 'completed', leased_at = null, lease_expires_at = null
where status in ('queued', 'leased');
set local role service_role;
select * from app_finance.enqueue_catalog_discovery_candidates(
  '[{"accountType":"credit_card","countryCode":"EG","issuerName":"Global Test Bank","productName":"Atlas Card","tier":"Gold","network":"visa","currencyCode":"EGP","officialUrl":"https://global-test.example/products/atlas"}]'::jsonb,
  1000
);
create temp table researched_lease as
select * from app_finance.get_catalog_research_work(1);
set local role postgres;
create temp table first_write as
select * from app_finance.upsert_catalog_research_result(
  pg_temp.write_envelope(
    (select queue_item_id from researched_lease),
    jsonb_set(pg_temp.valid_v2_research(),
      '{issuerMarketDefaults,paymentDueRule}',
      pg_temp.verified_value('{"type":"fixed_day_of_month","fixedDay":15}'::jsonb))
  )
);
select is((select changed from first_write), true,
  'the first researched result creates an immutable version');
select is((select count(*)::integer from app_finance.catalog_issuers
  where canonical_name = 'Global Test Bank'), 1,
  'result writing creates one normalized issuer');
select is((select count(*)::integer from app_finance.catalog_canonical_products
  where canonical_name = 'Atlas Card'), 1,
  'result writing creates one canonical product');
select is((select count(*)::integer from app_finance.catalog_issuer_markets
  where country_code = 'EG'), 1,
  'result writing creates the issuer country market');
select is((select count(*)::integer
  from app_finance.financial_product_catalog_sources s
  where s.version_id = (select version_id from first_write)), 1,
  'source provenance is persisted on the exact product version');
select is((select count(*)::integer
  from app_finance.catalog_issuer_market_sources), 1,
  'issuer-market default provenance is versioned separately');
grant select on first_write to authenticated;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-4000-8000-00000000c242',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'catalog-v2@test.local', '', now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-4000-8000-00000000c242","role":"authenticated"}';
select is(
  app_finance.catalog_resolved_public_configuration(
    (select product_id from first_write)
  ) #>> '{paymentDueRule,value,fixedDay}',
  '15',
  'issuer-market due rules apply when the product has no override'
);
set local role postgres;
update app_finance.financial_product_catalog
set last_checked_at = now() - interval '400 days'
where id = (select product_id from first_write);
set local role service_role;
select is((select queued_count from app_finance.enqueue_due_catalog_research()), 1,
  'stale refresh queues the exact product-market variant');
create temp table unchanged_lease as
select * from app_finance.get_catalog_research_work(1);
set local role postgres;
create temp table unchanged_write as
select * from app_finance.upsert_catalog_research_result(
  pg_temp.write_envelope(
    (select queue_item_id from unchanged_lease),
    jsonb_set(pg_temp.valid_v2_research(),
      '{issuerMarketDefaults,paymentDueRule}',
      pg_temp.verified_value('{"type":"fixed_day_of_month","fixedDay":15}'::jsonb))
  )
);
select is((select changed from unchanged_write), false,
  'verification-only refresh does not create a meaningless version');
select is((select count(*)::integer from app_finance.catalog_version_verifications
  where product_id = (select product_id from first_write)), 2,
  'each successful check has an immutable verification record');

insert into app_finance.catalog_research_queue (
  product_id, account_type, country_code, issuer_name, official_website,
  product_name, tier, network, currency_code, identity_key, work_key,
  reason, priority
)
select id, account_type, country_code, issuer_name, official_website,
  product_name, tier, network, currency_code, identity_key,
  'product:' || id::text, 'source_changed', 1000
from app_finance.financial_product_catalog
where id = (select product_id from first_write);
set local role service_role;
create temp table changed_lease as
select * from app_finance.get_catalog_research_work(1);
set local role postgres;
create temp table changed_write as
select * from app_finance.upsert_catalog_research_result(
  pg_temp.write_envelope(
    (select queue_item_id from changed_lease),
    jsonb_set(
      jsonb_set(
        jsonb_set(pg_temp.valid_v2_research(),
          '{issuerMarketDefaults,paymentDueRule}',
          pg_temp.verified_value('{"type":"fixed_day_of_month","fixedDay":15}'::jsonb)),
        '{paymentCycle,paymentDueRule}',
        pg_temp.verified_value('{"type":"fixed_day_of_month","fixedDay":25}'::jsonb)),
      '{accountForm,defaultDueDay}', pg_temp.verified_value('25'::jsonb)
    )
  )
);
select is((select changed from changed_write), true,
  'a material public-rule change creates a new immutable version');
select is((select count(*)::integer
  from app_finance.financial_product_catalog_versions
  where product_id = (select product_id from first_write)), 2,
  'changed research preserves the prior version and adds one version');
select ok((select superseded_at is not null
  from app_finance.financial_product_catalog_versions
  where product_id = (select product_id from first_write)
  order by version_number limit 1),
  'the prior product version is retained as superseded history');
select throws_ok(
  $$update app_finance.financial_product_catalog_versions
    set research_payload = '{}'::jsonb
    where id = (select version_id from first_write)$$,
  'catalog version payloads are immutable',
  'historical product payloads cannot be rewritten');
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-4000-8000-00000000c242","role":"authenticated"}';
select is(
  app_finance.catalog_resolved_public_configuration(
    (select product_id from first_write)
  ) #>> '{paymentDueRule,value,fixedDay}',
  '25',
  'a product-market due rule overrides the issuer-market default'
);

-- Least privilege and safe operational metrics.
set local role postgres;
select ok(not has_table_privilege('service_role',
  'app_finance.catalog_issuers', 'select'),
  'the curator has no arbitrary direct issuer-table access');
select ok(not has_table_privilege('authenticated',
  'app_finance.catalog_canonical_products', 'select'),
  'app users have no direct canonical-product table access');
select ok(has_function_privilege('service_role',
  'app_finance.enqueue_catalog_discovery_candidates(jsonb,integer)', 'execute'),
  'the approved discovery RPC is available to the curator');
select ok(not has_function_privilege('authenticated',
  'app_finance.upsert_catalog_research_result(jsonb)', 'execute'),
  'ordinary users cannot call the catalog result writer');
select is(app_finance.catalog_status_summary() ->> 'contractVersion',
  'finance-card-catalog-v2', 'status summary reports the global v2 contract');
select ok((app_finance.catalog_status_summary() ->> 'canonicalProducts')::integer >= 1,
  'status summary reports canonical-product metrics');
select ok(app_finance.catalog_status_summary() ? 'countriesCovered',
  'status summary reports country coverage');
select is(app_finance.catalog_status_summary() #>> '{batch,default}', '25',
  'status summary exposes the 25-item operational default');
select is(app_finance.catalog_status_summary() #>> '{batch,maximum}', '50',
  'status summary exposes the 50-item hard maximum');
select ok(not (app_finance.catalog_status_summary()::text ~*
  'account|balance|transaction|creditlimit'),
  'status summary contains no private account-level financial data');

select * from finish();
rollback;
