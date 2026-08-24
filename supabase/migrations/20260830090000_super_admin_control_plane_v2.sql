-- Transactional invariants for Finance Suit Super Admin control-plane v2.
-- Browser callers never receive EXECUTE on these functions; protected Edge
-- Functions invoke them with service-role authority after verifying the JWT.

create or replace function app_commercial.update_monetization_duration(
  p_actor_user_id uuid,
  p_duration_days integer,
  p_reason text
) returns app_commercial.monetization_state
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_before app_commercial.monetization_state%rowtype;
  v_after app_commercial.monetization_state%rowtype;
begin
  if char_length(btrim(coalesce(p_reason, ''))) < 6 then
    raise exception 'reason_required';
  end if;
  if p_duration_days is null or p_duration_days < 1 or p_duration_days > 3650 then
    raise exception 'invalid_duration';
  end if;
  select * into v_before
    from app_commercial.monetization_state where singleton for update;
  if v_before.mode <> 'open_early_access' then
    raise exception 'duration_locked_after_cycle_start';
  end if;
  if v_before.configured_duration_days = p_duration_days then return v_before; end if;
  update app_commercial.monetization_state
    set configured_duration_days = p_duration_days, updated_by = p_actor_user_id
    where singleton returning * into v_after;
  perform app_private.audit_commercial_mutation(
    p_actor_user_id, 'update_monetization_duration', 'monetization_state',
    'singleton', to_jsonb(v_before), to_jsonb(v_after), btrim(p_reason)
  );
  return v_after;
end;
$$;

create or replace function app_commercial.transition_paid_live(
  p_actor_user_id uuid,
  p_reason text
) returns app_commercial.monetization_state
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_before app_commercial.monetization_state%rowtype;
  v_after app_commercial.monetization_state%rowtype;
begin
  if char_length(btrim(coalesce(p_reason, ''))) < 6 then raise exception 'reason_required'; end if;
  select * into v_before
    from app_commercial.monetization_state where singleton for update;
  if v_before.mode = 'paid_live' then return v_before; end if;
  if v_before.mode <> 'timed_early_access' then raise exception 'invalid_mode_transition'; end if;
  if v_before.timed_early_access_ends_at is null or now() < v_before.timed_early_access_ends_at then
    raise exception 'timed_early_access_not_finished';
  end if;
  update app_commercial.monetization_state
    set mode = 'paid_live', updated_by = p_actor_user_id
    where singleton returning * into v_after;
  perform app_private.audit_commercial_mutation(
    p_actor_user_id, 'transition_paid_live', 'monetization_state', 'singleton',
    to_jsonb(v_before), to_jsonb(v_after), btrim(p_reason)
  );
  return v_after;
end;
$$;

create or replace function app_commercial.publish_plan_price(
  p_actor_user_id uuid,
  p_price_id uuid,
  p_reason text
) returns app_commercial.plan_prices
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_before app_commercial.plan_prices%rowtype;
  v_after app_commercial.plan_prices%rowtype;
  v_now timestamptz := now();
begin
  if char_length(btrim(coalesce(p_reason, ''))) < 6 then raise exception 'reason_required'; end if;
  select * into v_before from app_commercial.plan_prices where id = p_price_id for update;
  if not found then raise exception 'price_not_found'; end if;
  if v_before.status = 'published' then return v_before; end if;
  if v_before.status <> 'draft' then raise exception 'price_not_draft'; end if;
  if v_before.provider <> 'manual' and v_before.provider_sync_status <> 'synced' then
    raise exception 'provider_not_synced';
  end if;
  update app_commercial.plan_prices
    set status = 'archived', effective_until = v_now
    where plan_key = v_before.plan_key and provider = v_before.provider
      and interval = v_before.interval and status = 'published'
      and effective_until is null and id <> p_price_id;
  update app_commercial.plan_prices
    set status = 'published', effective_from = greatest(effective_from, v_now),
        effective_until = null
    where id = p_price_id returning * into v_after;
  perform app_private.audit_commercial_mutation(
    p_actor_user_id, 'publish_price', 'plan_price', p_price_id::text,
    to_jsonb(v_before), to_jsonb(v_after), btrim(p_reason)
  );
  return v_after;
