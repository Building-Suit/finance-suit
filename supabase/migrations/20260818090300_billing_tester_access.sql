-- Limited access to the real Play purchase flow while monetization remains
-- open. This record never grants an entitlement.
create table app_commercial.billing_testers (
  user_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default true,
  reason text not null check (char_length(trim(reason)) between 6 and 1000),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_billing_testers_updated_at
  before update on app_commercial.billing_testers
  for each row execute function app_private.set_updated_at();

alter table app_commercial.billing_testers enable row level security;
create policy billing_testers_owner_or_admin_select on app_commercial.billing_testers
  for select to authenticated
  using (user_id = (select auth.uid()) or app_private.is_commercial_admin((select auth.uid())));
create policy billing_testers_admin_all on app_commercial.billing_testers
  for all to authenticated
  using (app_private.is_commercial_admin((select auth.uid())))
  with check (app_private.is_commercial_admin((select auth.uid())));
grant select on app_commercial.billing_testers to authenticated;
grant select, insert, update, delete on app_commercial.billing_testers to service_role;

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
    'billing_test_access', exists(select 1 from app_commercial.billing_testers bt
      where bt.user_id = (select auth.uid()) and bt.enabled),
    'billing_readiness', (select jsonb_build_object(
      'provider', pc.status,
      'product', coalesce((select provider_sync_status::text from app_commercial.plan_prices
        where provider = 'google_play' and provider_product_id = 'finance_suit_pro'
        order by created_at desc limit 1), 'not_configured'),
      'verification', case when exists (select 1 from app_commercial.paid_subscriptions where last_verified_at is not null)
        then 'verified' else 'not_verified' end)
      from app_commercial.provider_configurations pc where pc.provider = 'google_play')
  );
$$;
