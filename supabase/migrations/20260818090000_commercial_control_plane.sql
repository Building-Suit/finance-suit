-- Finance Suit commercial control plane.
-- Authoritative money uses integer minor units. User identity is auth.users.id,
-- matching app_core.profiles.id. This migration is additive and never touches
-- existing financial records.

create schema if not exists app_commercial;

alter role authenticator set pgrst.db_schemas =
  'app_core,app_finance,app_work,app_salary,app_reports,app_commercial';
notify pgrst, 'reload config';

create type app_commercial.plan_key as enum ('free', 'pro');
create type app_commercial.billing_provider as enum ('google_play', 'apple_app_store', 'manual');
create type app_commercial.billing_interval as enum ('none', 'month', 'year');
create type app_commercial.config_status as enum ('draft', 'published', 'archived');
create type app_commercial.provider_sync_status as enum ('not_configured', 'draft', 'pending_sync', 'synced', 'mismatch', 'failed');
create type app_commercial.feature_value_type as enum ('boolean', 'limit');
create type app_commercial.campaign_type as enum ('early_access', 'standard_trial', 'promotion');
create type app_commercial.grant_source as enum ('early_access', 'standard_trial', 'admin_grant', 'migration', 'promotional_campaign');
create type app_commercial.grant_status as enum ('active', 'ended', 'revoked');
create type app_commercial.subscription_status as enum (
  'pending', 'active', 'in_grace_period', 'on_hold', 'paused',
  'canceled', 'expired', 'revoked', 'verification_failed'
);
create type app_commercial.effective_source as enum ('free', 'paid', 'admin_grant', 'early_access', 'standard_trial');
create type app_commercial.admin_role as enum ('super_admin', 'billing_admin', 'support_admin', 'read_only_admin');
create type app_commercial.admin_status as enum ('active', 'suspended', 'revoked');
create type app_commercial.announcement_severity as enum ('info', 'success', 'warning', 'critical');
create type app_commercial.announcement_audience as enum ('all', 'free', 'pro', 'early_access');

create table app_commercial.platform_admins (
  user_id uuid primary key references auth.users (id) on delete cascade,
  role app_commercial.admin_role not null,
  status app_commercial.admin_status not null default 'active',
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (created_by is null or created_by <> user_id)
);

create trigger trg_platform_admins_updated_at
  before update on app_commercial.platform_admins
  for each row execute function app_private.set_updated_at();

create or replace function app_private.is_commercial_admin(
  p_user_id uuid,
  p_roles app_commercial.admin_role[] default array['super_admin']::app_commercial.admin_role[]
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from app_commercial.platform_admins a
    where a.user_id = p_user_id
      and a.status = 'active'
      and a.role = any(p_roles)
  );
$$;

create or replace function app_commercial.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select app_private.is_commercial_admin((select auth.uid()), array['super_admin']::app_commercial.admin_role[]);
$$;

