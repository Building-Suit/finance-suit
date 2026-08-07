-- Consumers of the two enum values added in 20260816090000:
--
-- 1. `highest_daily_balance_lookback`: a percent basis equal to the highest
--    running debit balance the facility reached in the lookback window —
--    the exact basis Egyptian quarterly stamp duty uses. The ledger holds
--    every balance-affecting transaction, so the peak is reconstructable;
--    `lookback_cycles` on the rule version counts months here.
--
-- 2. `foreign_merchant_home_currency`: the foreign-fee condition "merchant
--    outside home AND billed in the card's own currency". Purchases billed
--    in a foreign currency carry the bank's markup inside the exchange
--    rate and post no separate fee line, so `either`/`both`/
--    `currency_differs` all misfire on real statements.

-- ---------------------------------------------------------------------------
-- Highest running balance over a window of whole days
-- ---------------------------------------------------------------------------

-- The balance changes only on transaction dates, so the daily peak is the
-- maximum of the running balance evaluated after each day inside the
-- window, seeded with the balance the account carried into the window.
-- Business dates only (occurred_on), never created_at. The window is
-- [p_on - lookback months, p_on): the charge date itself is excluded,
-- matching a fee assessed "on the last N months".
create or replace function app_finance.highest_daily_balance_minor(
  p_account_id uuid,
  p_on date,
  p_lookback_months integer
)
returns bigint
language sql
stable
set search_path = ''
as $$
  with bounds as (
    select (p_on - make_interval(
      months => greatest(coalesce(p_lookback_months, 3), 1)
    ))::date as start_on
  ),
  opening as (
    select a.opening_balance_minor - coalesce((
        select sum(
          case when t.destination_account_id = a.id
            then t.amount_minor
            else -t.amount_minor
          end
        )
        from app_finance.financial_transactions t
        where (t.source_account_id = a.id
            or t.destination_account_id = a.id)
          and t.occurred_on < (select start_on from bounds)
      ), 0) as balance_minor
    from app_finance.accounts a
    where a.id = p_account_id
  ),
  daily as (
    select t.occurred_on,
      sum(
        case when t.source_account_id = p_account_id
          then t.amount_minor
          else -t.amount_minor
        end
      ) as delta_minor
    from app_finance.financial_transactions t
    where (t.source_account_id = p_account_id
        or t.destination_account_id = p_account_id)
      and t.occurred_on >= (select start_on from bounds)
      and t.occurred_on < p_on
    group by t.occurred_on
  ),
  running as (
    select (select balance_minor from opening)
      + sum(d.delta_minor) over (order by d.occurred_on) as balance_minor
    from daily d
  )
  select greatest(
    coalesce((select max(r.balance_minor) from running r), 0),
    coalesce((select o.balance_minor from opening o), 0),
    0
  )::bigint;
$$;

revoke execute on function app_finance.highest_daily_balance_minor(
  uuid, date, integer
) from public, anon;
grant execute on function app_finance.highest_daily_balance_minor(
  uuid, date, integer
) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- The schedule engine learns the new basis. Identical to the 0026 version
-- except for the one added `when 'highest_daily_balance_lookback'` arm.
-- ---------------------------------------------------------------------------

