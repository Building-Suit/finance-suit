-- RLS policies and the entitlement resolver call this helper while running as
-- `authenticated`. The private schema was intentionally locked down earlier,
-- but omitting this narrow grant made policy evaluation fail with 42501 before
-- ownership checks could complete.
--
-- Keep the helper safe for authenticated execution: a caller can check only
-- their own admin status. Service-role requests do not rely on this helper and
-- continue to bypass RLS normally.
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
  select p_user_id = (select auth.uid())
    and exists (
      select 1
      from app_commercial.platform_admins a
      where a.user_id = p_user_id
        and a.status = 'active'
        and a.role = any(p_roles)
    );
$$;

grant usage on schema app_private to authenticated;
revoke execute on function app_private.is_commercial_admin(uuid, app_commercial.admin_role[])
  from public, anon;
grant execute on function app_private.is_commercial_admin(uuid, app_commercial.admin_role[])
  to authenticated, service_role;

notify pgrst, 'reload schema';
