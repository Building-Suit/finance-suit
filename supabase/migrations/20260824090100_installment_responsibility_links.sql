-- Installment responsibility linking: an installment plan stays entirely the
-- owner's (the Credit Card / BNPL liability, the purchase expense, the dues,
-- the facility payments), but the owner may link it to a person responsible
-- for reimbursing them:
--
--   * custom person  — a private local name, no Finance Suit account, active
--     immediately, reimbursements recorded manually by the owner;
--   * network user   — an accepted Finance Suit Network contact who must
--     review a server-built snapshot of the installment terms and explicitly
--     accept before the responsibility becomes active, and who can reimburse
--     through the existing network transfer rail.
--
-- Hard invariants (tested in pgTAP):
--   * linking, accepting, rejecting, and unlinking never move money;
--   * a reimbursement increases one of the owner's asset accounts but never
--     touches the facility liability, installment dues, or payment
--     allocations — facility repayment stays a separate explicit action;
--   * reimbursements are transfers, never income;
--   * the linked user reads only sanitized, installment-scoped data through
--     narrow RPCs — plan/due/account RLS is not broadened at all.

-- ---------------------------------------------------------------------------
-- Enums (fresh types, so same-transaction use is safe)
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'responsibility_link_type') then
    create type app_finance.responsibility_link_type as enum
      ('custom', 'network');
  end if;
  if not exists (select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'responsibility_link_status') then
    create type app_finance.responsibility_link_status as enum
      ('pending', 'accepted', 'rejected');
  end if;
  if not exists (select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'reimbursement_method') then
    create type app_finance.reimbursement_method as enum
      ('network_transfer', 'manual_external');
  end if;
  if not exists (select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'reimbursement_status') then
    create type app_finance.reimbursement_status as enum
      ('pending', 'received', 'rejected');
  end if;
end $$;

grant usage on type app_finance.responsibility_link_type
to authenticated, service_role;
grant usage on type app_finance.responsibility_link_status
to authenticated, service_role;
grant usage on type app_finance.reimbursement_method
to authenticated, service_role;
grant usage on type app_finance.reimbursement_status
to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Responsibility links
-- ---------------------------------------------------------------------------

-- user_id is always the plan owner. responsible_user_id is set only for
-- network links and never equals the owner. History is append-only: unlink
-- soft-removes with removed_at, rejection keeps the row, and reassignment
-- creates a new row, so "who was responsible when" stays auditable.
create table if not exists app_finance.installment_responsibility_links (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  plan_id uuid not null,
  link_type app_finance.responsibility_link_type not null,
  custom_name text
    check (custom_name is null or char_length(custom_name) between 1 and 80),
  network_connection_id uuid
    references app_finance.network_connections (id) on delete set null,
  responsible_user_id uuid
    references auth.users (id) on delete set null,
  status app_finance.responsibility_link_status not null default 'pending',
  responsibility_from_sequence integer not null
    check (responsibility_from_sequence >= 1),
  plan_revision_at_request integer not null
    check (plan_revision_at_request >= 1),
  request_snapshot jsonb,
  shared_note text check (shared_note is null or char_length(shared_note) <= 500),
  requested_at timestamptz not null default now(),
  responded_at timestamptz,
  accepted_at timestamptz,
  rejected_at timestamptz,
  removed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint responsibility_links_owner_unique unique (id, user_id),
  constraint responsibility_links_plan_owner_fk
    foreign key (plan_id, user_id)
    references app_finance.installment_plans (id, user_id) on delete cascade,
  constraint responsibility_links_no_self
    check (responsible_user_id is null or responsible_user_id <> user_id),
  -- Custom links carry a name and no network identity; network links carry
  -- no custom name (network ids may be detached later by deletion cascades).
  constraint responsibility_links_shape check (
    (link_type = 'custom' and custom_name is not null
      and network_connection_id is null and responsible_user_id is null)
    or (link_type = 'network' and custom_name is null)
  ),
  -- Custom links are born accepted; only network links can be pending.
  constraint responsibility_links_custom_accepted check (
    link_type = 'network' or status = 'accepted'
  ),
  constraint responsibility_links_status_shape check (
    (status = 'pending' and accepted_at is null and rejected_at is null)
    or (status = 'accepted' and accepted_at is not null
      and rejected_at is null)
    or (status = 'rejected' and rejected_at is not null
      and accepted_at is null)
  )
);

drop trigger if exists trg_responsibility_links_updated_at
  on app_finance.installment_responsibility_links;
create trigger trg_responsibility_links_updated_at
  before update on app_finance.installment_responsibility_links
  for each row execute function app_private.set_updated_at();

-- One live (pending or accepted, not removed) responsibility per plan: a due
-- can never have two active responsible people.
create unique index if not exists idx_responsibility_links_one_live_per_plan
  on app_finance.installment_responsibility_links (plan_id)
  where status in ('pending', 'accepted') and removed_at is null;

create index if not exists idx_responsibility_links_plan
  on app_finance.installment_responsibility_links (plan_id, user_id);
create index if not exists idx_responsibility_links_responsible
  on app_finance.installment_responsibility_links
  (responsible_user_id, status)
  where responsible_user_id is not null;
create index if not exists idx_responsibility_links_connection
  on app_finance.installment_responsibility_links (network_connection_id)
  where network_connection_id is not null;

-- ---------------------------------------------------------------------------
-- Reimbursements
-- ---------------------------------------------------------------------------

-- user_id is always the plan owner (the party being reimbursed). due_id is
-- nullable only because a restructure may replace unpaid dues: history keeps
-- the recorded sequence number and amount even if the schedule row is gone.
create table if not exists app_finance.installment_reimbursements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  plan_id uuid not null,
  due_id uuid,
  due_sequence_number integer not null check (due_sequence_number >= 1),
  responsibility_link_id uuid not null,
  responsible_user_id uuid
    references auth.users (id) on delete set null,
  amount_minor bigint not null check (amount_minor > 0),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  method app_finance.reimbursement_method not null,
  status app_finance.reimbursement_status not null default 'pending',
  network_transfer_id uuid
    references app_finance.network_transfers (id) on delete set null,
  owner_destination_account_id uuid,
  owner_transaction_id uuid,
  note text check (note is null or char_length(note) <= 500),
  received_on date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint installment_reimbursements_owner_unique unique (id, user_id),
  constraint installment_reimbursements_plan_owner_fk
    foreign key (plan_id, user_id)
    references app_finance.installment_plans (id, user_id) on delete cascade,
  constraint installment_reimbursements_due_owner_fk
    foreign key (due_id, user_id)
    references app_finance.installment_dues (id, user_id)
    on delete set null (due_id),
  constraint installment_reimbursements_link_owner_fk
    foreign key (responsibility_link_id, user_id)
    references app_finance.installment_responsibility_links (id, user_id)
    on delete cascade,
  constraint installment_reimbursements_dest_owner_fk
    foreign key (owner_destination_account_id, user_id)
    references app_finance.accounts (id, user_id)
    on delete set null (owner_destination_account_id),
  constraint installment_reimbursements_tx_owner_fk
    foreign key (owner_transaction_id, user_id)
    references app_finance.financial_transactions (id, user_id)
    on delete set null (owner_transaction_id),
  -- Manual reimbursements are recorded by the owner after the fact, so they
  -- are born received; network reimbursements settle through the transfer.
  constraint installment_reimbursements_method_shape check (
    (method = 'manual_external' and status = 'received')
    or method = 'network_transfer'
  ),
  constraint installment_reimbursements_received_shape check (
    status <> 'received' or received_on is not null
  )
);

