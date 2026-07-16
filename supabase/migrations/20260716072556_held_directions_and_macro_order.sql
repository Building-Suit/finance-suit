-- Add bidirectional held amounts and deterministic macro-run ordering.
-- Existing held rows keep their original meaning: money the user owes.

-- ---------------------------------------------------------------------------
-- Held amount direction
-- ---------------------------------------------------------------------------
create type app_finance.held_amount_direction as enum (
  'i_owe',
  'owed_to_me'
);

alter table app_finance.held_amounts
  add column direction app_finance.held_amount_direction
  not null default 'i_owe';

grant usage on type app_finance.held_amount_direction
to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Stable display order for transactions created as one macro batch
-- ---------------------------------------------------------------------------
-- `created_at` remains the audit timestamp. `sort_at` is a presentation key:
-- macro actions receive adjacent values in their logical execution order so
-- newest-first transaction and history lists can reproduce that order.
alter table app_finance.financial_transactions
  add column sort_at timestamptz;

update app_finance.financial_transactions
  set sort_at = created_at;

alter table app_finance.financial_transactions
  alter column sort_at set default clock_timestamp(),
  alter column sort_at set not null;

drop index if exists app_finance.idx_tx_user_date;
create index idx_tx_user_date
  on app_finance.financial_transactions (
    user_id,
    occurred_on desc,
    sort_at desc,
    id desc
  );

-- Preserve existing macro item order, then make every future position
-- non-negative and unique inside its macro. This also protects the RPC from
-- malformed or older clients that send duplicate positions.
with ordered_items as (
  select
    id,
    row_number() over (
      partition by macro_id
      order by position, created_at, id
    )::integer - 1 as normalized_position
  from app_finance.transaction_macro_items
)
update app_finance.transaction_macro_items item
  set position = ordered.normalized_position
  from ordered_items ordered
  where item.id = ordered.id;

drop index if exists app_finance.idx_macro_items_macro_position;

alter table app_finance.transaction_macro_items
  add constraint macro_items_position_nonnegative check (position >= 0),
  add constraint macro_items_macro_position_unique unique (macro_id, position);

create index idx_macro_items_macro_owner_fk
  on app_finance.transaction_macro_items (macro_id, user_id);
create index idx_macro_items_user_id_fk
  on app_finance.transaction_macro_items (user_id);

-- ---------------------------------------------------------------------------
-- History view: append the stable sort key without changing existing columns
-- ---------------------------------------------------------------------------
create or replace view app_reports.history_items
with (security_invoker = on) as
  select
    t.id,
    t.user_id,
    'transaction'::text as record_group,
    t.transaction_kind::text as record_type,
    t.occurred_on as record_date,
    t.created_at,
    t.amount_minor,
    abs(t.amount_minor) as amount_abs_minor,
    t.currency_code,
    t.source_account_id,
    t.destination_account_id,
    t.category_id,
    t.counterparty,
    t.salary_period_id,
    coalesce(t.title, initcap(replace(t.transaction_kind::text, '_', ' '))) as title,
    t.notes,
    t.sort_at
  from app_finance.financial_transactions t
  union all
  select
    w.id,
    w.user_id,
    'work'::text as record_group,
    w.entry_type::text as record_type,
    w.work_date as record_date,
    w.created_at,
    w.computed_amount_minor as amount_minor,
    abs(w.computed_amount_minor) as amount_abs_minor,
    ss.currency_code,
    null::uuid as source_account_id,
    null::uuid as destination_account_id,
    null::uuid as category_id,
    null::text as counterparty,
    null::uuid as salary_period_id,
    initcap(replace(w.entry_type::text, '_', ' ')) as title,
    w.notes,
    w.created_at as sort_at
  from app_work.work_entries w
  left join app_salary.salary_settings ss on ss.user_id = w.user_id
  union all
  select
    a.id,
    a.user_id,
    'salary_adjustment'::text as record_group,
    a.adjustment_type::text as record_type,
    a.effective_date as record_date,
    a.created_at,
    case
      when a.adjustment_type = 'deduction' then -a.amount_minor
      else a.amount_minor
    end as amount_minor,
    a.amount_minor as amount_abs_minor,
    ss.currency_code,
    null::uuid as source_account_id,
    null::uuid as destination_account_id,
    null::uuid as category_id,
    null::text as counterparty,
    null::uuid as salary_period_id,
    coalesce(a.title, initcap(a.adjustment_type::text)) as title,
    a.notes,
    a.created_at as sort_at
  from app_salary.salary_adjustments a
  left join app_salary.salary_settings ss on ss.user_id = a.user_id;