create or replace function app_finance.apply_credit_card_fees(
  p_through date default null
)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_through date := coalesce(p_through, current_date);
  v_rule record;
  v_calc app_finance.credit_card_fee_rule_versions;
  v_on date;
  v_basis bigint;
  v_amount bigint;
  v_suppressed boolean;
  v_suppressed_ids uuid[];
  v_tx_id uuid;
  v_cycle_id uuid;
  v_bounds record;
  v_count integer := 0;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select array_agg(loser.id) into v_suppressed_ids
    from app_finance.credit_card_fee_rules loser
    where loser.user_id = v_user_id
      and loser.is_active and loser.state = 'configured'
      and loser.trigger_kind = 'schedule'
      and loser.mutual_exclusion_group is not null
      and coalesce(loser.next_charge_on, loser.starts_on) <= v_through
      and exists (
        select 1 from app_finance.credit_card_fee_rules winner
        where winner.account_id = loser.account_id
          and winner.mutual_exclusion_group = loser.mutual_exclusion_group
          and winner.id <> loser.id
          and winner.user_id = v_user_id
          and winner.is_active and winner.state = 'configured'
          and winner.trigger_kind = 'schedule'
          and coalesce(winner.next_charge_on, winner.starts_on) <= v_through
          and (winner.priority < loser.priority
            or (winner.priority = loser.priority
              and winner.created_at < loser.created_at))
      );

  for v_rule in
    select r.*, a.currency_code, s.statement_day, s.default_due_day,
        s.facility_status, s.credit_limit_minor
    from app_finance.credit_card_fee_rules r
    join app_finance.accounts a on a.id = r.account_id
    join app_finance.credit_facility_settings s on s.account_id = r.account_id
    where r.user_id = v_user_id
      and r.is_active
      and r.state = 'configured'
      and r.trigger_kind = 'schedule'
      and not a.is_archived
      and s.facility_status = 'active'
      and coalesce(r.next_charge_on, r.starts_on) <= v_through
    order by r.created_at
  loop
    v_on := coalesce(v_rule.next_charge_on, v_rule.starts_on);

    perform set_config('app_finance.facility_internal', 'on', true);

    v_calc := app_finance.resolve_or_create_fee_rule_version(
      (select fr from app_finance.credit_card_fee_rules fr
        where fr.id = v_rule.id),
      v_on
    );

    v_suppressed := v_rule.id = any(v_suppressed_ids);

    if v_suppressed or v_calc.calculation_type = 'manual' then
      v_amount := 0;
    else
      v_basis := case v_calc.percent_basis
        when 'credit_limit' then v_rule.credit_limit_minor
        when 'outstanding_balance' then
          app_finance.facility_outstanding_minor(v_rule.account_id)
        when 'highest_statement_due_lookback' then
          app_finance.highest_statement_due_minor(
            v_rule.account_id, v_on, v_calc.lookback_cycles
          )
        when 'highest_daily_balance_lookback' then
          app_finance.highest_daily_balance_minor(
            v_rule.account_id, v_on, v_calc.lookback_cycles
          )
        when 'statement_balance' then coalesce((
          select y.remaining_minor
          from app_finance.credit_card_statement_summaries y
          where y.account_id = v_rule.account_id
          order by y.cycle_close desc limit 1
        ), 0)
        else 0
      end;

      v_amount := app_finance.calculate_rule_amount(v_calc, v_basis);
    end if;

    if v_amount <= 0 then
      -- Nothing to charge (zero basis, manual/unknown, or suppressed by
      -- mutual exclusion); still move the schedule forward.
      update app_finance.credit_card_fee_rules
        set next_charge_on = case v_calc.frequency
            when 'once' then null
            when 'monthly' then (v_on + make_interval(months => 1))::date
            when 'quarterly' then (v_on + make_interval(months => 3))::date
            else (v_on + make_interval(years => 1))::date
          end,
          is_active = (v_calc.frequency <> 'once')
        where id = v_rule.id;
      perform set_config('app_finance.facility_internal', '', true);
      continue;
    end if;

    insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      source_account_id, category_id, title
    ) values (
      v_user_id, 'expense', v_on, v_amount, v_rule.currency_code,
      v_rule.account_id, v_rule.category_id, v_rule.name
    )
    returning id into v_tx_id;

    begin
      insert into app_finance.credit_card_fee_charges (
        user_id, rule_id, rule_version_id, transaction_id, charged_on,
        amount_minor, expected_amount_minor, actual_amount_minor,
        calculation_snapshot
      ) values (
        v_user_id, v_rule.id, v_calc.id, v_tx_id, v_on, v_amount,
        v_amount, v_amount,
        jsonb_build_object(
          'calculation_type', v_calc.calculation_type,
          'basis_minor', v_basis,
          'percent_basis', v_calc.percent_basis,
          'percent_basis_points', v_calc.percent_basis_points,
          'fixed_amount_minor', v_calc.fixed_amount_minor,
          'minimum_minor', v_calc.minimum_minor,
          'maximum_minor', v_calc.maximum_minor
        )
      );
    exception when unique_violation then
      -- Another run already charged this date; drop the duplicate expense.
      delete from app_finance.financial_transactions where id = v_tx_id;
      perform set_config('app_finance.facility_internal', '', true);
      continue;
    end;

    if v_rule.statement_day is not null then
      select * into v_bounds from app_finance.statement_bounds_for(
        v_rule.statement_day, v_rule.default_due_day, v_on
      );
      insert into app_finance.credit_card_statement_cycles (
        user_id, account_id, cycle_start, cycle_close, due_on
      ) values (
        v_user_id, v_rule.account_id, v_bounds.cycle_start,
        v_bounds.cycle_close, v_bounds.due_on
      )
      on conflict (account_id, cycle_close) do nothing;
      select id into v_cycle_id
        from app_finance.credit_card_statement_cycles
        where account_id = v_rule.account_id
          and cycle_close = v_bounds.cycle_close;
      insert into app_finance.credit_card_statement_items (
        user_id, cycle_id, transaction_id, amount_minor
      ) values (v_user_id, v_cycle_id, v_tx_id, v_amount);
      update app_finance.credit_card_fee_charges
        set statement_cycle_id = v_cycle_id
        where rule_id = v_rule.id and charged_on = v_on
          and trigger_transaction_id is null;
    end if;

    update app_finance.credit_card_fee_rules
      set next_charge_on = case v_calc.frequency
          when 'once' then null
          when 'monthly' then (v_on + make_interval(months => 1))::date
          when 'quarterly' then (v_on + make_interval(months => 3))::date
          else (v_on + make_interval(years => 1))::date
        end,
        is_active = (v_calc.frequency <> 'once')
      where id = v_rule.id;

    perform set_config('app_finance.facility_internal', '', true);
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- charge_credit_card learns the new foreign condition. Identical to the
-- 0026 version except for the one added `when
-- 'foreign_merchant_home_currency'` arm; the signature is unchanged.
-- ---------------------------------------------------------------------------

