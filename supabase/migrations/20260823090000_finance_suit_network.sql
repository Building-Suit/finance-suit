-- Finance Suit Network: connect users, keep private directional aliases, and
-- record mutually acknowledged transfers between them.
--
-- A network contact is a private transfer destination identity, NOT remote
-- account access. Connecting two users changes nothing about the RLS on
-- accounts, balances, transactions, income, salary, or facilities. The only
-- shared state lives in the three tables below plus narrow RPC results.
--
-- Money model: a network transfer starts as a shared 'pending' request with
-- zero ledger impact on either side. Rejection also books nothing. Acceptance
-- atomically creates exactly two user-local ledger rows — a source-only
-- transfer on the sender and a destination-only transfer on the receiver —
-- through the acceptance RPC, and only through it. This is a ledger/network
-- record inside Finance Suit, not a real banking or payment rail.

-- ---------------------------------------------------------------------------
-- Enums (fresh types, so same-transaction use is safe)
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'network_add_request_status') then
    create type app_finance.network_add_request_status as enum
      ('pending', 'accepted', 'rejected');
  end if;
  if not exists (select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'network_transfer_status') then
    create type app_finance.network_transfer_status as enum
      ('pending', 'rejected', 'accepted');
  end if;
  if not exists (select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'network_transfer_origin') then
    create type app_finance.network_transfer_origin as enum
      ('manual', 'recurring_rule', 'income_allocation',
       'extra_work_allocation', 'rollover_allocation');
  end if;
end $$;

grant usage on type app_finance.network_add_request_status
to authenticated, service_role;
grant usage on type app_finance.network_transfer_status
to authenticated, service_role;
grant usage on type app_finance.network_transfer_origin
to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Add requests
-- ---------------------------------------------------------------------------

-- The requester's alias is private to the requester: the recipient sees the
-- requester's real profile name and email, never the alias chosen for them.
create table if not exists app_finance.network_add_requests (
  id uuid primary key default gen_random_uuid(),
  requester_user_id uuid not null references auth.users (id) on delete cascade,
  recipient_user_id uuid not null references auth.users (id) on delete cascade,
  requester_alias_for_recipient text not null
    check (char_length(requester_alias_for_recipient) between 1 and 80),
  status app_finance.network_add_request_status not null default 'pending',
  requested_at timestamptz not null default now(),
  responded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint network_add_requests_no_self
    check (requester_user_id <> recipient_user_id),
  constraint network_add_requests_response_shape check (
    (status = 'pending' and responded_at is null)
    or (status <> 'pending' and responded_at is not null)
  )
);

drop trigger if exists trg_network_add_requests_updated_at
  on app_finance.network_add_requests;
create trigger trg_network_add_requests_updated_at
  before update on app_finance.network_add_requests
  for each row execute function app_private.set_updated_at();

-- One pending request per unordered user pair: while A -> B is pending,
-- B -> A must respond to the existing request instead of creating another.
create unique index if not exists idx_network_add_requests_pending_pair
  on app_finance.network_add_requests (
    least(requester_user_id, recipient_user_id),
    greatest(requester_user_id, recipient_user_id))
  where status = 'pending';

create index if not exists idx_network_add_requests_recipient
  on app_finance.network_add_requests (recipient_user_id, status, requested_at desc);
create index if not exists idx_network_add_requests_requester
  on app_finance.network_add_requests (requester_user_id, status, requested_at desc);

-- ---------------------------------------------------------------------------
-- Connections
-- ---------------------------------------------------------------------------