end;
$$;

create or replace function app_commercial.upsert_platform_admin(
  p_actor_user_id uuid,
  p_user_id uuid,
  p_role app_commercial.admin_role,
  p_status app_commercial.admin_status,
  p_reason text
) returns app_commercial.platform_admins
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_before app_commercial.platform_admins%rowtype;
  v_after app_commercial.platform_admins%rowtype;
  v_active_super_admins integer;
begin
  if char_length(btrim(coalesce(p_reason, ''))) < 6 then raise exception 'reason_required'; end if;
  if not exists (select 1 from auth.users where id = p_user_id) then raise exception 'user_not_found'; end if;
  lock table app_commercial.platform_admins in share row exclusive mode;
  select * into v_before from app_commercial.platform_admins where user_id = p_user_id;
  select count(*) into v_active_super_admins from app_commercial.platform_admins
    where role = 'super_admin' and status = 'active';
  if p_user_id = p_actor_user_id and (p_role <> 'super_admin' or p_status <> 'active') then
    raise exception 'self_revocation_forbidden';
  end if;
  if v_before.user_id is not null and v_before.role = 'super_admin' and v_before.status = 'active'
      and (p_role <> 'super_admin' or p_status <> 'active') and v_active_super_admins <= 1 then
    raise exception 'last_super_admin_forbidden';
  end if;
  insert into app_commercial.platform_admins (user_id, role, status, created_by)
    values (p_user_id, p_role, p_status, p_actor_user_id)
    on conflict (user_id) do update set role = excluded.role, status = excluded.status
    returning * into v_after;
  perform app_private.audit_commercial_mutation(
    p_actor_user_id, 'update_platform_admin', 'platform_admin', p_user_id::text,
    case when v_before.user_id is null then null else to_jsonb(v_before) end,
    to_jsonb(v_after), btrim(p_reason)
  );
  return v_after;
end;
$$;

create or replace function app_finance.admin_requeue_catalog_research(
  p_actor_user_id uuid,
  p_queue_item_id uuid,
  p_reason text
) returns app_finance.catalog_research_queue
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_before app_finance.catalog_research_queue%rowtype;
  v_after app_finance.catalog_research_queue%rowtype;
  v_max_attempts integer;
begin
  if char_length(btrim(coalesce(p_reason, ''))) < 6 then raise exception 'reason_required'; end if;
  select max_attempts into v_max_attempts from app_finance.catalog_configuration where singleton;
  select * into v_before from app_finance.catalog_research_queue where id = p_queue_item_id for update;
  if not found then raise exception 'queue_item_not_found'; end if;
  if v_before.status = 'queued' then return v_before; end if;
  if v_before.status <> 'failed' or v_before.attempts >= v_max_attempts then
    raise exception 'requeue_guard_failed';
  end if;
  update app_finance.catalog_research_queue
    set status = 'queued', available_at = now(), leased_at = null,
        lease_expires_at = null, last_error = null
    where id = p_queue_item_id returning * into v_after;
  perform app_private.audit_commercial_mutation(
    p_actor_user_id, 'requeue_catalog_research', 'catalog_research_queue',
    p_queue_item_id::text, to_jsonb(v_before), to_jsonb(v_after), btrim(p_reason)
  );
  return v_after;
end;
$$;

create or replace function app_finance.update_catalog_configuration_admin(
  p_actor_user_id uuid,
  p_freshness_days integer,
  p_curator_batch_size integer,
  p_lease_minutes integer,
  p_max_attempts integer,
  p_enqueue_rate_limit_per_hour integer,
  p_reason text
) returns app_finance.catalog_configuration
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_before app_finance.catalog_configuration%rowtype;
  v_after app_finance.catalog_configuration%rowtype;