create table app_commercial.plans (
  key app_commercial.plan_key primary key,
  display_name text not null check (char_length(display_name) between 1 and 80),
  description text not null default '' check (char_length(description) <= 500),
  enabled boolean not null default true,
  public boolean not null default true,
  sort_order integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_plans_updated_at
  before update on app_commercial.plans
  for each row execute function app_private.set_updated_at();

create table app_commercial.plan_prices (
  id uuid primary key default gen_random_uuid(),
  plan_key app_commercial.plan_key not null references app_commercial.plans (key),
  provider app_commercial.billing_provider not null,
  interval app_commercial.billing_interval not null,
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  amount_minor bigint not null check (amount_minor >= 0),
  provider_product_id text check (provider_product_id is null or char_length(provider_product_id) between 1 and 160),
  provider_base_plan_id text check (provider_base_plan_id is null or char_length(provider_base_plan_id) between 1 and 160),
  status app_commercial.config_status not null default 'draft',
  provider_sync_status app_commercial.provider_sync_status not null default 'not_configured',
  effective_from timestamptz not null default now(),
  effective_until timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (effective_until is null or effective_until > effective_from),
  check (
    (plan_key = 'free' and interval = 'none' and amount_minor = 0)
    or (plan_key <> 'free' and interval in ('month', 'year') and amount_minor > 0)
  )
);

create unique index idx_plan_prices_one_published_active
  on app_commercial.plan_prices (plan_key, provider, interval)
  where status = 'published' and effective_until is null;
create index idx_plan_prices_public
  on app_commercial.plan_prices (status, plan_key, provider, interval);

create trigger trg_plan_prices_updated_at
  before update on app_commercial.plan_prices
  for each row execute function app_private.set_updated_at();

create table app_commercial.features (
  key text primary key check (key ~ '^[a-z][a-z0-9_]*$'),
  title text not null check (char_length(title) between 1 and 120),
  description text not null default '' check (char_length(description) <= 700),
  value_type app_commercial.feature_value_type not null default 'boolean',
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_features_updated_at
  before update on app_commercial.features
  for each row execute function app_private.set_updated_at();

create table app_commercial.plan_feature_entitlements (
  plan_key app_commercial.plan_key not null references app_commercial.plans (key) on delete cascade,
  feature_key text not null references app_commercial.features (key) on delete cascade,
  enabled boolean not null default false,
  limit_value integer check (limit_value is null or limit_value >= 0),
  config jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (plan_key, feature_key)
);

create trigger trg_plan_feature_entitlements_updated_at
  before update on app_commercial.plan_feature_entitlements
  for each row execute function app_private.set_updated_at();

create table app_commercial.promotional_campaigns (
  id uuid primary key default gen_random_uuid(),
  key text not null unique check (key ~ '^[a-z][a-z0-9_]*$'),
  name text not null check (char_length(name) between 1 and 120),
  campaign_type app_commercial.campaign_type not null,
  active boolean not null default false,
  plan_key app_commercial.plan_key not null references app_commercial.plans (key),
  duration_days integer not null check (duration_days between 1 and 3650),
  eligible_from timestamptz,
  eligible_until timestamptz,
  absolute_ends_at timestamptz,
  notes text not null default '' check (char_length(notes) <= 2000),
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (eligible_until is null or eligible_from is null or eligible_until > eligible_from)
);

create unique index idx_campaigns_one_active_per_type
  on app_commercial.promotional_campaigns (campaign_type)
  where active;

create trigger trg_promotional_campaigns_updated_at
  before update on app_commercial.promotional_campaigns
  for each row execute function app_private.set_updated_at();

create table app_commercial.entitlement_grants (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  plan_key app_commercial.plan_key not null references app_commercial.plans (key),
  source app_commercial.grant_source not null,
  campaign_id uuid references app_commercial.promotional_campaigns (id),
  starts_at timestamptz not null,
  ends_at timestamptz,
  status app_commercial.grant_status not null default 'active',
  granted_by uuid references auth.users (id),
  reason text not null default '' check (char_length(reason) <= 1000),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or ends_at > starts_at)
);

create unique index idx_entitlement_grants_user_campaign_once
  on app_commercial.entitlement_grants (user_id, campaign_id)
  where campaign_id is not null;
create index idx_entitlement_grants_resolver
  on app_commercial.entitlement_grants (user_id, status, starts_at, ends_at);

create trigger trg_entitlement_grants_updated_at
  before update on app_commercial.entitlement_grants
  for each row execute function app_private.set_updated_at();

create table app_commercial.paid_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  provider app_commercial.billing_provider not null,
  plan_key app_commercial.plan_key not null references app_commercial.plans (key),
  plan_price_id uuid references app_commercial.plan_prices (id),
  provider_product_id text not null check (char_length(provider_product_id) between 1 and 160),
  provider_base_plan_id text check (provider_base_plan_id is null or char_length(provider_base_plan_id) between 1 and 160),
  provider_purchase_token_hash text not null,
  provider_obfuscated_account_id text,
  status app_commercial.subscription_status not null,
  starts_at timestamptz,
  expires_at timestamptz,
  auto_renewing boolean,
  canceled_at timestamptz,
  last_verified_at timestamptz,
  provider_raw_status text,
  provider_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (expires_at is null or starts_at is null or expires_at > starts_at)
);

create unique index idx_paid_subscriptions_provider_token
  on app_commercial.paid_subscriptions (provider, provider_purchase_token_hash);
create index idx_paid_subscriptions_resolver
  on app_commercial.paid_subscriptions (user_id, status, expires_at);

create trigger trg_paid_subscriptions_updated_at
  before update on app_commercial.paid_subscriptions
  for each row execute function app_private.set_updated_at();

