-- On an upgraded database the original function has already been preserved
-- as *_unfiltered. Rebuild the public contract from that source and attach
-- each BNPL account's ordinary purchases to its earliest unpaid installment.
do $migration$
begin
  if to_regprocedure(
    'app_finance.home_current_month_obligations_unfiltered(date)'
  ) is null then
    return;
  end if;

  execute $function$
    create or replace function app_finance.home_current_month_obligations(
      p_today date default current_date
    )
    returns table (
      obligation_id uuid, obligation_kind text, source_account_id uuid,
      source_name text, masked_identifier text, related_id uuid, due_on date,
      currency_code text, remaining_minor bigint, minimum_due_minor bigint,
      paid_minor bigint, obligation_status text, title text, sort_rank integer,
      details jsonb
    )
    language sql security invoker set search_path = ''
    as $body$
      with base as (
        select source.*
        from app_finance.home_current_month_obligations_unfiltered(p_today)
          as source
        where source.obligation_kind <> 'recurring_expense'
           or not exists (
             select 1 from app_finance.accounts account
             where account.id = source.source_account_id
               and account.account_type = 'credit_card'
           )
      ),
      ordinary as (
        select
          t.source_account_id as account_id,
          sum(t.amount_minor)::bigint as amount_minor,
          jsonb_agg(jsonb_build_object(
            'id', t.id,
            'title', coalesce(t.title, t.counterparty, 'Purchase'),
            'occurred_on', t.occurred_on,
            'amount_minor', t.amount_minor
          ) order by t.occurred_on, t.id) as items
        from app_finance.financial_transactions t
        join app_finance.accounts account on account.id = t.source_account_id
        left join app_finance.installment_plans plan
          on plan.purchase_transaction_id = t.id and plan.user_id = t.user_id
        where t.user_id = (select auth.uid())
          and t.transaction_kind = 'expense'
          and account.account_type = 'bnpl'
          and plan.id is null
        group by t.source_account_id
      ),
      first_bnpl_due as (
        select distinct on (source_account_id)
          obligation_id, source_account_id
        from base
        where obligation_kind = 'installment_due'
        order by source_account_id, due_on, obligation_id
      ),
      merged as (
        select
          b.obligation_id, b.obligation_kind, b.source_account_id,
          b.source_name, b.masked_identifier, b.related_id, b.due_on,
          b.currency_code,
          (b.remaining_minor + case when b.obligation_id = first.obligation_id
            then coalesce(o.amount_minor, 0) else 0 end)::bigint
            as remaining_minor,
          (b.minimum_due_minor + case when b.obligation_id = first.obligation_id
            then coalesce(o.amount_minor, 0) else 0 end)::bigint
            as minimum_due_minor,
          b.paid_minor, b.obligation_status, b.title, b.sort_rank,
          case when b.obligation_id = first.obligation_id then
            b.details || jsonb_build_object(
              'items', coalesce(o.items, '[]'::jsonb),
              'installments', jsonb_build_array(jsonb_build_object(
                'id', b.obligation_id,
                'title', coalesce(b.details->>'plan_title', b.title),
                'sequence_number', b.details->>'sequence_number',
                'installment_count', b.details->'installment_count',
                'due_on', b.due_on,
                'remaining_minor', b.remaining_minor
              ))
            ) else b.details end as details
        from base b
        left join first_bnpl_due first on first.obligation_id = b.obligation_id
        left join ordinary o on o.account_id = b.source_account_id
      ),
      ordinary_only as (
        select
          gen_random_uuid() as obligation_id,
          'bnpl_purchase'::text as obligation_kind,
          o.account_id as source_account_id,
          account.name as source_name,
          settings.last_four_digits as masked_identifier,
          null::uuid as related_id,
          p_today as due_on,
          account.currency_code,
          o.amount_minor as remaining_minor,
          o.amount_minor as minimum_due_minor,
          0::bigint as paid_minor,
          'due_today'::text as obligation_status,
          account.name || ' — Purchases' as title,
          1 as sort_rank,
          jsonb_build_object('items', o.items, 'installments', '[]'::jsonb)
            as details
        from ordinary o
        join app_finance.accounts account on account.id = o.account_id
        join app_finance.credit_facility_settings settings
          on settings.account_id = account.id
        where not exists (
          select 1 from first_bnpl_due first
          where first.source_account_id = o.account_id
        )
      )
      select * from merged
      union all
      select * from ordinary_only
      order by sort_rank, due_on, source_name, obligation_id
    $body$
  $function$;

  revoke all on function app_finance.home_current_month_obligations(date)
    from public, anon;
  grant execute on function app_finance.home_current_month_obligations(date)
    to authenticated, service_role;
  notify pgrst, 'reload schema';
end
$migration$;
