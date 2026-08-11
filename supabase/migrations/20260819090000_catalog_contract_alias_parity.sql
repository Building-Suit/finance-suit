-- Correct the v1 curator contract and add trusted, exact catalog aliases.
-- Historical catalog versions are intentionally left untouched.

create or replace function app_private.catalog_value_definitions()
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'product', jsonb_build_object(
      'allowed', jsonb_build_array('issuerName','productName','tier','network','currencyCode'),
      'required', jsonb_build_array('issuerName','productName','tier','network','currencyCode'),
      'types', jsonb_build_object(
        'issuerName','string','productName','string','tier','string|null',
        'network',jsonb_build_array('visa','mastercard','other','unknown'),
        'currencyCode','ISO-4217 string|null'
      )
    ),
    'accountForm', jsonb_build_object(
      'allowed', jsonb_build_array(
        'suggestedName','creditLimitMinor','defaultDueDay','statementDay',
        'minPaymentMethod','minPaymentFixedMinor','minPaymentBasisPoints'
      ),
      'required', jsonb_build_array(
        'suggestedName','creditLimitMinor','defaultDueDay','statementDay',
        'minPaymentMethod','minPaymentFixedMinor','minPaymentBasisPoints'
      ),
      'types', jsonb_build_object(
        'suggestedName','string|null','creditLimitMinor','null',
        'defaultDueDay','integer|null','statementDay','integer|null',
        'minPaymentMethod',jsonb_build_array('full','fixed','percent','greater_of'),
        'minPaymentFixedMinor','integer|null','minPaymentBasisPoints','integer|null'
      )
    ),
    'unknownShape', jsonb_build_object(
      'value',null,'status','unknown','confidence',null,'sourceIds','[]'::jsonb
    )
  );
$$;

