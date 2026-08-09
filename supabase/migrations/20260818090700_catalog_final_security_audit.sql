-- Final catalog security/correctness hardening.
--
-- Keep catalog data public-only, make every historical artifact immutable,
-- and narrow the recurring automation surface without changing the app-user
-- enqueue contract.

create index if not exists catalog_research_queue_product_id_idx
  on app_finance.catalog_research_queue (product_id)
  where product_id is not null;

-- This RPC returns a constant JSON contract and needs no elevated privileges.
alter function app_finance.get_catalog_research_contract() security invoker;

create or replace function app_private.assert_catalog_public_payload(
  p_research jsonb
)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_collection jsonb;
  v_node jsonb;
  v_key text;
  v_source_ids text[];
begin
  if jsonb_typeof(p_research) <> 'object' then
    raise exception 'catalog research must be a JSON object'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from app_private.catalog_json_nodes(p_research) n
    cross join lateral jsonb_object_keys(
      case when jsonb_typeof(n) = 'object' then n else '{}'::jsonb end
    ) k
    where lower(regexp_replace(k, '[_-]', '', 'g')) in (
      'pan','cardnumber','fullcardnumber','cvv','cvc','pin','otp','password',
      'usernotes','uservalue','outstandingbalance','transactionhistory',
      'statementdata','personaldueamount','authtoken','accesstoken',
      'providerapikey','service_role_key','servicerolekey','apikey'
    )
  ) then
    raise exception 'private or user-provided data is forbidden in the global catalog'
      using errcode = '22023';
  end if;

  if p_research::text ~ '([0-9][ -]?){13,19}'
    or p_research::text ~ 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
    or p_research::text ~ '(sb_secret_|sk-[A-Za-z0-9_-]{16,}|AIza[A-Za-z0-9_-]{20,})' then
    raise exception 'credential-like or card-number-like content is forbidden in the global catalog'
      using errcode = '22023';
  end if;

  if jsonb_array_length(coalesce(p_research -> 'conflicts', '[]'::jsonb)) <> 0 then
    raise exception 'user-specific conflicts are forbidden in the global catalog'
      using errcode = '22023';
  end if;

  if exists (
    select 1 from jsonb_object_keys(p_research -> 'product') k
    where k not in ('issuerName','productName','tier','network','currencyCode')
  ) or exists (
    select 1 from jsonb_object_keys(p_research -> 'accountForm') k
    where k not in (
      'suggestedName','creditLimitMinor','defaultDueDay','statementDay',
      'minPaymentMethod','minPaymentFixedMinor','minPaymentBasisPoints'
    )
  ) then
    raise exception 'unknown catalog value field' using errcode = '22023';
  end if;

  for v_collection in
    select p_research -> 'product'
    union all
    select p_research -> 'accountForm'
  loop
    if jsonb_typeof(v_collection) <> 'object' then
      raise exception 'catalog value collections must be JSON objects'
        using errcode = '22023';
    end if;

    for v_key, v_node in select key, value from jsonb_each(v_collection)
    loop
      if jsonb_typeof(v_node) <> 'object'
        or not (v_node ?& array['value','status','confidence','sourceIds'])
        or exists (
          select 1 from jsonb_object_keys(v_node) k
          where k not in ('value','status','confidence','sourceIds')
        )
        or jsonb_typeof(v_node -> 'sourceIds') <> 'array'
        or exists (
          select 1 from jsonb_array_elements(v_node -> 'sourceIds') sid
          where jsonb_typeof(sid) <> 'string'
        ) then
        raise exception 'malformed researched value: %', v_key
          using errcode = '22023';
      end if;

      if v_node ->> 'status' not in (
        'verified','probable','conflicting','unknown','not_applicable'
      ) then
        raise exception 'invalid catalog field status'
          using errcode = '22023';
      end if;

      if v_node ->> 'status' in ('verified','probable','conflicting')
        and (
          v_node -> 'value' = 'null'::jsonb
          or coalesce(v_node ->> 'confidence', '') not in ('high','medium','low')
        ) then
        raise exception 'researched values require a value and confidence'
          using errcode = '22023';
      end if;

      if v_node ->> 'status' in ('unknown','not_applicable')
        and (v_node -> 'value' <> 'null'::jsonb
          or v_node -> 'confidence' <> 'null'::jsonb
          or jsonb_array_length(v_node -> 'sourceIds') <> 0) then
        raise exception 'unknown and not-applicable values must be empty'
          using errcode = '22023';
      end if;
    end loop;
  end loop;

  if not ((p_research -> 'product') ?& array['issuerName','productName'])
    or not ((p_research -> 'accountForm') ? 'creditLimitMinor') then
    raise exception 'required catalog values are missing'
      using errcode = '22023';
  end if;

  if p_research #>> '{accountForm,creditLimitMinor,status}' <> 'unknown'
    or p_research #> '{accountForm,creditLimitMinor,value}' <> 'null'::jsonb
    or p_research #> '{accountForm,creditLimitMinor,confidence}' <> 'null'::jsonb
    or jsonb_array_length(
      p_research #> '{accountForm,creditLimitMinor,sourceIds}'
    ) <> 0 then
    raise exception 'personal credit limit is forbidden in the global catalog'
      using errcode = '22023';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_research -> 'sources') s
    where exists (
      select 1 from jsonb_object_keys(s) k
      where k not in (
        'id','url','title','officialDomain','publishedDate','effectiveDate',
        'contentHash'
      )
    )
  ) then
    raise exception 'unknown source provenance field'
      using errcode = '22023';
  end if;

  select coalesce(array_agg(s ->> 'id'), '{}'::text[])
    into v_source_ids
  from jsonb_array_elements(p_research -> 'sources') s;

  for v_node in
    select n from app_private.catalog_json_nodes(p_research) n
    where jsonb_typeof(n) = 'object' and n ? 'sourceIds'
  loop
    if exists (
      select 1 from jsonb_array_elements_text(v_node -> 'sourceIds') sid
      where sid <> all(v_source_ids)
    ) then
      raise exception 'research field references an unknown source identifier'
        using errcode = '22023';
    end if;
    if v_node ->> 'status' = 'verified' and not exists (
      select 1
      from jsonb_array_elements_text(v_node -> 'sourceIds') sid
      join jsonb_array_elements(p_research -> 'sources') s
        on s ->> 'id' = sid
      where (s ->> 'officialDomain')::boolean
    ) then
      raise exception 'verified catalog values require official source provenance'
        using errcode = '22023';
    end if;
  end loop;
