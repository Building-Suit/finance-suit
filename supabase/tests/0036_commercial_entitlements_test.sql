begin;
create extension if not exists pgtap with schema extensions;

select plan(20);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'commercial-a@test.local', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Commercial A"}', now(), now()),
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'commercial-b@test.local', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Commercial B"}', now(), now()),
  ('00000000-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin@test.local', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Admin"}', now(), now());

select has_table('app_commercial', 'plans', 'commercial plans exists');
select has_table('app_commercial', 'plan_prices', 'commercial prices exists');
select has_table('app_commercial', 'entitlement_grants', 'entitlement grants exists');
select has_table('app_commercial', 'paid_subscriptions', 'paid subscriptions exists');
select has_table('app_commercial', 'audit_log', 'audit log exists');

select ok((select relrowsecurity from pg_class where oid = 'app_commercial.entitlement_grants'::regclass), 'RLS on entitlement grants');
select ok((select relrowsecurity from pg_class where oid = 'app_commercial.paid_subscriptions'::regclass), 'RLS on paid subscriptions');

select is(
  (select count(*)::int from app_commercial.entitlement_grants where user_id = '00000000-0000-0000-0000-0000000000c1'),
  1,
  'new profile trigger grants one initial entitlement'
);

select is(
  (select effective_plan::text from app_commercial.resolve_effective_entitlement('00000000-0000-0000-0000-0000000000c1')),
  'pro',
  'early access resolves as pro'
);

select is(
  (select source::text from app_commercial.resolve_effective_entitlement('00000000-0000-0000-0000-0000000000c1')),
  'early_access',
  'initial source resolves as early access'
);

update app_commercial.promotional_campaigns
set duration_days = 30
where key = 'early_access_2026';

select is(
  (
    select round(extract(epoch from (ends_at - starts_at)) / 86400)::int
    from app_commercial.entitlement_grants
    where user_id = '00000000-0000-0000-0000-0000000000c1'
  ),
  90,
  'changing campaign duration does not shorten existing grant'
);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'commercial-c@test.local', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Commercial C"}', now(), now());

select is(
  (
    select round(extract(epoch from (ends_at - starts_at)) / 86400)::int
    from app_commercial.entitlement_grants
    where user_id = '00000000-0000-0000-0000-0000000000c3'
  ),
  30,
  'new grants use changed campaign duration'
);

delete from app_commercial.entitlement_grants
where user_id = '00000000-0000-0000-0000-0000000000c2';

insert into app_commercial.entitlement_grants (
  user_id, plan_key, source, starts_at, ends_at, reason
)
values (
  '00000000-0000-0000-0000-0000000000c2',
  'pro',
  'early_access',
  now() - interval '91 days',
  now() - interval '1 day',
  'expired fixture'
);

select is(
  (select effective_plan::text from app_commercial.resolve_effective_entitlement('00000000-0000-0000-0000-0000000000c2')),
  'free',
  'expired grant falls back to free'
);

insert into app_commercial.paid_subscriptions (
  user_id, provider, plan_key, provider_product_id, provider_base_plan_id,
  provider_purchase_token_hash, status, starts_at, expires_at, auto_renewing
)
values (
  '00000000-0000-0000-0000-0000000000c2', 'google_play', 'pro',
  'finance_suit_pro', 'pro-monthly-egp', 'hash-paid', 'active',
  now(), now() + interval '1 month', true
);

select is(
  (select source::text from app_commercial.resolve_effective_entitlement('00000000-0000-0000-0000-0000000000c2')),
  'paid',
  'active paid subscription wins'
);

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}';

select throws_ok(
  $$insert into app_commercial.entitlement_grants (user_id, plan_key, source, starts_at, ends_at, reason)
    values ('00000000-0000-0000-0000-0000000000c1', 'pro', 'admin_grant', now(), now() + interval '1 year', 'self upgrade')$$,
  '42501',
  null,
  'ordinary user cannot self-grant pro'
);

select is(
  (select count(*)::int from app_commercial.entitlement_grants where user_id = '00000000-0000-0000-0000-0000000000c2'),
  0,
  'ordinary user cannot read another user grants'
);

select throws_ok(
  $$select * from app_commercial.resolve_effective_entitlement('00000000-0000-0000-0000-0000000000c2')$$,
  '42501',
  null,
  'ordinary user cannot resolve another user entitlement'
);

reset role;
insert into app_commercial.platform_admins (user_id, role, status)
values ('00000000-0000-0000-0000-0000000000ad', 'super_admin', 'active');

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000ad","role":"authenticated"}';

select is(
  (select count(*)::int from app_commercial.entitlement_grants where user_id = '00000000-0000-0000-0000-0000000000c1'),
  1,
  'super admin can read user grants'
);

select is(
  (select effective_plan::text from app_commercial.resolve_effective_entitlement('00000000-0000-0000-0000-0000000000c1')),
  'pro',
  'super admin can resolve user entitlement'
);

select throws_ok(
  $$delete from app_commercial.audit_log$$,
  '42501',
  null,
  'audit log is append-only to authenticated clients'
);

select * from finish();
rollback;
