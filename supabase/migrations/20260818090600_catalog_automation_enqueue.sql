-- Separate trusted catalog automation enqueue from the authenticated app path.
-- Supabase Management SQL runs as postgres without JWT claims, so it cannot
-- and must not use the auth.uid()-scoped user RPC.

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
    or (p_currency_code is not null and upper(btrim(p_currency_code)) !~ '^[A-Z]{3}$')
    or (p_network is not null and lower(btrim(p_network)) not in ('visa','mastercard','other','unknown'))
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

  v_work_key := case when v_product_id is null then 'identity:' || v_identity
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
        btrim(p_issuer_name),
        nullif(btrim(p_official_website), ''),
        btrim(p_product_name),
        nullif(btrim(p_tier), ''),
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

create or replace function app_finance.enqueue_catalog_research_automation(
  p_account_type app_finance.account_type,
  p_country_code text,
  p_issuer_name text,
  p_product_name text,
  p_tier text default null,
  p_network text default null,
  p_currency_code text default null,
  p_official_website text default null,
  p_reason app_finance.catalog_queue_reason default 'initial_seed',
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
begin
  if p_reason not in (
    'initial_seed', 'new_product', 'stale', 'conflicting_sources',
    'missing_fields', 'source_changed', 'manual_review'
  ) then
    raise exception 'invalid automation queue reason' using errcode = '22023';
  end if;

  return query
  select e.queue_item_id, e.queue_status
  from app_private.enqueue_catalog_research_common(
    p_account_type, p_country_code, p_issuer_name, p_product_name,
    p_tier, p_network, p_currency_code, p_official_website,
    p_reason, p_priority, null
  ) e;
end;
$$;

revoke execute on function app_private.enqueue_catalog_research_common(
  app_finance.account_type,text,text,text,text,text,text,text,
  app_finance.catalog_queue_reason,integer,uuid
) from public, anon, authenticated;

revoke execute on function app_finance.enqueue_catalog_research_automation(
  app_finance.account_type,text,text,text,text,text,text,text,
  app_finance.catalog_queue_reason,integer
) from public, anon, authenticated;

grant execute on function app_finance.enqueue_catalog_research_automation(
  app_finance.account_type,text,text,text,text,text,text,text,
  app_finance.catalog_queue_reason,integer
) to service_role;

notify pgrst, 'reload schema';
