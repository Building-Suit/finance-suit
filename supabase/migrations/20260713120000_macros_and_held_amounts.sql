-- Transaction macros (saved multi-action shortcuts, optionally reversible)
-- and held amounts (money owed to someone, optionally linked to a
-- transaction). Money stays bigint minor units; business dates are date.

-- ---------------------------------------------------------------------------
-- transaction_macros
-- ---------------------------------------------------------------------------
create table app_finance.transaction_macros (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint transaction_macros_owner_unique unique (id, user_id)
);

create trigger trg_transaction_macros_updated_at
  before update on app_finance.transaction_macros
  for each row execute function app_private.set_updated_at();

create unique index idx_macros_name_per_user
  on app_finance.transaction_macros (user_id, lower(name));

-- ---------------------------------------------------------------------------
-- transaction_macro_items
-- ---------------------------------------------------------------------------
create table app_finance.transaction_macro_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  macro_id uuid not null,
  position integer not null default 0,
  transaction_kind app_finance.transaction_kind not null,
  amount_minor bigint not null check (amount_minor > 0),
  source_account_id uuid,
  destination_account_id uuid,
  category_id uuid,
  counterparty text check (char_length(counterparty) <= 120),
  title text check (char_length(title) <= 120),
  notes text check (char_length(notes) <= 1000),
  is_reversible boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Ownership-aware references: no cross-user macro/account/category linkage.
  constraint macro_items_macro_owner_fk
    foreign key (macro_id, user_id)
    references app_finance.transaction_macros (id, user_id) on delete cascade,
  constraint macro_items_source_owner_fk
    foreign key (source_account_id, user_id)
    references app_finance.accounts (id, user_id),
  constraint macro_items_destination_owner_fk
    foreign key (destination_account_id, user_id)
    references app_finance.accounts (id, user_id),
  constraint macro_items_category_owner_fk
    foreign key (category_id, user_id)
    references app_finance.transaction_categories (id, user_id),
  -- Salary income is created only by the salary payment RPC.
  constraint macro_items_kind_allowed check (transaction_kind <> 'salary_income'),
  -- Same direction rules as financial_transactions.
  constraint macro_items_direction_by_kind check (
    (transaction_kind in ('expense', 'allowance_given')
      and source_account_id is not null
      and destination_account_id is null)
    or
    (transaction_kind in ('custom_income', 'freelance_income')
      and destination_account_id is not null
      and source_account_id is null)
    or
    (transaction_kind = 'transfer'
      and source_account_id is not null
      and destination_account_id is not null
      and source_account_id <> destination_account_id)
  )
);

create trigger trg_transaction_macro_items_updated_at
  before update on app_finance.transaction_macro_items
  for each row execute function app_private.set_updated_at();

create index idx_macro_items_macro_position
  on app_finance.transaction_macro_items (macro_id, position, created_at, id);
create index idx_macro_items_source_owner_fk
  on app_finance.transaction_macro_items (source_account_id, user_id)
  where source_account_id is not null;
create index idx_macro_items_destination_owner_fk
  on app_finance.transaction_macro_items (destination_account_id, user_id)
  where destination_account_id is not null;
create index idx_macro_items_category_owner_fk
  on app_finance.transaction_macro_items (category_id, user_id)
  where category_id is not null;

-- ---------------------------------------------------------------------------
-- held_amounts
-- ---------------------------------------------------------------------------
-- Composite key so child rows can reference transactions ownership-aware.
alter table app_finance.financial_transactions
  add constraint financial_transactions_owner_unique unique (id, user_id);

create table app_finance.held_amounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  amount_minor bigint not null check (amount_minor > 0),
  currency_code text not null default 'EGP' check (currency_code ~ '^[A-Z]{3}$'),
  counterparty text not null check (char_length(counterparty) between 1 and 120),
  held_on date not null,
  settled_on date,
  transaction_id uuid,
  title text check (char_length(title) <= 120),
  notes text check (char_length(notes) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint held_amounts_transaction_owner_fk
    foreign key (transaction_id, user_id)
    references app_finance.financial_transactions (id, user_id)
    on delete set null (transaction_id),
  constraint held_settled_not_before_held check (
    settled_on is null or settled_on >= held_on
  )
);

create trigger trg_held_amounts_updated_at
  before update on app_finance.held_amounts
  for each row execute function app_private.set_updated_at();

create index idx_held_amounts_user_date
  on app_finance.held_amounts (user_id, held_on desc, created_at desc, id desc);
create index idx_held_amounts_transaction_owner_fk
  on app_finance.held_amounts (transaction_id, user_id)
  where transaction_id is not null;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table app_finance.transaction_macros enable row level security;
alter table app_finance.transaction_macro_items enable row level security;
alter table app_finance.held_amounts enable row level security;

create policy transaction_macros_select on app_finance.transaction_macros
  for select to authenticated using ((select auth.uid()) = user_id);
create policy transaction_macros_insert on app_finance.transaction_macros
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy transaction_macros_update on app_finance.transaction_macros
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy transaction_macros_delete on app_finance.transaction_macros
  for delete to authenticated using ((select auth.uid()) = user_id);

create policy transaction_macro_items_select on app_finance.transaction_macro_items
  for select to authenticated using ((select auth.uid()) = user_id);
create policy transaction_macro_items_insert on app_finance.transaction_macro_items
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy transaction_macro_items_update on app_finance.transaction_macro_items
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy transaction_macro_items_delete on app_finance.transaction_macro_items
  for delete to authenticated using ((select auth.uid()) = user_id);

create policy held_amounts_select on app_finance.held_amounts
  for select to authenticated using ((select auth.uid()) = user_id);
create policy held_amounts_insert on app_finance.held_amounts
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy held_amounts_update on app_finance.held_amounts
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy held_amounts_delete on app_finance.held_amounts
  for delete to authenticated using ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- Atomic macro upsert (macro row + full item replacement)
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
    coalesce((t.item ->> 'position')::integer, t.ordinality::integer - 1),
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
-- Atomic macro application (forward or reverse)
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

  -- Reversible macros are named after the destination ("Work"), so runs are
  -- titled "To Work" / "From Work"; one-way macros keep their plain name.
  v_direction_title := case
    when p_reverse then 'From ' || v_macro.name
    when v_reversible then 'To ' || v_macro.name
    else v_macro.name
  end;

  for v_item in
    select * from app_finance.transaction_macro_items
    where macro_id = p_macro_id
      and (not p_reverse or is_reversible)
    order by position, created_at, id
  loop
    v_source := v_item.source_account_id;
    v_destination := v_item.destination_account_id;
    -- A reversed transfer moves the money back.
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
      counterparty, title, notes
    ) values (
      v_user_id, v_item.transaction_kind, p_occurred_on, v_item.amount_minor,
      coalesce(v_source_currency, v_destination_currency),
      v_source, v_destination, v_item.category_id,
      v_item.counterparty, v_title, v_item.notes
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

-- ---------------------------------------------------------------------------
-- Realtime publication
-- ---------------------------------------------------------------------------
alter publication supabase_realtime add table app_finance.transaction_macros;
alter publication supabase_realtime add table app_finance.transaction_macro_items;
alter publication supabase_realtime add table app_finance.held_amounts;
