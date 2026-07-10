begin;
create extension if not exists pgtap with schema extensions;

select plan(24);

-- Tables exist
select has_table('public', 'profiles', 'profiles exists');
select has_table('public', 'user_preferences', 'user_preferences exists');
select has_table('public', 'salary_settings', 'salary_settings exists');
select has_table('public', 'salary_adjustments', 'salary_adjustments exists');
select has_table('public', 'salary_periods', 'salary_periods exists');
select has_table('public', 'official_holidays', 'official_holidays exists');
select has_table('public', 'work_entries', 'work_entries exists');
select has_table('public', 'accounts', 'accounts exists');
select has_table('public', 'transaction_categories', 'transaction_categories exists');
select has_table('public', 'financial_transactions', 'financial_transactions exists');

-- RLS enabled everywhere
select ok((select relrowsecurity from pg_class where oid = 'public.profiles'::regclass), 'RLS on profiles');
select ok((select relrowsecurity from pg_class where oid = 'public.user_preferences'::regclass), 'RLS on user_preferences');
select ok((select relrowsecurity from pg_class where oid = 'public.salary_settings'::regclass), 'RLS on salary_settings');
select ok((select relrowsecurity from pg_class where oid = 'public.salary_adjustments'::regclass), 'RLS on salary_adjustments');
select ok((select relrowsecurity from pg_class where oid = 'public.salary_periods'::regclass), 'RLS on salary_periods');
select ok((select relrowsecurity from pg_class where oid = 'public.official_holidays'::regclass), 'RLS on official_holidays');
select ok((select relrowsecurity from pg_class where oid = 'public.work_entries'::regclass), 'RLS on work_entries');
select ok((select relrowsecurity from pg_class where oid = 'public.accounts'::regclass), 'RLS on accounts');
select ok((select relrowsecurity from pg_class where oid = 'public.transaction_categories'::regclass), 'RLS on transaction_categories');
select ok((select relrowsecurity from pg_class where oid = 'public.financial_transactions'::regclass), 'RLS on financial_transactions');

-- Business-date columns are real date columns, separate from created_at
select col_type_is('public', 'work_entries', 'work_date', 'date', 'work_date is date');
select col_type_is('public', 'financial_transactions', 'occurred_on', 'date', 'occurred_on is date');
select col_type_is('public', 'salary_adjustments', 'effective_date', 'date', 'effective_date is date');

-- Money is bigint minor units
select col_type_is('public', 'financial_transactions', 'amount_minor', 'bigint', 'amount_minor is bigint');

select * from finish();
rollback;
