do $$
declare
  v_missing text[] := array[]::text[];
  v_without_rls integer;
begin
  if to_regclass('app_finance.held_amounts') is null then
    v_missing := array_append(v_missing, 'app_finance.held_amounts');
  end if;
  if to_regclass('app_reports.history_items') is null then
    v_missing := array_append(v_missing, 'app_reports.history_items');
  end if;
  if to_regclass('app_finance.income_sources') is null then
    v_missing := array_append(v_missing, 'app_finance.income_sources');
  end if;
  if to_regclass('app_finance.income_occurrences') is null then
    v_missing := array_append(v_missing, 'app_finance.income_occurrences');
  end if;
  if to_regclass('app_finance.income_source_allocations') is null then
    v_missing := array_append(v_missing, 'app_finance.income_source_allocations');
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'app_finance'
      and table_name = 'held_amounts'
      and column_name = 'transaction_kind'
  ) then
    v_missing := array_append(v_missing, 'held_amounts.transaction_kind');
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'app_finance'
      and table_name = 'held_amounts'
      and column_name = 'category_id'
  ) then
    v_missing := array_append(v_missing, 'held_amounts.category_id');
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'held_transaction_kind_allowed'
      and conrelid = 'app_finance.held_amounts'::regclass
  ) then
    v_missing := array_append(v_missing, 'held_transaction_kind_allowed');
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'held_kind_matches_direction'
      and conrelid = 'app_finance.held_amounts'::regclass
  ) then
    v_missing := array_append(v_missing, 'held_kind_matches_direction');
  end if;

  if to_regprocedure(
    'app_finance.save_held_amount(app_finance.transaction_kind,bigint,text,text,date,text,text,uuid,uuid,uuid,uuid)'
  ) is null then
    v_missing := array_append(v_missing, 'typed save_held_amount');
  end if;
  if to_regprocedure(
    'app_finance.save_held_amount(app_finance.held_amount_direction,bigint,text,text,date,text,text,uuid,uuid,uuid)'
  ) is not null then
    raise exception 'Legacy direction-based save_held_amount overload remains';
  end if;
  if to_regprocedure(
    'app_finance.set_held_amount_settled(uuid,date)'
  ) is null then
    v_missing := array_append(v_missing, 'set_held_amount_settled');
  end if;
  if to_regprocedure('app_finance.delete_held_amount(uuid)') is null then
    v_missing := array_append(v_missing, 'delete_held_amount');
  end if;

  if cardinality(v_missing) > 0 then
    raise exception 'Missing required Finance Suit objects: %',
      array_to_string(v_missing, ', ');
  end if;

  select count(*)::integer
    into v_without_rls
  from pg_tables
  where schemaname like 'app\_%' escape '\'
    and rowsecurity = false;

  if v_without_rls <> 0 then
    raise exception '% private app_* tables do not have RLS enabled',
      v_without_rls;
  end if;

  raise notice 'finance_suit_schema_verified: % RLS-protected app_* tables',
    (
      select count(*)
      from pg_tables
      where schemaname like 'app\_%' escape '\'
        and rowsecurity
    );
end;
$$;