create table app_commercial.billing_events (
  id uuid primary key default gen_random_uuid(),
  provider app_commercial.billing_provider not null,
  provider_event_id text not null,
  event_type text not null check (char_length(event_type) between 1 and 100),
  subscription_id uuid references app_commercial.paid_subscriptions (id),
  user_id uuid references auth.users (id) on delete set null,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  processing_result text not null default 'received' check (char_length(processing_result) <= 120),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (provider, provider_event_id)
);

create table app_commercial.app_config (
  key text primary key check (key ~ '^[a-z][a-z0-9_]*$'),
  value jsonb not null,
  status app_commercial.config_status not null default 'published',
  validation jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_app_config_updated_at
  before update on app_commercial.app_config
  for each row execute function app_private.set_updated_at();

create table app_commercial.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 140),
  body text not null check (char_length(body) between 1 and 2000),
  active boolean not null default false,
  severity app_commercial.announcement_severity not null default 'info',
  audience app_commercial.announcement_audience not null default 'all',
  starts_at timestamptz,
  ends_at timestamptz,
  dismissible boolean not null default true,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at > starts_at)
);

create trigger trg_announcements_updated_at
  before update on app_commercial.announcements
  for each row execute function app_private.set_updated_at();

create table app_commercial.audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references auth.users (id) on delete set null,
  action text not null check (char_length(action) between 1 and 160),
  target_type text not null check (char_length(target_type) between 1 and 120),
  target_id text,
  before_state jsonb,
  after_state jsonb,
  reason text not null default '' check (char_length(reason) <= 2000),
  correlation_id text,
  created_at timestamptz not null default now()
);