create or replace function app_private.assert_catalog_public_payload(p_research jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_defs jsonb := app_private.catalog_value_definitions();
  v_collection jsonb;
  v_node jsonb;
  v_key text;
  v_name text;
  v_allowed text[];
  v_required text[];
  v_source_ids text[];
begin
  if jsonb_typeof(p_research) <> 'object' then
    raise exception 'catalog research must be a JSON object' using errcode = '22023';
  end if;
  if exists (
    select 1 from app_private.catalog_json_nodes(p_research) n
    cross join lateral jsonb_object_keys(case when jsonb_typeof(n)='object' then n else '{}'::jsonb end) k
    where lower(regexp_replace(k, '[_-]', '', 'g')) in (
      'pan','cardnumber','fullcardnumber','cvv','cvc','pin','otp','password',
      'usernotes','uservalue','outstandingbalance','transactionhistory','statementdata',
      'personaldueamount','authtoken','accesstoken','providerapikey','service_role_key',
      'servicerolekey','apikey'
    )
  ) then
    raise exception 'private or user-provided data is forbidden in the global catalog' using errcode='22023';
  end if;
  if p_research::text ~ '([0-9][ -]?){13,19}'
    or p_research::text ~ 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
    or p_research::text ~ '(sb_secret_|sk-[A-Za-z0-9_-]{16,}|AIza[A-Za-z0-9_-]{20,})' then
    raise exception 'credential-like or card-number-like content is forbidden in the global catalog' using errcode='22023';
  end if;
  if jsonb_array_length(coalesce(p_research->'conflicts','[]'::jsonb)) <> 0 then
    raise exception 'user-specific conflicts are forbidden in the global catalog' using errcode='22023';
  end if;

  for v_name in select unnest(array['product','accountForm']) loop
    v_collection := p_research -> v_name;
    if jsonb_typeof(v_collection) <> 'object' then
      raise exception 'catalog value collections must be JSON objects' using errcode='22023';
    end if;
    select array_agg(value order by ordinality) into v_allowed
      from jsonb_array_elements_text(v_defs #> array[v_name,'allowed']) with ordinality;
    select array_agg(value order by ordinality) into v_required
      from jsonb_array_elements_text(v_defs #> array[v_name,'required']) with ordinality;
    if exists (select from jsonb_object_keys(v_collection) k where k <> all(v_allowed)) then
      raise exception 'unknown catalog value field' using errcode='22023';
    end if;
    if not (v_collection ?& v_required) then
      raise exception 'required catalog values are missing' using errcode='22023';
    end if;
    for v_key,v_node in select key,value from jsonb_each(v_collection) loop
      if jsonb_typeof(v_node)<>'object'
        or not (v_node ?& array['value','status','confidence','sourceIds'])
        or (select count(*) from jsonb_object_keys(v_node)) <> 4
        or exists (select from jsonb_object_keys(v_node) k where k <> all(array['value','status','confidence','sourceIds']))
        or jsonb_typeof(v_node->'sourceIds') <> 'array'
        or exists (select from jsonb_array_elements(v_node->'sourceIds') s where jsonb_typeof(s)<>'string') then
        raise exception 'malformed researched value: %',v_key using errcode='22023';
      end if;
      if v_node->>'status' not in ('verified','probable','conflicting','unknown','not_applicable') then
        raise exception 'invalid catalog field status' using errcode='22023';
      end if;
      if v_name='accountForm' and v_key='creditLimitMinor'
        and v_node <> v_defs->'unknownShape' then
        raise exception 'personal credit limit is forbidden in the global catalog' using errcode='22023';
      end if;
      if v_node->>'status' in ('verified','probable','conflicting') and
        (v_node->'value'='null'::jsonb or coalesce(v_node->>'confidence','') not in ('high','medium','low')) then
        raise exception 'researched values require a value and confidence' using errcode='22023';
      end if;
      if v_node->>'status' in ('probable','conflicting')
        and jsonb_array_length(v_node->'sourceIds')=0 then
        raise exception 'probable and conflicting values require source provenance' using errcode='22023';
      end if;
      if v_node->>'status' in ('unknown','not_applicable') and
        (v_node->'value'<>'null'::jsonb or v_node->'confidence'<>'null'::jsonb or jsonb_array_length(v_node->'sourceIds')<>0) then
        raise exception 'unknown and not-applicable values must be empty' using errcode='22023';
      end if;
      if v_node->>'status' in ('verified','probable','conflicting') and (
        (v_key in ('issuerName','productName','tier','suggestedName') and jsonb_typeof(v_node->'value')<>'string')
        or (v_key='network' and v_node->>'value' not in ('visa','mastercard','other','unknown'))
        or (v_key='currencyCode' and v_node->>'value' !~ '^[A-Z]{3}$')
        or (v_key in ('creditLimitMinor','defaultDueDay','statementDay','minPaymentFixedMinor','minPaymentBasisPoints')
            and jsonb_typeof(v_node->'value')<>'number')
        or (v_key='minPaymentMethod' and v_node->>'value' not in ('full','fixed','percent','greater_of'))
      ) then
        raise exception 'invalid catalog value type or enum: %',v_key using errcode='22023';
      end if;
    end loop;
  end loop;

  if p_research #>> '{accountForm,creditLimitMinor,status}' <> 'unknown'
    or (p_research #> '{accountForm,creditLimitMinor}') <> v_defs->'unknownShape' then
    raise exception 'personal credit limit is forbidden in the global catalog' using errcode='22023';
  end if;
  if p_research #>> '{product,issuerName,status}' in ('unknown','not_applicable')
    or p_research #> '{product,issuerName,value}' = 'null'::jsonb
    or p_research #>> '{product,productName,status}' in ('unknown','not_applicable')
    or p_research #> '{product,productName,value}' = 'null'::jsonb then
    raise exception 'resolved catalog identity values are required' using errcode='22023';
  end if;

  if exists (select from jsonb_array_elements(p_research->'sources') s
    where exists (select from jsonb_object_keys(s) k where k not in
      ('id','url','title','officialDomain','publishedDate','effectiveDate','contentHash'))) then
    raise exception 'unknown source provenance field' using errcode='22023';
  end if;
  select coalesce(array_agg(s->>'id'),'{}'::text[]) into v_source_ids
    from jsonb_array_elements(p_research->'sources') s;
  for v_node in select n from app_private.catalog_json_nodes(p_research) n
    where jsonb_typeof(n)='object' and n?'sourceIds' loop
    if exists (select from jsonb_array_elements_text(v_node->'sourceIds') sid where sid<>all(v_source_ids)) then
      raise exception 'research field references an unknown source identifier' using errcode='22023';
    end if;
    if v_node->>'status'='verified' and not exists (
      select from jsonb_array_elements_text(v_node->'sourceIds') sid
      join jsonb_array_elements(p_research->'sources') s on s->>'id'=sid
      where (s->>'officialDomain')::boolean) then
      raise exception 'verified catalog values require official source provenance' using errcode='22023';
    end if;
  end loop;
end;
$$;

create or replace function app_finance.get_catalog_research_contract()
returns jsonb language sql stable security invoker set search_path='' as $$
  with d as (select app_private.catalog_value_definitions() v)
  select jsonb_build_object(
    'contractVersion','finance-card-catalog-v1',
    'researchStatuses',jsonb_build_array('resolved','ambiguous','insufficient_information','error'),
    'fieldStatuses',jsonb_build_array('verified','probable','conflicting','unknown','not_applicable'),
    'confidenceLevels',jsonb_build_array('high','medium','low'),
    'productIdentity',jsonb_build_object('required',jsonb_build_array('accountType','countryCode','issuerName','productName'),'optional',jsonb_build_array('officialWebsite','tier','network','currencyCode'),'accountTypes',jsonb_build_array('credit_card','bnpl'),'networks',jsonb_build_array('visa','mastercard','other','unknown')),
    'writeEnvelope',jsonb_build_object('required',jsonb_build_array('contractVersion','queueItemId','productIdentity','researchStatus','research')),
    'valueShape',jsonb_build_object('required',jsonb_build_array('value','status','confidence','sourceIds'),'exactKeys',true,'unknown',d.v->'unknownShape'),
    'productValueFields',(d.v->'product')||jsonb_build_object('unknown',d.v->'unknownShape','suggestedNameForbidden',true,'allRequiredEvenWhenUnknown',true),
    'accountFormValueFields',(d.v->'accountForm')||jsonb_build_object('unknown',d.v->'unknownShape','creditLimitMinorRule','must equal the global unknown wrapper','allRequiredEvenWhenUnknown',true),
    'researchPayload',jsonb_build_object('required',jsonb_build_array('product','accountForm','rules','installmentTenors','sources','unresolvedRequiredFields','conflicts','unsupportedFindings')),
    'sourceShape',jsonb_build_object('required',jsonb_build_array('id','url','title','officialDomain','publishedDate','effectiveDate'),'optional',jsonb_build_array('contentHash')),
    'feeRuleShape',jsonb_build_object('required',jsonb_build_array('feeType','calculationType','frequency','fixedAmountMinor','percentBasisPoints','percentBasis','minimumMinor','maximumMinor','lookbackCycles','status','confidence','sourceIds')),
    'installmentTenorShape',jsonb_build_object('required',jsonb_build_array('fromMonths','toMonths','ratePercentBasisPoints','method','period','status','sourceIds')),
    'unsupportedFindingShape',jsonb_build_object('required',jsonb_build_array('description','note')),
    'sourceRequirements',jsonb_build_array('Every sourceIds entry must reference sources[].id','Every verified value or rule must cite at least one officialDomain source','Probable and conflicting values require value, confidence, and valid sources'),
    'forbiddenPrivateFields',jsonb_build_array('pan','cardNumber','fullCardNumber','cvv','cvc','pin','otp','password','userNotes','outstandingBalance','transactionHistory','statementData','personalDueAmount','authToken','providerApiKey')
  ) from d;
$$;

create table app_finance.financial_product_catalog_aliases (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references app_finance.financial_product_catalog(id),
  account_type app_finance.account_type not null,
  country_code text not null check(country_code ~ '^[A-Z]{2}$'),
  issuer_alias text not null check(char_length(issuer_alias) between 1 and 160),
  product_alias text not null check(char_length(product_alias) between 1 and 160),
  normalized_issuer_alias text not null,
  normalized_product_alias text not null,
  created_at timestamptz not null default now(),
  unique(account_type,country_code,normalized_issuer_alias,normalized_product_alias)
);

create or replace function app_private.set_catalog_alias_identity()
returns trigger language plpgsql set search_path='' as $$
declare v_product app_finance.financial_product_catalog%rowtype;
begin
  select * into strict v_product from app_finance.financial_product_catalog where id=new.product_id;
  new.account_type:=v_product.account_type; new.country_code:=v_product.country_code;
  new.issuer_alias:=regexp_replace(btrim(new.issuer_alias),'[[:space:]]+',' ','g');
  new.product_alias:=regexp_replace(btrim(new.product_alias),'[[:space:]]+',' ','g');
  new.normalized_issuer_alias:=app_private.catalog_normalize_text(new.issuer_alias);
  new.normalized_product_alias:=app_private.catalog_normalize_text(new.product_alias);
  return new;
end; $$;
create trigger trg_catalog_alias_identity before insert or update on app_finance.financial_product_catalog_aliases
for each row execute function app_private.set_catalog_alias_identity();
alter table app_finance.financial_product_catalog_aliases enable row level security;
revoke all on app_finance.financial_product_catalog_aliases from public,anon,authenticated;

create or replace function app_finance.resolve_catalog_research_alias(p_queue_item_id uuid,p_catalog_product_id uuid)
returns table(queue_item_id uuid, catalog_product_id uuid, queue_status app_finance.catalog_queue_status, alias_id uuid)
language plpgsql security definer set search_path='' as $$
declare q app_finance.catalog_research_queue%rowtype; p app_finance.financial_product_catalog%rowtype; a uuid; v_now timestamptz:=now();
begin
  if p_queue_item_id is null or p_catalog_product_id is null then raise exception 'queue item and catalog product are required' using errcode='22023'; end if;
  select * into q from app_finance.catalog_research_queue where id=p_queue_item_id for update;
  if not found or q.status not in ('leased','completed') then raise exception 'queue item is not eligible for alias resolution' using errcode='55000'; end if;
  select * into p from app_finance.financial_product_catalog where id=p_catalog_product_id;
  if not found or p.status<>'active' then raise exception 'canonical catalog product must be active' using errcode='22023'; end if;
  if q.account_type<>p.account_type then raise exception 'alias account type does not match canonical product' using errcode='22023'; end if;
  if q.country_code<>p.country_code then raise exception 'alias country does not match canonical product' using errcode='22023'; end if;
  if q.status='completed' and q.product_id is distinct from p.id then raise exception 'completed queue item resolves to another product' using errcode='55000'; end if;
  insert into app_finance.financial_product_catalog_aliases(product_id,account_type,country_code,issuer_alias,product_alias,normalized_issuer_alias,normalized_product_alias)
  values(p.id,p.account_type,p.country_code,q.issuer_name,q.product_name,'pending','pending')
  on conflict(account_type,country_code,normalized_issuer_alias,normalized_product_alias) do nothing returning id into a;
  if a is null then select id into a from app_finance.financial_product_catalog_aliases where account_type=p.account_type and country_code=p.country_code and normalized_issuer_alias=app_private.catalog_normalize_text(q.issuer_name) and normalized_product_alias=app_private.catalog_normalize_text(q.product_name) and product_id=p.id; end if;
  if a is null then raise exception 'alias pair already maps to another canonical product' using errcode='23505'; end if;
  update app_finance.catalog_research_queue set product_id=p.id,status='completed',leased_at=null,lease_expires_at=null,last_error=null where id=q.id;
  if q.status='leased' then insert into app_finance.catalog_research_runs(task_name,run_type,status,completed_at,item_count,completed_count,summary)
    values('catalog-curator','curator','completed',v_now,1,1,jsonb_build_object('action','alias_resolution','queueItemId',q.id,'productId',p.id)); end if;
  return query select q.id,p.id,'completed'::app_finance.catalog_queue_status,a;
end; $$;

create or replace function app_finance.catalog_search(p_account_type app_finance.account_type,p_country_code text,p_issuer_name text,p_product_name text,p_tier text default null,p_network text default null,p_currency_code text default null)
returns table(catalog_product_id uuid,catalog_version_id uuid,account_type app_finance.account_type,country_code text,issuer_name text,official_website text,product_name text,tier text,network text,currency_code text,version_number integer,research_payload jsonb,sources jsonb,verified_at timestamptz,is_fresh boolean,age_days integer,match_quality integer)
language sql stable security definer set search_path='' as $$
with i as (select app_private.catalog_normalize_text(p_issuer_name) issuer,app_private.catalog_normalize_text(p_product_name) product,app_private.catalog_normalize_text(p_tier) tier,app_private.catalog_normalize_text(p_network) network,upper(btrim(coalesce(p_currency_code,''))) currency), c as (
select p.*,v.id version_id,v.version_number,v.research_payload,v.verified_at,
coalesce((select jsonb_agg(jsonb_build_object('id',s.source_identifier,'url',s.url,'title',s.title,'officialDomain',s.official_domain,'publishedDate',s.published_date,'effectiveDate',s.effective_date,'contentHash',s.content_hash,'checkedAt',s.checked_at) order by s.source_identifier) from app_finance.financial_product_catalog_sources s where s.version_id=v.id),'[]'::jsonb) source_payload,
case when a.id is not null then 100 else (case when app_private.catalog_normalize_text(p.issuer_name)=i.issuer then 40 else 20 end)+(case when app_private.catalog_normalize_text(p.product_name)=i.product then 40 else 20 end)+case when i.tier='' then 0 else 8 end+case when i.network='' then 0 else 6 end+case when i.currency='' then 0 else 6 end end score
from app_finance.financial_product_catalog p cross join i
left join app_finance.financial_product_catalog_aliases a on a.product_id=p.id and a.account_type=p_account_type and a.country_code=upper(btrim(p_country_code)) and a.normalized_issuer_alias=i.issuer and a.normalized_product_alias=i.product
join lateral(select cv.* from app_finance.financial_product_catalog_versions cv where cv.product_id=p.id and cv.superseded_at is null order by cv.version_number desc limit 1)v on true
where p.status='active' and p.account_type=p_account_type and p.country_code=upper(btrim(p_country_code)) and i.issuer<>'' and i.product<>''
and(i.tier='' or app_private.catalog_normalize_text(p.tier)=i.tier) and(i.network='' or app_private.catalog_normalize_text(p.network)=i.network) and(i.currency='' or coalesce(p.currency_code,'')=i.currency)
and(a.id is not null or ((app_private.catalog_normalize_text(p.issuer_name)=i.issuer or app_private.catalog_normalize_text(p.issuer_name) like '%'||i.issuer||'%' or i.issuer like '%'||app_private.catalog_normalize_text(p.issuer_name)||'%') and (app_private.catalog_normalize_text(p.product_name)=i.product or app_private.catalog_normalize_text(p.product_name) like '%'||i.product||'%' or i.product like '%'||app_private.catalog_normalize_text(p.product_name)||'%'))))
select c.id,c.version_id,c.account_type,c.country_code,c.issuer_name,c.official_website,c.product_name,c.tier,c.network,c.currency_code,c.version_number,c.research_payload,c.source_payload,c.verified_at,c.last_checked_at>=now()-cfg.freshness_window,greatest(0,floor(extract(epoch from(now()-c.last_checked_at))/86400))::integer,c.score from c cross join app_finance.catalog_configuration cfg order by c.score desc,c.identity_key,c.version_number desc limit 5;
$$;

revoke execute on function app_private.catalog_value_definitions() from public,anon,authenticated,service_role;
-- The invoker-rights public contract composes this read-only constant helper.
grant execute on function app_private.catalog_value_definitions() to authenticated,service_role;
revoke execute on function app_private.set_catalog_alias_identity() from public,anon,authenticated,service_role;
revoke execute on function app_finance.resolve_catalog_research_alias(uuid,uuid) from public,anon,authenticated;
grant execute on function app_finance.resolve_catalog_research_alias(uuid,uuid) to service_role;
notify pgrst,'reload schema';
