-- Held amounts against a Network contact.
--
-- A held amount has always been a private note to self with a free-text
-- counterparty: "I owe Ahmed 500". If Ahmed is also a Finance Suit user, only
-- one of the two people involved knew the number existed. This migration lets
-- a hold name a network connection instead of a string, and shows the other
-- side "<alias> is holding <amount> for/against you".
--
-- The exposure is deliberately one-way and read-only. The counterparty sees
-- the hold; it does not touch their balances, their held totals, or their
-- available balance, and they cannot act on it. The network privacy model —
-- connecting grants zero access to the other side's accounts, balances or
-- transactions — is preserved everywhere except the narrow projection in
-- app_finance.list_holds_against_me() below.
--
-- Shape follows 20260824090100_installment_responsibility_links.sql, which
-- solved the same cross-user display problem for installments.

-- ---------------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------------

-- shared_note is new so there is exactly one free-text field the owner
-- knowingly shares, the role network_transfers.shared_note already plays.
-- title and notes stay private.
alter table app_finance.held_amounts
  add column if not exists network_connection_id uuid
    references app_finance.network_connections (id) on delete set null,
  add column if not exists counterparty_user_id uuid
    references auth.users (id) on delete set null,
  add column if not exists shared_note text
    check (shared_note is null or char_length(shared_note) <= 500);

alter table app_finance.held_amounts
  drop constraint if exists held_amounts_network_no_self,
  add constraint held_amounts_network_no_self
    check (counterparty_user_id is null or counterparty_user_id <> user_id);

-- Deliberately no "both null or both set" constraint. Both columns are ON
-- DELETE SET NULL, so a departing peer must be able to degrade the row into a
-- plain free-text hold rather than block the cascade — the same convention as
-- network_transfers.sender_source_account_id. The counterparty text survives,
-- so nothing in the owner's UI goes blank.

create index if not exists idx_held_amounts_counterparty_user
  on app_finance.held_amounts (counterparty_user_id, settled_on)
  where counterparty_user_id is not null;
create index if not exists idx_held_amounts_network_connection
  on app_finance.held_amounts (network_connection_id)
  where network_connection_id is not null;

-- ---------------------------------------------------------------------------
-- Notification catalog
-- ---------------------------------------------------------------------------

insert into app_core.notification_event_catalog
  (event_key, category, is_critical, entity_type)
values
  ('held_amount.recorded_against_you', 'network', false, 'held_amount'),
  ('held_amount.updated',              'network', false, 'held_amount'),
  ('held_amount.settled',              'network', false, 'held_amount'),
  ('held_amount.removed',              'network', false, 'held_amount')
on conflict (event_key) do update
  set category = excluded.category,
      is_critical = excluded.is_critical,
      entity_type = excluded.entity_type;