create or replace function app_finance.charge_credit_card(
  p_account_id uuid,
  p_title text,
  p_category_id uuid,
  p_occurred_on date,
  p_amount_minor bigint,
  p_notes text default null,
  p_charge_id uuid default null,
  p_transaction_subtype app_finance.card_transaction_subtype
    default 'purchase',
  p_is_foreign_currency boolean default false,
  p_is_foreign_merchant boolean default false,
  p_original_amount_minor bigint default null,
  p_original_currency_code text default null,
  p_exchange_rate numeric default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_card record;
  v_settings record;
  v_outstanding bigint;
  v_tx_id uuid;
  v_cycle_id uuid;
  v_bounds record;
  v_fx_rule app_finance.credit_card_fee_rules;
  v_cash_trigger app_finance.card_rule_trigger;
  v_cash_rule app_finance.credit_card_fee_rules;
  v_calc app_finance.credit_card_fee_rule_versions;
  v_condition_met boolean;
  v_fee_amount bigint;
  v_fee_tx_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_charge_id is not null then
    select id into v_tx_id from app_finance.financial_transactions
      where id = p_charge_id and user_id = v_user_id;
    if v_tx_id is not null then
      return v_tx_id;
    end if;
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'invalid_amount: must be positive';
  end if;

  select a.id, a.currency_code, a.account_type into v_card
    from app_finance.accounts a
    where a.id = p_account_id and a.user_id = v_user_id and not a.is_archived
    for update;
  if v_card is null then
    raise exception 'invalid_account: account not found or archived';
  end if;
  if v_card.account_type <> 'credit_card' then
    raise exception
      'invalid_account: ordinary card charges require a credit card';
  end if;
  select * into v_settings
    from app_finance.credit_facility_settings
    where account_id = p_account_id and user_id = v_user_id;
  if v_settings is null then
    raise exception
      'facility_not_configured: set a credit limit before financing purchases';
  end if;
  if v_settings.facility_status <> 'active' then
    raise exception
      'facility_not_active: this card cannot fund new purchases';
  end if;
  if v_settings.statement_day is null then
    raise exception
      'card_not_configured: set a statement closing day first';
  end if;
  if not exists (
    select 1 from app_finance.transaction_categories c
    where c.id = p_category_id and c.user_id = v_user_id
      and not c.is_archived and c.category_kind = 'expense'
  ) then
    raise exception 'invalid_category: expense category required';
  end if;

  v_outstanding := app_finance.facility_outstanding_minor(p_account_id);
  if v_outstanding + p_amount_minor > v_settings.credit_limit_minor then
    raise exception 'insufficient_credit: purchase exceeds available credit';
  end if;

  select * into v_bounds from app_finance.statement_bounds_for(
    v_settings.statement_day, v_settings.default_due_day, p_occurred_on
  );

  perform set_config('app_finance.facility_internal', 'on', true);

  insert into app_finance.financial_transactions (
    id, user_id, transaction_kind, occurred_on, amount_minor, currency_code,
    source_account_id, category_id, title, notes
  ) values (
    coalesce(p_charge_id, gen_random_uuid()), v_user_id, 'expense',
    p_occurred_on, p_amount_minor, v_card.currency_code, p_account_id,
    p_category_id, p_title, p_notes
  )
  returning id into v_tx_id;

  insert into app_finance.credit_card_statement_cycles (
    user_id, account_id, cycle_start, cycle_close, due_on
  ) values (
    v_user_id, p_account_id, v_bounds.cycle_start, v_bounds.cycle_close,
    v_bounds.due_on
  )
  on conflict (account_id, cycle_close) do nothing;

  select id into v_cycle_id
    from app_finance.credit_card_statement_cycles
    where account_id = p_account_id and cycle_close = v_bounds.cycle_close;

  insert into app_finance.credit_card_statement_items (
    user_id, cycle_id, transaction_id, amount_minor
  ) values (v_user_id, v_cycle_id, v_tx_id, p_amount_minor);

  -- Foreign markup: ordinary purchases only, evaluated against however the
  -- rule says "foreign" is decided (currency, merchant location, either,
  -- both, or merchant-abroad-billed-in-home-currency) — never assumed just
  -- because the currency differs.
  if p_transaction_subtype = 'purchase' then
    v_fx_rule := app_finance.resolve_trigger_rule(
      p_account_id, v_user_id, 'foreign_transaction'
    );
    if v_fx_rule.id is not null then
      v_calc := app_finance.resolve_or_create_fee_rule_version(
        v_fx_rule, p_occurred_on
      );
      v_condition_met := case v_calc.apply_when
        when 'currency_differs' then p_is_foreign_currency
        when 'merchant_outside_home' then p_is_foreign_merchant
        when 'both' then p_is_foreign_currency and p_is_foreign_merchant
        when 'foreign_merchant_home_currency' then
          p_is_foreign_merchant and not p_is_foreign_currency
        else p_is_foreign_currency or p_is_foreign_merchant
      end;
      if v_condition_met and v_calc.calculation_type <> 'manual' then
        v_fee_amount := app_finance.calculate_rule_amount(
          v_calc, p_amount_minor
        );
        if v_fee_amount > 0 then
          insert into app_finance.financial_transactions (
            user_id, transaction_kind, occurred_on, amount_minor,
            currency_code, source_account_id, category_id, title
          ) values (
            v_user_id, 'expense', p_occurred_on, v_fee_amount,
            v_card.currency_code, p_account_id, v_fx_rule.category_id,
            v_fx_rule.name
          )
          returning id into v_fee_tx_id;
          insert into app_finance.credit_card_fee_charges (
            user_id, rule_id, rule_version_id, transaction_id, charged_on,
            amount_minor, trigger_transaction_id, statement_cycle_id,
            expected_amount_minor, actual_amount_minor, calculation_snapshot
          ) values (
            v_user_id, v_fx_rule.id, v_calc.id, v_fee_tx_id, p_occurred_on,
            v_fee_amount, v_tx_id, v_cycle_id, v_fee_amount, v_fee_amount,
            jsonb_build_object(
              'basis_minor', p_amount_minor,
              'is_foreign_currency', p_is_foreign_currency,
              'is_foreign_merchant', p_is_foreign_merchant,
              'original_amount_minor', p_original_amount_minor,
              'original_currency_code', p_original_currency_code,
              'exchange_rate', p_exchange_rate
            )
          );
          insert into app_finance.credit_card_statement_items (
            user_id, cycle_id, transaction_id, amount_minor
          ) values (v_user_id, v_cycle_id, v_fee_tx_id, v_fee_amount);
        end if;
      end if;
    end if;
  else
    -- Cash advances and wallet loads are never treated like a purchase:
    -- a distinct fee category applies, matched to the exact subtype.
    v_cash_trigger := case p_transaction_subtype
      when 'domestic_cash_advance' then 'domestic_cash_advance'
      when 'international_cash_advance' then 'international_cash_advance'
      else 'wallet_transaction'
    end;
    v_cash_rule := app_finance.resolve_trigger_rule(
      p_account_id, v_user_id, v_cash_trigger
    );
    if v_cash_rule.id is not null then
      v_calc := app_finance.resolve_or_create_fee_rule_version(
        v_cash_rule, p_occurred_on
      );
      if v_calc.calculation_type <> 'manual' then
        v_fee_amount := app_finance.calculate_rule_amount(
          v_calc, p_amount_minor
        );
        if v_fee_amount > 0 then
          insert into app_finance.financial_transactions (
            user_id, transaction_kind, occurred_on, amount_minor,
            currency_code, source_account_id, category_id, title
          ) values (
            v_user_id, 'expense', p_occurred_on, v_fee_amount,
            v_card.currency_code, p_account_id, v_cash_rule.category_id,
            v_cash_rule.name
          )
          returning id into v_fee_tx_id;
          insert into app_finance.credit_card_fee_charges (
            user_id, rule_id, rule_version_id, transaction_id, charged_on,
            amount_minor, trigger_transaction_id, statement_cycle_id,
            expected_amount_minor, actual_amount_minor, calculation_snapshot
          ) values (
            v_user_id, v_cash_rule.id, v_calc.id, v_fee_tx_id, p_occurred_on,
            v_fee_amount, v_tx_id, v_cycle_id, v_fee_amount, v_fee_amount,
            jsonb_build_object(
              'basis_minor', p_amount_minor,
              'transaction_subtype', p_transaction_subtype
            )
          );
          insert into app_finance.credit_card_statement_items (
            user_id, cycle_id, transaction_id, amount_minor
          ) values (v_user_id, v_cycle_id, v_fee_tx_id, v_fee_amount);
        end if;
      end if;
    end if;
  end if;

  perform set_config('app_finance.facility_internal', '', true);
  return v_tx_id;
end;
$$;

notify pgrst, 'reload schema';
