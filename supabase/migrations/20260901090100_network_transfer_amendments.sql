-- Sender control over a still-pending network transfer.
--
-- Until now the sender could only wait: once a request existed, the receiver
-- alone decided its fate. A wrong amount or a wrong contact was permanent
-- clutter in both inboxes. This migration lets the sender withdraw a pending
-- request outright, or amend its amount, source account, date and note while
-- the receiver has not answered.
--
-- Nothing here books a ledger row. app_finance.accept_network_transfer stays
-- the only path that writes app_finance.financial_transactions, which is what
-- keeps app_private.protect_network_transactions' invariant and the
-- double-book protection intact. The pending amount is held against the
-- sender's available balance by 20260901090200_account_available_balance.sql,
-- which reads status = 'pending' — so cancelling or amending moves that hold
-- with no ledger involvement at all.

-- ---------------------------------------------------------------------------
-- State columns
-- ---------------------------------------------------------------------------

-- cancelled_at is deliberately NOT responded_at. responded_at means "the
-- receiver decided", and the rejected/accepted branches of the state CHECK
-- already bind it to that meaning. A sender withdrawing a request is not a
-- response, and conflating the two would make "did the receiver ever see
-- this?" unanswerable.
alter table app_finance.network_transfers
  add column if not exists cancelled_at timestamptz,
  add column if not exists amended_at timestamptz,
  add column if not exists amendment_count integer not null default 0
    check (amendment_count >= 0);

alter table app_finance.network_transfers
  drop constraint if exists network_transfers_state_fields,
  add constraint network_transfers_state_fields check (
    (status = 'pending' and responded_at is null and cancelled_at is null
      and sender_transaction_id is null
      and receiver_transaction_id is null
      and receiver_destination_account_id is null)
    or (status = 'cancelled' and cancelled_at is not null
      and responded_at is null
      and sender_transaction_id is null
      and receiver_transaction_id is null
      and receiver_destination_account_id is null)
    or (status = 'rejected' and responded_at is not null
      and cancelled_at is null
      and sender_transaction_id is null
      and receiver_transaction_id is null)
    or (status = 'accepted' and responded_at is not null
      and cancelled_at is null)
  );

-- The table is revoke-all plus an explicit column grant, so new columns are
-- not selectable by default. Without this the columns are invisible to any
-- direct client select (everything currently goes through
-- list_network_transfers, so the omission would hide until it did not).
grant select (cancelled_at, amended_at, amendment_count)
  on app_finance.network_transfers to authenticated;

-- Supports the pending-hold aggregate in app_finance.account_hold_totals.
create index if not exists idx_network_transfers_pending_source
  on app_finance.network_transfers (sender_source_account_id)
  where status = 'pending' and sender_source_account_id is not null;

-- ---------------------------------------------------------------------------
-- Notification catalog
-- ---------------------------------------------------------------------------

insert into app_core.notification_event_catalog
  (event_key, category, is_critical, entity_type)
values
  ('network.transfer_cancelled', 'network', false, 'network_transfer'),
  ('network.transfer_amended',   'network', false, 'network_transfer')
on conflict (event_key) do update
  set category = excluded.category,
      is_critical = excluded.is_critical,
      entity_type = excluded.entity_type;