create or replace function app_private.audit_commercial_mutation(
  p_actor_user_id uuid,
  p_action text,
  p_target_type text,
  p_target_id text,
  p_before_state jsonb,
  p_after_state jsonb,
  p_reason text,
  p_correlation_id text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  insert into app_commercial.audit_log (
    actor_user_id, action, target_type, target_id, before_state, after_state,
    reason, correlation_id
  )
  values (
    p_actor_user_id, p_action, p_target_type, p_target_id, p_before_state,
    p_after_state, coalesce(p_reason, ''), p_correlation_id
  )
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function app_commercial.resolve_effective_entitlement(
  p_user_id uuid default null,
  p_now timestamptz default now()
)
returns table (
  user_id uuid,
  effective_plan app_commercial.plan_key,
  source app_commercial.effective_source,
  starts_at timestamptz,
  ends_at timestamptz,
  subscription_status app_commercial.subscription_status,
  renewal_at timestamptz,
  features jsonb,
  limits jsonb,
  metadata jsonb
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_user uuid := coalesce(p_user_id, (select auth.uid()));
begin
  if v_user is null then
    raise exception 'missing authenticated user' using errcode = '28000';
  end if;
  if current_user not in ('postgres', 'service_role', 'supabase_admin')
    and v_user <> (select auth.uid())
    and not app_private.is_commercial_admin((select auth.uid())) then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  return query
  with chosen as (
    select
      s.user_id,
      s.plan_key,
      s.source,
      s.starts_at,
      s.ends_at,
      s.subscription_status,
      s.renewal_at,
      s.priority,
      s.metadata
    from (
      select
        ps.user_id,
        ps.plan_key,
        'paid'::app_commercial.effective_source as source,
        ps.starts_at,
        ps.expires_at as ends_at,
        ps.status as subscription_status,
        case when ps.auto_renewing is true then ps.expires_at else null end as renewal_at,
        10 as priority,
        jsonb_build_object('subscription_id', ps.id, 'provider', ps.provider) as metadata
      from app_commercial.paid_subscriptions ps
      where ps.user_id = v_user
        and ps.status in ('active', 'in_grace_period', 'canceled')
        and (ps.expires_at is null or ps.expires_at > p_now)

      union all

      select
        eg.user_id,
        eg.plan_key,
        case
          when eg.source = 'admin_grant' then 'admin_grant'::app_commercial.effective_source
          when eg.source in ('early_access', 'migration', 'promotional_campaign') then 'early_access'::app_commercial.effective_source
          else 'standard_trial'::app_commercial.effective_source
        end,
        eg.starts_at,
        eg.ends_at,
        null::app_commercial.subscription_status,
        null::timestamptz,
        case
          when eg.source = 'admin_grant' then 20
          when eg.source in ('early_access', 'migration', 'promotional_campaign') then 30
          else 40
        end,
        jsonb_build_object('grant_id', eg.id, 'campaign_id', eg.campaign_id, 'grant_source', eg.source) as metadata
      from app_commercial.entitlement_grants eg
      where eg.user_id = v_user
        and eg.plan_key = 'pro'
        and eg.status = 'active'
        and eg.starts_at <= p_now
        and (eg.ends_at is null or eg.ends_at > p_now)

      union all

      select
        v_user,
        'free'::app_commercial.plan_key,
        'free'::app_commercial.effective_source,
        null::timestamptz,
        null::timestamptz,
        null::app_commercial.subscription_status,
        null::timestamptz,
        100,
        '{}'::jsonb
    ) s
    order by s.priority, s.ends_at desc nulls first
    limit 1
  ),
  feature_rows as (
    select
      f.key,
      coalesce(pfe.enabled, false) and f.active as enabled,
      case when coalesce(pfe.enabled, false) and f.active then pfe.limit_value else 0 end as limit_value
    from chosen c
    join app_commercial.features f on true
    left join app_commercial.plan_feature_entitlements pfe
      on pfe.plan_key = c.plan_key and pfe.feature_key = f.key
  )
  select
    c.user_id,
    c.plan_key,
    c.source,
    c.starts_at,
    c.ends_at,
    c.subscription_status,
    c.renewal_at,
    coalesce(jsonb_object_agg(fr.key, fr.enabled), '{}'::jsonb) as features,
    coalesce(jsonb_object_agg(fr.key, fr.limit_value) filter (where fr.limit_value is not null), '{}'::jsonb) as limits,
    c.metadata
  from chosen c
  left join feature_rows fr on true
  group by c.user_id, c.plan_key, c.source, c.starts_at, c.ends_at, c.subscription_status, c.renewal_at, c.metadata;
end;
$$;

create or replace function app_private.grant_initial_commercial_entitlement(
  p_user_id uuid,
  p_reason text default 'Initial commercial entitlement grant'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_campaign app_commercial.promotional_campaigns%rowtype;
  v_starts_at timestamptz := now();
  v_ends_at timestamptz;
  v_source app_commercial.grant_source;
  v_grant_id uuid;
begin
  select *
  into v_campaign
  from app_commercial.promotional_campaigns c
  where c.active
    and c.campaign_type = 'early_access'
    and (c.eligible_from is null or c.eligible_from <= v_starts_at)
    and (c.eligible_until is null or c.eligible_until >= v_starts_at)
  order by c.created_at desc
  limit 1;

  if not found then
    select *
    into v_campaign
    from app_commercial.promotional_campaigns c
    where c.active
      and c.campaign_type = 'standard_trial'
    order by c.created_at desc
    limit 1;
  end if;

  if not found then
    return null;
  end if;

  v_ends_at := least(
    v_starts_at + make_interval(days => v_campaign.duration_days),
    coalesce(v_campaign.absolute_ends_at, 'infinity'::timestamptz)
  );
  v_source := case v_campaign.campaign_type
    when 'early_access' then 'early_access'::app_commercial.grant_source
    when 'standard_trial' then 'standard_trial'::app_commercial.grant_source
    else 'promotional_campaign'::app_commercial.grant_source
  end;

  insert into app_commercial.entitlement_grants (
    user_id, plan_key, source, campaign_id, starts_at, ends_at, reason
  )
  values (
    p_user_id, v_campaign.plan_key, v_source, v_campaign.id, v_starts_at,
    v_ends_at, p_reason
  )
  on conflict do nothing
  returning id into v_grant_id;

  return v_grant_id;
end;
$$;

create or replace function app_private.handle_new_user_commercial_grant()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app_private.grant_initial_commercial_entitlement(new.id, 'Automatic signup grant');
  return new;
end;
$$;

create trigger trg_app_core_profile_commercial_grant
  after insert on app_core.profiles
  for each row execute function app_private.handle_new_user_commercial_grant();

create or replace function app_commercial.current_published_catalog()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'plans', coalesce((
      select jsonb_agg(to_jsonb(p) order by p.sort_order)
      from app_commercial.plans p
      where p.enabled and p.public
    ), '[]'::jsonb),
    'prices', coalesce((
      select jsonb_agg(to_jsonb(pp) order by pp.plan_key, pp.interval)
      from app_commercial.plan_prices pp
      join app_commercial.plans p on p.key = pp.plan_key
      where pp.status = 'published'
        and p.enabled and p.public
        and pp.effective_from <= now()
        and (pp.effective_until is null or pp.effective_until > now())
    ), '[]'::jsonb),
    'features', coalesce((
      select jsonb_agg(to_jsonb(f) order by f.key)
      from app_commercial.features f
      where f.active
    ), '[]'::jsonb)
  );
$$;

create table app_commercial.provider_configurations (
  provider app_commercial.billing_provider primary key,
  package_name text not null default 'com.buildingsuit.finance',
  status app_commercial.provider_sync_status not null default 'not_configured',
  last_successful_sync_at timestamptz,
  last_error text,
  webhook_health jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_provider_configurations_updated_at
  before update on app_commercial.provider_configurations
  for each row execute function app_private.set_updated_at();

-- RLS
alter table app_commercial.platform_admins enable row level security;
alter table app_commercial.plans enable row level security;
alter table app_commercial.plan_prices enable row level security;
alter table app_commercial.features enable row level security;
alter table app_commercial.plan_feature_entitlements enable row level security;
alter table app_commercial.promotional_campaigns enable row level security;
alter table app_commercial.entitlement_grants enable row level security;
alter table app_commercial.paid_subscriptions enable row level security;
alter table app_commercial.billing_events enable row level security;
alter table app_commercial.app_config enable row level security;
alter table app_commercial.announcements enable row level security;
alter table app_commercial.audit_log enable row level security;
alter table app_commercial.provider_configurations enable row level security;

create policy platform_admins_select_self_or_super on app_commercial.platform_admins
  for select to authenticated
  using (user_id = (select auth.uid()) or app_private.is_commercial_admin((select auth.uid())));

create policy plans_read_public_or_admin on app_commercial.plans
  for select to authenticated
  using ((enabled and public) or app_private.is_commercial_admin((select auth.uid())));
create policy plans_admin_all on app_commercial.plans
  for all to authenticated
  using (app_private.is_commercial_admin((select auth.uid())))
  with check (app_private.is_commercial_admin((select auth.uid())));

create policy plan_prices_read_public_or_admin on app_commercial.plan_prices
  for select to authenticated
  using (
    status = 'published'
    or app_private.is_commercial_admin((select auth.uid()))
  );
create policy plan_prices_admin_all on app_commercial.plan_prices
  for all to authenticated
  using (app_private.is_commercial_admin((select auth.uid())))
  with check (app_private.is_commercial_admin((select auth.uid())));

create policy features_read_public_or_admin on app_commercial.features
  for select to authenticated
  using (active or app_private.is_commercial_admin((select auth.uid())));
create policy features_admin_all on app_commercial.features
  for all to authenticated
  using (app_private.is_commercial_admin((select auth.uid())))
  with check (app_private.is_commercial_admin((select auth.uid())));

create policy plan_feature_entitlements_read on app_commercial.plan_feature_entitlements
  for select to authenticated
  using (true);
create policy plan_feature_entitlements_admin_all on app_commercial.plan_feature_entitlements
  for all to authenticated
  using (app_private.is_commercial_admin((select auth.uid())))
  with check (app_private.is_commercial_admin((select auth.uid())));

create policy promotional_campaigns_admin_read on app_commercial.promotional_campaigns
  for select to authenticated
  using (app_private.is_commercial_admin((select auth.uid())));
create policy promotional_campaigns_admin_all on app_commercial.promotional_campaigns
  for all to authenticated
  using (app_private.is_commercial_admin((select auth.uid())))
  with check (app_private.is_commercial_admin((select auth.uid())));

create policy entitlement_grants_owner_or_admin_select on app_commercial.entitlement_grants
  for select to authenticated
  using (user_id = (select auth.uid()) or app_private.is_commercial_admin((select auth.uid())));
create policy entitlement_grants_admin_all on app_commercial.entitlement_grants
  for all to authenticated
  using (app_private.is_commercial_admin((select auth.uid())))
  with check (app_private.is_commercial_admin((select auth.uid())));

create policy paid_subscriptions_owner_or_admin_select on app_commercial.paid_subscriptions
  for select to authenticated
  using (user_id = (select auth.uid()) or app_private.is_commercial_admin((select auth.uid())));
create policy paid_subscriptions_admin_all on app_commercial.paid_subscriptions
  for all to authenticated
  using (app_private.is_commercial_admin((select auth.uid())))
  with check (app_private.is_commercial_admin((select auth.uid())));

create policy billing_events_admin_select on app_commercial.billing_events
  for select to authenticated
  using (app_private.is_commercial_admin((select auth.uid())));

create policy app_config_read_published_or_admin on app_commercial.app_config
  for select to authenticated
  using (status = 'published' or app_private.is_commercial_admin((select auth.uid())));
create policy app_config_admin_all on app_commercial.app_config
  for all to authenticated
  using (app_private.is_commercial_admin((select auth.uid())))
  with check (app_private.is_commercial_admin((select auth.uid())));

create policy announcements_read_active_or_admin on app_commercial.announcements
  for select to authenticated
  using (
    (active and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at > now()))
    or app_private.is_commercial_admin((select auth.uid()))
  );
create policy announcements_admin_all on app_commercial.announcements
  for all to authenticated
  using (app_private.is_commercial_admin((select auth.uid())))
  with check (app_private.is_commercial_admin((select auth.uid())));

create policy audit_log_admin_select on app_commercial.audit_log
  for select to authenticated
  using (app_private.is_commercial_admin((select auth.uid())));

create policy provider_configurations_admin_select on app_commercial.provider_configurations
  for select to authenticated
  using (app_private.is_commercial_admin((select auth.uid())));
create policy provider_configurations_admin_all on app_commercial.provider_configurations
  for all to authenticated
  using (app_private.is_commercial_admin((select auth.uid())))
  with check (app_private.is_commercial_admin((select auth.uid())));

grant usage on schema app_commercial to authenticated;
grant select on
  app_commercial.plans,
  app_commercial.plan_prices,
  app_commercial.features,
  app_commercial.plan_feature_entitlements,
  app_commercial.entitlement_grants,
  app_commercial.paid_subscriptions,
  app_commercial.app_config,
  app_commercial.announcements,
  app_commercial.platform_admins,
  app_commercial.billing_events,
  app_commercial.audit_log,
  app_commercial.provider_configurations
to authenticated;
grant insert, update, delete on
  app_commercial.plans,
  app_commercial.plan_prices,
  app_commercial.features,
  app_commercial.plan_feature_entitlements,
  app_commercial.promotional_campaigns,
  app_commercial.entitlement_grants,
  app_commercial.app_config,
  app_commercial.announcements,
  app_commercial.provider_configurations
to authenticated;
grant execute on function app_commercial.resolve_effective_entitlement(uuid, timestamptz) to authenticated;
grant execute on function app_commercial.current_published_catalog() to authenticated;
grant execute on function app_commercial.is_super_admin() to authenticated;

insert into app_commercial.plans (key, display_name, description, sort_order)
values
  ('free', 'Finance Suit Free', 'Permanent free access for core personal finance management.', 10),
  ('pro', 'Finance Suit Pro', 'Advanced automation, salary, facility, reporting, and convenience capabilities.', 20)
on conflict (key) do update set
  display_name = excluded.display_name,
  description = excluded.description,
  sort_order = excluded.sort_order;

insert into app_commercial.plan_prices (
  plan_key, provider, interval, currency_code, amount_minor,
  provider_product_id, provider_base_plan_id, status, provider_sync_status
)
values
  ('free', 'manual', 'none', 'EGP', 0, null, null, 'published', 'synced'),
  ('pro', 'google_play', 'month', 'EGP', 6000, 'finance_suit_pro', 'pro-monthly-egp', 'published', 'pending_sync'),
  ('pro', 'google_play', 'year', 'EGP', 60000, 'finance_suit_pro', 'pro-yearly-egp', 'published', 'pending_sync')
on conflict do nothing;

insert into app_commercial.features (key, title, description, value_type)
values
  ('core_accounts', 'Core accounts', 'Create and maintain normal finance accounts.', 'boolean'),
  ('transactions', 'Transactions', 'Manual income, expense, transfer, and category tracking.', 'boolean'),
  ('basic_dashboard', 'Basic dashboard', 'Cash-flow overview and current financial summaries.', 'boolean'),
  ('recurring_entries', 'Recurring entries', 'Recurring finance tracking and occurrences.', 'limit'),
  ('transaction_macros', 'Transaction macros', 'Reusable transaction automation macros.', 'limit'),
  ('income_automation', 'Income automation', 'Income sources, allocations, and acceptance workflows.', 'limit'),
  ('salary_advanced', 'Advanced salary handling', 'Salary settings, periods, adjustments, and splitting.', 'boolean'),
  ('credit_facilities', 'Credit cards and facilities', 'Credit card, BNPL, statement, fee, and installment management.', 'boolean'),
  ('advanced_reports', 'Advanced reports', 'Server-backed history, reporting, charts, and forecasts.', 'boolean'),
  ('ai_card_research', 'AI card research', 'Server-side card and BNPL product research assistance.', 'limit')
on conflict (key) do update set
  title = excluded.title,
  description = excluded.description,
  value_type = excluded.value_type;

insert into app_commercial.plan_feature_entitlements (plan_key, feature_key, enabled, limit_value)
select 'free', key, true,
  case key
    when 'recurring_entries' then 3
    when 'transaction_macros' then 3
    when 'income_automation' then 2
    when 'ai_card_research' then 0
    else null
  end
from app_commercial.features
where key in ('core_accounts', 'transactions', 'basic_dashboard', 'recurring_entries', 'transaction_macros', 'income_automation')
on conflict (plan_key, feature_key) do update set
  enabled = excluded.enabled,
  limit_value = excluded.limit_value;

insert into app_commercial.plan_feature_entitlements (plan_key, feature_key, enabled, limit_value)
select 'pro', key, true, null
from app_commercial.features
on conflict (plan_key, feature_key) do update set
  enabled = excluded.enabled,
  limit_value = excluded.limit_value;

insert into app_commercial.promotional_campaigns (
  key, name, campaign_type, active, plan_key, duration_days, eligible_from, notes
)
values
  ('early_access_2026', 'Finance Suit Early Access 2026', 'early_access', true, 'pro', 90, now(), 'Initial 90-day Pro promotional entitlement. Future duration changes affect new grants only.'),
  ('standard_pro_trial', 'Standard Pro Trial', 'standard_trial', false, 'pro', 30, null, 'Default trial used for new users after Early Access is disabled.')
on conflict (key) do update set
  name = excluded.name,
  duration_days = excluded.duration_days,
  notes = excluded.notes;

insert into app_commercial.app_config (key, value, status, validation)
values
  ('general', '{"support_email":"tarekian99@gmail.com","support_url":"","privacy_url":"https://buildingsuit.app/legal/privacy-policy.html","terms_url":"https://buildingsuit.app/legal/terms.html"}', 'published', '{"type":"general"}'),
  ('maintenance', '{"enabled":false,"title":"Maintenance","message":"","admin_bypass":true}', 'published', '{"type":"maintenance"}'),
  ('version_policy', '{"android":{"latest":"0.6.0","recommended":"0.6.0","minimum":"0.6.0","force_update":false,"message":"","play_store_url":""}}', 'published', '{"type":"version_policy"}'),
  ('monetization', '{"early_access_enabled":true,"standard_trial_days":30,"ads":{"enabled":false}}', 'published', '{"type":"monetization"}')
on conflict (key) do update set value = excluded.value, validation = excluded.validation;

insert into app_commercial.provider_configurations (provider, package_name, status, metadata)
values ('google_play', 'com.buildingsuit.finance', 'pending_sync', '{"product_id":"finance_suit_pro","monthly_base_plan_id":"pro-monthly-egp","yearly_base_plan_id":"pro-yearly-egp"}')
on conflict (provider) do update set metadata = excluded.metadata;

-- Existing Finance Suit profiles receive the Early Access grant from this
-- migration time. The unique user+campaign index prevents duplicate grants.
insert into app_commercial.entitlement_grants (
  user_id, plan_key, source, campaign_id, starts_at, ends_at, reason
)
select
  p.id,
  c.plan_key,
  'migration',
  c.id,
  now(),
  now() + make_interval(days => c.duration_days),
  'Existing Finance Suit user Early Access backfill'
from app_core.profiles p
join app_commercial.promotional_campaigns c on c.key = 'early_access_2026'
where not exists (
  select 1 from app_commercial.entitlement_grants eg
  where eg.user_id = p.id and eg.campaign_id = c.id
);