drop trigger if exists trg_installment_reimbursements_updated_at
  on app_finance.installment_reimbursements;
create trigger trg_installment_reimbursements_updated_at
  before update on app_finance.installment_reimbursements
  for each row execute function app_private.set_updated_at();

-- One reimbursement per network transfer: acceptance settles exactly one row.
create unique index if not exists idx_installment_reimbursements_transfer
  on app_finance.installment_reimbursements (network_transfer_id)
  where network_transfer_id is not null;

create index if not exists idx_installment_reimbursements_due
  on app_finance.installment_reimbursements (due_id, status)
  where due_id is not null;
create index if not exists idx_installment_reimbursements_link
  on app_finance.installment_reimbursements (responsibility_link_id, status);
create index if not exists idx_installment_reimbursements_plan
  on app_finance.installment_reimbursements (plan_id, user_id);
create index if not exists idx_installment_reimbursements_responsible
  on app_finance.installment_reimbursements (responsible_user_id)
  where responsible_user_id is not null;

-- ---------------------------------------------------------------------------
-- Ledger integration: protected one-sided reimbursement inflow
-- ---------------------------------------------------------------------------

-- A manually recorded (custom person) reimbursement books as a one-sided
-- transfer into one of the owner's asset accounts: it raises the asset,
-- counts as a transfer (never income), and does not touch the facility.
-- is_reimbursement_inflow is the structural marker (never nulled by a
-- cascade); installment_reimbursement_id links back for display.
alter table app_finance.financial_transactions
  add column if not exists is_reimbursement_inflow boolean not null
    default false,
  add column if not exists installment_reimbursement_id uuid;

alter table app_finance.financial_transactions
  drop constraint if exists tx_reimbursement_fk,
  add constraint tx_reimbursement_fk
    foreign key (installment_reimbursement_id)
    references app_finance.installment_reimbursements (id)
    on delete set null;

create index if not exists idx_tx_installment_reimbursement
  on app_finance.financial_transactions (installment_reimbursement_id)
  where installment_reimbursement_id is not null;

alter table app_finance.financial_transactions
  drop constraint if exists tx_reimbursement_link_shape,
  add constraint tx_reimbursement_link_shape check (
    is_reimbursement_inflow or installment_reimbursement_id is null
  );

-- Same shape rules as before plus the reimbursement inflow: a one-sided
-- destination-only transfer, mutually exclusive with network legs.
alter table app_finance.financial_transactions
  drop constraint if exists tx_direction_by_kind,
  add constraint tx_direction_by_kind check (
    (transaction_kind in ('expense', 'allowance_given')
      and not is_network_transfer
      and not is_reimbursement_inflow
      and source_account_id is not null
      and destination_account_id is null)
    or
    (transaction_kind in ('custom_income', 'freelance_income', 'salary_income')
      and not is_network_transfer
      and not is_reimbursement_inflow
      and destination_account_id is not null
      and source_account_id is null)
    or
    (transaction_kind = 'transfer'
      and not is_network_transfer
      and not is_reimbursement_inflow
      and source_account_id is not null
      and destination_account_id is not null
      and source_account_id <> destination_account_id)
    or
    (transaction_kind = 'transfer'
      and is_network_transfer
      and not is_reimbursement_inflow
      and ((source_account_id is not null and destination_account_id is null)
        or (destination_account_id is not null and source_account_id is null)))
    or
    (transaction_kind = 'transfer'
      and is_reimbursement_inflow
      and not is_network_transfer
      and destination_account_id is not null
      and source_account_id is null)
  );

-- Only the reimbursement RPCs may create reimbursement inflow rows, and
-- booked rows are immutable for the generic editors: deleting only the
-- ledger row while the reimbursement stays received would desynchronize
-- the shared state. Service-role/admin sessions stay unrestricted.
create or replace function app_private.protect_reimbursement_transactions()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if coalesce(current_setting('app_finance.responsibility_internal', true), '')
      = 'on'
    or (select auth.uid()) is null then
    return coalesce(new, old);
  end if;

  if tg_op = 'INSERT' then
    if new.is_reimbursement_inflow
      or new.installment_reimbursement_id is not null then
      raise exception
        'reimbursement_transaction_locked: reimbursements are recorded from the installment screen';
    end if;
  else
    if old.is_reimbursement_inflow
      or old.installment_reimbursement_id is not null then
      raise exception
        'reimbursement_transaction_locked: recorded reimbursements cannot be edited directly';
    end if;
    if tg_op = 'UPDATE'
      and (new.is_reimbursement_inflow
        or new.installment_reimbursement_id is not null) then
      raise exception
        'reimbursement_transaction_locked: reimbursements are recorded from the installment screen';
    end if;
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_protect_reimbursement_transactions
  on app_finance.financial_transactions;
create trigger trg_protect_reimbursement_transactions
  before insert or update or delete on app_finance.financial_transactions
  for each row execute function
    app_private.protect_reimbursement_transactions();

revoke execute on function app_private.protect_reimbursement_transactions()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Consent integrity guards on plans and dues
-- ---------------------------------------------------------------------------

-- update_installment_plan rewrites a plan by delete + recreate, which would
-- cascade away the responsibility history and any consent snapshot. A plan
-- that ever carried a responsibility link can therefore not be deleted
-- through that path; account deletion clears the link rows first and passes.
create or replace function app_private.protect_linked_plan_delete()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (
    select 1 from app_finance.installment_responsibility_links l
    where l.plan_id = old.id
  ) then
    raise exception
      'plan_linked: this plan has responsibility history and cannot be rewritten';
  end if;
  return old;
end;
$$;

drop trigger if exists trg_protect_linked_plan_delete
  on app_finance.installment_plans;
create trigger trg_protect_linked_plan_delete
  before delete on app_finance.installment_plans
  for each row execute function app_private.protect_linked_plan_delete();

revoke execute on function app_private.protect_linked_plan_delete()
  from public, anon, authenticated;

-- A due with a pending reimbursement must not be replaced (restructure
-- deletes unpaid dues): the pending transfer must be accepted or rejected
-- first. Received history detaches gracefully through on delete set null.
create or replace function app_private.protect_due_with_pending_reimbursement()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (
    select 1 from app_finance.installment_reimbursements r
    where r.due_id = old.id and r.status = 'pending'
  ) then
    raise exception
      'reimbursement_pending: resolve the pending reimbursement before changing this installment';
  end if;
  return old;
end;
$$;

drop trigger if exists trg_protect_due_with_pending_reimbursement
  on app_finance.installment_dues;
create trigger trg_protect_due_with_pending_reimbursement
  before delete on app_finance.installment_dues
  for each row execute function
    app_private.protect_due_with_pending_reimbursement();

revoke execute on function
  app_private.protect_due_with_pending_reimbursement()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Row level security and privilege surface
-- ---------------------------------------------------------------------------

alter table app_finance.installment_responsibility_links
  enable row level security;
alter table app_finance.installment_reimbursements enable row level security;

-- Both parties may read the shared rows; third users see nothing. All writes
-- go through the RPCs below (no insert/update/delete grants), and the
-- snapshot inside the row is already sanitized server-side, so row-level
-- select leaks nothing beyond what the responsible user consented to.
drop policy if exists installment_responsibility_links_select
  on app_finance.installment_responsibility_links;
