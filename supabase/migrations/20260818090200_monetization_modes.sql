-- Explicit, server-controlled commercial lifecycle.  This migration is
-- additive: existing campaigns, grants, subscriptions and audit rows are not
-- rewritten.

create type app_commercial.monetization_mode as enum (
  'open_early_access',
  'timed_early_access',
  'paid_live'
);

alter type app_commercial.effective_source add value if not exists 'open_early_access';

create table app_commercial.monetization_state (
  singleton boolean primary key default true check (singleton),
  mode app_commercial.monetization_mode not null default 'open_early_access',
  timed_early_access_started_at timestamptz,
  timed_early_access_ends_at timestamptz,
  configured_duration_days integer not null default 90 check (configured_duration_days between 1 and 3650),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  check (
    (mode = 'timed_early_access' and timed_early_access_started_at is not null and timed_early_access_ends_at is not null)
    or mode <> 'timed_early_access'
  ),
  check (timed_early_access_ends_at is null or timed_early_access_ends_at > timed_early_access_started_at)
);

create trigger trg_monetization_state_updated_at
  before update on app_commercial.monetization_state
  for each row execute function app_private.set_updated_at();

insert into app_commercial.monetization_state (singleton, mode, configured_duration_days)
values (true, 'open_early_access', 90)
on conflict (singleton) do nothing;

alter table app_commercial.monetization_state enable row level security;
create policy monetization_state_read_authenticated on app_commercial.monetization_state
  for select to authenticated using (true);
create policy monetization_state_admin_all on app_commercial.monetization_state
  for all to authenticated
  using (app_private.is_commercial_admin((select auth.uid())))
  with check (app_private.is_commercial_admin((select auth.uid())));
grant select on app_commercial.monetization_state to authenticated;