-- The counterparty's view of a hold lives in the Network screen, beside the
-- other shared objects, so the existing /money/network route covers it.
create or replace function app_private.notification_route_for(
  p_event_key text,
  p_entity_id uuid,
  p_payload jsonb
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_event_key like 'credit_card.%'
      or p_event_key like 'installment.%'
      or p_event_key like 'bnpl.%'
      or p_event_key = 'facility.payment_recorded'
    then case
      when coalesce(p_payload ->> 'account_id', '') ~
        '^[0-9a-fA-F-]{36}$'
      then '/money/facilities/' || (p_payload ->> 'account_id')
      else '/money'
    end
    when p_event_key like 'network.%' then '/money/network'
    when p_event_key like 'held_amount.%' then '/money/network'
    when p_event_key = 'installment_link.request_received'
    then case
      when p_entity_id is not null
      then '/money/linked/' || p_entity_id::text
      else '/money/network'
    end
    when p_event_key like 'installment_link.%' then '/money'
    when p_event_key = 'system.developer_test' then '/home'
    else null
  end;
$$;

revoke execute on function app_private.notification_route_for(
  text, uuid, jsonb
) from public, anon, authenticated;
grant execute on function app_private.notification_route_for(text, uuid, jsonb)
  to service_role;

-- ---------------------------------------------------------------------------
-- Name resolution
-- ---------------------------------------------------------------------------

-- Each side sees the other under their own private directional alias. The
-- alias columns are never client-selectable, hence the definer-only grant.
-- Mirrors app_private.responsibility_counterparty_name.
create or replace function app_private.held_counterparty_name(
  p_held app_finance.held_amounts,
  p_viewer_user_id uuid
)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when p_viewer_user_id = p_held.user_id then coalesce((
      select case when c.user_a_id = p_held.user_id
        then c.user_a_alias_for_b else c.user_b_alias_for_a end
      from app_finance.network_connections c
      where c.id = p_held.network_connection_id
    ), nullif(p_held.counterparty, ''), 'Network contact')
    else coalesce((
      select case when c.user_a_id = p_held.counterparty_user_id
        then c.user_a_alias_for_b else c.user_b_alias_for_a end
      from app_finance.network_connections c
      where c.id = p_held.network_connection_id
    ), (
      select coalesce(nullif(pr.display_name, ''), 'Finance Suit user')
      from app_core.profiles pr where pr.id = p_held.user_id
    ), 'Finance Suit user')
  end;
$$;

revoke execute on function app_private.held_counterparty_name(
  app_finance.held_amounts, uuid
) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Definer helpers reachable from the invoker-context held RPCs
-- ---------------------------------------------------------------------------

-- app_finance.save_held_amount is SECURITY INVOKER and stays that way — it
-- relies on RLS rather than on definer privileges. It therefore cannot read
-- the alias columns or reach app_private.create_notification, both of which
-- are revoked from `authenticated`. These two helpers are the narrow definer
-- hops that close the gap, pinning identity internally exactly as
-- app_private.create_network_transfer does.
create or replace function app_private.resolve_held_network_counterparty(
  p_connection_id uuid
)
returns table (counterparty_user_id uuid, alias text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_connection app_finance.network_connections%rowtype;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_connection
  from app_finance.network_connections c
  where c.id = p_connection_id
    and v_user_id in (c.user_a_id, c.user_b_id)
    and c.removed_at is null;
  if v_connection is null then
    raise exception
      'network_destination_unavailable: this contact was removed from your network';
  end if;

  counterparty_user_id := case
    when v_connection.user_a_id = v_user_id then v_connection.user_b_id
    else v_connection.user_a_id
  end;
  alias := case
    when v_connection.user_a_id = v_user_id then v_connection.user_a_alias_for_b
    else v_connection.user_b_alias_for_a
  end;
  return next;
end;
$$;

revoke execute on function app_private.resolve_held_network_counterparty(uuid)
  from public, anon;
grant execute on function app_private.resolve_held_network_counterparty(uuid)
  to authenticated, service_role;

-- Granted to `authenticated` for the same reason, which makes both guards
-- below load-bearing: without the event-key allow-list this is a primitive for
-- minting arbitrary catalogued notifications, and without the ownership check
-- it is one for aiming them at arbitrary users.
create or replace function app_private.notify_held_amount_counterparty(
  p_held_id uuid,
  p_event_key text,
  p_discriminator text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_held app_finance.held_amounts%rowtype;
  v_connection_active boolean;
begin
  if p_event_key not in (
    'held_amount.recorded_against_you', 'held_amount.updated',
    'held_amount.settled', 'held_amount.removed'
  ) then
    raise exception 'invalid_event: %', p_event_key;
  end if;

  select * into v_held
  from app_finance.held_amounts h
  where h.id = p_held_id;
  if v_held is null then
    return;
  end if;
  if v_user_id is not null and v_held.user_id <> v_user_id then
    raise exception 'not_authorized: not your held amount';
  end if;
  if v_held.counterparty_user_id is null
    or v_held.network_connection_id is null then
    return;
  end if;

  select (c.removed_at is null) into v_connection_active
  from app_finance.network_connections c
  where c.id = v_held.network_connection_id;
  if not coalesce(v_connection_active, false) then
    return;
  end if;

  perform app_private.create_notification(
    p_user_id := v_held.counterparty_user_id,
    p_event_key := p_event_key,
    -- Repeatable events need the discriminator: create_notification dedupes on
    -- (user_id, dedupe_key) with ON CONFLICT DO NOTHING, so without it only the
    -- first update or settlement would ever reach the counterparty.
    p_dedupe_key := p_event_key || ':' || p_held_id::text
      || coalesce(':' || p_discriminator, ''),
    p_payload := jsonb_build_object(
      'type', p_event_key,
      'counterparty_name',
        app_private.held_counterparty_name(
          v_held, v_held.counterparty_user_id
        ),
      'direction', v_held.direction::text,
      'amount_text', case
        when app_private.network_show_amounts(v_held.counterparty_user_id)
          then v_held.currency_code || ' ' ||
            to_char(v_held.amount_minor / 100.0, 'FM999,999,999,990.00')
        else null
      end
    ),
    p_entity_type := 'held_amount',
    p_entity_id := p_held_id,
    p_route := '/money/network'
  );
end;
$$;

revoke execute on function app_private.notify_held_amount_counterparty(
  uuid, text, text
) from public, anon;
grant execute on function app_private.notify_held_amount_counterparty(
  uuid, text, text
) to authenticated, service_role;

-- Detachment cannot go through notify_held_amount_counterparty: by the time it
-- runs, the row no longer points at the contact being told about it. The
-- ownership check is against the caller rather than the row for the same
-- reason.
create or replace function app_private.notify_held_amount_counterparty_detached(
  p_owner_user_id uuid,
  p_counterparty_user_id uuid,
  p_connection_id uuid,
  p_held_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_connection_active boolean;
begin
  if v_user_id is not null and p_owner_user_id <> v_user_id then
    raise exception 'not_authorized: not your held amount';
  end if;
  if p_counterparty_user_id is null or p_connection_id is null then
    return;
  end if;

  select (c.removed_at is null) into v_connection_active
  from app_finance.network_connections c
  where c.id = p_connection_id;
  if not coalesce(v_connection_active, false) then
    return;
  end if;

  perform app_private.create_notification(
    p_user_id := p_counterparty_user_id,
    p_event_key := 'held_amount.removed',
    p_dedupe_key := 'held_amount.removed:' || p_held_id::text,
    p_payload := jsonb_build_object(
      'type', 'held_amount.removed',
      'counterparty_name', coalesce((
        select case when c.user_a_id = p_counterparty_user_id
          then c.user_a_alias_for_b else c.user_b_alias_for_a end
        from app_finance.network_connections c where c.id = p_connection_id
      ), 'Finance Suit user')
    ),
    p_entity_type := 'held_amount',
    p_entity_id := p_held_id,
    p_route := '/money/network'
  );
end;
$$;

revoke execute on function app_private.notify_held_amount_counterparty_detached(
  uuid, uuid, uuid, uuid
) from public, anon;
grant execute on function app_private.notify_held_amount_counterparty_detached(
  uuid, uuid, uuid, uuid
) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- save_held_amount
-- ---------------------------------------------------------------------------

-- Appending parameters changes the function's identity, so this is a drop and
-- recreate. Existing 11-argument PostgREST calls still resolve because the two
-- new parameters have defaults.
drop function if exists app_finance.save_held_amount(
  app_finance.transaction_kind, bigint, text, text, date, text, text,
  uuid, uuid, uuid, uuid
);

-- Stays SECURITY INVOKER: RLS is what confines it to the caller's own rows.
create function app_finance.save_held_amount(
  p_transaction_kind app_finance.transaction_kind,
  p_amount_minor bigint,
  p_currency_code text,
  p_counterparty text,
  p_held_on date,
  p_title text default null,
  p_notes text default null,
  p_account_id uuid default null,
  p_category_id uuid default null,
  p_transaction_id uuid default null,
  p_held_id uuid default null,
  p_network_connection_id uuid default null,
  p_shared_note text default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_held app_finance.held_amounts%rowtype;
  v_account app_finance.accounts%rowtype;
  v_held_id uuid;
  v_linked_transaction_id uuid := p_transaction_id;
  v_settlement_transaction_id uuid;
  v_direction app_finance.held_amount_direction;
  v_outgoing boolean;
  v_category_kind app_finance.category_kind;
  v_counterparty text := p_counterparty;
  v_counterparty_user_id uuid;
  v_shared_note text := nullif(btrim(coalesce(p_shared_note, '')), '');
  v_previous_counterparty_user_id uuid;
  v_previous_connection_id uuid;
  v_material_change boolean := true;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  if p_amount_minor <= 0 then raise exception 'invalid_amount: amount must be positive'; end if;
  if p_transaction_kind not in ('expense', 'allowance_given', 'custom_income', 'freelance_income') then
    raise exception 'invalid_kind: held amounts support expense, allowance, and income kinds';
  end if;

  v_outgoing := p_transaction_kind in ('expense', 'allowance_given');
  v_direction := case when v_outgoing
    then 'i_owe'::app_finance.held_amount_direction
    else 'owed_to_me'::app_finance.held_amount_direction
  end;

  -- A network hold labels itself from the connection: the caller's own private
  -- alias, resolved server-side. Client-supplied text is ignored so counterparty
  -- can never drift from the contact it names.
  if p_network_connection_id is not null then
    select r.counterparty_user_id, r.alias
      into v_counterparty_user_id, v_counterparty
    from app_private.resolve_held_network_counterparty(
      p_network_connection_id
    ) r;
  end if;

  if p_category_id is not null then
    select category_kind into v_category_kind
    from app_finance.transaction_categories
    where id = p_category_id and user_id = v_user_id and not is_archived;
    if v_category_kind is null then
      raise exception 'not_found: category';
    end if;
    if v_category_kind <> (case p_transaction_kind
      when 'expense' then 'expense'::app_finance.category_kind
      when 'allowance_given' then 'allowance'::app_finance.category_kind
      else 'income'::app_finance.category_kind
    end) then
      raise exception 'invalid_category: category kind does not match transaction kind';
    end if;
  end if;

  if p_held_id is not null then
    select * into v_held
    from app_finance.held_amounts
    where id = p_held_id and user_id = v_user_id
    for update;
    if v_held is null then raise exception 'not_found: held amount'; end if;
    v_linked_transaction_id := coalesce(v_held.linked_transaction_id, case when not v_held.manages_transaction then v_held.transaction_id end);
    v_settlement_transaction_id := coalesce(v_held.settlement_transaction_id, case when v_held.manages_transaction then v_held.transaction_id end);
    v_previous_counterparty_user_id := v_held.counterparty_user_id;
    v_previous_connection_id := v_held.network_connection_id;
    v_material_change := v_held.amount_minor <> p_amount_minor
      or v_held.currency_code <> p_currency_code
      or v_held.held_on <> p_held_on
      or v_held.direction <> v_direction
      or v_held.shared_note is distinct from v_shared_note;
  end if;

  select * into v_account
  from app_finance.accounts
  where id = p_account_id and user_id = v_user_id and not is_archived;
  if v_account is null then raise exception 'invalid_account: account not found or archived'; end if;
  if v_account.currency_code <> p_currency_code then
    raise exception 'currency_mismatch: held amount and account must match';
  end if;

  if v_linked_transaction_id is not null then
    perform 1 from app_finance.financial_transactions
    where id = v_linked_transaction_id and user_id = v_user_id;
    if not found then raise exception 'not_found: linked transaction'; end if;
  end if;

  if p_held_id is not null and v_held.settled_on is not null then
    if v_settlement_transaction_id is null then
      insert into app_finance.financial_transactions (
        user_id, transaction_kind, occurred_on, amount_minor, currency_code,
        source_account_id, destination_account_id, category_id,
        counterparty, title, notes
      ) values (
        v_user_id, p_transaction_kind, v_held.settled_on, p_amount_minor, p_currency_code,
        case when v_outgoing then p_account_id end,
        case when not v_outgoing then p_account_id end,
        p_category_id, v_counterparty, p_title, p_notes
      ) returning id into v_settlement_transaction_id;
    else
      update app_finance.financial_transactions
      set transaction_kind = p_transaction_kind,
          occurred_on = v_held.settled_on,
          amount_minor = p_amount_minor,
          currency_code = p_currency_code,
          source_account_id = case when v_outgoing then p_account_id end,
          destination_account_id = case when not v_outgoing then p_account_id end,
          category_id = p_category_id,
          counterparty = v_counterparty,
          title = p_title,
          notes = p_notes
      where id = v_settlement_transaction_id and user_id = v_user_id;
      if not found then raise exception 'not_found: settlement transaction'; end if;
    end if;
  end if;

  if p_held_id is null then
    insert into app_finance.held_amounts (
      user_id, direction, transaction_kind, category_id,
      amount_minor, currency_code, counterparty, held_on,
      transaction_id, linked_transaction_id, settlement_transaction_id,
      account_id, manages_transaction, title, notes,
      network_connection_id, counterparty_user_id, shared_note
    ) values (
      v_user_id, v_direction, p_transaction_kind, p_category_id,
      p_amount_minor, p_currency_code, v_counterparty, p_held_on,
      v_linked_transaction_id, v_linked_transaction_id, null,
      p_account_id, true, p_title, p_notes,
      p_network_connection_id, v_counterparty_user_id, v_shared_note
    ) returning id into v_held_id;
  else
    update app_finance.held_amounts
    set direction = v_direction,
        transaction_kind = p_transaction_kind,
        category_id = p_category_id,
        amount_minor = p_amount_minor,
        currency_code = p_currency_code,
        counterparty = v_counterparty,
        held_on = p_held_on,
        transaction_id = coalesce(v_settlement_transaction_id, v_linked_transaction_id),
        linked_transaction_id = v_linked_transaction_id,
        settlement_transaction_id = v_settlement_transaction_id,
        account_id = p_account_id,
        manages_transaction = true,
        title = p_title,
        notes = p_notes,
        network_connection_id = p_network_connection_id,
        counterparty_user_id = v_counterparty_user_id,
        shared_note = v_shared_note
    where id = p_held_id and user_id = v_user_id
    returning id into v_held_id;
  end if;

  -- A re-pointed link is a removal for the old contact and a fresh record for
  -- the new one; only then does an unchanged link fall through to 'updated'.
  if v_previous_counterparty_user_id is not null
    and v_previous_counterparty_user_id is distinct from v_counterparty_user_id then
    perform app_private.notify_held_amount_counterparty_detached(
      v_user_id, v_previous_counterparty_user_id, v_previous_connection_id,
      v_held_id
    );
  end if;

  if v_counterparty_user_id is not null then
    if v_previous_counterparty_user_id is distinct from v_counterparty_user_id then
      perform app_private.notify_held_amount_counterparty(
        v_held_id, 'held_amount.recorded_against_you'
      );
    elsif v_material_change then
      perform app_private.notify_held_amount_counterparty(
        v_held_id, 'held_amount.updated',
        p_amount_minor::text || ':' || p_held_on::text
      );
    end if;
  end if;

  return v_held_id;
end;
$$;

grant execute on function app_finance.save_held_amount(
  app_finance.transaction_kind, bigint, text, text, date, text, text,
  uuid, uuid, uuid, uuid, uuid, text
) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Settle and delete
-- ---------------------------------------------------------------------------

-- Settling books the stored kind and category on the settlement date.
create or replace function app_finance.set_held_amount_settled(
  p_held_id uuid,
  p_settled_on date
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_held app_finance.held_amounts%rowtype;
  v_account app_finance.accounts%rowtype;
  v_transaction_id uuid;
  v_outgoing boolean;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;

  select * into v_held
  from app_finance.held_amounts
  where id = p_held_id and user_id = v_user_id
  for update;
  if v_held is null then raise exception 'not_found: held amount'; end if;

  v_transaction_id := v_held.settlement_transaction_id;

  if p_settled_on is null then
    if v_transaction_id is not null then
      delete from app_finance.financial_transactions
      where id = v_transaction_id and user_id = v_user_id;
    end if;
    update app_finance.held_amounts
    set settled_on = null,
        settlement_transaction_id = null,
        transaction_id = linked_transaction_id,
        manages_transaction = linked_transaction_id is null
    where id = p_held_id and user_id = v_user_id;
    -- Re-opening a settled hold is a change the counterparty should see.
    perform app_private.notify_held_amount_counterparty(
      p_held_id, 'held_amount.updated',
      v_held.amount_minor::text || ':reopened'
    );
    return;
  end if;

  if v_held.account_id is null then
    select * into v_account
    from app_finance.accounts
    where user_id = v_user_id
      and currency_code = v_held.currency_code
      and not is_archived
    order by is_default desc, created_at, id
    limit 1;
  else
    select * into v_account
    from app_finance.accounts
    where id = v_held.account_id and user_id = v_user_id and not is_archived;
  end if;
  if v_account is null then raise exception 'invalid_account: account not found or archived'; end if;
  if v_account.currency_code <> v_held.currency_code then
    raise exception 'currency_mismatch: held amount and account must match';
  end if;

  v_outgoing := v_held.transaction_kind in ('expense', 'allowance_given');

  if v_transaction_id is null then
    insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      source_account_id, destination_account_id, category_id,
      counterparty, title, notes
    ) values (
      v_user_id, v_held.transaction_kind, p_settled_on, v_held.amount_minor, v_held.currency_code,
      case when v_outgoing then v_account.id end,
      case when not v_outgoing then v_account.id end,
      v_held.category_id, v_held.counterparty, v_held.title, v_held.notes
    ) returning id into v_transaction_id;
  else
    update app_finance.financial_transactions
    set transaction_kind = v_held.transaction_kind,
        occurred_on = p_settled_on,
        amount_minor = v_held.amount_minor,
        currency_code = v_held.currency_code,
        source_account_id = case when v_outgoing then v_account.id end,
        destination_account_id = case when not v_outgoing then v_account.id end,
        category_id = v_held.category_id,
        counterparty = v_held.counterparty,
        title = v_held.title,
        notes = v_held.notes
    where id = v_transaction_id and user_id = v_user_id;
    if not found then raise exception 'not_found: settlement transaction'; end if;
  end if;

  update app_finance.held_amounts
  set settled_on = p_settled_on,
      settlement_transaction_id = v_transaction_id,
      transaction_id = v_transaction_id,
      account_id = v_account.id,
      manages_transaction = true
  where id = p_held_id and user_id = v_user_id;

  perform app_private.notify_held_amount_counterparty(
    p_held_id, 'held_amount.settled', p_settled_on::text
  );
end;
$$;

-- Deleting a held amount must only ever remove the settlement transaction
-- it created, never a linked origin transaction.
create or replace function app_finance.delete_held_amount(p_held_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_settlement_transaction_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  -- Notify before deleting: the helper reads the row, and after the delete
  -- there is nothing left to read. Same transaction, so the two roll back
  -- together.
  perform app_private.notify_held_amount_counterparty(
    p_held_id, 'held_amount.removed'
  );

  delete from app_finance.held_amounts
    where id = p_held_id and user_id = v_user_id
    returning settlement_transaction_id
    into v_settlement_transaction_id;
  if not found then
    raise exception 'not_found: held amount';
  end if;

  if v_settlement_transaction_id is not null then
    delete from app_finance.financial_transactions
      where id = v_settlement_transaction_id and user_id = v_user_id;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Alias snapshot upkeep
-- ---------------------------------------------------------------------------

-- counterparty stays NOT NULL and carries the owner's private alias for the
-- contact, so the existing Held tab and settlement-transaction paths need no
-- null handling and the label survives the connection being removed. The cost
-- is a snapshot that must be refreshed on rename, for the caller's own rows
-- only.
create or replace function app_finance.rename_network_contact(
  p_connection_id uuid,
  p_new_alias text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_alias text := btrim(coalesce(p_new_alias, ''));
  v_connection app_finance.network_connections%rowtype;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if char_length(v_alias) < 1 or char_length(v_alias) > 80 then
    raise exception 'invalid_alias: choose a name between 1 and 80 characters';
  end if;

  select * into v_connection
  from app_finance.network_connections c
  where c.id = p_connection_id
    and v_user_id in (c.user_a_id, c.user_b_id)
    and c.removed_at is null
  for update;
  if v_connection is null then
    raise exception 'not_found: network connection';
  end if;

  if v_connection.user_a_id = v_user_id then
    update app_finance.network_connections
      set user_a_alias_for_b = v_alias where id = p_connection_id;
  else
    update app_finance.network_connections
      set user_b_alias_for_a = v_alias where id = p_connection_id;
  end if;

  update app_finance.held_amounts
    set counterparty = v_alias
    where user_id = v_user_id
      and network_connection_id = p_connection_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- The cross-user read
-- ---------------------------------------------------------------------------

-- The entire cross-user exposure of held amounts, and nothing else. Absent by
-- design: account_id, category_id, every transaction id, title, notes,
-- user_id, manages_transaction. shared_note is the one free-text field the
-- owner opted into sharing.
--
-- No cross-user RLS policy is added — app_finance.held_amounts keeps its four
-- `auth.uid() = user_id` policies untouched, and this definer function is the
-- only way the other side sees anything. That is the deliberate difference
-- from installment_responsibility_links, which was designed as a shared object
-- from day one; held_amounts is a private ledger table with private free text
-- in it.
--
-- owner_direction is the owner's stored direction, which the client flips for
-- display: the owner's 'i_owe' means the viewer is owed ("holding for you"),
-- and 'owed_to_me' means the viewer owes ("holding against you").
create or replace function app_finance.list_holds_against_me()
returns table (
  held_id uuid,
  connection_id uuid,
  owner_direction app_finance.held_amount_direction,
  counterparty_alias text,
  amount_minor bigint,
  currency_code text,
  held_on date,
  settled_on date,
  shared_note text,
  connection_active boolean,
  recorded_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    h.id,
    h.network_connection_id,
    h.direction,
    app_private.held_counterparty_name(h, (select auth.uid())),
    h.amount_minor,
    h.currency_code,
    h.held_on,
    h.settled_on,
    h.shared_note,
    (c.id is not null and c.removed_at is null),
    h.created_at,
    h.updated_at
  from app_finance.held_amounts h
  join app_finance.network_connections c on c.id = h.network_connection_id
  where (select auth.uid()) is not null
    and h.counterparty_user_id = (select auth.uid())
    and c.removed_at is null
  order by h.settled_on nulls first, h.held_on desc, h.id desc;
$$;

revoke execute on function app_finance.list_holds_against_me()
  from public, anon;
grant execute on function app_finance.list_holds_against_me()
  to authenticated, service_role;

notify pgrst, 'reload schema';