create policy installment_responsibility_links_select
  on app_finance.installment_responsibility_links
  for select to authenticated
  using ((select auth.uid()) in (user_id, responsible_user_id));

drop policy if exists installment_reimbursements_select
  on app_finance.installment_reimbursements;
create policy installment_reimbursements_select
  on app_finance.installment_reimbursements
  for select to authenticated
  using ((select auth.uid()) in (user_id, responsible_user_id));

revoke all on table app_finance.installment_responsibility_links
  from authenticated;
grant select on table app_finance.installment_responsibility_links
  to authenticated;

revoke all on table app_finance.installment_reimbursements from authenticated;
grant select on table app_finance.installment_reimbursements to authenticated;

grant select, insert, update, delete on
  app_finance.installment_responsibility_links,
  app_finance.installment_reimbursements
to service_role;

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

-- Fingerprint of the material responsibility terms: the exact remaining
-- schedule (sequence, date, amount) from the responsibility start, plus the
-- currency. Facility payments never touch dues, so paying the bank does not
-- change the fingerprint; a restructure or plan rewrite does.
create or replace function app_private.responsibility_terms_fingerprint(
  p_plan_id uuid,
  p_from_sequence integer
)
returns text
language sql
stable
set search_path = ''
as $$
  select md5(
    coalesce((
      select string_agg(
        d.sequence_number || ':' || d.due_on || ':' || d.amount_minor, '|'
        order by d.sequence_number)
      from app_finance.installment_dues d
      where d.plan_id = p_plan_id
        and d.sequence_number >= p_from_sequence
        and not d.is_presettled
    ), '')
    || '#' || (select p.currency_code from app_finance.installment_plans p
      where p.id = p_plan_id)
  );
$$;

revoke execute on function app_private.responsibility_terms_fingerprint(
  uuid, integer
) from public, anon, authenticated;

-- Earliest due the responsibility can start at: the first schedule row that
-- is neither presettled (imported history) nor fully covered by facility
-- payments. This is authoritative due status, not calendar date, so a
-- current posted-but-unpaid installment is included.
create or replace function app_private.responsibility_start_sequence(
  p_plan_id uuid
)
returns integer
language sql
stable
set search_path = ''
as $$
  select min(s.sequence_number)
  from app_finance.installment_due_statuses s
  where s.plan_id = p_plan_id
    and s.remaining_minor > 0
    and not exists (
      select 1 from app_finance.installment_dues d
      where d.id = s.id and d.is_presettled
    );
$$;

revoke execute on function app_private.responsibility_start_sequence(uuid)
  from public, anon, authenticated;

-- Server-built, sanitized snapshot of the installment terms a responsible
-- person reviews. It intentionally contains no balances, credit limit,
-- available credit, card digits, owner notes, or anything outside this one
-- plan. It is stored as consent evidence and re-rendered as current terms.
create or replace function app_private.build_responsibility_snapshot(
  p_plan_id uuid,
  p_from_sequence integer
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_plan record;
  v_remaining record;
  v_paid_count integer;
begin
  select p.id, p.revision, p.title, p.purchased_on, p.first_due_on,
      p.installment_count, p.purchase_price_minor, p.down_payment_minor,
      p.financed_principal_minor, p.financing_fees_minor, p.interest_minor,
      p.total_payable_minor, p.currency_code, p.pricing_method,
      p.interest_rate_basis_points, p.interest_rate_period,
      p.interest_method, p.status,
      a.name as facility_name, a.account_type as facility_type,
      c.name as category_name,
      coalesce(nullif(pr.display_name, ''), 'Finance Suit user')
        as owner_display_name
    into v_plan
    from app_finance.installment_plans p
    join app_finance.accounts a on a.id = p.account_id
    left join app_finance.transaction_categories c on c.id = p.category_id
    left join app_core.profiles pr on pr.id = p.user_id
    where p.id = p_plan_id;
  if v_plan is null then
    raise exception 'not_found: installment plan';
  end if;

  select count(*)::integer into v_paid_count
    from app_finance.installment_due_statuses s
    where s.plan_id = p_plan_id and s.remaining_minor = 0;

  select
      count(*)::integer as remaining_count,
      coalesce(sum(d.amount_minor), 0)::bigint as remaining_total_minor,
      min(d.due_on) as next_due_on,
      max(d.due_on) as final_due_on,
      min(d.amount_minor) as min_amount_minor,
      max(d.amount_minor) as max_amount_minor
    into v_remaining
    from app_finance.installment_dues d
    where d.plan_id = p_plan_id
      and d.sequence_number >= p_from_sequence
      and not d.is_presettled;

  return jsonb_build_object(
    'schema_version', 1,
    'plan_id', v_plan.id,
    'plan_revision', v_plan.revision,
    'terms_fingerprint',
      app_private.responsibility_terms_fingerprint(p_plan_id, p_from_sequence),
    'title', v_plan.title,
    'owner_display_name', v_plan.owner_display_name,
    'facility_name', v_plan.facility_name,
    'facility_type', v_plan.facility_type,
    'category_name', v_plan.category_name,
    'purchased_on', v_plan.purchased_on,
    'first_due_on', v_plan.first_due_on,
    'currency_code', v_plan.currency_code,
    'purchase_price_minor', v_plan.purchase_price_minor,
    'down_payment_minor', v_plan.down_payment_minor,
    'financed_principal_minor', v_plan.financed_principal_minor,
    'financing_fees_minor', v_plan.financing_fees_minor,
    'interest_minor', v_plan.interest_minor,
    'total_payable_minor', v_plan.total_payable_minor,
    'pricing_method', v_plan.pricing_method,
    'interest_rate_basis_points', v_plan.interest_rate_basis_points,
    'interest_rate_period', v_plan.interest_rate_period,
    'interest_method', v_plan.interest_method,
    'installment_count', v_plan.installment_count,
    'paid_installment_count', v_paid_count,
    'responsibility_from_sequence', p_from_sequence,
    'remaining_count', v_remaining.remaining_count,
    'remaining_total_minor', v_remaining.remaining_total_minor,
    'next_due_on', v_remaining.next_due_on,
    'final_due_on', v_remaining.final_due_on,
    'typical_installment_minor', v_remaining.max_amount_minor
  );
end;
$$;

revoke execute on function app_private.build_responsibility_snapshot(
  uuid, integer
) from public, anon, authenticated;

-- The responsibility-relevant due schedule with its reimbursement state.
-- Reimbursements are aggregated per due across ALL links of the plan, not
-- just the viewing link: after a reassignment the new person must see (and
-- be limited by) what the previous person already covered, so one due can
-- never be collected twice. Pending amounts reserve remaining reimbursement.
create or replace function app_private.responsibility_due_schedule(
  p_link app_finance.installment_responsibility_links
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'due_id', d.id,
      'sequence_number', d.sequence_number,
      'due_on', d.due_on,
      'amount_minor', d.amount_minor,
      'received_minor', coalesce(r.received_minor, 0),
      'pending_minor', coalesce(r.pending_minor, 0),
      'remaining_minor', greatest(
        d.amount_minor
          - coalesce(r.received_minor, 0) - coalesce(r.pending_minor, 0), 0),
      'reimbursement_status', case
        when coalesce(r.received_minor, 0) >= d.amount_minor then 'received'
        when coalesce(r.pending_minor, 0) > 0 then 'pending'
        when coalesce(r.received_minor, 0) > 0 then 'partial'
        else 'not_paid'
      end
    ) order by d.sequence_number), '[]'::jsonb)
  from app_finance.installment_dues d
  left join lateral (
    select
      sum(r.amount_minor) filter (where r.status = 'received')
        as received_minor,
      sum(r.amount_minor) filter (where r.status = 'pending')
        as pending_minor
    from app_finance.installment_reimbursements r
    where r.due_id = d.id
  ) r on true
  where d.plan_id = p_link.plan_id
    and d.sequence_number >= p_link.responsibility_from_sequence
    and not d.is_presettled;
