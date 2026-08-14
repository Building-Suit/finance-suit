-- Read-only browser for the public financial-product catalog populated by the
-- scheduled research workflow. This migration was first applied remotely
-- before the future-dated catalog base migration existed. Keep it replay-safe:
-- catalog v2 defines the final function after all catalog tables are present.
do $migration$
begin
  if to_regclass('app_finance.financial_product_catalog') is null then
    return;
  end if;

  execute $function$
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
    as $body$
      select
        product.id,
        version.id,
        product.account_type,
        product.country_code,
        product.issuer_name,
        product.official_website,
        product.product_name,
        product.tier,
        product.network,
        product.currency_code,
        version.version_number,
        version.research_payload,
        coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', source.source_identifier,
            'url', source.url,
            'title', source.title,
            'officialDomain', source.official_domain,
            'publishedDate', source.published_date,
            'effectiveDate', source.effective_date,
            'contentHash', source.content_hash,
            'checkedAt', source.checked_at
          ) order by source.source_identifier)
          from app_finance.financial_product_catalog_sources source
          where source.version_id = version.id
        ), '[]'::jsonb),
        version.verified_at,
        version.verified_at >= now() - interval '90 days',
        greatest(
          0,
          floor(extract(epoch from (now() - version.verified_at)) / 86400)
        )::integer,
        100
      from app_finance.financial_product_catalog product
      join lateral (
        select candidate.*
        from app_finance.financial_product_catalog_versions candidate
        where candidate.product_id = product.id
          and candidate.superseded_at is null
        order by candidate.version_number desc
        limit 1
      ) version on true
      where (select auth.uid()) is not null
        and product.status = 'active'
        and product.account_type = p_account_type
        and (
          nullif(upper(btrim(coalesce(p_country_code, ''))), '') is null
          or product.country_code = upper(btrim(p_country_code))
        )
        and (
          nullif(app_private.catalog_normalize_text(p_query), '') is null
          or app_private.catalog_normalize_text(product.issuer_name)
              like '%' || app_private.catalog_normalize_text(p_query) || '%'
          or app_private.catalog_normalize_text(product.product_name)
              like '%' || app_private.catalog_normalize_text(p_query) || '%'
        )
      order by product.issuer_name, product.product_name, product.tier
    $body$
  $function$;

  execute 'revoke all on function app_finance.catalog_browse('
    || 'app_finance.account_type, text, text) from public, anon';
  execute 'grant execute on function app_finance.catalog_browse('
    || 'app_finance.account_type, text, text) to authenticated';
end;
$migration$;
