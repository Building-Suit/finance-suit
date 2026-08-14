-- Restore a single save_recurring_rule entry point.
--
-- 20260822090000 added p_is_foreign_currency with a default, which created a
-- second overload instead of replacing the original. With both in place any
-- 13-argument call — released clients through PostgREST and the pgTAP suite
-- alike — fails with "function is not unique" (42725). The 14-parameter
-- version behaves identically when the new flag is omitted, so the
-- superseded 13-parameter overload is dropped; older clients resolve to the
-- surviving function through its default.

drop function if exists app_finance.save_recurring_rule(
  text, app_finance.recurring_rule_kind, bigint,
  app_finance.recurring_frequency, smallint, date, smallint, uuid, uuid,
  uuid, text, uuid, boolean
);

revoke execute on function app_finance.save_recurring_rule(
  text, app_finance.recurring_rule_kind, bigint,
  app_finance.recurring_frequency, smallint, date, smallint, uuid, uuid,
  uuid, text, uuid, boolean, boolean
) from public, anon;
grant execute on function app_finance.save_recurring_rule(
  text, app_finance.recurring_rule_kind, bigint,
  app_finance.recurring_frequency, smallint, date, smallint, uuid, uuid,
  uuid, text, uuid, boolean, boolean
) to authenticated, service_role;

notify pgrst, 'reload schema';