begin
  if char_length(btrim(coalesce(p_reason, ''))) < 6 then raise exception 'reason_required'; end if;
  if p_freshness_days not between 1 and 365
      or p_curator_batch_size not between 1 and 50
      or p_lease_minutes not between 1 and 1440
      or p_max_attempts not between 1 and 20
      or p_enqueue_rate_limit_per_hour not between 1 and 1000 then
    raise exception 'invalid_catalog_configuration';
  end if;
  select * into v_before from app_finance.catalog_configuration where singleton for update;
  update app_finance.catalog_configuration set
    freshness_window = make_interval(days => p_freshness_days),
    curator_batch_size = p_curator_batch_size,
    lease_duration = make_interval(mins => p_lease_minutes),
    max_attempts = p_max_attempts,
    enqueue_rate_limit_per_hour = p_enqueue_rate_limit_per_hour
    where singleton returning * into v_after;
  perform app_private.audit_commercial_mutation(
    p_actor_user_id, 'update_catalog_configuration', 'catalog_configuration',
    'singleton', to_jsonb(v_before), to_jsonb(v_after), btrim(p_reason)
  );
  return v_after;
end;
$$;

create or replace function app_finance.admin_catalog_products(
  p_query text default '',
  p_status app_finance.catalog_product_status default null,
  p_offset integer default 0,
  p_limit integer default 25
) returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with filtered as (
    select p.*, v.id as current_version_id, v.version_number,
      v.research_status, v.verified_at
    from app_finance.financial_product_catalog p
    left join app_finance.financial_product_catalog_versions v
      on v.product_id = p.id and v.superseded_at is null
    where (p_status is null or p.status = p_status)
      and (coalesce(btrim(p_query), '') = '' or p.issuer_name ilike '%' || p_query || '%'
        or p.product_name ilike '%' || p_query || '%')
  )
  select jsonb_build_object(
    'count', (select count(*) from filtered),
    'products', coalesce((select jsonb_agg(to_jsonb(f) order by f.updated_at desc)
      from (select * from filtered order by updated_at desc offset greatest(p_offset, 0)
        limit least(greatest(p_limit, 1), 100)) f), '[]'::jsonb)
  );
$$;

create or replace function app_finance.admin_catalog_product_detail(p_product_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'product', to_jsonb(p),
    'versions', coalesce((select jsonb_agg(to_jsonb(v) - 'research_payload' order by v.version_number desc)
      from app_finance.financial_product_catalog_versions v where v.product_id = p.id), '[]'::jsonb),
    'sources', coalesce((select jsonb_agg(to_jsonb(s) order by s.checked_at desc)
      from app_finance.financial_product_catalog_sources s
      join app_finance.financial_product_catalog_versions v on v.id = s.version_id
      where v.product_id = p.id), '[]'::jsonb)
  ) from app_finance.financial_product_catalog p where p.id = p_product_id;
$$;

create or replace function app_finance.admin_catalog_queue(
  p_status app_finance.catalog_queue_status default null,
  p_offset integer default 0,
  p_limit integer default 25
) returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with filtered as (
    select * from app_finance.catalog_research_queue
    where p_status is null or status = p_status
  )
  select jsonb_build_object(
    'count', (select count(*) from filtered),
    'items', coalesce((select jsonb_agg(to_jsonb(f) order by f.priority desc, f.created_at)
      from (select * from filtered order by priority desc, created_at
        offset greatest(p_offset, 0) limit least(greatest(p_limit, 1), 100)) f), '[]'::jsonb)
  );
$$;

create or replace function app_finance.admin_catalog_runs(
  p_offset integer default 0,
  p_limit integer default 25
) returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'count', (select count(*) from app_finance.catalog_research_runs),
    'runs', coalesce((select jsonb_agg(to_jsonb(r) order by r.started_at desc)
      from (select * from app_finance.catalog_research_runs order by started_at desc
        offset greatest(p_offset, 0) limit least(greatest(p_limit, 1), 100)) r), '[]'::jsonb)
  );
$$;

create or replace function app_finance.admin_catalog_configuration()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$ select to_jsonb(c) from app_finance.catalog_configuration c where singleton; $$;

