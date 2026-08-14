-- Canonical Home "Next due" read contract. This deliberately has calendar
-- month semantics (plus overdue items), which differ from the rolling
-- `credit_facility_summaries.upcoming_due_minor` card-carousel field.

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
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_month_start date := date_trunc('month', p_today)::date;
  v_month_end date := (date_trunc('month', p_today)
    + interval '1 month - 1 day')::date;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  -- Materializing is idempotent and does not create ledger transactions. The
  -- Home surface needs every pending expense occurrence in this calendar
  -- month, not only the earliest item inside a rule's reminder window.
  perform app_finance.materialize_recurring_occurrences(v_month_end);

  return query
  with card_statements as (
    select
      y.id as obligation_id,
      'card_statement'::text as obligation_kind,
      y.account_id as source_account_id,
      a.name as source_name,
      s.last_four_digits as masked_identifier,
      y.id as related_id,
      y.due_on,
      y.currency_code,
      y.total_remaining_minor as remaining_minor,
      least(y.minimum_due_minor, y.total_remaining_minor)::bigint
        as minimum_due_minor,
      y.total_paid_minor as paid_minor,
      case
        when y.due_on < p_today then 'overdue'
        when y.due_on = p_today then 'due_today'
        when y.total_paid_minor > 0 then 'partially_paid'
        else 'upcoming'
      end as obligation_status,
      a.name || ' — Statement due' as title,
      case when y.due_on < p_today then 0
        when y.due_on = p_today then 1 else 2 end as sort_rank,
      jsonb_build_object(
        'cycle_start', y.cycle_start,
        'cycle_close', y.cycle_close,
        'statement_due_minor', y.total_statement_due_minor,
        'ordinary_charges_minor', y.ordinary_statement_charges_minor,
        'fee_charges_minor', y.fee_charges_minor,
        'installment_due_minor', y.installment_due_minor,
        'items', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', si.id,
            'kind', case when fc.id is null then 'purchase' else 'fee' end,
            'title', coalesce(t.title, t.counterparty, fr.name, 'Charge'),
            'counterparty', t.counterparty,
            'occurred_on', t.occurred_on,
            'category', cat.name,
            'amount_minor', si.amount_minor
          ) order by t.occurred_on, si.id)
          from app_finance.credit_card_statement_items si
          join app_finance.financial_transactions t on t.id = si.transaction_id
          left join app_finance.transaction_categories cat on cat.id = t.category_id
          left join app_finance.credit_card_fee_charges fc
            on fc.transaction_id = t.id
          left join app_finance.credit_card_fee_rules fr on fr.id = fc.rule_id
          where si.cycle_id = y.id and si.user_id = v_user_id
        ), '[]'::jsonb),
        'installments', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', ds.id,
            'plan_id', ds.plan_id,
            'title', ds.plan_title,
            'sequence_number', ds.sequence_number,
            'installment_count', p.installment_count,
            'due_on', ds.due_on,
            'amount_minor', ds.amount_minor,
            'paid_minor', ds.paid_minor,
            'remaining_minor', ds.remaining_minor
          ) order by ds.sequence_number)
          from app_finance.installment_due_statuses ds
          join app_finance.installment_plans p on p.id = ds.plan_id
          where ds.account_id = y.account_id
            and ds.due_on = y.due_on
            and ds.plan_status <> 'cancelled'
        ), '[]'::jsonb)
      ) as details
    from app_finance.credit_card_statement_summaries y
    join app_finance.accounts a on a.id = y.account_id
    join app_finance.credit_facility_settings s on s.account_id = y.account_id
    where y.user_id = v_user_id
      and y.total_remaining_minor > 0
      and y.due_on <= v_month_end
  ),
  bnpl_ordinary_purchases as (
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
    join app_finance.accounts a on a.id = t.source_account_id
    left join app_finance.installment_plans p
      on p.purchase_transaction_id = t.id and p.user_id = t.user_id
    where t.user_id = v_user_id
      and t.transaction_kind = 'expense'
      and a.account_type = 'bnpl'
      and p.id is null
    group by t.source_account_id
  ),
  bnpl_installments as (
    select
      ds.id as obligation_id,
      'installment_due'::text as obligation_kind,
      ds.account_id as source_account_id,
      a.name as source_name,
      s.last_four_digits as masked_identifier,
      ds.plan_id as related_id,
      ds.due_on,
      ds.currency_code,
      (ds.remaining_minor + case when ds.id = first_due.id
        then coalesce(ordinary.amount_minor, 0) else 0 end)::bigint
        as remaining_minor,
      (ds.remaining_minor + case when ds.id = first_due.id
        then coalesce(ordinary.amount_minor, 0) else 0 end)::bigint
        as minimum_due_minor,
      ds.paid_minor,
      case
        when ds.due_on < p_today then 'overdue'
        when ds.due_on = p_today then 'due_today'
        when ds.paid_minor > 0 then 'partially_paid'
        else 'upcoming'
      end as obligation_status,
      a.name || ' — ' || ds.plan_title as title,
      case when ds.due_on < p_today then 0
        when ds.due_on = p_today then 1 else 2 end as sort_rank,
      jsonb_build_object(
        'plan_title', p.title,
        'sequence_number', ds.sequence_number,
        'installment_count', p.installment_count,
        'purchase_date', p.purchased_on,
        'purchase_price_minor', p.purchase_price_minor,
        'financed_principal_minor', p.financed_principal_minor,
        'financing_fees_minor', p.financing_fees_minor,
        'plan_remaining_minor', ps.remaining_minor,
        'category', cat.name,
        'items', case when ds.id = first_due.id
          then coalesce(ordinary.items, '[]'::jsonb) else '[]'::jsonb end,
        'installments', jsonb_build_array(jsonb_build_object(
          'id', ds.id,
          'title', ds.plan_title,
          'sequence_number', ds.sequence_number,
          'installment_count', p.installment_count,
          'due_on', ds.due_on,
          'remaining_minor', ds.remaining_minor
        ))
      ) as details
    from app_finance.installment_due_statuses ds
    join app_finance.installment_plans p on p.id = ds.plan_id
    join app_finance.installment_plan_summaries ps on ps.id = p.id
    join app_finance.accounts a on a.id = ds.account_id
    join app_finance.credit_facility_settings s on s.account_id = ds.account_id
    left join app_finance.transaction_categories cat on cat.id = p.category_id
    left join bnpl_ordinary_purchases ordinary on ordinary.account_id = ds.account_id
    left join lateral (
      select due.id
      from app_finance.installment_due_statuses due
      where due.account_id = ds.account_id
        and due.plan_status <> 'cancelled'
        and due.remaining_minor > 0
      order by due.due_on, due.id
      limit 1
    ) first_due on true
    where ds.user_id = v_user_id
      and a.account_type = 'bnpl'
      and ds.plan_status <> 'cancelled'
      and ds.remaining_minor > 0
      and ds.due_on <= v_month_end
  ),
  bnpl_ordinary_only as (
    select
      gen_random_uuid() as obligation_id,
      'bnpl_purchase'::text as obligation_kind,
      ordinary.account_id as source_account_id,
      a.name as source_name,
      s.last_four_digits as masked_identifier,
      null::uuid as related_id,
      p_today as due_on,
      a.currency_code,
      ordinary.amount_minor as remaining_minor,
      ordinary.amount_minor as minimum_due_minor,
      0::bigint as paid_minor,
      'due_today'::text as obligation_status,
      a.name || ' — Purchases' as title,
      1 as sort_rank,
      jsonb_build_object('items', ordinary.items, 'installments', '[]'::jsonb)
        as details
    from bnpl_ordinary_purchases ordinary
    join app_finance.accounts a on a.id = ordinary.account_id
    join app_finance.credit_facility_settings s on s.account_id = a.id
    where not exists (
      select 1 from app_finance.installment_due_statuses due
      where due.account_id = ordinary.account_id
        and due.plan_status <> 'cancelled'
        and due.remaining_minor > 0
        and due.due_on <= v_month_end
    )
  ),
  recurring_expenses as (
    select
      o.id as obligation_id,
      'recurring_expense'::text as obligation_kind,
      r.source_account_id,
      r.name as source_name,
      null::text as masked_identifier,
      r.id as related_id,
      o.scheduled_on as due_on,
      r.currency_code,
      o.expected_amount_minor as remaining_minor,
      o.expected_amount_minor as minimum_due_minor,
      0::bigint as paid_minor,
      case
        when o.scheduled_on < p_today then 'overdue'
        when o.scheduled_on = p_today then 'due_today'
        else 'upcoming'
      end as obligation_status,
      r.name || ' — Recurring payment' as title,
      case when o.scheduled_on < p_today then 0
        when o.scheduled_on = p_today then 1 else 2 end as sort_rank,
      jsonb_build_object(
        'frequency', r.frequency,
        'category', cat.name,
        'source_account_name', source.name,
        'snoozed_until', o.snoozed_until,
        'occurrence_status', o.status
      ) as details
    from app_finance.recurring_occurrences o
    join app_finance.recurring_rules r on r.id = o.rule_id
    join app_finance.accounts source on source.id = r.source_account_id
    left join app_finance.transaction_categories cat on cat.id = r.category_id
    where o.user_id = v_user_id
      and r.rule_kind = 'expense'
      -- A card-funded recurring rule is a future card charge, not a direct
      -- cash obligation. It becomes payable through its card statement.
      and source.account_type <> 'credit_card'
      and o.status = 'pending'
      and o.scheduled_on <= v_month_end
  )
  select * from card_statements
  union all select * from bnpl_installments
  union all select * from bnpl_ordinary_only
  union all select * from recurring_expenses
  order by sort_rank, due_on, source_name, obligation_id;
end;
$$;

revoke all on function app_finance.home_current_month_obligations(date)
  from public, anon;
grant execute on function app_finance.home_current_month_obligations(date)
  to authenticated, service_role;

notify pgrst, 'reload schema';