-- The canonical resolver is deliberately the only place that applies open
-- Early Access.  The synthetic entitlement is not stored as a grant.
create or replace function app_commercial.resolve_effective_entitlement(
  p_user_id uuid default null,
  p_now timestamptz default now()
)
returns table (
  user_id uuid, effective_plan app_commercial.plan_key,
  source app_commercial.effective_source, starts_at timestamptz,
  ends_at timestamptz, subscription_status app_commercial.subscription_status,
  renewal_at timestamptz, features jsonb, limits jsonb, metadata jsonb
)
language plpgsql stable security invoker set search_path = '' as $$
declare v_user uuid := coalesce(p_user_id, (select auth.uid()));
begin
  if v_user is null then raise exception 'missing authenticated user' using errcode = '28000'; end if;
  if current_user not in ('postgres', 'service_role', 'supabase_admin')
    and v_user <> (select auth.uid())
    and not app_private.is_commercial_admin((select auth.uid())) then
    raise exception 'not authorized' using errcode = '42501';
  end if;
  return query
  with state as (select * from app_commercial.monetization_state where singleton),
  chosen as (
    select * from (
      -- Explicit grants and verified subscriptions always outrank the open
      -- mode. This retains their source for correct user-facing messaging.
      select eg.user_id, eg.plan_key, 'admin_grant'::app_commercial.effective_source source,
        eg.starts_at, eg.ends_at, null::app_commercial.subscription_status subscription_status,
        null::timestamptz renewal_at, 10 priority,
        jsonb_build_object('grant_id', eg.id, 'grant_source', eg.source) metadata
      from app_commercial.entitlement_grants eg
      where eg.user_id = v_user and eg.plan_key = 'pro' and eg.source = 'admin_grant'
        and eg.status = 'active' and eg.starts_at <= p_now and (eg.ends_at is null or eg.ends_at > p_now)
      union all
      select ps.user_id, ps.plan_key, 'paid'::app_commercial.effective_source,
        ps.starts_at, ps.expires_at, ps.status,
        case when ps.auto_renewing then ps.expires_at else null end, 20,
        jsonb_build_object('subscription_id', ps.id, 'provider', ps.provider,
          'base_plan_id', ps.provider_base_plan_id)
      from app_commercial.paid_subscriptions ps
      where ps.user_id = v_user and ps.status in ('active','in_grace_period','canceled')
        and (ps.expires_at is null or ps.expires_at > p_now)
      union all
      select v_user, 'pro'::app_commercial.plan_key, 'open_early_access'::app_commercial.effective_source,
        null::timestamptz, null::timestamptz, null::app_commercial.subscription_status,
        null::timestamptz, 30, jsonb_build_object('mode', 'open_early_access')
      from state where mode = 'open_early_access'
      union all
      select eg.user_id, eg.plan_key,
        case when eg.source in ('early_access','migration','promotional_campaign')
          then 'early_access'::app_commercial.effective_source else 'standard_trial'::app_commercial.effective_source end,
        eg.starts_at, eg.ends_at, null::app_commercial.subscription_status,
        null::timestamptz,
        case when eg.source in ('early_access','migration','promotional_campaign') then 40 else 50 end,
        jsonb_build_object('grant_id', eg.id, 'grant_source', eg.source, 'campaign_id', eg.campaign_id)
      from app_commercial.entitlement_grants eg
      where eg.user_id = v_user and eg.plan_key = 'pro' and eg.status = 'active'
        and eg.starts_at <= p_now and (eg.ends_at is null or eg.ends_at > p_now)
      union all
      select v_user, 'free'::app_commercial.plan_key, 'free'::app_commercial.effective_source,
        null, null, null, null, 100, '{}'::jsonb
    ) candidates order by priority, ends_at desc nulls first limit 1
  ), feature_rows as (
    select f.key, coalesce(pfe.enabled, false) and f.active enabled,
      case when coalesce(pfe.enabled, false) and f.active then pfe.limit_value else 0 end limit_value
    from chosen c join app_commercial.features f on true
    left join app_commercial.plan_feature_entitlements pfe on pfe.plan_key = c.plan_key and pfe.feature_key = f.key
  )
  select c.user_id, c.plan_key, c.source, c.starts_at, c.ends_at, c.subscription_status, c.renewal_at,
    coalesce(jsonb_object_agg(fr.key, fr.enabled), '{}'::jsonb),
    coalesce(jsonb_object_agg(fr.key, fr.limit_value) filter (where fr.limit_value is not null), '{}'::jsonb), c.metadata
  from chosen c left join feature_rows fr on true
  group by c.user_id, c.plan_key, c.source, c.starts_at, c.ends_at, c.subscription_status, c.renewal_at, c.metadata;
end;
$$;

