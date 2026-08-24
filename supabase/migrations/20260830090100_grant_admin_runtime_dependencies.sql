-- get_catalog_research_contract() is SECURITY INVOKER and composes the safe,
-- constant-valued helper below. The v2 migration revoked the helper from
-- service_role, causing every catalog overview request to fail with 42501.
grant execute on function app_private.catalog_unknown_value()
  to service_role;

-- This table was created after the schema-wide service_role grant, so it was
-- never included in that grant. The control plane reads it directly while all
-- state transitions remain behind audited RPCs.
grant select on table app_commercial.monetization_state
  to service_role;

notify pgrst, 'reload schema';
