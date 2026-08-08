begin;
create extension if not exists pgtap with schema extensions;

select plan(7);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'commercial-fresh@test.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000ad', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'commercial-admin@test.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into app_commercial.platform_admins (user_id, role, status)
values ('00000000-0000-4000-8000-0000000000ad', 'super_admin', 'active');

select ok(
  has_schema_privilege('authenticated', 'app_private', 'usage'),
  'authenticated can enter the private schema for the RLS helper only'
);

select ok(
  has_function_privilege(
    'authenticated',
    'app_private.is_commercial_admin(uuid,app_commercial.admin_role[])',
    'execute'
  ),
  'authenticated can execute the commercial RLS helper'
);

select ok(
  not has_function_privilege(
    'anon',
    'app_private.is_commercial_admin(uuid,app_commercial.admin_role[])',
    'execute'
  ),
  'anonymous callers cannot execute the commercial RLS helper'
);

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-0000000000f1","role":"authenticated"}';

select is(
  (select source::text from app_commercial.resolve_effective_entitlement()),
  'open_early_access',
  'a newly authenticated user can open Subscription without a 42501 error'
);

select is(
  app_private.is_commercial_admin('00000000-0000-4000-8000-0000000000f1'),
  false,
  'an ordinary user is not an admin'
);

select is(
  app_private.is_commercial_admin('00000000-0000-4000-8000-0000000000ad'),
  false,
  'an authenticated user cannot inspect another user admin status'
);

select is(
  (select count(*)::integer from app_commercial.platform_admins),
  0,
  'an ordinary user cannot read another platform admin row'
);

select * from finish();
rollback;
