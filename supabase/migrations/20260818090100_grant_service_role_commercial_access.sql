grant usage on schema app_core, app_commercial to service_role;

grant select on all tables in schema app_core to service_role;

grant select, insert, update, delete on all tables in schema app_commercial to service_role;

grant execute on all functions in schema app_commercial to service_role;