$$;

revoke execute on function app_private.responsibility_due_schedule(
  app_finance.installment_responsibility_links
) from public, anon, authenticated;

-- Counterparty label for a link as seen by one side: the owner sees the
-- custom name or their private alias for the contact; the responsible user
-- sees their own private alias for the owner (falling back to the owner's
-- real display name).
create or replace function app_private.responsibility_counterparty_name(
  p_link app_finance.installment_responsibility_links,
  p_viewer_user_id uuid
)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when p_link.link_type = 'custom' then p_link.custom_name
    when p_viewer_user_id = p_link.user_id then coalesce((
      select case when c.user_a_id = p_link.user_id
        then c.user_a_alias_for_b else c.user_b_alias_for_a end
      from app_finance.network_connections c
      where c.id = p_link.network_connection_id
    ), (
      select coalesce(nullif(pr.display_name, ''), 'Network contact')
      from app_core.profiles pr where pr.id = p_link.responsible_user_id
    ), 'Network contact')
    else coalesce((
      select case when c.user_a_id = p_link.responsible_user_id
        then c.user_a_alias_for_b else c.user_b_alias_for_a end
      from app_finance.network_connections c
      where c.id = p_link.network_connection_id
    ), (
      select coalesce(nullif(pr.display_name, ''), 'Finance Suit user')
      from app_core.profiles pr where pr.id = p_link.user_id
    ), 'Finance Suit user')
  end;
$$;

revoke execute on function app_private.responsibility_counterparty_name(
  app_finance.installment_responsibility_links, uuid
) from public, anon, authenticated;