-- The pair is normalized (user_a_id < user_b_id) so one active connection per
-- pair is a simple partial unique index. Aliases are directional and private:
-- user_a_alias_for_b is what A calls B, user_b_alias_for_a is what B calls A.
-- Neither column is selectable by clients (see column grants below); the
-- direction is resolved server-side in list_network_contacts.
create table if not exists app_finance.network_connections (
  id uuid primary key default gen_random_uuid(),
  user_a_id uuid not null references auth.users (id) on delete cascade,
  user_b_id uuid not null references auth.users (id) on delete cascade,
  user_a_alias_for_b text not null
    check (char_length(user_a_alias_for_b) between 1 and 80),
  user_b_alias_for_a text not null
    check (char_length(user_b_alias_for_a) between 1 and 80),
  accepted_request_id uuid
    references app_finance.network_add_requests (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  removed_at timestamptz,
  constraint network_connections_ordered_pair check (user_a_id < user_b_id)
);

drop trigger if exists trg_network_connections_updated_at
  on app_finance.network_connections;
create trigger trg_network_connections_updated_at
  before update on app_finance.network_connections
  for each row execute function app_private.set_updated_at();

create unique index if not exists idx_network_connections_active_pair
  on app_finance.network_connections (user_a_id, user_b_id)
  where removed_at is null;

create index if not exists idx_network_connections_user_a
  on app_finance.network_connections (user_a_id) where removed_at is null;
create index if not exists idx_network_connections_user_b
  on app_finance.network_connections (user_b_id) where removed_at is null;

-- ---------------------------------------------------------------------------
-- Network transfers
-- ---------------------------------------------------------------------------

-- Pending and rejected transfers are only shared request objects: no
-- financial_transactions rows exist for them and no balance moves. Account
-- and transaction links stay nullable in every state so account/user deletion
-- cascades can detach them without rewriting history (same convention as
-- recurring_occurrences.transaction_id).
create table if not exists app_finance.network_transfers (
  id uuid primary key default gen_random_uuid(),
  connection_id uuid
    references app_finance.network_connections (id) on delete set null,
  sender_user_id uuid not null references auth.users (id) on delete cascade,
  receiver_user_id uuid not null references auth.users (id) on delete cascade,
  sender_source_account_id uuid,
  receiver_destination_account_id uuid,
  amount_minor bigint not null check (amount_minor > 0),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  status app_finance.network_transfer_status not null default 'pending',
  requested_on date not null,
  requested_at timestamptz not null default now(),
  responded_at timestamptz,
  sender_transaction_id uuid
    references app_finance.financial_transactions (id) on delete set null,
  receiver_transaction_id uuid
    references app_finance.financial_transactions (id) on delete set null,
  origin_kind app_finance.network_transfer_origin not null default 'manual',
  origin_id uuid,
  idempotency_key text check (char_length(idempotency_key) between 1 and 120),
  shared_note text check (char_length(shared_note) <= 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint network_transfers_no_self
    check (sender_user_id <> receiver_user_id),
  constraint network_transfers_sender_source_owner_fk
    foreign key (sender_source_account_id, sender_user_id)
    references app_finance.accounts (id, user_id)
    on delete set null (sender_source_account_id),
  constraint network_transfers_receiver_destination_owner_fk
    foreign key (receiver_destination_account_id, receiver_user_id)
    references app_finance.accounts (id, user_id)
    on delete set null (receiver_destination_account_id),
  constraint network_transfers_state_fields check (
    (status = 'pending' and responded_at is null
      and sender_transaction_id is null
      and receiver_transaction_id is null
      and receiver_destination_account_id is null)
    or (status = 'rejected' and responded_at is not null
      and sender_transaction_id is null
      and receiver_transaction_id is null)
    or (status = 'accepted' and responded_at is not null)
  ),
  constraint network_transfers_origin_shape check (
    origin_kind = 'manual'
    or (origin_id is not null and idempotency_key is not null)
  )
);

drop trigger if exists trg_network_transfers_updated_at
  on app_finance.network_transfers;
create trigger trg_network_transfers_updated_at
  before update on app_finance.network_transfers
  for each row execute function app_private.set_updated_at();

-- Automation retries must not create duplicate transfer requests.
create unique index if not exists idx_network_transfers_idempotency
  on app_finance.network_transfers (sender_user_id, idempotency_key)
  where idempotency_key is not null;

-- Exactly one shared transfer per ledger row.
create unique index if not exists idx_network_transfers_sender_tx
  on app_finance.network_transfers (sender_transaction_id)
  where sender_transaction_id is not null;
create unique index if not exists idx_network_transfers_receiver_tx
  on app_finance.network_transfers (receiver_transaction_id)
  where receiver_transaction_id is not null;

create index if not exists idx_network_transfers_sender
  on app_finance.network_transfers
  (sender_user_id, status, requested_on desc, id desc);
create index if not exists idx_network_transfers_receiver
  on app_finance.network_transfers
  (receiver_user_id, status, requested_on desc, id desc);
create index if not exists idx_network_transfers_connection
  on app_finance.network_transfers (connection_id)
  where connection_id is not null;
create index if not exists idx_network_transfers_origin
  on app_finance.network_transfers (origin_kind, origin_id)
  where origin_id is not null;

-- ---------------------------------------------------------------------------
-- Ledger integration
-- ---------------------------------------------------------------------------

-- An accepted network transfer books as two one-sided 'transfer' rows: the
-- sender's row has only a source account, the receiver's row has only a
-- destination account. is_network_transfer is the structural marker (it can
-- never be nulled by a cascade), network_transfer_id links back to the shared
-- record for display and may be detached when the peer's data is deleted.
alter table app_finance.financial_transactions
  add column if not exists is_network_transfer boolean not null default false,
  add column if not exists network_transfer_id uuid;

alter table app_finance.financial_transactions
  drop constraint if exists tx_network_transfer_fk,
  add constraint tx_network_transfer_fk
    foreign key (network_transfer_id)
    references app_finance.network_transfers (id)
    on delete set null;

create index if not exists idx_tx_network_transfer
  on app_finance.financial_transactions (network_transfer_id)
  where network_transfer_id is not null;

alter table app_finance.financial_transactions
  drop constraint if exists tx_network_link_shape,
  add constraint tx_network_link_shape check (
    is_network_transfer or network_transfer_id is null
  );

-- Transfers stay two-sided between own accounts, except network legs which
-- are one-sided by design (the other side lives in the other user's ledger).
alter table app_finance.financial_transactions
  drop constraint if exists tx_direction_by_kind,
  add constraint tx_direction_by_kind check (
    (transaction_kind in ('expense', 'allowance_given')
      and not is_network_transfer
      and source_account_id is not null
      and destination_account_id is null)
    or
    (transaction_kind in ('custom_income', 'freelance_income', 'salary_income')
      and not is_network_transfer
      and destination_account_id is not null
      and source_account_id is null)
    or
    (transaction_kind = 'transfer'
      and not is_network_transfer
      and source_account_id is not null
      and destination_account_id is not null
      and source_account_id <> destination_account_id)
    or
    (transaction_kind = 'transfer'
      and is_network_transfer
      and ((source_account_id is not null and destination_account_id is null)
        or (destination_account_id is not null and source_account_id is null)))
  );

-- Only the network transfer RPCs may create network ledger rows, and booked
-- rows are immutable for the generic editors: one user's ledger must never
-- diverge from the other's. The trusted RPCs mark themselves with a
-- transaction-local flag; service-role and admin sessions (no JWT subject)
-- stay unrestricted so account deletion and support tooling work.
create or replace function app_private.protect_network_transactions()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if coalesce(current_setting('app_finance.network_internal', true), '')
      = 'on'
    or (select auth.uid()) is null then
    return coalesce(new, old);
  end if;

  if tg_op = 'INSERT' then
    if new.is_network_transfer or new.network_transfer_id is not null then
      raise exception
        'network_transaction_locked: network transfers are created by acceptance only';
    end if;
  else
    if old.is_network_transfer or old.network_transfer_id is not null then
      raise exception
        'network_transaction_locked: accepted network transfers cannot be edited';
    end if;
    if tg_op = 'UPDATE'
      and (new.is_network_transfer or new.network_transfer_id is not null) then
      raise exception
        'network_transaction_locked: network transfers are created by acceptance only';
    end if;
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_protect_network_transactions
  on app_finance.financial_transactions;
create trigger trg_protect_network_transactions
  before insert or update or delete on app_finance.financial_transactions
  for each row execute function app_private.protect_network_transactions();

revoke execute on function app_private.protect_network_transactions()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Row level security and privilege surface
-- ---------------------------------------------------------------------------

alter table app_finance.network_add_requests enable row level security;
alter table app_finance.network_connections enable row level security;
alter table app_finance.network_transfers enable row level security;

drop policy if exists network_add_requests_select
  on app_finance.network_add_requests;
create policy network_add_requests_select on app_finance.network_add_requests
  for select to authenticated
  using ((select auth.uid()) in (requester_user_id, recipient_user_id));

drop policy if exists network_connections_select
  on app_finance.network_connections;
create policy network_connections_select on app_finance.network_connections
  for select to authenticated
  using ((select auth.uid()) in (user_a_id, user_b_id));

drop policy if exists network_transfers_select
  on app_finance.network_transfers;
create policy network_transfers_select on app_finance.network_transfers
  for select to authenticated
  using ((select auth.uid()) in (sender_user_id, receiver_user_id));

-- All writes go through the RPCs below; clients never mutate rows directly.
-- Column-level select keeps each side's private fields private even between
-- the two connected parties: aliases resolve only through
-- list_network_contacts, and neither party can read the other's account or
-- transaction ids off a transfer row.
revoke all on table app_finance.network_add_requests from authenticated;
grant select (id, requester_user_id, recipient_user_id, status,
  requested_at, responded_at, created_at, updated_at)
  on app_finance.network_add_requests to authenticated;

revoke all on table app_finance.network_connections from authenticated;
grant select (id, user_a_id, user_b_id, accepted_request_id,
  created_at, updated_at, removed_at)
  on app_finance.network_connections to authenticated;

revoke all on table app_finance.network_transfers from authenticated;
grant select (id, connection_id, sender_user_id, receiver_user_id,
  amount_minor, currency_code, status, requested_on, requested_at,
  responded_at, origin_kind, origin_id, idempotency_key, shared_note,
  created_at, updated_at)
  on app_finance.network_transfers to authenticated;

grant select, insert, update, delete on
  app_finance.network_add_requests,
  app_finance.network_connections,
  app_finance.network_transfers
to service_role;

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

-- Escape a raw search string for use inside a like/ilike pattern.
create or replace function app_private.escape_like(p_text text)
returns text
language sql
immutable
set search_path = ''
as $$
  select replace(replace(replace(p_text, '\', '\\'), '%', '\%'), '_', '\_');
$$;

revoke execute on function app_private.escape_like(text)
  from public, anon, authenticated;

-- Queue a push notification for every enabled device of the target user.
-- Amounts are included only when the recipient opted in (show_amounts).
-- Safe to call repeatedly: the outbox unique key makes each notification
-- exactly-once per device, obligation, kind, and local date.
create or replace function app_private.enqueue_network_notification(
  p_user_id uuid,
  p_obligation_type text,
  p_obligation_id uuid,
  p_reminder_kind text,
  p_payload jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_device record;
begin
  for v_device in
    select d.id, d.timezone
    from app_core.push_devices d
    where d.user_id = p_user_id and d.is_enabled
  loop
    insert into app_core.notification_outbox (
      user_id, device_id, obligation_type, obligation_id, reminder_kind,
      scheduled_local_date, payload_snapshot
    ) values (
      p_user_id, v_device.id, p_obligation_type, p_obligation_id,
      p_reminder_kind,
      (now() at time zone coalesce(v_device.timezone, 'Africa/Cairo'))::date,
      p_payload
    )
    on conflict on constraint notification_outbox_idempotent do nothing;
  end loop;
end;
$$;

revoke execute on function app_private.enqueue_network_notification(
  uuid, text, uuid, text, jsonb
) from public, anon, authenticated;

-- Whether the recipient wants amounts inside push payloads.
create or replace function app_private.network_show_amounts(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select p.show_amounts from app_core.notification_preferences p
    where p.user_id = p_user_id
  ), false);
$$;

revoke execute on function app_private.network_show_amounts(uuid)
  from public, anon, authenticated;

-- Trusted internal creation path shared by the manual RPC and the automation
-- acceptance paths (recurring rules, income allocations, extra-work routing).
-- Inserts only a pending request object: no ledger rows, no balance impact.
-- SECURITY DEFINER because invoker-context automation RPCs must reach the
-- connection row and the outbox; an authenticated caller can only ever create
-- transfers for their own user id.
create or replace function app_private.create_network_transfer(
  p_sender_user_id uuid,
  p_connection_id uuid,
  p_source_account_id uuid,
  p_amount_minor bigint,
  p_requested_on date,
  p_shared_note text,
  p_origin_kind app_finance.network_transfer_origin,
  p_origin_id uuid,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_connection app_finance.network_connections%rowtype;
  v_receiver_user_id uuid;
  v_source record;
  v_transfer_id uuid;
begin
  if (select auth.uid()) is not null
      and (select auth.uid()) <> p_sender_user_id then
    raise exception 'not_authorized: sender mismatch';
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'invalid_amount: must be positive';
  end if;

  if p_idempotency_key is not null then
    select nt.id into v_transfer_id
    from app_finance.network_transfers nt
    where nt.sender_user_id = p_sender_user_id
      and nt.idempotency_key = p_idempotency_key;
    if v_transfer_id is not null then
      return v_transfer_id;
    end if;
  end if;

  select * into v_connection
  from app_finance.network_connections c
  where c.id = p_connection_id
    and p_sender_user_id in (c.user_a_id, c.user_b_id);
  if v_connection is null then
    raise exception 'not_found: network connection';
  end if;
  if v_connection.removed_at is not null then
    raise exception
      'network_destination_unavailable: this contact was removed from your network';
  end if;

  v_receiver_user_id := case
    when v_connection.user_a_id = p_sender_user_id then v_connection.user_b_id
    else v_connection.user_a_id
  end;

  -- The sender moves their own cash: owned, active, asset accounts only.
  select a.id, a.currency_code, a.account_type into v_source
  from app_finance.accounts a
  where a.id = p_source_account_id
    and a.user_id = p_sender_user_id
    and not a.is_archived;
  if v_source is null then
    raise exception 'invalid_account: source not found or archived';
  end if;
  if app_finance.account_role(v_source.account_type) <> 'asset' then
    raise exception 'invalid_account: network transfers move your own cash';
  end if;

  insert into app_finance.network_transfers (
    connection_id, sender_user_id, receiver_user_id,
    sender_source_account_id, amount_minor, currency_code,
    requested_on, origin_kind, origin_id, idempotency_key, shared_note
  ) values (
    p_connection_id, p_sender_user_id, v_receiver_user_id,
    p_source_account_id, p_amount_minor, v_source.currency_code,
    p_requested_on, p_origin_kind, p_origin_id, p_idempotency_key,
    nullif(btrim(coalesce(p_shared_note, '')), '')
  )
  on conflict (sender_user_id, idempotency_key)
    where idempotency_key is not null
  do nothing
  returning id into v_transfer_id;

  if v_transfer_id is null then
    select nt.id into v_transfer_id
    from app_finance.network_transfers nt
    where nt.sender_user_id = p_sender_user_id
      and nt.idempotency_key = p_idempotency_key;
    return v_transfer_id;
  end if;

  perform app_private.enqueue_network_notification(
    v_receiver_user_id, 'network_transfer', v_transfer_id,
    'network_transfer_pending',
    jsonb_build_object(
      'type', 'network_transfer_pending',
      'reminder_kind', 'network_transfer_pending',
      'counterparty_name', case
        when v_connection.user_a_id = v_receiver_user_id
          then v_connection.user_a_alias_for_b
        else v_connection.user_b_alias_for_a
      end,
      'amount_text', case
        when app_private.network_show_amounts(v_receiver_user_id)
          then v_source.currency_code || ' ' ||
            to_char(p_amount_minor / 100.0, 'FM999,999,999,990.00')
        else null
      end
    )
  );

  return v_transfer_id;
end;
$$;

-- Executable by authenticated because the recurring/income acceptance RPCs
-- run as the caller; the auth.uid() guard above pins the sender identity.
revoke execute on function app_private.create_network_transfer(
  uuid, uuid, uuid, bigint, date, text,
  app_finance.network_transfer_origin, uuid, text
) from public, anon;
grant execute on function app_private.create_network_transfer(
  uuid, uuid, uuid, bigint, date, text,
  app_finance.network_transfer_origin, uuid, text
) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- User discovery
-- ---------------------------------------------------------------------------

-- Narrow, authenticated-only search. Name queries need three characters and
-- do a bounded case-insensitive substring match on the profile display name;
-- queries containing '@' are an exact case-insensitive email lookup so the
-- endpoint cannot be used for broad email enumeration. Results carry only
-- identity plus the relationship state — never accounts, balances, or
-- transactions. SECURITY DEFINER because emails live in auth.users, which is
-- never exposed to clients directly.
create or replace function app_finance.search_network_users(p_query text)
returns table (
  target_user_id uuid,
  display_name text,
  email text,
  relationship_state text,
  request_direction text,
  request_id uuid
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_query text := btrim(coalesce(p_query, ''));
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if position('@' in v_query) > 0 then
    return query
    select * from app_private.network_user_results(
      v_user_id,
      (select array_agg(u.id) from auth.users u
        where lower(u.email) = lower(v_query) and u.id <> v_user_id)
    );
    return;
  end if;

  if char_length(v_query) < 3 then
    return;
  end if;

  return query
  select * from app_private.network_user_results(
    v_user_id,
    (select array_agg(matched.id) from (
      select p.id
      from app_core.profiles p
      where p.id <> v_user_id
        and p.display_name ilike
          '%' || app_private.escape_like(v_query) || '%'
      order by lower(p.display_name), p.id
      limit 20
    ) matched)
  );
end;
$$;

-- Shared projection for search results: identity + relationship state.
create or replace function app_private.network_user_results(
  p_viewer_user_id uuid,
  p_user_ids uuid[]
)
returns table (
  target_user_id uuid,
  display_name text,
  email text,
  relationship_state text,
  request_direction text,
  request_id uuid
)
language sql
stable
set search_path = ''
as $$
  select
    p.id,
    p.display_name,
    coalesce(u.email, ''),
    case
      when c.id is not null then 'connected'
      when r.requester_user_id = p_viewer_user_id then 'outgoing_pending'
      when r.recipient_user_id = p_viewer_user_id then 'incoming_pending'
      else 'none'
    end,
    case
      when c.id is not null then null
      when r.requester_user_id = p_viewer_user_id then 'outgoing'
      when r.recipient_user_id = p_viewer_user_id then 'incoming'
      else null
    end,
    case when c.id is null then r.id end
  from app_core.profiles p
  join auth.users u on u.id = p.id
  left join lateral (
    select c.id from app_finance.network_connections c
    where c.removed_at is null
      and least(c.user_a_id, c.user_b_id)
        = least(p_viewer_user_id, p.id)
      and greatest(c.user_a_id, c.user_b_id)
        = greatest(p_viewer_user_id, p.id)
    limit 1
  ) c on true
  left join lateral (
    select r.id, r.requester_user_id, r.recipient_user_id
    from app_finance.network_add_requests r
    where r.status = 'pending'
      and least(r.requester_user_id, r.recipient_user_id)
        = least(p_viewer_user_id, p.id)
      and greatest(r.requester_user_id, r.recipient_user_id)
        = greatest(p_viewer_user_id, p.id)
    limit 1
  ) r on true
  where p.id = any (coalesce(p_user_ids, array[]::uuid[]))
  order by lower(p.display_name), p.id
  limit 20;
$$;

revoke execute on function app_private.network_user_results(uuid, uuid[])
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Add request lifecycle
-- ---------------------------------------------------------------------------

create or replace function app_finance.send_network_add_request(
  p_target_user_id uuid,
  p_local_alias text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_alias text := btrim(coalesce(p_local_alias, ''));
  v_display_name text;
  v_request_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if char_length(v_alias) < 1 or char_length(v_alias) > 80 then
    raise exception 'invalid_alias: choose a name between 1 and 80 characters';
  end if;
  if p_target_user_id is null or p_target_user_id = v_user_id then
    raise exception 'invalid_target: you cannot add yourself';
  end if;
  if not exists (
    select 1 from app_core.profiles p where p.id = p_target_user_id
  ) then
    raise exception 'not_found: user';
  end if;

  if exists (
    select 1 from app_finance.network_connections c
    where c.removed_at is null
      and least(c.user_a_id, c.user_b_id)
        = least(v_user_id, p_target_user_id)
      and greatest(c.user_a_id, c.user_b_id)
        = greatest(v_user_id, p_target_user_id)
  ) then
    raise exception 'already_connected: this person is already in your network';
  end if;

  select r.id into v_request_id
  from app_finance.network_add_requests r
  where r.status = 'pending'
    and least(r.requester_user_id, r.recipient_user_id)
      = least(v_user_id, p_target_user_id)
    and greatest(r.requester_user_id, r.recipient_user_id)
      = greatest(v_user_id, p_target_user_id);
  if v_request_id is not null then
    raise exception
      'request_already_pending: a request between you two is already waiting';
  end if;

  begin
    insert into app_finance.network_add_requests (
      requester_user_id, recipient_user_id, requester_alias_for_recipient
    ) values (v_user_id, p_target_user_id, v_alias)
    returning id into v_request_id;
  exception when unique_violation then
    raise exception
      'request_already_pending: a request between you two is already waiting';
  end;

  select p.display_name into v_display_name
  from app_core.profiles p where p.id = v_user_id;

  perform app_private.enqueue_network_notification(
    p_target_user_id, 'network_add_request', v_request_id,
    'network_request_received',
    jsonb_build_object(
      'type', 'network_add_request',
      'reminder_kind', 'network_request_received',
      'counterparty_name', coalesce(nullif(v_display_name, ''), 'Someone')
    )
  );

  return v_request_id;
end;
$$;

create or replace function app_finance.accept_network_add_request(
  p_request_id uuid,
  p_local_alias text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_alias text := btrim(coalesce(p_local_alias, ''));
  v_request app_finance.network_add_requests%rowtype;
  v_connection_id uuid;
  v_user_a uuid;
  v_user_b uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if char_length(v_alias) < 1 or char_length(v_alias) > 80 then
    raise exception 'invalid_alias: choose a name between 1 and 80 characters';
  end if;

  select * into v_request
  from app_finance.network_add_requests r
  where r.id = p_request_id
    and v_user_id in (r.requester_user_id, r.recipient_user_id)
  for update;
  if v_request is null then
    raise exception 'not_found: add request';
  end if;
  if v_request.recipient_user_id <> v_user_id then
    raise exception 'not_authorized: only the recipient can respond';
  end if;
  if v_request.status <> 'pending' then
    raise exception 'already_decided: this request was already handled';
  end if;

  if exists (
    select 1 from app_finance.network_connections c
    where c.removed_at is null
      and least(c.user_a_id, c.user_b_id)
        = least(v_request.requester_user_id, v_request.recipient_user_id)
      and greatest(c.user_a_id, c.user_b_id)
        = greatest(v_request.requester_user_id, v_request.recipient_user_id)
  ) then
    raise exception 'already_connected: this person is already in your network';
  end if;

  v_user_a := least(v_request.requester_user_id, v_request.recipient_user_id);
  v_user_b :=
    greatest(v_request.requester_user_id, v_request.recipient_user_id);

  -- Directional alias mapping: what the requester typed is what the
  -- requester calls the recipient; what the recipient just typed is what the
  -- recipient calls the requester. Neither ever overwrites a profile name.
  insert into app_finance.network_connections (
    user_a_id, user_b_id, user_a_alias_for_b, user_b_alias_for_a,
    accepted_request_id
  ) values (
    v_user_a,
    v_user_b,
    case when v_user_a = v_request.requester_user_id
      then v_request.requester_alias_for_recipient else v_alias end,
    case when v_user_b = v_request.requester_user_id
      then v_request.requester_alias_for_recipient else v_alias end,
    v_request.id
  )
  returning id into v_connection_id;

  update app_finance.network_add_requests
    set status = 'accepted', responded_at = now()
    where id = v_request.id;

  perform app_private.enqueue_network_notification(
    v_request.requester_user_id, 'network_add_request', v_request.id,
    'network_request_accepted',
    jsonb_build_object(
      'type', 'network_add_request_accepted',
      'reminder_kind', 'network_request_accepted',
      'counterparty_name', v_request.requester_alias_for_recipient
    )
  );

  return v_connection_id;
end;
$$;

create or replace function app_finance.reject_network_add_request(
  p_request_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_request app_finance.network_add_requests%rowtype;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_request
  from app_finance.network_add_requests r
  where r.id = p_request_id
    and v_user_id in (r.requester_user_id, r.recipient_user_id)
  for update;
  if v_request is null then
    raise exception 'not_found: add request';
  end if;
  if v_request.recipient_user_id <> v_user_id then
    raise exception 'not_authorized: only the recipient can respond';
  end if;
  if v_request.status <> 'pending' then
    raise exception 'already_decided: this request was already handled';
  end if;

  update app_finance.network_add_requests
    set status = 'rejected', responded_at = now()
    where id = v_request.id;
end;
$$;

-- Both directions with identity resolved server-side. The requester's private
-- alias is returned only to the requester (their own Sent list); the incoming
-- side sees the requester's real name and email instead.
create or replace function app_finance.list_network_add_requests()
returns table (
  request_id uuid,
  direction text,
  other_user_id uuid,
  other_display_name text,
  other_email text,
  my_alias text,
  status app_finance.network_add_request_status,
  requested_at timestamptz,
  responded_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    r.id,
    case when r.requester_user_id = (select auth.uid())
      then 'outgoing' else 'incoming' end,
    other.id,
    p.display_name,
    coalesce(u.email, ''),
    case when r.requester_user_id = (select auth.uid())
      then r.requester_alias_for_recipient end,
    r.status,
    r.requested_at,
    r.responded_at
  from app_finance.network_add_requests r
  cross join lateral (
    select case when r.requester_user_id = (select auth.uid())
      then r.recipient_user_id else r.requester_user_id end as id
  ) other
  join app_core.profiles p on p.id = other.id
  join auth.users u on u.id = other.id
  where (select auth.uid()) is not null
    and (select auth.uid()) in (r.requester_user_id, r.recipient_user_id)
  order by r.requested_at desc, r.id desc;
$$;

-- ---------------------------------------------------------------------------
-- Connection management
-- ---------------------------------------------------------------------------

-- The canonical contacts projection: the caller's own directional alias plus
-- the contact's real identity. Alias direction is resolved here, server-side,
-- so no client widget ever re-implements it.
create or replace function app_finance.list_network_contacts()
returns table (
  connection_id uuid,
  other_user_id uuid,
  local_alias text,
  real_display_name text,
  email text,
  connected_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    c.id,
    other.id,
    case when c.user_a_id = (select auth.uid())
      then c.user_a_alias_for_b else c.user_b_alias_for_a end,
    p.display_name,
    coalesce(u.email, ''),
    c.created_at
  from app_finance.network_connections c
  cross join lateral (
    select case when c.user_a_id = (select auth.uid())
      then c.user_b_id else c.user_a_id end as id
  ) other
  join app_core.profiles p on p.id = other.id
  join auth.users u on u.id = other.id
  where (select auth.uid()) is not null
    and (select auth.uid()) in (c.user_a_id, c.user_b_id)
    and c.removed_at is null
  order by lower(case when c.user_a_id = (select auth.uid())
    then c.user_a_alias_for_b else c.user_b_alias_for_a end), c.id;
$$;

-- Renames only the caller's own alias for the other person; the other
-- direction belongs to the other user and is never touched.
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
end;
$$;

-- Soft removal: history stays, but no new transfers can be created and no
-- pending transfer on this connection can be accepted anymore.
create or replace function app_finance.remove_network_connection(
  p_connection_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  update app_finance.network_connections c
    set removed_at = now()
    where c.id = p_connection_id
      and v_user_id in (c.user_a_id, c.user_b_id)
      and c.removed_at is null;
  if not found then
    raise exception 'not_found: network connection';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Network transfer lifecycle
-- ---------------------------------------------------------------------------

-- Creates the shared pending request. Only 'manual' is accepted from clients:
-- automation origins are created server-side by the acceptance paths of
-- recurring rules and income occurrences, so origin linkage cannot be forged.
create or replace function app_finance.create_network_transfer_request(
  p_connection_id uuid,
  p_source_account_id uuid,
  p_amount_minor bigint,
  p_requested_on date,
  p_shared_note text default null,
  p_origin_kind app_finance.network_transfer_origin default 'manual',
  p_origin_id uuid default null,
  p_idempotency_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_origin_kind <> 'manual' or p_origin_id is not null then
    raise exception
      'invalid_origin: automation transfers are created by their automations';
  end if;

  return app_private.create_network_transfer(
    v_user_id, p_connection_id, p_source_account_id, p_amount_minor,
    coalesce(p_requested_on, current_date), p_shared_note,
    'manual', null, nullif(btrim(coalesce(p_idempotency_key, '')), '')
  );
end;
$$;

-- The only path that may book cross-user ledger rows. Everything financial is
-- derived from locked server data: the client contributes nothing beyond the
-- transfer id and which of their own accounts receives the money.
create or replace function app_finance.accept_network_transfer(
  p_transfer_id uuid,
  p_destination_account_id uuid
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
  if v_transfer.status <> 'pending' then
    raise exception 'already_decided: this transfer was already handled';
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

  -- Revalidate sender funds now: pending never reserved anything.
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

-- Direction-aware projection of the caller's transfers. Each side sees the
-- shared facts (amount, currency, dates, status, note, counterparty alias)
-- plus only their own account: the sender never learns the receiver's
-- destination and the receiver never learns the sender's source.
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
  connection_active boolean
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
    (c.id is not null and c.removed_at is null)
  from app_finance.network_transfers nt
  left join app_finance.network_connections c on c.id = nt.connection_id
  where (select auth.uid()) is not null
    and (select auth.uid()) in (nt.sender_user_id, nt.receiver_user_id)
  order by nt.requested_at desc, nt.id desc;
$$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

revoke execute on function app_finance.search_network_users(text)
  from public, anon;
grant execute on function app_finance.search_network_users(text)
  to authenticated, service_role;

revoke execute on function app_finance.send_network_add_request(uuid, text)
  from public, anon;
grant execute on function app_finance.send_network_add_request(uuid, text)
  to authenticated, service_role;

revoke execute on function app_finance.accept_network_add_request(uuid, text)
  from public, anon;
grant execute on function app_finance.accept_network_add_request(uuid, text)
  to authenticated, service_role;

revoke execute on function app_finance.reject_network_add_request(uuid)
  from public, anon;
grant execute on function app_finance.reject_network_add_request(uuid)
  to authenticated, service_role;

revoke execute on function app_finance.list_network_add_requests()
  from public, anon;
grant execute on function app_finance.list_network_add_requests()
  to authenticated, service_role;

revoke execute on function app_finance.list_network_contacts()
  from public, anon;
grant execute on function app_finance.list_network_contacts()
  to authenticated, service_role;

revoke execute on function app_finance.rename_network_contact(uuid, text)
  from public, anon;
grant execute on function app_finance.rename_network_contact(uuid, text)
  to authenticated, service_role;

revoke execute on function app_finance.remove_network_connection(uuid)
  from public, anon;
grant execute on function app_finance.remove_network_connection(uuid)
  to authenticated, service_role;

revoke execute on function app_finance.create_network_transfer_request(
  uuid, uuid, bigint, date, text, app_finance.network_transfer_origin,
  uuid, text
) from public, anon;
grant execute on function app_finance.create_network_transfer_request(
  uuid, uuid, bigint, date, text, app_finance.network_transfer_origin,
  uuid, text
) to authenticated, service_role;

revoke execute on function app_finance.accept_network_transfer(uuid, uuid)
  from public, anon;
grant execute on function app_finance.accept_network_transfer(uuid, uuid)
  to authenticated, service_role;

revoke execute on function app_finance.reject_network_transfer(uuid)
  from public, anon;
grant execute on function app_finance.reject_network_transfer(uuid)
  to authenticated, service_role;

revoke execute on function app_finance.list_network_transfers()
  from public, anon;
grant execute on function app_finance.list_network_transfers()
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Notification outbox kinds
-- ---------------------------------------------------------------------------

alter table app_core.notification_outbox
  drop constraint if exists notification_outbox_obligation_type_check;
alter table app_core.notification_outbox
  add constraint notification_outbox_obligation_type_check check (
    obligation_type in (
      'credit_card_statement_due', 'installment_due', 'bnpl_due',
      'facility_payment', 'statement_due', 'payment', 'plan', 'general',
      'network_add_request', 'network_transfer'
    )
  );

alter table app_core.notification_outbox
  drop constraint if exists notification_outbox_reminder_kind_check;
alter table app_core.notification_outbox
  add constraint notification_outbox_reminder_kind_check check (
    reminder_kind in (
      'due_soon', 'due_today', 'overdue', 'payment_confirmation',
      'lead', 'due_tomorrow', 'payment_success', 'plan_completed',
      'near_limit',
      'network_request_received', 'network_request_accepted',
      'network_transfer_pending', 'network_transfer_accepted',
      'network_transfer_rejected'
    )
  );

-- ---------------------------------------------------------------------------
-- Deletion cascade
-- ---------------------------------------------------------------------------

-- Product-data deletion: the departing user's requests and connections go
-- away (contacts disappear from the peer's network), pending transfers are
-- withdrawn, but accepted/rejected transfer history stays so the surviving
-- user's ledger keeps its context. The peer's booked one-sided rows remain
-- valid because is_network_transfer, not the shared row, carries the shape.
create or replace function app_core.delete_finance_suit_data(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_user_id is null then
    raise exception 'user_id_required';
  end if;

  perform set_config('app_finance.facility_internal', 'on', true);
  perform set_config('app_finance.network_internal', 'on', true);

  update app_salary.salary_periods
    set paid_transaction_id = null
    where user_id = p_user_id;
  update app_finance.income_occurrences
    set primary_transaction_id = null
    where user_id = p_user_id;
  update app_finance.financial_transactions
    set salary_period_id = null, income_occurrence_id = null
    where user_id = p_user_id;

  delete from app_core.notification_outbox where user_id = p_user_id;
  delete from app_core.push_devices where user_id = p_user_id;
  delete from app_core.notification_preferences where user_id = p_user_id;

  delete from app_finance.network_transfers
    where status = 'pending'
      and (sender_user_id = p_user_id or receiver_user_id = p_user_id);
  delete from app_finance.network_connections
    where user_a_id = p_user_id or user_b_id = p_user_id;
  delete from app_finance.network_add_requests
    where requester_user_id = p_user_id or recipient_user_id = p_user_id;

  delete from app_finance.recurring_occurrences where user_id = p_user_id;
  delete from app_finance.recurring_rules where user_id = p_user_id;
  delete from app_finance.installment_payment_allocations
    where user_id = p_user_id;
  delete from app_finance.credit_card_statement_allocations
    where user_id = p_user_id;
  delete from app_finance.credit_card_fee_charges where user_id = p_user_id;
  delete from app_finance.credit_card_statement_items
    where user_id = p_user_id;
  delete from app_finance.credit_card_statement_cycles
    where user_id = p_user_id;
  delete from app_finance.credit_card_fee_rules where user_id = p_user_id;
  delete from app_finance.installment_plan_revisions
    where user_id = p_user_id;
  delete from app_finance.installment_dues where user_id = p_user_id;
  delete from app_finance.installment_plans where user_id = p_user_id;
  delete from app_finance.credit_facility_settings where user_id = p_user_id;
  delete from app_finance.held_amounts where user_id = p_user_id;
  delete from app_finance.transaction_macro_items where user_id = p_user_id;
  delete from app_finance.transaction_macros where user_id = p_user_id;
  delete from app_finance.financial_transactions where user_id = p_user_id;
  delete from app_finance.income_occurrences where user_id = p_user_id;
  delete from app_finance.income_source_allocations where user_id = p_user_id;
  delete from app_finance.income_sources where user_id = p_user_id;
  delete from app_salary.salary_periods where user_id = p_user_id;
  delete from app_finance.transaction_categories where user_id = p_user_id;
  delete from app_finance.accounts where user_id = p_user_id;
  delete from app_work.work_entries where user_id = p_user_id;
  delete from app_work.official_holidays where user_id = p_user_id;
  delete from app_salary.salary_adjustments where user_id = p_user_id;
  delete from app_salary.salary_settings where user_id = p_user_id;
  delete from app_core.user_preferences where user_id = p_user_id;
  delete from app_core.profiles where id = p_user_id;

  perform set_config('app_finance.facility_internal', '', true);
  perform set_config('app_finance.network_internal', '', true);
end;
$$;

comment on function app_core.delete_finance_suit_data(uuid) is
  'Deletes Finance Suit product data only; preserves shared Auth and public legacy data.';

revoke all on function app_core.delete_finance_suit_data(uuid) from public;
revoke all on function app_core.delete_finance_suit_data(uuid) from anon;
revoke all on function app_core.delete_finance_suit_data(uuid)
from authenticated;
grant execute on function app_core.delete_finance_suit_data(uuid)
to service_role;

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'network_add_requests',
    'network_connections',
    'network_transfers'
  ] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'app_finance'
        and tablename = v_table
    ) then
      execute format(
        'alter publication supabase_realtime add table app_finance.%I',
        v_table
      );
    end if;
  end loop;
end;
$$;

notify pgrst, 'reload schema';
