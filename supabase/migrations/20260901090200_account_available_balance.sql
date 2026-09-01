-- Available balance: what an account actually has left to spend.
--
-- Two things already commit money without booking it. A pending network
-- transfer is money the sender has promised and will hand over the moment the
-- receiver taps accept. An unsettled held amount is money the user has already
-- earmarked. Neither writes a ledger row — by design, since
-- app_finance.accept_network_transfer must stay the only path that books a
-- network transfer — so both were invisible in the balance, and the Accounts
-- tab happily showed money that was already spoken for.
--
-- This migration derives the reservation instead of booking it, and surfaces
-- it per account.

-- ---------------------------------------------------------------------------
-- Hold totals — deliberately NOT security_invoker
-- ---------------------------------------------------------------------------

-- app_finance.network_transfers is revoke-all plus an explicit column grant
-- (20260823090000) that withholds sender_source_account_id from
-- `authenticated`; supabase/tests/0043 asserts it. app_finance.account_balances
-- is security_invoker, and app_private.enforce_account_balance — which is NOT
-- security definer — selects from that view on every single transaction
-- insert. Computing this aggregate inline there would therefore raise 42501
-- for every authenticated caller and break every financial write in the app.
--
-- So this view runs in owner context on purpose. Safety here is structural
-- rather than privilege-based:
--   * the WHERE clause pins every row to the caller's own accounts;
--   * the composite foreign keys network_transfers_sender_source_owner_fk and
--     held_amounts_account_owner_fk guarantee a hold recorded against account X
--     can only ever belong to X's owner, so nothing another user controls can
--     appear in your totals;
--   * a null auth.uid() (service_role, pgTAP running as postgres) sees
--     everything, matching app_private.protect_network_transactions.
--
-- Correlated scalar subqueries, not a grouped LEFT JOIN: a subquery with GROUP
-- BY is an optimisation fence for the join qualification, so it would
-- aggregate every user's rows on every read. Correlated form pushes the
-- account predicate down into the partial indexes.
create or replace view app_finance.account_hold_totals as
  select
    a.id as account_id,
    a.user_id,
    (select coalesce(sum(nt.amount_minor), 0)::bigint
       from app_finance.network_transfers nt
      where nt.sender_source_account_id = a.id
        and nt.sender_user_id = a.user_id
        and nt.status = 'pending') as pending_transfer_hold_minor,
    (select coalesce(sum(h.amount_minor), 0)::bigint
       from app_finance.held_amounts h
      where h.account_id = a.id
        and h.user_id = a.user_id
        and h.settled_on is null
        and h.direction = 'i_owe') as held_outgoing_minor,
    (select coalesce(sum(h.amount_minor), 0)::bigint
       from app_finance.held_amounts h
      where h.account_id = a.id
        and h.user_id = a.user_id
        and h.settled_on is null
        and h.direction = 'owed_to_me') as held_incoming_minor
  from app_finance.accounts a
  where (select auth.uid()) is null or a.user_id = (select auth.uid());

revoke all on table app_finance.account_hold_totals from public, anon;
grant select on table app_finance.account_hold_totals
  to authenticated, service_role;

create index if not exists idx_held_amounts_active_account
  on app_finance.held_amounts (account_id, direction)
  where settled_on is null and account_id is not null;

-- ---------------------------------------------------------------------------
-- account_balances
-- ---------------------------------------------------------------------------

-- Appending columns keeps every existing reader of the view valid; the
-- existing column list is reproduced unchanged (42P16 forbids inserting
-- mid-view). All six SQL consumers select balance_minor by name, and the
-- Flutter repository selects star, so the only client-side change is
-- AccountBalance.fromJson learning the new names.
--
-- Direction policy:
--   * pending outgoing transfers and i_owe holds REDUCE availability. That
--     money is committed; treating it as spendable is the exact failure this
--     view exists to prevent.
--   * owed_to_me holds do NOT increase it. The cash is not in the account, and
--     settling an owed_to_me hold books a destination transaction — counting
--     it now would double-count it later. It is reported separately as an
--     expectation, never folded into the available figure.
--   * balance_minor keeps its exact current meaning.
--     app_private.enforce_account_balance and
--     app_finance.accept_network_transfer continue to gate on it, never on
--     available_balance_minor: reserving is not the same as spending, and
--     available is explicitly allowed to go negative.
create or replace view app_finance.account_balances
with (security_invoker = on) as
  select
    a.id as account_id,
    a.user_id,
    a.name,
    a.account_type,
    a.currency_code,
    a.is_default,
    a.is_archived,
    a.allow_negative_balance,
    a.opening_balance_minor,
    (a.opening_balance_minor + coalesce(f.net, 0))::bigint as balance_minor,
    coalesce(f.total_in, 0)::bigint as total_incoming_minor,
    coalesce(f.total_out, 0)::bigint as total_outgoing_minor,
    a.hide_from_home,
    coalesce(hold.pending_transfer_hold_minor, 0)::bigint
      as pending_transfer_hold_minor,
    coalesce(hold.held_outgoing_minor, 0)::bigint as held_outgoing_minor,
    coalesce(hold.held_incoming_minor, 0)::bigint as held_incoming_minor,
    (coalesce(hold.pending_transfer_hold_minor, 0)
      + coalesce(hold.held_outgoing_minor, 0))::bigint as reserved_minor,
    (a.opening_balance_minor + coalesce(f.net, 0)
      - coalesce(hold.pending_transfer_hold_minor, 0)
      - coalesce(hold.held_outgoing_minor, 0))::bigint
      as available_balance_minor
  from app_finance.accounts a
  left join (
    select
      account_id,
      sum(signed_amount_minor) as net,
      sum(signed_amount_minor) filter (where signed_amount_minor > 0) as total_in,
      -sum(signed_amount_minor) filter (where signed_amount_minor < 0) as total_out
    from app_finance.account_flows
    group by account_id
  ) f on f.account_id = a.id
  left join app_finance.account_hold_totals hold on hold.account_id = a.id;

notify pgrst, 'reload schema';