end;
$$;

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
  if old.superseded_at is not null and (
    new.superseded_at is distinct from old.superseded_at
    or new.effective_until is distinct from old.effective_until
  ) then
    raise exception 'a superseded catalog version cannot be changed'
      using errcode = '55000';
  end if;
  if old.superseded_at is null and new.superseded_at is null
    and new.effective_until is distinct from old.effective_until then
    raise exception 'current catalog version end date cannot be changed'
      using errcode = '55000';
  end if;
  if old.superseded_at is null and new.superseded_at is not null
    and new.effective_until is null then
    raise exception 'a superseded catalog version requires an effective end date'
      using errcode = '55000';
  end if;
  return new;
end;
$$;

create or replace function app_private.validate_catalog_version_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  perform app_private.assert_catalog_public_payload(new.research_payload);
  return new;
end;
$$;

create trigger trg_financial_product_catalog_versions_validate
  before insert on app_finance.financial_product_catalog_versions
  for each row execute function app_private.validate_catalog_version_insert();

create or replace function app_private.protect_catalog_source()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'catalog version sources are immutable' using errcode = '55000';
end;
$$;

create trigger trg_financial_product_catalog_sources_immutable
  before update or delete on app_finance.financial_product_catalog_sources
  for each row execute function app_private.protect_catalog_source();

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
       + case when i.tier = '' then 0 else 8 end
       + case when i.network = '' then 0 else 6 end
       + case when i.currency = '' then 0 else 6 end
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
      and (i.tier = '' or app_private.catalog_normalize_text(p.tier) = i.tier)
      and (i.network = '' or app_private.catalog_normalize_text(p.network) = i.network)
      and (i.currency = '' or coalesce(p.currency_code, '') = i.currency)
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
returns table (
  queue_item_id uuid,
  queue_status app_finance.catalog_queue_status
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_limit integer;
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  if p_reason not in ('new_product', 'stale', 'user_requested', 'missing_fields') then
    raise exception 'authenticated callers cannot use this queue reason' using errcode = '42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_user_id::text, 9047301)
  );

  select c.enqueue_rate_limit_per_hour into v_limit
  from app_finance.catalog_configuration c
  where c.singleton;

  if (select count(*) from app_finance.catalog_research_queue q
      where q.requested_by = v_user_id
        and q.created_at >= now() - interval '1 hour') >= v_limit then
    raise exception 'catalog enqueue rate limit exceeded' using errcode = 'P0001';
  end if;

  return query
  select e.queue_item_id, e.queue_status
  from app_private.enqueue_catalog_research_common(
    p_account_type, p_country_code, p_issuer_name, p_product_name,
    p_tier, p_network, p_currency_code, p_official_website,
    p_reason, p_priority, v_user_id
  ) e;
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
  if p_queue_item_id is null then
    raise exception 'queue item id is required' using errcode = '22023';
  end if;
  select * into v_queue from app_finance.catalog_research_queue
    where id = p_queue_item_id for update;
  if not found or v_queue.status <> 'leased' then
    raise exception 'queue item is not leased' using errcode = '55000';
  end if;
  select max_attempts into v_max
  from app_finance.catalog_configuration where singleton;

  -- Store only a fixed operational category. Raw provider text can contain
  -- echoed PANs, user notes, bearer tokens, or provider credentials.
  v_error := case
    when coalesce(p_error, '') ~* '(timeout|timed out)' then 'provider timeout'
    when coalesce(p_error, '') ~* '(rate.?limit|too many requests)' then 'provider rate limited'
    when coalesce(p_error, '') ~* '(unavailable|connection|network)' then 'provider unavailable'
    when coalesce(p_error, '') ~* '(invalid|malformed|schema|parse)' then 'provider response invalid'
    else 'catalog research failed'
  end;

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