-- Narrow public wrapper for display labels: resolves the counterparty name
-- for the caller's side of a link they are party to. SECURITY DEFINER only
-- because alias columns are not client-selectable; the party check keeps it
-- as private as the row itself.
create or replace function app_finance.responsibility_display_name(
  p_link_id uuid
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select app_private.responsibility_counterparty_name(l, (select auth.uid()))
  from app_finance.installment_responsibility_links l
  where l.id = p_link_id
    and (select auth.uid()) in (l.user_id, l.responsible_user_id);
$$;

-- ---------------------------------------------------------------------------
-- Link lifecycle RPCs
-- ---------------------------------------------------------------------------

-- Shared owner-side validation: the plan must be the caller's, active, and
-- free of a live link; returns the plan row locked.
create or replace function app_private.lock_plan_for_linking(
  p_user_id uuid,
  p_plan_id uuid
)
returns app_finance.installment_plans
language plpgsql
set search_path = ''
as $$
declare
  v_plan app_finance.installment_plans%rowtype;
begin
  select * into v_plan
    from app_finance.installment_plans p
    where p.id = p_plan_id and p.user_id = p_user_id
    for update;
  if v_plan is null then
    raise exception 'not_found: installment plan';
  end if;
  if v_plan.status <> 'active' then
    raise exception
      'plan_not_linkable: only an active installment plan can be linked';
  end if;
  if exists (
    select 1 from app_finance.installment_responsibility_links l
    where l.plan_id = p_plan_id
      and l.status in ('pending', 'accepted')
      and l.removed_at is null
  ) then
    raise exception
      'already_linked: this installment already has a responsible person';
  end if;
  return v_plan;
end;
$$;

revoke execute on function app_private.lock_plan_for_linking(uuid, uuid)
  from public, anon, authenticated;

-- Custom person: private attribution only. No Finance Suit account, no
-- consent round-trip, active immediately, zero ledger impact.
create or replace function app_finance.link_installment_to_custom_person(
  p_plan_id uuid,
  p_custom_name text,
  p_shared_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_name text := btrim(coalesce(p_custom_name, ''));
  v_plan app_finance.installment_plans%rowtype;
  v_from integer;
  v_link_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if char_length(v_name) < 1 or char_length(v_name) > 80 then
    raise exception 'invalid_name: choose a name between 1 and 80 characters';
  end if;

  v_plan := app_private.lock_plan_for_linking(v_user_id, p_plan_id);
  v_from := app_private.responsibility_start_sequence(p_plan_id);
  if v_from is null then
    raise exception
      'plan_not_linkable: this installment has nothing left to reimburse';
  end if;

  insert into app_finance.installment_responsibility_links (
    user_id, plan_id, link_type, custom_name, status,
    responsibility_from_sequence, plan_revision_at_request,
    request_snapshot, shared_note, accepted_at, responded_at
  ) values (
    v_user_id, p_plan_id, 'custom', v_name, 'accepted',
    v_from, v_plan.revision,
    app_private.build_responsibility_snapshot(p_plan_id, v_from),
    nullif(btrim(coalesce(p_shared_note, '')), ''), now(), now()
  )
  returning id into v_link_id;

  return v_link_id;
end;
$$;

-- Network person: must already be an accepted, active network contact of
-- the owner. Creates only a pending request object carrying a server-built
-- consent snapshot; the installment itself is untouched and no balance,
-- due, or ledger row changes because of the pending link.
create or replace function app_finance.request_installment_responsibility(
  p_plan_id uuid,
  p_network_connection_id uuid,
  p_shared_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_plan app_finance.installment_plans%rowtype;
  v_connection app_finance.network_connections%rowtype;
  v_responsible uuid;
  v_from integer;
  v_link_id uuid;
  v_owner_name text;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  -- The responsible user is always derived from the trusted connection row,
  -- never accepted from the client.
  select * into v_connection
    from app_finance.network_connections c
    where c.id = p_network_connection_id
      and v_user_id in (c.user_a_id, c.user_b_id)
    for update;
  if v_connection is null then
    raise exception 'not_found: network connection';
  end if;
  if v_connection.removed_at is not null then
    raise exception
      'network_destination_unavailable: this contact was removed from your network';
  end if;
  v_responsible := case when v_connection.user_a_id = v_user_id
    then v_connection.user_b_id else v_connection.user_a_id end;

  v_plan := app_private.lock_plan_for_linking(v_user_id, p_plan_id);
  v_from := app_private.responsibility_start_sequence(p_plan_id);
  if v_from is null then
    raise exception
      'plan_not_linkable: this installment has nothing left to reimburse';
  end if;

  insert into app_finance.installment_responsibility_links (
    user_id, plan_id, link_type, network_connection_id, responsible_user_id,
    status, responsibility_from_sequence, plan_revision_at_request,
    request_snapshot, shared_note
  ) values (
    v_user_id, p_plan_id, 'network', p_network_connection_id, v_responsible,
    'pending', v_from, v_plan.revision,
    app_private.build_responsibility_snapshot(p_plan_id, v_from),
    nullif(btrim(coalesce(p_shared_note, '')), '')
  )
  returning id into v_link_id;

  select coalesce(nullif(pr.display_name, ''), 'Someone') into v_owner_name
    from app_core.profiles pr where pr.id = v_user_id;

  perform app_private.enqueue_network_notification(
    v_responsible, 'installment_link', v_link_id,
    'installment_link_request',
    jsonb_build_object(
      'type', 'installment_link_request',
      'reminder_kind', 'installment_link_request',
      'counterparty_name', v_owner_name,
      'plan_title', v_plan.title
    )
  );

  return v_link_id;
end;
$$;

-- Consent: only the intended network user, only while pending, only while
-- the connection is still active, and only if the material terms are still
-- exactly what was reviewed. Acceptance changes no balance and creates no
-- financial transaction.
create or replace function app_finance.accept_installment_responsibility(
  p_link_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_link app_finance.installment_responsibility_links%rowtype;
  v_plan app_finance.installment_plans%rowtype;
  v_current_fingerprint text;
  v_alias text;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_link
    from app_finance.installment_responsibility_links l
    where l.id = p_link_id
      and v_user_id in (l.user_id, l.responsible_user_id)
    for update;
  if v_link is null then
    raise exception 'not_found: installment link request';
  end if;
  if v_link.link_type <> 'network'
    or v_link.responsible_user_id is distinct from v_user_id then
    raise exception
      'not_authorized: only the responsible person can respond';
  end if;
  if v_link.status = 'accepted' and v_link.removed_at is null then
    return v_link.id;
  end if;
  if v_link.status <> 'pending' or v_link.removed_at is not null then
    raise exception 'already_decided: this request was already handled';
  end if;
  if v_link.network_connection_id is null or not exists (
    select 1 from app_finance.network_connections c
    where c.id = v_link.network_connection_id and c.removed_at is null
  ) then
    raise exception
      'network_destination_unavailable: this request can no longer be accepted';
  end if;

  select * into v_plan
    from app_finance.installment_plans p
    where p.id = v_link.plan_id
    for update;
  if v_plan is null or v_plan.status <> 'active' then
    raise exception
      'plan_not_linkable: this installment can no longer be linked';
  end if;

  v_current_fingerprint := app_private.responsibility_terms_fingerprint(
    v_link.plan_id, v_link.responsibility_from_sequence
  );
  if v_current_fingerprint
      is distinct from (v_link.request_snapshot ->> 'terms_fingerprint') then
    raise exception
      'terms_changed: this installment changed after the request was sent';
  end if;

  update app_finance.installment_responsibility_links
    set status = 'accepted', accepted_at = now(), responded_at = now()
    where id = v_link.id;

  v_alias := app_private.responsibility_counterparty_name(
    v_link, v_link.user_id
  );
  perform app_private.enqueue_network_notification(
    v_link.user_id, 'installment_link', v_link.id,
    'installment_link_accepted',
    jsonb_build_object(
      'type', 'installment_link_accepted',
      'reminder_kind', 'installment_link_accepted',
      'counterparty_name', v_alias,
      'plan_title', v_link.request_snapshot ->> 'title'
    )
  );

  return v_link.id;
end;
$$;

create or replace function app_finance.reject_installment_responsibility(
  p_link_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_link app_finance.installment_responsibility_links%rowtype;
  v_alias text;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_link
    from app_finance.installment_responsibility_links l
    where l.id = p_link_id
      and v_user_id in (l.user_id, l.responsible_user_id)
    for update;
  if v_link is null then
    raise exception 'not_found: installment link request';
  end if;
  if v_link.link_type <> 'network'
    or v_link.responsible_user_id is distinct from v_user_id then
    raise exception
      'not_authorized: only the responsible person can respond';
  end if;
  if v_link.status <> 'pending' then
    raise exception 'already_decided: this request was already handled';
  end if;

  -- Rejection is allowed even after the connection was removed: it only
  -- closes the shared request object and changes nothing financial.
  update app_finance.installment_responsibility_links
    set status = 'rejected', rejected_at = now(), responded_at = now()
    where id = v_link.id;

  v_alias := app_private.responsibility_counterparty_name(
    v_link, v_link.user_id
  );
  perform app_private.enqueue_network_notification(
    v_link.user_id, 'installment_link', v_link.id,
    'installment_link_rejected',
    jsonb_build_object(
      'type', 'installment_link_rejected',
      'reminder_kind', 'installment_link_rejected',
      'counterparty_name', v_alias,
      'plan_title', v_link.request_snapshot ->> 'title'
    )
  );
end;
$$;

-- Owner-side unlink: soft removal. Future responsibility ends, shared access
-- ends, history (including reimbursements) stays exactly as recorded.
create or replace function app_finance.remove_installment_responsibility(
  p_link_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_link app_finance.installment_responsibility_links%rowtype;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_link
    from app_finance.installment_responsibility_links l
    where l.id = p_link_id and l.user_id = v_user_id
    for update;
  if v_link is null then
    raise exception 'not_found: installment link';
  end if;
  if v_link.removed_at is not null then
    return;
  end if;
  if exists (
    select 1 from app_finance.installment_reimbursements r
    where r.responsibility_link_id = v_link.id and r.status = 'pending'
  ) then
    raise exception
      'reimbursement_pending: resolve the pending reimbursement before unlinking';
  end if;

  update app_finance.installment_responsibility_links
    set removed_at = now()
    where id = v_link.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Shared read RPCs (the narrow privacy surface)
-- ---------------------------------------------------------------------------

-- Everything the responsible person may see about the linked installment,
-- and the owner's view of the same link. Verifies the caller is one of the
-- two parties; a removed connection ends the responsible user's access to
-- pending requests but keeps their accepted history readable.
create or replace function app_finance.get_shared_installment_link_details(
  p_link_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_link app_finance.installment_responsibility_links%rowtype;
  v_plan record;
  v_current jsonb;
  v_current_fingerprint text;
  v_summary record;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_link
    from app_finance.installment_responsibility_links l
    where l.id = p_link_id
      and v_user_id in (l.user_id, l.responsible_user_id);
  if v_link is null then
    raise exception 'not_found: installment link';
  end if;
  if v_user_id = v_link.responsible_user_id
    and v_link.status = 'pending'
    and (v_link.removed_at is not null or v_link.network_connection_id is null
      or not exists (
        select 1 from app_finance.network_connections c
        where c.id = v_link.network_connection_id and c.removed_at is null
      )) then
    raise exception 'not_found: installment link';
  end if;

  select p.status into v_plan
    from app_finance.installment_plans p where p.id = v_link.plan_id;

  v_current_fingerprint := app_private.responsibility_terms_fingerprint(
    v_link.plan_id, v_link.responsibility_from_sequence
  );
  v_current := app_private.build_responsibility_snapshot(
    v_link.plan_id, v_link.responsibility_from_sequence
  );

  select
      coalesce(sum((e.value ->> 'amount_minor')::bigint), 0)::bigint
        as expected_minor,
      coalesce(sum((e.value ->> 'received_minor')::bigint), 0)::bigint
        as received_minor,
      coalesce(sum((e.value ->> 'pending_minor')::bigint), 0)::bigint
        as pending_minor,
      coalesce(sum((e.value ->> 'remaining_minor')::bigint), 0)::bigint
        as remaining_minor
    into v_summary
    from jsonb_array_elements(
      app_private.responsibility_due_schedule(v_link)) e;

  return jsonb_build_object(
    'link', jsonb_build_object(
      'id', v_link.id,
      'link_type', v_link.link_type,
      'status', v_link.status,
      'viewer_role', case when v_user_id = v_link.user_id
        then 'owner' else 'responsible' end,
      'counterparty_name', app_private.responsibility_counterparty_name(
        v_link, v_user_id),
      'shared_note', v_link.shared_note,
      'responsibility_from_sequence', v_link.responsibility_from_sequence,
      'plan_revision_at_request', v_link.plan_revision_at_request,
      'requested_at', v_link.requested_at,
      'responded_at', v_link.responded_at,
      'accepted_at', v_link.accepted_at,
      'rejected_at', v_link.rejected_at,
      'removed_at', v_link.removed_at,
      'connection_active', (v_link.link_type = 'custom' or exists (
        select 1 from app_finance.network_connections c
        where c.id = v_link.network_connection_id and c.removed_at is null
      ))
    ),
    'snapshot', v_link.request_snapshot,
    'current', v_current || jsonb_build_object(
      'plan_status', v_plan.status,
      'terms_changed', v_current_fingerprint
        is distinct from (v_link.request_snapshot ->> 'terms_fingerprint')
    ),
    'schedule', app_private.responsibility_due_schedule(v_link),
    'reimbursement_summary', jsonb_build_object(
      'expected_total_minor', v_summary.expected_minor,
      'received_total_minor', v_summary.received_minor,
      'pending_total_minor', v_summary.pending_minor,
      'remaining_total_minor', v_summary.remaining_minor
    )
  );
end;
$$;

-- The responsible user's list: pending requests to review plus accepted
-- links, each with sanitized headline facts only. Removed links and links
-- through removed connections drop out (history stays in the tables and in
-- the owner's view; this is the active surface).
create or replace function app_finance.list_my_linked_installments()
returns table (
  link_id uuid,
  status app_finance.responsibility_link_status,
  owner_name text,
  plan_title text,
  currency_code text,
  remaining_count integer,
  remaining_total_minor bigint,
  next_due_on date,
  next_due_amount_minor bigint,
  requested_at timestamptz,
  accepted_at timestamptz,
  terms_changed boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    l.id,
    l.status,
    app_private.responsibility_counterparty_name(l, (select auth.uid())),
    l.request_snapshot ->> 'title',
    l.request_snapshot ->> 'currency_code',
    (select count(*)::integer
      from jsonb_array_elements(app_private.responsibility_due_schedule(l)) e
      where (e.value ->> 'remaining_minor')::bigint > 0),
    (select coalesce(sum((e.value ->> 'remaining_minor')::bigint), 0)::bigint
      from jsonb_array_elements(app_private.responsibility_due_schedule(l)) e),
    (select min((e.value ->> 'due_on')::date)
      from jsonb_array_elements(app_private.responsibility_due_schedule(l)) e
      where (e.value ->> 'remaining_minor')::bigint > 0),
    (select (array_agg((e.value ->> 'amount_minor')::bigint
        order by (e.value ->> 'due_on')::date))[1]
      from jsonb_array_elements(app_private.responsibility_due_schedule(l)) e
      where (e.value ->> 'remaining_minor')::bigint > 0),
    l.requested_at,
    l.accepted_at,
    app_private.responsibility_terms_fingerprint(
      l.plan_id, l.responsibility_from_sequence)
      is distinct from (l.request_snapshot ->> 'terms_fingerprint')
  from app_finance.installment_responsibility_links l
  where (select auth.uid()) is not null
    and l.responsible_user_id = (select auth.uid())
    and l.link_type = 'network'
    and l.removed_at is null
    and l.status in ('pending', 'accepted')
    and exists (
      select 1 from app_finance.network_connections c
      where c.id = l.network_connection_id and c.removed_at is null
    )
  order by l.status, l.requested_at desc, l.id desc;
$$;

-- The owner's link rows for one plan (current chip + concise history).
create or replace function app_finance.list_installment_responsibility_links(
  p_plan_id uuid
)
returns table (
  link_id uuid,
  link_type app_finance.responsibility_link_type,
  status app_finance.responsibility_link_status,
  display_name text,
  shared_note text,
  responsibility_from_sequence integer,
  requested_at timestamptz,
  accepted_at timestamptz,
  rejected_at timestamptz,
  removed_at timestamptz,
  terms_changed boolean,
  expected_total_minor bigint,
  received_total_minor bigint,
  pending_total_minor bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    l.id,
    l.link_type,
    l.status,
    app_private.responsibility_counterparty_name(l, l.user_id),
    l.shared_note,
    l.responsibility_from_sequence,
    l.requested_at,
    l.accepted_at,
    l.rejected_at,
    l.removed_at,
    (l.status = 'accepted' and l.removed_at is null
      and app_private.responsibility_terms_fingerprint(
        l.plan_id, l.responsibility_from_sequence)
        is distinct from (l.request_snapshot ->> 'terms_fingerprint')),
    (select coalesce(sum((e.value ->> 'amount_minor')::bigint), 0)::bigint
      from jsonb_array_elements(app_private.responsibility_due_schedule(l)) e),
    coalesce((select sum(r.amount_minor)
      from app_finance.installment_reimbursements r
      where r.responsibility_link_id = l.id and r.status = 'received'),
      0)::bigint,
    coalesce((select sum(r.amount_minor)
      from app_finance.installment_reimbursements r
      where r.responsibility_link_id = l.id and r.status = 'pending'),
      0)::bigint
  from app_finance.installment_responsibility_links l
  where (select auth.uid()) is not null
    and l.user_id = (select auth.uid())
    and l.plan_id = p_plan_id
  order by l.created_at desc, l.id desc;
$$;

-- ---------------------------------------------------------------------------
-- Reimbursement RPCs
-- ---------------------------------------------------------------------------

-- Shared validation for a reimbursement against one due of a linked plan.
-- Returns the due row and enforces the overpayment rule: received plus
-- pending — across every link the plan ever had, so a reassigned plan can
-- never collect the same due twice — never exceeds the canonical amount.
create or replace function app_private.validate_reimbursement_due(
  p_link app_finance.installment_responsibility_links,
  p_due_id uuid,
  p_amount_minor bigint
)
returns app_finance.installment_dues
language plpgsql
set search_path = ''
as $$
declare
  v_due app_finance.installment_dues%rowtype;
  v_used bigint;
begin
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'invalid_amount: must be positive';
  end if;

  select * into v_due
    from app_finance.installment_dues d
    where d.id = p_due_id and d.plan_id = p_link.plan_id
    for update;
  if v_due is null then
    raise exception 'not_found: installment due';
  end if;
  if v_due.is_presettled
    or v_due.sequence_number < p_link.responsibility_from_sequence then
    raise exception
      'due_not_linked: this installment is outside the linked responsibility';
  end if;

  select coalesce(sum(r.amount_minor), 0) into v_used
    from app_finance.installment_reimbursements r
    where r.due_id = p_due_id
      and r.status in ('pending', 'received');
  if v_used + p_amount_minor > v_due.amount_minor then
    raise exception
      'reimbursement_exceeds_due: amount is larger than the remaining responsibility';
  end if;

  return v_due;
end;
$$;

revoke execute on function app_private.validate_reimbursement_due(
  app_finance.installment_responsibility_links, uuid, bigint
) from public, anon, authenticated;

-- Owner records a reimbursement received outside Finance Suit from a custom
-- person (cash, external bank, ...). Books a protected one-sided transfer
-- into one of the owner's own asset accounts: the asset rises, income totals
-- do not move, and the Credit Card / BNPL liability stays exactly as it was.
create or replace function
  app_finance.record_custom_installment_reimbursement(
  p_link_id uuid,
  p_due_id uuid,
  p_amount_minor bigint,
  p_received_on date,
  p_destination_account_id uuid,
  p_note text default null,
  p_reimbursement_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_link app_finance.installment_responsibility_links%rowtype;
  v_plan record;
  v_due app_finance.installment_dues%rowtype;
  v_destination record;
  v_reimbursement_id uuid;
  v_tx_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  -- Retry-safe: resubmitting the same reimbursement id returns it again.
  if p_reimbursement_id is not null then
    select r.id into v_reimbursement_id
      from app_finance.installment_reimbursements r
      where r.id = p_reimbursement_id and r.user_id = v_user_id;
    if v_reimbursement_id is not null then
      return v_reimbursement_id;
    end if;
  end if;

  select * into v_link
    from app_finance.installment_responsibility_links l
    where l.id = p_link_id and l.user_id = v_user_id
    for update;
  if v_link is null then
    raise exception 'not_found: installment link';
  end if;
  if v_link.link_type <> 'custom' then
    raise exception
      'invalid_link: network reimbursements arrive through network transfers';
  end if;
  if v_link.status <> 'accepted' or v_link.removed_at is not null then
    raise exception 'link_not_active: this link is no longer active';
  end if;

  select p.status, p.currency_code into v_plan
    from app_finance.installment_plans p
    where p.id = v_link.plan_id and p.user_id = v_user_id
    for update;
  if v_plan.status = 'cancelled' then
    raise exception
      'plan_not_linkable: a cancelled installment has nothing to reimburse';
  end if;

  v_due := app_private.validate_reimbursement_due(
    v_link, p_due_id, p_amount_minor
  );

  select a.id, a.currency_code, a.account_type into v_destination
    from app_finance.accounts a
    where a.id = p_destination_account_id and a.user_id = v_user_id
      and not a.is_archived
    for update;
  if v_destination is null then
    raise exception 'invalid_account: destination not found or archived';
  end if;
  if app_finance.account_role(v_destination.account_type) <> 'asset' then
    raise exception
      'invalid_account: reimbursements are received into an asset account';
  end if;
  if v_destination.currency_code <> v_plan.currency_code then
    raise exception
      'currency_mismatch: pick an account in the installment currency';
  end if;
  if p_received_on is null or p_received_on > current_date then
    raise exception 'invalid_date: the received date cannot be in the future';
  end if;

  insert into app_finance.installment_reimbursements (
    id, user_id, plan_id, due_id, due_sequence_number,
    responsibility_link_id, amount_minor, currency_code, method, status,
    owner_destination_account_id, note, received_on
  ) values (
    coalesce(p_reimbursement_id, gen_random_uuid()), v_user_id,
    v_link.plan_id, v_due.id, v_due.sequence_number, v_link.id,
    p_amount_minor, v_plan.currency_code, 'manual_external', 'received',
    p_destination_account_id,
    nullif(btrim(coalesce(p_note, '')), ''), p_received_on
  )
  returning id into v_reimbursement_id;

  perform set_config('app_finance.responsibility_internal', 'on', true);

  insert into app_finance.financial_transactions (
    user_id, transaction_kind, occurred_on, amount_minor, currency_code,
    destination_account_id, counterparty, title, notes,
    is_reimbursement_inflow, installment_reimbursement_id
  ) values (
    v_user_id, 'transfer', p_received_on, p_amount_minor,
    v_plan.currency_code, p_destination_account_id, v_link.custom_name,
    'Installment reimbursement',
    nullif(btrim(coalesce(p_note, '')), ''),
    true, v_reimbursement_id
  )
  returning id into v_tx_id;

  perform set_config('app_finance.responsibility_internal', '', true);

  update app_finance.installment_reimbursements
    set owner_transaction_id = v_tx_id
    where id = v_reimbursement_id;

  return v_reimbursement_id;
end;
$$;

-- The responsible network user sends a reimbursement for one linked due
-- from one of their own asset accounts, through the existing network
-- transfer rail: pending moves nothing, and only the owner's acceptance
-- books the two one-sided ledger legs.
create or replace function
  app_finance.create_installment_network_reimbursement(
  p_link_id uuid,
  p_due_id uuid,
  p_amount_minor bigint,
  p_source_account_id uuid,
  p_note text default null,
  p_reimbursement_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_link app_finance.installment_responsibility_links%rowtype;
  v_plan record;
  v_due app_finance.installment_dues%rowtype;
  v_source_currency text;
  v_reimbursement_id uuid;
  v_transfer_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_reimbursement_id is not null then
    select r.id into v_reimbursement_id
      from app_finance.installment_reimbursements r
      where r.id = p_reimbursement_id
        and r.responsible_user_id = v_user_id;
    if v_reimbursement_id is not null then
      return v_reimbursement_id;
    end if;
  end if;

  select * into v_link
    from app_finance.installment_responsibility_links l
    where l.id = p_link_id and l.responsible_user_id = v_user_id
    for update;
  if v_link is null then
    raise exception 'not_found: installment link';
  end if;
  if v_link.link_type <> 'network' then
    raise exception 'invalid_link: not a network responsibility';
  end if;
  if v_link.status <> 'accepted' or v_link.removed_at is not null then
    raise exception 'link_not_active: this link is no longer active';
  end if;
  if v_link.network_connection_id is null then
    raise exception
      'network_destination_unavailable: this contact is no longer connected';
  end if;

  select p.status, p.currency_code into v_plan
    from app_finance.installment_plans p where p.id = v_link.plan_id;
  if v_plan.status = 'cancelled' then
    raise exception
      'plan_not_linkable: a cancelled installment has nothing to reimburse';
  end if;

  -- Materially changed terms block new money until re-consent: the linked
  -- person never silently pays terms they did not review.
  if app_private.responsibility_terms_fingerprint(
      v_link.plan_id, v_link.responsibility_from_sequence)
      is distinct from (v_link.request_snapshot ->> 'terms_fingerprint') then
    raise exception
      'terms_changed: this installment changed after you accepted it';
  end if;

  v_due := app_private.validate_reimbursement_due(
    v_link, p_due_id, p_amount_minor
  );

  -- The transfer will carry the source account's currency; it must be the
  -- installment's currency so the reimbursement settles what is owed.
  select a.currency_code into v_source_currency
    from app_finance.accounts a
    where a.id = p_source_account_id and a.user_id = v_user_id;
  if v_source_currency is distinct from v_plan.currency_code then
    raise exception
      'currency_mismatch: pick an account in the installment currency';
  end if;

  insert into app_finance.installment_reimbursements (
    id, user_id, plan_id, due_id, due_sequence_number,
    responsibility_link_id, responsible_user_id, amount_minor,
    currency_code, method, status, note
  ) values (
    coalesce(p_reimbursement_id, gen_random_uuid()), v_link.user_id,
    v_link.plan_id, v_due.id, v_due.sequence_number, v_link.id,
    v_user_id, p_amount_minor, v_plan.currency_code, 'network_transfer',
    'pending', nullif(btrim(coalesce(p_note, '')), '')
  )
  returning id into v_reimbursement_id;

  -- The shared pending request object; sender identity is pinned to
  -- auth.uid() inside, and the deterministic idempotency key makes retries
  -- converge on one transfer.
  v_transfer_id := app_private.create_network_transfer(
    v_user_id, v_link.network_connection_id, p_source_account_id,
    p_amount_minor, current_date,
    coalesce(
      nullif(btrim(coalesce(p_note, '')), ''),
      (v_link.request_snapshot ->> 'title') || ' · #'
        || v_due.sequence_number
    ),
    'installment_reimbursement', v_reimbursement_id,
    'installment_reimbursement:' || v_reimbursement_id
  );

  update app_finance.installment_reimbursements
    set network_transfer_id = v_transfer_id
    where id = v_reimbursement_id;

  return v_reimbursement_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Settlement hook: network transfer decisions settle reimbursements
-- ---------------------------------------------------------------------------

-- accept_network_transfer / reject_network_transfer stay untouched; this
-- trigger closes the loop server-side so the client never has to (and never
-- can) mark a reimbursement received. Acceptance already moved the money
-- through the two one-sided network legs; here only the reimbursement state
-- and the audit links change — the facility liability, installment dues,
-- and payment allocations are untouched by design.
create or replace function app_private.settle_reimbursement_from_transfer()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.origin_kind <> 'installment_reimbursement'
    or new.status = old.status then
    return new;
  end if;

  if new.status = 'accepted' then
    update app_finance.installment_reimbursements r
      set status = 'received',
        received_on = current_date,
        owner_destination_account_id = new.receiver_destination_account_id,
        owner_transaction_id = new.receiver_transaction_id
      where r.id = new.origin_id and r.status = 'pending';
  elsif new.status = 'rejected' then
    update app_finance.installment_reimbursements r
      set status = 'rejected'
      where r.id = new.origin_id and r.status = 'pending';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_settle_reimbursement_from_transfer
  on app_finance.network_transfers;
create trigger trg_settle_reimbursement_from_transfer
  after update on app_finance.network_transfers
  for each row execute function
    app_private.settle_reimbursement_from_transfer();

revoke execute on function app_private.settle_reimbursement_from_transfer()
  from public, anon, authenticated;

-- A withdrawn pending transfer (peer deletion) leaves the reimbursement
-- resolvable again instead of stuck pending.
create or replace function app_private.release_reimbursement_on_transfer_delete()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.origin_kind = 'installment_reimbursement'
    and old.status = 'pending' then
    update app_finance.installment_reimbursements r
      set status = 'rejected'
      where r.id = old.origin_id and r.status = 'pending';
  end if;
  return old;
end;
$$;

drop trigger if exists trg_release_reimbursement_on_transfer_delete
  on app_finance.network_transfers;
create trigger trg_release_reimbursement_on_transfer_delete
  before delete on app_finance.network_transfers
  for each row execute function
    app_private.release_reimbursement_on_transfer_delete();

revoke execute on function
  app_private.release_reimbursement_on_transfer_delete()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Owner summary view (chips and reimbursement badges without N+1)
-- ---------------------------------------------------------------------------

create or replace view app_finance.installment_plan_responsibility_summaries
with (security_invoker = on) as
  select
    l.plan_id,
    l.user_id,
    l.id as link_id,
    l.link_type,
    l.status,
    app_finance.responsibility_display_name(l.id) as display_name,
    l.responsibility_from_sequence,
    l.requested_at,
    l.accepted_at,
    l.rejected_at,
    coalesce(recv.received_minor, 0)::bigint as received_total_minor,
    coalesce(recv.pending_minor, 0)::bigint as pending_total_minor,
    coalesce(expected.expected_minor, 0)::bigint as expected_total_minor,
    greatest(coalesce(expected.expected_minor, 0)
      - coalesce(recv.received_minor, 0), 0)::bigint
      as expected_remaining_minor
  from app_finance.installment_responsibility_links l
  left join lateral (
    select
      sum(r.amount_minor) filter (where r.status = 'received')
        as received_minor,
      sum(r.amount_minor) filter (where r.status = 'pending')
        as pending_minor
    from app_finance.installment_reimbursements r
    where r.responsibility_link_id = l.id
  ) recv on true
  left join lateral (
    select sum(d.amount_minor) as expected_minor
    from app_finance.installment_dues d
    where d.plan_id = l.plan_id
      and d.sequence_number >= l.responsibility_from_sequence
      and not d.is_presettled
  ) expected on true
  where l.removed_at is null and l.status in ('pending', 'accepted', 'rejected');

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
      'network_add_request', 'network_transfer', 'installment_link'
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
      'network_transfer_rejected',
      'installment_link_request', 'installment_link_accepted',
      'installment_link_rejected'
    )
  );

-- ---------------------------------------------------------------------------
-- Deletion cascade
-- ---------------------------------------------------------------------------

-- The departing user's own plans take their links and reimbursement history
-- with them (deleted before the plans so the linked-plan guard passes).
-- Links where the departing user was the responsible person are only closed:
-- the owner keeps the full auditable history of who reimbursed what.
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
  perform set_config('app_finance.responsibility_internal', 'on', true);

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

  update app_finance.installment_responsibility_links
    set removed_at = now()
    where responsible_user_id = p_user_id and removed_at is null;

  delete from app_finance.installment_reimbursements
    where user_id = p_user_id;
  delete from app_finance.installment_responsibility_links
    where user_id = p_user_id;

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
  perform set_config('app_finance.responsibility_internal', '', true);
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
-- Function grants
-- ---------------------------------------------------------------------------

revoke execute on function app_finance.responsibility_display_name(uuid)
  from public, anon;
grant execute on function app_finance.responsibility_display_name(uuid)
  to authenticated, service_role;

revoke execute on function app_finance.link_installment_to_custom_person(
  uuid, text, text
) from public, anon;
grant execute on function app_finance.link_installment_to_custom_person(
  uuid, text, text
) to authenticated, service_role;

revoke execute on function app_finance.request_installment_responsibility(
  uuid, uuid, text
) from public, anon;
grant execute on function app_finance.request_installment_responsibility(
  uuid, uuid, text
) to authenticated, service_role;

revoke execute on function app_finance.accept_installment_responsibility(uuid)
  from public, anon;
grant execute on function app_finance.accept_installment_responsibility(uuid)
  to authenticated, service_role;

revoke execute on function app_finance.reject_installment_responsibility(uuid)
  from public, anon;
grant execute on function app_finance.reject_installment_responsibility(uuid)
  to authenticated, service_role;

revoke execute on function app_finance.remove_installment_responsibility(uuid)
  from public, anon;
grant execute on function app_finance.remove_installment_responsibility(uuid)
  to authenticated, service_role;

revoke execute on function app_finance.get_shared_installment_link_details(
  uuid
) from public, anon;
grant execute on function app_finance.get_shared_installment_link_details(
  uuid
) to authenticated, service_role;

revoke execute on function app_finance.list_my_linked_installments()
  from public, anon;
grant execute on function app_finance.list_my_linked_installments()
  to authenticated, service_role;

revoke execute on function
  app_finance.list_installment_responsibility_links(uuid)
  from public, anon;
grant execute on function
  app_finance.list_installment_responsibility_links(uuid)
  to authenticated, service_role;

revoke execute on function
  app_finance.record_custom_installment_reimbursement(
    uuid, uuid, bigint, date, uuid, text, uuid
  ) from public, anon;
grant execute on function
  app_finance.record_custom_installment_reimbursement(
    uuid, uuid, bigint, date, uuid, text, uuid
  ) to authenticated, service_role;

revoke execute on function
  app_finance.create_installment_network_reimbursement(
    uuid, uuid, bigint, uuid, text, uuid
  ) from public, anon;
grant execute on function
  app_finance.create_installment_network_reimbursement(
    uuid, uuid, bigint, uuid, text, uuid
  ) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'installment_responsibility_links',
    'installment_reimbursements'
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