-- Legacy-shaped producers resolve their event key through this map.
create or replace function app_private.notification_event_key_for(
  p_legacy_type text,
  p_reminder_kind text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_legacy_type
    when 'credit_card_statement_due' then case p_reminder_kind
      when 'overdue' then 'credit_card.statement_overdue'
      when 'due_today' then 'credit_card.statement_due_today'
      else 'credit_card.statement_due_soon'
    end
    when 'installment_due' then case p_reminder_kind
      when 'overdue' then 'installment.overdue'
      when 'due_today' then 'installment.due_today'
      else 'installment.due_soon'
    end
    when 'bnpl_due' then case p_reminder_kind
      when 'overdue' then 'bnpl.overdue'
      when 'due_today' then 'bnpl.due_today'
      else 'bnpl.due_soon'
    end
    when 'facility_payment_confirmation' then 'facility.payment_recorded'
    when 'network_add_request' then 'network.add_request_received'
    when 'network_add_request_accepted' then 'network.add_request_accepted'
    when 'network_transfer_pending' then 'network.transfer_received'
    when 'network_transfer_accepted' then 'network.transfer_accepted'
    when 'network_transfer_rejected' then 'network.transfer_declined'
    when 'network_transfer_cancelled' then 'network.transfer_cancelled'
    when 'network_transfer_amended' then 'network.transfer_amended'
    when 'installment_link_request' then 'installment_link.request_received'
    when 'installment_link_accepted' then 'installment_link.accepted'
    when 'installment_link_rejected' then 'installment_link.declined'
    when 'developer_test' then 'system.developer_test'
    else null
  end;
$$;

revoke execute on function app_private.notification_event_key_for(text, text)
  from public, anon, authenticated;
grant execute on function app_private.notification_event_key_for(text, text)
  to service_role;

-- ---------------------------------------------------------------------------
-- Cancel
-- ---------------------------------------------------------------------------

-- Sender-side withdrawal of a pending request. Books nothing, and is allowed
-- even after the connection was removed: like reject_network_transfer, it only
-- closes the shared request object.
create or replace function app_finance.cancel_network_transfer(
  p_transfer_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_transfer app_finance.network_transfers%rowtype;
  v_alias text;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  -- The RLS-shaped predicate means a third party gets 'not_found' rather than
  -- learning that the transfer exists.
  select * into v_transfer
  from app_finance.network_transfers nt
  where nt.id = p_transfer_id
    and v_user_id in (nt.sender_user_id, nt.receiver_user_id)
  for update;
  if v_transfer is null then
    raise exception 'not_found: network transfer';
  end if;
  if v_transfer.sender_user_id <> v_user_id then
    raise exception 'not_authorized: only the sender can cancel';
  end if;
  if v_transfer.status = 'cancelled' then
    return;
  end if;
  if v_transfer.status <> 'pending' then
    raise exception 'already_decided: this transfer was already handled';
  end if;

  update app_finance.network_transfers
    set status = 'cancelled', cancelled_at = now()
    where id = v_transfer.id;

  -- The receiver's own private alias for the sender.
  select case
      when c.user_a_id = v_transfer.receiver_user_id then c.user_a_alias_for_b
      else c.user_b_alias_for_a
    end into v_alias
  from app_finance.network_connections c
  where c.id = v_transfer.connection_id;

  perform app_private.enqueue_network_notification(
    v_transfer.receiver_user_id, 'network_transfer', v_transfer.id,
    'network_transfer_cancelled',
    jsonb_build_object(
      'type', 'network_transfer_cancelled',
      'reminder_kind', 'network_transfer_cancelled',
      'counterparty_name', coalesce(v_alias, 'Network contact')
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Amend
-- ---------------------------------------------------------------------------

-- Null means "leave unchanged", which is why erasing the note needs its own
-- flag. Deliberately performs NO funds check: a pending transfer reserves
-- against the available balance, and available is allowed to go negative —
-- app_finance.accept_network_transfer still gates on the real balance_minor at
-- acceptance time, which is the only moment money actually moves.
create or replace function app_finance.amend_network_transfer(
  p_transfer_id uuid,
  p_amount_minor bigint default null,
  p_source_account_id uuid default null,
  p_requested_on date default null,
  p_shared_note text default null,
  p_clear_shared_note boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_transfer app_finance.network_transfers%rowtype;
  v_connection app_finance.network_connections%rowtype;
  v_source record;
  v_amount bigint;
  v_account_id uuid;
  v_requested_on date;
  v_shared_note text;
  v_alias text;
  v_count integer;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_transfer
  from app_finance.network_transfers nt
  where nt.id = p_transfer_id
    and v_user_id in (nt.sender_user_id, nt.receiver_user_id)
  for update;
  if v_transfer is null then
    raise exception 'not_found: network transfer';
  end if;
  if v_transfer.sender_user_id <> v_user_id then
    raise exception 'not_authorized: only the sender can change this transfer';
  end if;
  if v_transfer.status = 'cancelled' then
    raise exception 'transfer_cancelled: you already cancelled this transfer';
  end if;
  if v_transfer.status <> 'pending' then
    raise exception 'already_decided: this transfer was already handled';
  end if;

  if v_transfer.connection_id is null then
    raise exception
      'network_destination_unavailable: this contact was removed from your network';
  end if;
  select * into v_connection
  from app_finance.network_connections c
  where c.id = v_transfer.connection_id
  for update;
  if v_connection is null or v_connection.removed_at is not null then
    raise exception
      'network_destination_unavailable: this contact was removed from your network';
  end if;

  v_amount := coalesce(p_amount_minor, v_transfer.amount_minor);
  if v_amount <= 0 then
    raise exception 'invalid_amount: must be positive';
  end if;
  v_account_id := coalesce(
    p_source_account_id, v_transfer.sender_source_account_id
  );
  v_requested_on := coalesce(p_requested_on, v_transfer.requested_on);
  v_shared_note := case
    when p_clear_shared_note then null
    else coalesce(
      nullif(btrim(coalesce(p_shared_note, '')), ''), v_transfer.shared_note
    )
  end;

  -- Same validation the create path runs, so a source account can never enter
  -- a state acceptance would later reject.
  if v_account_id is null then
    raise exception 'invalid_account: source not found or archived';
  end if;
  select a.id, a.currency_code, a.account_type into v_source
  from app_finance.accounts a
  where a.id = v_account_id
    and a.user_id = v_user_id
    and not a.is_archived
  for update;
  if v_source is null then
    raise exception 'invalid_account: source not found or archived';
  end if;
  if app_finance.account_role(v_source.account_type) <> 'asset' then
    raise exception 'invalid_account: network transfers move your own cash';
  end if;

  -- Nothing material changed: leave the row and the receiver alone rather than
  -- burning an amendment and a push on a no-op.
  if v_amount = v_transfer.amount_minor
    and v_account_id is not distinct from v_transfer.sender_source_account_id
    and v_source.currency_code = v_transfer.currency_code
    and v_requested_on = v_transfer.requested_on
    and v_shared_note is not distinct from v_transfer.shared_note then
    return v_transfer.id;
  end if;

  -- currency_code follows the source account, exactly as the create path
  -- derives it. Letting the two drift would surface to the receiver as the
  -- opaque 'transfer_unavailable' from acceptance's currency check.
  update app_finance.network_transfers
    set amount_minor = v_amount,
      sender_source_account_id = v_account_id,
      currency_code = v_source.currency_code,
      requested_on = v_requested_on,
      shared_note = v_shared_note,
      amended_at = now(),
      amendment_count = amendment_count + 1
    where id = v_transfer.id
      and status = 'pending'
    returning amendment_count into v_count;

  v_alias := case
    when v_connection.user_a_id = v_transfer.receiver_user_id
      then v_connection.user_a_alias_for_b
    else v_connection.user_b_alias_for_a
  end;

  -- Called directly rather than through enqueue_network_notification: that
  -- helper keys dedupe on event_key:entity_id alone, so only the first
  -- amendment would ever reach the receiver. The amendment counter is what
  -- makes each change its own logical notification.
  perform app_private.create_notification(
    p_user_id := v_transfer.receiver_user_id,
    p_event_key := 'network.transfer_amended',
    p_dedupe_key := 'network.transfer_amended:' || v_transfer.id::text
      || ':' || v_count::text,
    p_payload := jsonb_build_object(
      'type', 'network_transfer_amended',
      'reminder_kind', 'network_transfer_amended',
      'counterparty_name', coalesce(v_alias, 'Network contact'),
      'amount_text', case
        when app_private.network_show_amounts(v_transfer.receiver_user_id)
          then v_source.currency_code || ' ' ||
            to_char(v_amount / 100.0, 'FM999,999,999,990.00')
        else null
      end
    ),
    p_entity_type := 'network_transfer',
    p_entity_id := v_transfer.id,
    p_route := '/money/network'
  );

  return v_transfer.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Accept — recreated to add the consent guard
-- ---------------------------------------------------------------------------

-- A function's argument list is part of its identity, so this is a drop and
-- recreate rather than a replace. Old two-argument PostgREST calls still
-- resolve because the third parameter has a default.
drop function if exists app_finance.accept_network_transfer(uuid, uuid);

-- The only path that may book cross-user ledger rows. Everything financial is
-- derived from locked server data: the client contributes nothing beyond the
-- transfer id and which of their own accounts receives the money.
--
-- p_expected_amount_minor is the receiver's consent token. Under READ
-- COMMITTED a blocked SELECT ... FOR UPDATE re-reads the committed row, so
-- without it a sender who amends while the receiver is looking at a stale card
-- would have the larger amount booked silently on tap.
create or replace function app_finance.accept_network_transfer(
  p_transfer_id uuid,
  p_destination_account_id uuid,
  p_expected_amount_minor bigint default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_transfer app_finance.network_transfers%rowtype;
  v_connection app_finance.network_connections%rowtype;
  v_source record;
  v_destination record;
  v_source_balance bigint;
  v_sender_alias_for_receiver text;
  v_receiver_alias_for_sender text;
  v_sender_tx_id uuid;
  v_receiver_tx_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_transfer
  from app_finance.network_transfers nt
  where nt.id = p_transfer_id
    and v_user_id in (nt.sender_user_id, nt.receiver_user_id)
  for update;
  if v_transfer is null then
    raise exception 'not_found: network transfer';
  end if;
  if v_transfer.receiver_user_id <> v_user_id then
    raise exception 'not_authorized: only the receiver can accept';
  end if;
  if v_transfer.status = 'accepted' then
    return v_transfer.id;
  end if;
  -- Ahead of the generic already_decided check so a withdrawn request says so.
  if v_transfer.status = 'cancelled' then
    raise exception 'transfer_cancelled: the sender cancelled this transfer';
  end if;
  if v_transfer.status <> 'pending' then
    raise exception 'already_decided: this transfer was already handled';
  end if;
  if p_expected_amount_minor is not null
    and p_expected_amount_minor <> v_transfer.amount_minor then
    raise exception 'transfer_changed: the sender changed this request';
  end if;

  if v_transfer.connection_id is null then
    raise exception
      'network_destination_unavailable: this transfer can no longer be accepted';
  end if;
  select * into v_connection
  from app_finance.network_connections c
  where c.id = v_transfer.connection_id
  for update;
  if v_connection is null or v_connection.removed_at is not null then
    raise exception
      'network_destination_unavailable: this transfer can no longer be accepted';
  end if;

  -- Lock the sender's source account. Any problem on the sender side maps to
  -- one generic error so the receiver learns nothing about the sender's
  -- accounts or balances.
  if v_transfer.sender_source_account_id is null then
    raise exception
      'transfer_unavailable: this transfer can no longer be accepted';
  end if;
  select a.id, a.currency_code, a.account_type, a.is_archived,
      a.allow_negative_balance
    into v_source
  from app_finance.accounts a
  where a.id = v_transfer.sender_source_account_id
    and a.user_id = v_transfer.sender_user_id
  for update;
  if v_source is null or v_source.is_archived
    or app_finance.account_role(v_source.account_type) <> 'asset'
    or v_source.currency_code <> v_transfer.currency_code then
    raise exception
      'transfer_unavailable: this transfer can no longer be accepted';
  end if;

  -- Revalidate sender funds now against the real balance. The pending hold is
  -- a display-side reservation only: it never blocked the sender from spending
  -- the money elsewhere, so acceptance is still the moment of truth.
  if not v_source.allow_negative_balance then
    select b.balance_minor into v_source_balance
    from app_finance.account_balances b
    where b.account_id = v_source.id;
    if coalesce(v_source_balance, 0) < v_transfer.amount_minor then
      raise exception
        'transfer_unavailable: this transfer can no longer be accepted';
    end if;
  end if;

  -- Lock and validate the receiver's own destination account.
  select a.id, a.currency_code, a.account_type, a.is_archived into v_destination
  from app_finance.accounts a
  where a.id = p_destination_account_id and a.user_id = v_user_id
  for update;
  if v_destination is null or v_destination.is_archived then
    raise exception 'invalid_account: destination not found or archived';
  end if;
  if app_finance.account_role(v_destination.account_type) <> 'asset' then
    raise exception 'invalid_account: destination must be an asset account';
  end if;
  if v_destination.currency_code <> v_transfer.currency_code then
    raise exception 'currency_mismatch: pick an account in the transfer currency';
  end if;

  v_sender_alias_for_receiver := case
    when v_connection.user_a_id = v_transfer.sender_user_id
      then v_connection.user_a_alias_for_b
    else v_connection.user_b_alias_for_a
  end;
  v_receiver_alias_for_sender := case
    when v_connection.user_a_id = v_transfer.receiver_user_id
      then v_connection.user_a_alias_for_b
    else v_connection.user_b_alias_for_a
  end;

  perform set_config('app_finance.network_internal', 'on', true);

  begin
    -- Sender leg: source only. Decreases the sender exactly once; the
    -- balance trigger re-checks the sender's negative-balance policy.
    insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      source_account_id, counterparty, title, notes,
      is_network_transfer, network_transfer_id
    ) values (
      v_transfer.sender_user_id, 'transfer', current_date,
      v_transfer.amount_minor, v_transfer.currency_code,
      v_transfer.sender_source_account_id,
      v_sender_alias_for_receiver, 'Network transfer',
      v_transfer.shared_note, true, v_transfer.id
    )
    returning id into v_sender_tx_id;

    -- Receiver leg: destination only. Increases the receiver exactly once.
    insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      destination_account_id, counterparty, title, notes,
      is_network_transfer, network_transfer_id
    ) values (
      v_transfer.receiver_user_id, 'transfer', current_date,
      v_transfer.amount_minor, v_transfer.currency_code,
      p_destination_account_id,
      v_receiver_alias_for_sender, 'Network transfer',
      v_transfer.shared_note, true, v_transfer.id
    )
    returning id into v_receiver_tx_id;
  exception when others then
    -- The balance trigger's message names the sender's account; never let
    -- that reach the receiver.
    if sqlerrm like 'insufficient_funds%'
      or sqlerrm like 'account_archived%' then
      raise exception
        'transfer_unavailable: this transfer can no longer be accepted';
    end if;
    raise;
  end;

  update app_finance.network_transfers
    set status = 'accepted',
      responded_at = now(),
      receiver_destination_account_id = p_destination_account_id,
      sender_transaction_id = v_sender_tx_id,
      receiver_transaction_id = v_receiver_tx_id
    where id = v_transfer.id;

  perform set_config('app_finance.network_internal', '', true);

  perform app_private.enqueue_network_notification(
    v_transfer.sender_user_id, 'network_transfer', v_transfer.id,
    'network_transfer_accepted',
    jsonb_build_object(
      'type', 'network_transfer_accepted',
      'reminder_kind', 'network_transfer_accepted',
      'counterparty_name', v_sender_alias_for_receiver,
      'amount_text', case
        when app_private.network_show_amounts(v_transfer.sender_user_id)
          then v_transfer.currency_code || ' ' ||
            to_char(v_transfer.amount_minor / 100.0,
              'FM999,999,999,990.00')
        else null
      end
    )
  );

  return v_transfer.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Reject — signature unchanged, cancelled branch added
-- ---------------------------------------------------------------------------

create or replace function app_finance.reject_network_transfer(
  p_transfer_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_transfer app_finance.network_transfers%rowtype;
  v_alias text;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_transfer
  from app_finance.network_transfers nt
  where nt.id = p_transfer_id
    and v_user_id in (nt.sender_user_id, nt.receiver_user_id)
  for update;
  if v_transfer is null then
    raise exception 'not_found: network transfer';
  end if;
  if v_transfer.receiver_user_id <> v_user_id then
    raise exception 'not_authorized: only the receiver can reject';
  end if;
  if v_transfer.status = 'cancelled' then
    raise exception 'transfer_cancelled: the sender cancelled this transfer';
  end if;
  if v_transfer.status <> 'pending' then
    raise exception 'already_decided: this transfer was already handled';
  end if;

  -- Rejection books nothing and is allowed even after the connection was
  -- removed: it only closes the shared request object.
  update app_finance.network_transfers
    set status = 'rejected', responded_at = now()
    where id = v_transfer.id;

  select case
      when c.user_a_id = v_transfer.sender_user_id then c.user_a_alias_for_b
      else c.user_b_alias_for_a
    end into v_alias
  from app_finance.network_connections c
  where c.id = v_transfer.connection_id;

  perform app_private.enqueue_network_notification(
    v_transfer.sender_user_id, 'network_transfer', v_transfer.id,
    'network_transfer_rejected',
    jsonb_build_object(
      'type', 'network_transfer_rejected',
      'reminder_kind', 'network_transfer_rejected',
      'counterparty_name', coalesce(v_alias, 'Network contact')
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- List — recreated to carry the new state
-- ---------------------------------------------------------------------------

-- A function's OUT list is part of its return type, so appending columns needs
-- a drop rather than a replace.
drop function if exists app_finance.list_network_transfers();

-- Direction-aware projection of the caller's transfers. Each side sees the
-- shared facts (amount, currency, dates, status, note, counterparty alias)
-- plus only their own account: the sender never learns the receiver's
-- destination and the receiver never learns the sender's source.
--
-- can_amend is derived here rather than in the client so the eligibility rule
-- lives beside the RPCs that enforce it. It gates both actions: today cancel
-- and amend share one predicate.
create or replace function app_finance.list_network_transfers()
returns table (
  transfer_id uuid,
  connection_id uuid,
  direction text,
  counterparty_alias text,
  amount_minor bigint,
  currency_code text,
  status app_finance.network_transfer_status,
  requested_on date,
  requested_at timestamptz,
  responded_at timestamptz,
  shared_note text,
  origin_kind app_finance.network_transfer_origin,
  my_account_id uuid,
  my_transaction_id uuid,
  connection_active boolean,
  cancelled_at timestamptz,
  amendment_count integer,
  can_amend boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    nt.id,
    nt.connection_id,
    case when nt.sender_user_id = (select auth.uid())
      then 'sent' else 'received' end,
    coalesce(case
      when c.id is null then null
      when c.user_a_id = (select auth.uid()) then c.user_a_alias_for_b
      else c.user_b_alias_for_a
    end, ''),
    nt.amount_minor,
    nt.currency_code,
    nt.status,
    nt.requested_on,
    nt.requested_at,
    nt.responded_at,
    nt.shared_note,
    nt.origin_kind,
    case when nt.sender_user_id = (select auth.uid())
      then nt.sender_source_account_id
      else nt.receiver_destination_account_id end,
    case when nt.sender_user_id = (select auth.uid())
      then nt.sender_transaction_id
      else nt.receiver_transaction_id end,
    (c.id is not null and c.removed_at is null),
    nt.cancelled_at,
    nt.amendment_count,
    (nt.sender_user_id = (select auth.uid())
      and nt.status = 'pending'
      and c.id is not null and c.removed_at is null)
  from app_finance.network_transfers nt
  left join app_finance.network_connections c on c.id = nt.connection_id
  where (select auth.uid()) is not null
    and (select auth.uid()) in (nt.sender_user_id, nt.receiver_user_id)
  order by nt.requested_at desc, nt.id desc;
$$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

-- Every drop above took its grants with it; re-issue them or the RPC 403s.

revoke execute on function app_finance.cancel_network_transfer(uuid)
  from public, anon;
grant execute on function app_finance.cancel_network_transfer(uuid)
  to authenticated, service_role;

revoke execute on function app_finance.amend_network_transfer(
  uuid, bigint, uuid, date, text, boolean
) from public, anon;
grant execute on function app_finance.amend_network_transfer(
  uuid, bigint, uuid, date, text, boolean
) to authenticated, service_role;

revoke execute on function app_finance.accept_network_transfer(
  uuid, uuid, bigint
) from public, anon;
grant execute on function app_finance.accept_network_transfer(
  uuid, uuid, bigint
) to authenticated, service_role;

revoke execute on function app_finance.reject_network_transfer(uuid)
  from public, anon;
grant execute on function app_finance.reject_network_transfer(uuid)
  to authenticated, service_role;

revoke execute on function app_finance.list_network_transfers()
  from public, anon;
grant execute on function app_finance.list_network_transfers()
  to authenticated, service_role;

notify pgrst, 'reload schema';