create or replace function app_core.admin_notification_health()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'outbox', jsonb_build_object(
      'pending', (select count(*) from app_core.notification_outbox where status in ('pending','retry')),
      'sending', (select count(*) from app_core.notification_outbox where status = 'sending'),
      'failed', (select count(*) from app_core.notification_outbox where status = 'failed'),
      'sent', (select count(*) from app_core.notification_outbox where status = 'sent' and sent_at >= now() - interval '7 days'),
      'attemptDistribution', coalesce((select jsonb_object_agg(attempt_count, total)
        from (select attempt_count, count(*) total from app_core.notification_outbox
          where created_at >= now() - interval '7 days' group by attempt_count) d), '{}'::jsonb)
    ),
    'devices', jsonb_build_object(
      'enabled', (select count(*) from app_core.push_devices where is_enabled),
      'disabled', (select count(*) from app_core.push_devices where not is_enabled)
    ),
    'logicalRecent', (select count(*) from app_core.notifications where created_at >= now() - interval '7 days'),
    'lastActivity', (select max(coalesce(sent_at, last_attempt_at, created_at)) from app_core.notification_outbox),
    'eventCatalog', coalesce((select jsonb_agg(jsonb_build_object(
      'event_key', event_key, 'category', category, 'is_critical', is_critical,
      'entity_type', entity_type, 'active', true
    ) order by event_key) from app_core.notification_event_catalog), '[]'::jsonb)
  );
$$;

revoke all on function app_commercial.update_monetization_duration(uuid, integer, text) from public, anon, authenticated;
revoke all on function app_commercial.transition_paid_live(uuid, text) from public, anon, authenticated;
revoke all on function app_commercial.publish_plan_price(uuid, uuid, text) from public, anon, authenticated;
revoke all on function app_commercial.upsert_platform_admin(uuid, uuid, app_commercial.admin_role, app_commercial.admin_status, text) from public, anon, authenticated;
revoke all on function app_finance.admin_requeue_catalog_research(uuid, uuid, text) from public, anon, authenticated;
revoke all on function app_finance.update_catalog_configuration_admin(uuid, integer, integer, integer, integer, integer, text) from public, anon, authenticated;
revoke all on function app_finance.admin_catalog_products(text, app_finance.catalog_product_status, integer, integer) from public, anon, authenticated;
revoke all on function app_finance.admin_catalog_product_detail(uuid) from public, anon, authenticated;
revoke all on function app_finance.admin_catalog_queue(app_finance.catalog_queue_status, integer, integer) from public, anon, authenticated;
revoke all on function app_finance.admin_catalog_runs(integer, integer) from public, anon, authenticated;
revoke all on function app_finance.admin_catalog_configuration() from public, anon, authenticated;
revoke all on function app_core.admin_notification_health() from public, anon, authenticated;

grant execute on function app_commercial.update_monetization_duration(uuid, integer, text) to service_role;
grant execute on function app_commercial.transition_paid_live(uuid, text) to service_role;
grant execute on function app_commercial.publish_plan_price(uuid, uuid, text) to service_role;
grant execute on function app_commercial.upsert_platform_admin(uuid, uuid, app_commercial.admin_role, app_commercial.admin_status, text) to service_role;
grant execute on function app_finance.admin_requeue_catalog_research(uuid, uuid, text) to service_role;
grant execute on function app_finance.update_catalog_configuration_admin(uuid, integer, integer, integer, integer, integer, text) to service_role;
grant execute on function app_finance.admin_catalog_products(text, app_finance.catalog_product_status, integer, integer) to service_role;
grant execute on function app_finance.admin_catalog_product_detail(uuid) to service_role;
grant execute on function app_finance.admin_catalog_queue(app_finance.catalog_queue_status, integer, integer) to service_role;
grant execute on function app_finance.admin_catalog_runs(integer, integer) to service_role;
grant execute on function app_finance.admin_catalog_configuration() to service_role;
grant execute on function app_core.admin_notification_health() to service_role;
