-- Restore legacy public API access while keeping the new app on module schemas.
-- Existing finance tracker clients still query public.expenses/incomes/etc.
alter role authenticator set pgrst.db_schemas =
  'public,app_core,app_finance,app_work,app_salary,app_reports';

-- Existing auth users predate the app_core profile trigger. Backfill them so
-- old accounts can enter the new app without needing to re-register.
insert into app_core.profiles (id, display_name)
select
  u.id,
  coalesce(
    nullif(u.raw_user_meta_data ->> 'display_name', ''),
    nullif(u.raw_user_meta_data ->> 'full_name', ''),
    nullif(u.raw_user_meta_data ->> 'name', ''),
    nullif(split_part(u.email, '@', 1), ''),
    ''
  ) as display_name
from auth.users u
where not exists (
  select 1
  from app_core.profiles p
  where p.id = u.id
);

-- Keep the existing public trigger for the legacy app, but make it idempotent
-- so it cannot block new signups if a public profile row is already present.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, coalesce(new.email, ''))
  on conflict (id) do update
    set email = excluded.email,
        updated_at = now()
    where public.profiles.email is distinct from excluded.email;

  return new;
end;
$$;

notify pgrst, 'reload config';
notify pgrst, 'reload schema';
