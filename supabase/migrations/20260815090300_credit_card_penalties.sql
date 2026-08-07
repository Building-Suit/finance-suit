-- Late-payment and over-limit penalties: statement-event triggers,
-- evaluated in their own sweep so a client (or cron) can run them exactly
-- like `apply_credit_card_fees`. Both are idempotent per statement cycle
-- via the same (rule, charged_on, trigger_transaction, statement_cycle)
-- key the rest of the engine already uses, so an over-limit fee can never
-- recursively trigger another one: the cycle it would belong to already
-- has a charge by the time it is evaluated again.

create or replace function app_finance.apply_statement_penalty_fees(
  p_through date default null
)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_through date := coalesce(p_through, current_date);
  v_cycle record;
  v_account record;
  v_rule app_finance.credit_card_fee_rules;
  v_calc app_finance.credit_card_fee_rule_versions;
  v_basis bigint;
  v_amount bigint;
  v_tx_id uuid;
  v_outstanding bigint;
  v_tolerance bigint;
  v_over_by bigint;
  v_count integer := 0;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  -- ---------------------------------------------------------------------
  -- Late payment: the minimum due was not met by the due date. Never
  -- triggers merely because the full statement was not paid in full.
  -- ---------------------------------------------------------------------
  for v_cycle in
    select y.id as cycle_id, y.account_id, y.due_on, y.charges_minor,
        y.paid_minor, y.minimum_due_minor
    from app_finance.credit_card_statement_summaries y
    join app_finance.accounts a on a.id = y.account_id
    join app_finance.credit_facility_settings s on s.account_id = y.account_id
    where y.user_id = v_user_id
      and not a.is_archived
      and s.facility_status = 'active'
      and y.due_on <= v_through
      and y.minimum_due_minor > 0
      and y.paid_minor < y.minimum_due_minor
      and not exists (
        select 1 from app_finance.credit_card_fee_charges c
        join app_finance.credit_card_fee_rules r on r.id = c.rule_id
        where r.trigger_kind = 'late_payment_missed_minimum'
          and c.statement_cycle_id = y.id
      )
  loop
    v_rule := app_finance.resolve_trigger_rule(
      v_cycle.account_id, v_user_id, 'late_payment_missed_minimum'
    );
    if v_rule.id is null then
      continue;
    end if;

    v_calc := app_finance.resolve_or_create_fee_rule_version(
      v_rule, v_cycle.due_on
    );
    if v_calc.calculation_type = 'manual' then
      continue;
    end if;

    v_basis := case v_calc.percent_basis
      when 'credit_limit' then (
        select s.credit_limit_minor from app_finance.credit_facility_settings s
        where s.account_id = v_cycle.account_id
      )
      when 'outstanding_balance' then
        app_finance.facility_outstanding_minor(v_cycle.account_id)
      else v_cycle.charges_minor
    end;
    v_amount := app_finance.calculate_rule_amount(v_calc, v_basis);
    if v_amount <= 0 then
      continue;
    end if;

    perform set_config('app_finance.facility_internal', 'on', true);

    insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      source_account_id, category_id, title
    )
    select v_user_id, 'expense', v_cycle.due_on, v_amount, a.currency_code,
        v_cycle.account_id, v_rule.category_id, v_rule.name
      from app_finance.accounts a where a.id = v_cycle.account_id
    returning id into v_tx_id;

    begin
      insert into app_finance.credit_card_fee_charges (
        user_id, rule_id, rule_version_id, transaction_id, charged_on,
        amount_minor, statement_cycle_id, expected_amount_minor,
        actual_amount_minor, calculation_snapshot
      ) values (
        v_user_id, v_rule.id, v_calc.id, v_tx_id, v_cycle.due_on, v_amount,
        v_cycle.cycle_id, v_amount, v_amount,
        jsonb_build_object(
          'basis_minor', v_basis, 'minimum_due_minor',
          v_cycle.minimum_due_minor, 'paid_minor', v_cycle.paid_minor
        )
      );
    exception when unique_violation then
      delete from app_finance.financial_transactions where id = v_tx_id;
      perform set_config('app_finance.facility_internal', '', true);
      continue;
    end;

    perform set_config('app_finance.facility_internal', '', true);
    v_count := v_count + 1;
  end loop;

  -- ---------------------------------------------------------------------
  -- Over limit: outstanding exceeds the credit limit plus any configured
  -- tolerance. Charged at most once per statement cycle, so the fee it
  -- generates (which itself increases outstanding) can never recurse —
  -- the next evaluation of the same cycle finds a charge already there.
  -- ---------------------------------------------------------------------
  for v_account in
    select a.id as account_id, a.currency_code, s.credit_limit_minor,
        s.statement_day, s.default_due_day
    from app_finance.accounts a
    join app_finance.credit_facility_settings s on s.account_id = a.id
    where a.user_id = v_user_id
      and a.account_type = 'credit_card'
      and not a.is_archived
      and s.facility_status = 'active'
  loop
    v_rule := app_finance.resolve_trigger_rule(
      v_account.account_id, v_user_id, 'over_limit_event'
    );
    if v_rule.id is null then
      continue;
    end if;

    v_calc := app_finance.resolve_or_create_fee_rule_version(
      v_rule, v_through
    );
    if v_calc.calculation_type = 'manual' then
      continue;
    end if;

    v_outstanding := app_finance.facility_outstanding_minor(
      v_account.account_id
    );
    v_tolerance := coalesce(v_calc.tolerance_minor, 0) + round(
      v_account.credit_limit_minor::numeric
        * coalesce(v_calc.tolerance_basis_points, 0) / 10000
    )::bigint;
    v_over_by := v_outstanding - (v_account.credit_limit_minor + v_tolerance);
    if v_over_by <= 0 then
      continue;
    end if;

    -- Identify "this cycle" only when a statement day is configured;
    -- otherwise fall back to one charge per calendar day.
    declare
      v_cycle_id uuid;
      v_charged_on date := v_through;
    begin
      -- Set the bypass flag before touching any protected table: the
      -- statement-cycle lookup below writes to credit_card_statement_cycles
      -- (RPC-only), not just the charge/transaction inserts further down.
      perform set_config('app_finance.facility_internal', 'on', true);

      if v_account.statement_day is not null then
        declare
          v_bounds record;
        begin
          select * into v_bounds from app_finance.statement_bounds_for(
            v_account.statement_day, v_account.default_due_day, v_through
          );
          insert into app_finance.credit_card_statement_cycles (
            user_id, account_id, cycle_start, cycle_close, due_on
          ) values (
            v_user_id, v_account.account_id, v_bounds.cycle_start,
            v_bounds.cycle_close, v_bounds.due_on
          )
          on conflict (account_id, cycle_close) do nothing;
          select id into v_cycle_id
            from app_finance.credit_card_statement_cycles
            where account_id = v_account.account_id
              and cycle_close = v_bounds.cycle_close;
        end;
      end if;

      if exists (
        select 1 from app_finance.credit_card_fee_charges c
        where c.rule_id = v_rule.id
          and c.statement_cycle_id is not distinct from v_cycle_id
          and (v_cycle_id is not null
            or c.charged_on = v_charged_on)
      ) then
        perform set_config('app_finance.facility_internal', '', true);
        continue;
      end if;

      v_basis := case v_calc.percent_basis
        when 'credit_limit' then v_account.credit_limit_minor
        else v_outstanding
      end;
      v_amount := app_finance.calculate_rule_amount(v_calc, v_basis);
      if v_amount <= 0 then
        perform set_config('app_finance.facility_internal', '', true);
        continue;
      end if;

      insert into app_finance.financial_transactions (
        user_id, transaction_kind, occurred_on, amount_minor, currency_code,
        source_account_id, category_id, title
      ) values (
        v_user_id, 'expense', v_charged_on, v_amount, v_account.currency_code,
        v_account.account_id, v_rule.category_id, v_rule.name
      )
      returning id into v_tx_id;

      begin
        insert into app_finance.credit_card_fee_charges (
          user_id, rule_id, rule_version_id, transaction_id, charged_on,
          amount_minor, statement_cycle_id, expected_amount_minor,
          actual_amount_minor, calculation_snapshot
        ) values (
          v_user_id, v_rule.id, v_calc.id, v_tx_id, v_charged_on, v_amount,
          v_cycle_id, v_amount, v_amount,
          jsonb_build_object(
            'basis_minor', v_basis, 'outstanding_minor', v_outstanding,
            'credit_limit_minor', v_account.credit_limit_minor,
            'tolerance_minor', v_tolerance, 'over_by_minor', v_over_by
          )
        );
      exception when unique_violation then
        delete from app_finance.financial_transactions where id = v_tx_id;
        perform set_config('app_finance.facility_internal', '', true);
        continue;
      end;

      if v_cycle_id is not null then
        insert into app_finance.credit_card_statement_items (
          user_id, cycle_id, transaction_id, amount_minor
        ) values (v_user_id, v_cycle_id, v_tx_id, v_amount);
      end if;

      perform set_config('app_finance.facility_internal', '', true);
      v_count := v_count + 1;
    end;
  end loop;

  return v_count;
end;
$$;

revoke execute on function app_finance.apply_statement_penalty_fees(date)
from public, anon;
grant execute on function app_finance.apply_statement_penalty_fees(date)
to authenticated, service_role;

notify pgrst, 'reload schema';