-- New users do not receive a misleading timed grant while access is open.
create or replace function app_private.grant_initial_commercial_entitlement(
  p_user_id uuid, p_reason text default 'Initial commercial entitlement grant'
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_mode app_commercial.monetization_mode;
  v_campaign app_commercial.promotional_campaigns%rowtype;
  v_starts_at timestamptz := now();
  v_ends_at timestamptz;
  v_source app_commercial.grant_source;
  v_grant_id uuid;
begin
  select mode into v_mode from app_commercial.monetization_state where singleton;
  if v_mode = 'open_early_access' then return null; end if;
  select * into v_campaign from app_commercial.promotional_campaigns c
  where c.active and c.campaign_type = 'early_access'
    and (c.eligible_from is null or c.eligible_from <= v_starts_at)
    and (c.eligible_until is null or c.eligible_until >= v_starts_at)
  order by c.created_at desc limit 1;
  if not found then
    select * into v_campaign from app_commercial.promotional_campaigns c
    where c.active and c.campaign_type = 'standard_trial'
    order by c.created_at desc limit 1;
  end if;
  if not found then return null; end if;
  v_ends_at := least(v_starts_at + make_interval(days => v_campaign.duration_days),
    coalesce(v_campaign.absolute_ends_at, 'infinity'::timestamptz));
  v_source := case v_campaign.campaign_type
    when 'early_access' then 'early_access'::app_commercial.grant_source
    when 'standard_trial' then 'standard_trial'::app_commercial.grant_source
    else 'promotional_campaign'::app_commercial.grant_source end;
  insert into app_commercial.entitlement_grants (
    user_id, plan_key, source, campaign_id, starts_at, ends_at, reason
  ) values (p_user_id, v_campaign.plan_key, v_source, v_campaign.id,
    v_starts_at, v_ends_at, p_reason)
  on conflict do nothing returning id into v_grant_id;
  return v_grant_id;
end;
$$;

create or replace function app_commercial.start_monetization_cycle(
  p_actor_user_id uuid, p_reason text
) returns app_commercial.monetization_state
language plpgsql security definer set search_path = '' as $$
declare v_state app_commercial.monetization_state%rowtype;
declare v_before jsonb;
declare v_campaign app_commercial.promotional_campaigns%rowtype;
declare v_started_at timestamptz := now();
begin
  if char_length(trim(coalesce(p_reason, ''))) < 6 then raise exception 'reason_required'; end if;
  select * into v_state from app_commercial.monetization_state where singleton for update;
  if v_state.mode = 'timed_early_access' then return v_state; end if;
  if v_state.mode <> 'open_early_access' then raise exception 'invalid_mode_transition'; end if;
  v_before := to_jsonb(v_state);
  select * into v_campaign from app_commercial.promotional_campaigns
    where campaign_type = 'early_access' order by created_at desc limit 1 for update;
  if not found then raise exception 'early_access_campaign_missing'; end if;
  update app_commercial.promotional_campaigns set active = true,
    eligible_from = v_started_at, absolute_ends_at = v_started_at + make_interval(days => v_state.configured_duration_days)
    where id = v_campaign.id returning * into v_campaign;
  update app_commercial.monetization_state set mode = 'timed_early_access',
    timed_early_access_started_at = v_started_at,
    timed_early_access_ends_at = v_started_at + make_interval(days => configured_duration_days),
    updated_by = p_actor_user_id where singleton returning * into v_state;
  insert into app_commercial.entitlement_grants (user_id, plan_key, source, campaign_id, starts_at, ends_at, granted_by, reason)
  select p.id, 'pro', 'early_access', v_campaign.id, v_started_at,
    v_state.timed_early_access_ends_at, p_actor_user_id, 'Timed Early Access launch cohort'
  from app_core.profiles p
  on conflict do nothing;
  perform app_private.audit_commercial_mutation(p_actor_user_id, 'start_monetization_cycle',
    'monetization_state', 'singleton', v_before, to_jsonb(v_state), p_reason);
  return v_state;
end;
$$;
grant execute on function app_commercial.start_monetization_cycle(uuid, text) to service_role;

create or replace function app_commercial.current_published_catalog()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object(
    'plans', coalesce((select jsonb_agg(to_jsonb(p) order by p.sort_order)
      from app_commercial.plans p where p.enabled and p.public), '[]'::jsonb),
    'prices', coalesce((select jsonb_agg(to_jsonb(pp) order by pp.plan_key, pp.interval)
      from app_commercial.plan_prices pp join app_commercial.plans p on p.key = pp.plan_key
      where pp.status = 'published' and p.enabled and p.public and pp.effective_from <= now()
        and (pp.effective_until is null or pp.effective_until > now())), '[]'::jsonb),
    'features', coalesce((select jsonb_agg(to_jsonb(f) order by f.key)
      from app_commercial.features f where f.active), '[]'::jsonb),
    'monetization', (select jsonb_build_object('mode', mode, 'timed_early_access_ends_at', timed_early_access_ends_at)
      from app_commercial.monetization_state where singleton),
    'billing_readiness', (select jsonb_build_object(
      'provider', pc.status, 'product', coalesce((select provider_sync_status::text from app_commercial.plan_prices where provider = 'google_play' and provider_product_id = 'finance_suit_pro' order by created_at desc limit 1), 'not_configured'),
      'verification', case when exists (select 1 from app_commercial.paid_subscriptions where last_verified_at is not null) then 'verified' else 'not_verified' end)
      from app_commercial.provider_configurations pc where pc.provider = 'google_play')
  );
$$;
