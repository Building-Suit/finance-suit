-- This migration may sort before the original function in a fresh database,
-- so it patches an already-deployed database only when the function exists.
-- The source migration is also corrected for clean rebuilds.
do $migration$
begin
  if to_regprocedure(
    'app_finance.home_current_month_obligations(date)'
  ) is null then
    return;
  end if;

  if to_regprocedure(
    'app_finance.home_current_month_obligations_unfiltered(date)'
  ) is null then
    alter function app_finance.home_current_month_obligations(date)
      rename to home_current_month_obligations_unfiltered;
  end if;

  execute $function$
    create or replace function app_finance.home_current_month_obligations(
      p_today date default current_date
    )
    returns table (
      obligation_id uuid,
      obligation_kind text,
      source_account_id uuid,
      source_name text,
      masked_identifier text,
      related_id uuid,
      due_on date,
      currency_code text,
      remaining_minor bigint,
      minimum_due_minor bigint,
      paid_minor bigint,
      obligation_status text,
      title text,
      sort_rank integer,
      details jsonb
    )
    language sql
    security invoker
    set search_path = ''
    as $body$
      select source.*
      from app_finance.home_current_month_obligations_unfiltered(p_today)
        as source
      where source.obligation_kind <> 'recurring_expense'
         or not exists (
           select 1
           from app_finance.accounts account
           where account.id = source.source_account_id
             and account.account_type = 'credit_card'
         )
    $body$
  $function$;

  revoke all on function app_finance.home_current_month_obligations(date)
    from public, anon;
  grant execute on function app_finance.home_current_month_obligations(date)
    to authenticated, service_role;
  notify pgrst, 'reload schema';
end
$migration$;