create or replace function app_finance.record_catalog_automation_heartbeat(
  p_task_name text
)
returns table (run_id uuid, recorded_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_now timestamptz := now();
  v_task_name text := btrim(coalesce(p_task_name, ''));
begin
  if char_length(v_task_name) not between 1 and 160
    or v_task_name !~ '^[A-Za-z0-9][A-Za-z0-9._:-]*$' then
    raise exception 'invalid task name' using errcode = '22023';
  end if;
  insert into app_finance.catalog_research_runs (
    task_name, run_type, status, started_at, completed_at, summary
  ) values (v_task_name, 'heartbeat', 'completed', v_now, v_now, '{}'::jsonb)
  returning id into v_id;
  return query select v_id, v_now;
end;
$$;

revoke execute on function app_private.catalog_normalize_text(text)
  from public, anon, authenticated, service_role;
revoke execute on function app_private.catalog_identity_key(
  app_finance.account_type,text,text,text,text,text,text
) from public, anon, authenticated, service_role;
revoke execute on function app_private.set_catalog_identity()
  from public, anon, authenticated, service_role;
revoke execute on function app_private.protect_catalog_version()
  from public, anon, authenticated, service_role;
revoke execute on function app_private.catalog_json_nodes(jsonb)
  from public, anon, authenticated, service_role;
revoke execute on function app_private.enqueue_catalog_research_common(
  app_finance.account_type,text,text,text,text,text,text,text,
  app_finance.catalog_queue_reason,integer,uuid
) from public, anon, authenticated, service_role;
revoke execute on function app_private.assert_catalog_public_payload(jsonb)
  from public, anon, authenticated, service_role;
revoke execute on function app_private.validate_catalog_version_insert()
  from public, anon, authenticated, service_role;
revoke execute on function app_private.protect_catalog_source()
  from public, anon, authenticated, service_role;

revoke execute on function app_finance.enqueue_due_catalog_research()
  from public, anon, authenticated;
revoke execute on function app_finance.get_catalog_research_work(integer)
  from public, anon, authenticated;
revoke execute on function app_finance.upsert_catalog_research_result(jsonb)
  from public, anon, authenticated;
revoke execute on function app_finance.fail_catalog_research_work(uuid,text)
  from public, anon, authenticated;
revoke execute on function app_finance.record_catalog_automation_heartbeat(text)
  from public, anon, authenticated;
revoke execute on function app_finance.catalog_status_summary()
  from public, anon, authenticated;

notify pgrst, 'reload schema';