-- ---------------------------------------------------------------------------
-- Atomic macro upsert: server-owned contiguous item positions
-- ---------------------------------------------------------------------------
create or replace function app_finance.save_macro(
  p_name text,
  p_items jsonb,
  p_macro_id uuid default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_macro_id uuid := p_macro_id;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_items is null
     or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'macro_empty: a macro needs at least one action';
  end if;

  if v_macro_id is null then
    insert into app_finance.transaction_macros (user_id, name)
    values (v_user_id, p_name)
    returning id into v_macro_id;
  else
    update app_finance.transaction_macros
      set name = p_name
      where id = v_macro_id and user_id = v_user_id;
    if not found then
      raise exception 'not_found: macro';
    end if;
    delete from app_finance.transaction_macro_items
      where macro_id = v_macro_id and user_id = v_user_id;
  end if;

  insert into app_finance.transaction_macro_items (
    user_id, macro_id, position, transaction_kind, amount_minor,
    source_account_id, destination_account_id, category_id,
    counterparty, title, notes, is_reversible
  )
  select
    v_user_id,
    v_macro_id,
    t.ordinality::integer - 1,
    (t.item ->> 'transaction_kind')::app_finance.transaction_kind,
    (t.item ->> 'amount_minor')::bigint,
    (t.item ->> 'source_account_id')::uuid,
    (t.item ->> 'destination_account_id')::uuid,
    (t.item ->> 'category_id')::uuid,
    nullif(t.item ->> 'counterparty', ''),
    nullif(t.item ->> 'title', ''),
    nullif(t.item ->> 'notes', ''),
    coalesce((t.item ->> 'is_reversible')::boolean, false)
  from jsonb_array_elements(p_items) with ordinality as t(item, ordinality);

  return v_macro_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Atomic macro application: authored forward order, inverse reverse order
-- ---------------------------------------------------------------------------
create or replace function app_finance.apply_macro(
  p_macro_id uuid,
  p_occurred_on date,
  p_reverse boolean default false
)
returns setof uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_macro record;
  v_reversible boolean;
  v_direction_title text;
  v_item record;
  v_source uuid;
  v_destination uuid;
  v_source_currency text;
  v_destination_currency text;
  v_title text;
  v_tx_id uuid;
  v_applied integer := 0;
  v_run_sort_at timestamptz := clock_timestamp();
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_macro
    from app_finance.transaction_macros
    where id = p_macro_id and user_id = v_user_id;
  if v_macro is null then
    raise exception 'not_found: macro';
  end if;

  select exists (
    select 1 from app_finance.transaction_macro_items
    where macro_id = p_macro_id and is_reversible
  ) into v_reversible;
  if p_reverse and not v_reversible then
    raise exception 'macro_not_reversible: this macro has no reversible actions';
  end if;

  v_direction_title := case
    when p_reverse then 'From ' || v_macro.name
    when v_reversible then 'To ' || v_macro.name
    else v_macro.name
  end;

  for v_item in
    select * from app_finance.transaction_macro_items
    where macro_id = p_macro_id
      and (not p_reverse or is_reversible)
    order by
      case when p_reverse then position end desc,
      case when not p_reverse then position end asc,
      case when p_reverse then created_at end desc,
      case when not p_reverse then created_at end asc,
      case when p_reverse then id end desc,
      case when not p_reverse then id end asc
  loop
    v_source := v_item.source_account_id;
    v_destination := v_item.destination_account_id;
    if p_reverse and v_item.transaction_kind = 'transfer' then
      v_source := v_item.destination_account_id;
      v_destination := v_item.source_account_id;
    end if;

    v_source_currency := null;
    v_destination_currency := null;
    if v_source is not null then
      select currency_code into v_source_currency
        from app_finance.accounts
        where id = v_source and user_id = v_user_id and not is_archived;
      if v_source_currency is null then
        raise exception 'invalid_account: source not found or archived';
      end if;
    end if;
    if v_destination is not null then
      select currency_code into v_destination_currency
        from app_finance.accounts
        where id = v_destination and user_id = v_user_id and not is_archived;
      if v_destination_currency is null then
        raise exception 'invalid_account: destination not found or archived';
      end if;
    end if;
    if v_source_currency is not null
       and v_destination_currency is not null
       and v_source_currency <> v_destination_currency then
      raise exception 'currency_mismatch: transfers require matching currencies';
    end if;

    v_title := left(
      case
        when v_item.title is null then v_direction_title
        else v_direction_title || ' · ' || v_item.title
      end,
      120);

    insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      source_account_id, destination_account_id, category_id,
      counterparty, title, notes, sort_at
    ) values (
      v_user_id, v_item.transaction_kind, p_occurred_on, v_item.amount_minor,
      coalesce(v_source_currency, v_destination_currency),
      v_source, v_destination, v_item.category_id,
      v_item.counterparty, v_title, v_item.notes,
      v_run_sort_at - (v_applied * interval '1 microsecond')
    )
    returning id into v_tx_id;

    v_applied := v_applied + 1;
    return next v_tx_id;
  end loop;

  if v_applied = 0 then
    raise exception 'macro_empty: a macro needs at least one action';
  end if;

  return;
end;
$$;

notify pgrst, 'reload schema';
