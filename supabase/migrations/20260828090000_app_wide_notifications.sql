-- App-wide notification subsystem.
--
-- Before this migration a "notification" was a row in
-- `app_core.notification_outbox`, which is a *per-device push delivery*
-- record. That conflated three different things:
--
--   * a user with two phones saw the same notification twice in the
--     Notification Center;
--   * a user with no registered device (push denied, iOS, fresh install)
--     had no notification history at all;
--   * history only appeared once FCM had accepted the message, so a push
--     outage silently swallowed the in-app record too.
--
-- This migration introduces `app_core.notifications` as the single logical
-- notification per user, keeps `notification_outbox` as the per-device
-- delivery queue that now points at it, and routes every producer through
-- one authoritative creation function. It is forward-only: existing outbox
-- rows are backfilled into logical notifications with their original
-- timestamps and read state, and legacy-shaped rows keep working.

-- ---------------------------------------------------------------------------
-- Event catalog: the single source of truth for notification event keys
-- ---------------------------------------------------------------------------

-- Machine keys are stable and never user-visible. Human text is composed by
-- the sender (Edge Function) and localized by the client from `event_key`.
create table if not exists app_core.notification_event_catalog (
  event_key text primary key check (
    event_key ~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$'
  ),
  category text not null check (
    category in ('due', 'overdue', 'payment', 'network', 'system', 'security')
  ),
  -- Critical events are always written to the in-app history. The user may
  -- still silence the push channel for them; the Settings UI states this.
  is_critical boolean not null default false,
  entity_type text check (char_length(entity_type) <= 64),
  created_at timestamptz not null default now(),
  constraint notification_event_catalog_key_category_unique
    unique (event_key, category)
);

insert into app_core.notification_event_catalog
  (event_key, category, is_critical, entity_type)
values
  ('credit_card.statement_due_soon',  'due',      false, 'credit_card_statement'),
  ('credit_card.statement_due_today', 'due',      false, 'credit_card_statement'),
  ('credit_card.statement_overdue',   'overdue',  false, 'credit_card_statement'),
  ('installment.due_soon',            'due',      false, 'installment_due'),
  ('installment.due_today',           'due',      false, 'installment_due'),
  ('installment.overdue',             'overdue',  false, 'installment_due'),
  ('bnpl.due_soon',                   'due',      false, 'installment_due'),
  ('bnpl.due_today',                  'due',      false, 'installment_due'),
  ('bnpl.overdue',                    'overdue',  false, 'installment_due'),
  ('facility.payment_recorded',       'payment',  false, 'financial_transaction'),
  ('network.add_request_received',    'network',  false, 'network_add_request'),
  ('network.add_request_accepted',    'network',  false, 'network_add_request'),
  ('network.transfer_received',       'network',  false, 'network_transfer'),
  ('network.transfer_accepted',       'network',  false, 'network_transfer'),
  ('network.transfer_declined',       'network',  false, 'network_transfer'),
  ('installment_link.request_received', 'network', false, 'installment_link'),
  ('installment_link.accepted',       'network',  false, 'installment_link'),
  ('installment_link.declined',       'network',  false, 'installment_link'),
  ('system.developer_test',           'system',   false, null)
on conflict (event_key) do update
  set category = excluded.category,
      is_critical = excluded.is_critical,
      entity_type = excluded.entity_type;

alter table app_core.notification_event_catalog enable row level security;

-- The catalog is reference data, not user data: the Settings screen reads it
-- so it can only offer categories the backend actually supports.
drop policy if exists notification_event_catalog_select
  on app_core.notification_event_catalog;
create policy notification_event_catalog_select
  on app_core.notification_event_catalog
  for select to authenticated using (true);

revoke insert, update, delete on table app_core.notification_event_catalog
  from authenticated;
grant select on table app_core.notification_event_catalog to authenticated;

-- ---------------------------------------------------------------------------
-- Logical notifications: exactly one row per user per logical event
-- ---------------------------------------------------------------------------

create table if not exists app_core.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  event_key text not null,
  category text not null,
  entity_type text check (char_length(entity_type) <= 64),
  entity_id uuid,
  -- Resolved in-app destination. The client still validates the shape and
  -- re-reads the target under RLS; a payload is never authorization.
  route text check (char_length(route) <= 512),
  payload jsonb not null default '{}'::jsonb,
  -- Deterministic logical identity. Every producer derives it from
  -- (event + entity + occurrence) so retries, cron reruns, trigger replays
  -- and concurrent workers converge on one row.
  dedupe_key text not null check (char_length(dedupe_key) between 1 and 512),
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint notifications_dedupe_unique unique (user_id, dedupe_key),
  constraint notifications_event_category_fk
    foreign key (event_key, category)
    references app_core.notification_event_catalog (event_key, category)
);

-- Newest-first keyset pagination for the Notification Center.
create index if not exists idx_notifications_history
  on app_core.notifications (user_id, created_at desc, id desc);

-- Authoritative unread count without reading the history pages.
create index if not exists idx_notifications_unread
  on app_core.notifications (user_id, created_at desc, id desc)
  where read_at is null;

create index if not exists idx_notifications_entity
  on app_core.notifications (user_id, entity_type, entity_id)
  where entity_id is not null;

alter table app_core.notifications enable row level security;

drop policy if exists notifications_select on app_core.notifications;
create policy notifications_select on app_core.notifications
  for select to authenticated using ((select auth.uid()) = user_id);

-- Read state is the only thing a client may change, and only on its own rows.
drop policy if exists notifications_update_read_state on app_core.notifications;
create policy notifications_update_read_state on app_core.notifications
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- `alter default privileges` in this schema grants full DML on new tables.
-- Notifications are system-authored: strip everything back to reading the
-- row and stamping read state.
revoke all on table app_core.notifications from authenticated;
grant select on table app_core.notifications to authenticated;
grant update (read_at) on table app_core.notifications to authenticated;
grant select, insert, update, delete on table app_core.notifications
  to service_role;

-- ---------------------------------------------------------------------------
-- Outbox becomes a pure per-device delivery queue for a logical notification
-- ---------------------------------------------------------------------------

alter table app_core.notification_outbox
  add column if not exists notification_id uuid
    references app_core.notifications (id) on delete cascade;

-- The obligation columns describe the legacy device-shaped row. New rows
-- carry their meaning on the logical notification instead.
alter table app_core.notification_outbox
  alter column obligation_type drop not null,
  alter column obligation_id drop not null,
  alter column reminder_kind drop not null,
  alter column scheduled_local_date drop not null;

alter table app_core.notification_outbox
  drop constraint if exists notification_outbox_shape;
alter table app_core.notification_outbox
  add constraint notification_outbox_shape check (
    notification_id is not null
    or (
      obligation_type is not null
      and obligation_id is not null
      and reminder_kind is not null
      and scheduled_local_date is not null
    )
  );

-- One delivery attempt per (logical notification, device). This is what makes
-- worker retries and duplicate producer calls exactly-once per device.
create unique index if not exists idx_notification_outbox_notification_device
  on app_core.notification_outbox (notification_id, device_id)
  where notification_id is not null;

create index if not exists idx_notification_outbox_notification
  on app_core.notification_outbox (notification_id)
  where notification_id is not null;

-- ---------------------------------------------------------------------------
-- Channel-aware preferences
-- ---------------------------------------------------------------------------

-- The three existing switches keep their meaning as the category master
-- switch (they gate whether the notification exists at all). The new
-- `*_push_enabled` columns gate only the push channel, so a user can keep
-- in-app history while silencing their lock screen.
alter table app_core.notification_preferences
  add column if not exists due_push_enabled boolean not null default true,
  add column if not exists overdue_push_enabled boolean not null default true,
  add column if not exists payment_push_enabled boolean not null default true,
  add column if not exists network_enabled boolean not null default true,
  add column if not exists network_push_enabled boolean not null default true,
  add column if not exists system_push_enabled boolean not null default true;

-- ---------------------------------------------------------------------------
-- Preference resolution
-- ---------------------------------------------------------------------------

create or replace function app_private.notification_channel_allowed(
  p_user_id uuid,
  p_event_key text,
  p_channel text
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_catalog record;
  v_prefs record;
  v_master boolean;
  v_push boolean;
begin
  if p_user_id is null or p_channel not in ('in_app', 'push') then
    return false;
  end if;

  select c.category, c.is_critical into v_catalog
    from app_core.notification_event_catalog c
    where c.event_key = p_event_key;
  if not found then
    return false;
  end if;

  -- The left join guarantees exactly one row, so a user who never saved
  -- preferences behaves identically to the column defaults.
  select
    coalesce(p.due_reminders_enabled, true) as due_reminders_enabled,
    coalesce(p.overdue_reminders_enabled, true) as overdue_reminders_enabled,
    coalesce(p.payment_confirmations_enabled, true)
      as payment_confirmations_enabled,
    coalesce(p.network_enabled, true) as network_enabled,
    coalesce(p.due_push_enabled, true) as due_push_enabled,
    coalesce(p.overdue_push_enabled, true) as overdue_push_enabled,
    coalesce(p.payment_push_enabled, true) as payment_push_enabled,
    coalesce(p.network_push_enabled, true) as network_push_enabled,
    coalesce(p.system_push_enabled, true) as system_push_enabled
    into strict v_prefs
    from (select p_user_id as uid) s
    left join app_core.notification_preferences p on p.user_id = s.uid;

  case v_catalog.category
    when 'due' then
      v_master := v_prefs.due_reminders_enabled;
      v_push := v_prefs.due_push_enabled;
    when 'overdue' then
      v_master := v_prefs.overdue_reminders_enabled;
      v_push := v_prefs.overdue_push_enabled;
    when 'payment' then
      v_master := v_prefs.payment_confirmations_enabled;
      v_push := v_prefs.payment_push_enabled;
    when 'network' then
      v_master := v_prefs.network_enabled;
      v_push := v_prefs.network_push_enabled;
    else
      -- system and security categories are always recorded in-app.
      v_master := true;
      v_push := v_prefs.system_push_enabled;
  end case;

  if v_catalog.is_critical then
    v_master := true;
  end if;

  if p_channel = 'in_app' then
    return v_master;
  end if;
  return v_master and v_push;
end;
$$;

revoke execute on function app_private.notification_channel_allowed(
  uuid, text, text
) from public, anon, authenticated;
grant execute on function app_private.notification_channel_allowed(
  uuid, text, text
) to service_role;

-- ---------------------------------------------------------------------------
-- Per-user timezone and locale for scheduling and composition
-- ---------------------------------------------------------------------------

-- Scheduling must follow the *user's* configured timezone, not whichever
-- device happened to register last. `app_core.user_preferences` already owns
-- that setting; devices are only a fallback for users who never saved one.
create or replace function app_core.notification_user_context(
  p_user_ids uuid[] default null
)
returns table (user_id uuid, timezone text, locale text)
language sql
stable
security definer
set search_path = ''
as $$
  select
    u.id,
    coalesce(
      nullif(p.timezone, ''),
      nullif(d.timezone, ''),
      'Africa/Cairo'
    ),
    coalesce(nullif(p.locale, ''), nullif(d.locale, ''), 'en')
  from auth.users u
  left join app_core.user_preferences p on p.user_id = u.id
  left join lateral (
    select dd.timezone, dd.locale
    from app_core.push_devices dd
    where dd.user_id = u.id and dd.is_enabled
    order by dd.last_seen_at desc
    limit 1
  ) d on true
  where p_user_ids is null or u.id = any (p_user_ids);
$$;

revoke all on function app_core.notification_user_context(uuid[]) from public;
revoke all on function app_core.notification_user_context(uuid[]) from anon;
revoke all on function app_core.notification_user_context(uuid[])
  from authenticated;
grant execute on function app_core.notification_user_context(uuid[])
  to service_role;

-- ---------------------------------------------------------------------------
-- The single authoritative notification creation path
-- ---------------------------------------------------------------------------

create or replace function app_private.create_notification(
  p_user_id uuid,
  p_event_key text,
  p_dedupe_key text,
  p_payload jsonb default '{}'::jsonb,
  p_entity_type text default null,
  p_entity_id uuid default null,
  p_route text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_catalog record;
  v_notification_id uuid;
  v_created boolean := false;
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
begin
  if p_user_id is null then
    raise exception 'notification_user_required';
  end if;
  if p_dedupe_key is null or char_length(p_dedupe_key) = 0 then
    raise exception 'notification_dedupe_key_required';
  end if;

  select c.event_key, c.category, c.entity_type into v_catalog
    from app_core.notification_event_catalog c
    where c.event_key = p_event_key;
  if not found then
    raise exception 'unknown_notification_event_key: %', p_event_key;
  end if;

  if not app_private.notification_channel_allowed(
    p_user_id, p_event_key, 'in_app'
  ) then
    return null;
  end if;

  v_payload := v_payload
    || jsonb_build_object('event_key', p_event_key, 'category', v_catalog.category);

  insert into app_core.notifications (
    user_id, event_key, category, entity_type, entity_id, route, payload,
    dedupe_key
  ) values (
    p_user_id,
    p_event_key,
    v_catalog.category,
    coalesce(p_entity_type, v_catalog.entity_type),
    p_entity_id,
    p_route,
    v_payload,
    p_dedupe_key
  )
  on conflict (user_id, dedupe_key) do nothing
  returning id into v_notification_id;

  if v_notification_id is not null then
    v_created := true;
  else
    -- Already created by an earlier run. Return the same logical id and do
    -- not fan out a second time; this is the idempotency guarantee.
    select n.id into v_notification_id
      from app_core.notifications n
      where n.user_id = p_user_id and n.dedupe_key = p_dedupe_key;
    return v_notification_id;
  end if;

  if v_created and app_private.notification_channel_allowed(
    p_user_id, p_event_key, 'push'
  ) then
    insert into app_core.notification_outbox (
      user_id, device_id, notification_id, status, next_attempt_at,
      payload_snapshot
    )
    select
      p_user_id,
      d.id,
      v_notification_id,
      'pending',
      now(),
      v_payload || jsonb_build_object(
        'notification_id', v_notification_id,
        'route', p_route
      )
    from app_core.push_devices d
    where d.user_id = p_user_id and d.is_enabled
    on conflict do nothing;
  end if;

  return v_notification_id;
end;
$$;

revoke execute on function app_private.create_notification(
  uuid, text, text, jsonb, text, uuid, text
) from public, anon, authenticated;
grant execute on function app_private.create_notification(
  uuid, text, text, jsonb, text, uuid, text
) to service_role;

-- Service-role entry point so the Edge Function can use the same path as
-- database triggers. Still refuses unknown event keys and still honours
-- preferences; there is no privileged bypass.
create or replace function app_core.enqueue_notification(
  p_user_id uuid,
  p_event_key text,
  p_dedupe_key text,
  p_payload jsonb default '{}'::jsonb,
  p_entity_type text default null,
  p_entity_id uuid default null,
  p_route text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is not null then
    -- Reachable only via PostgREST with a user JWT. Clients must never mint
    -- their own system notifications.
    raise exception 'forbidden';
  end if;
  return app_private.create_notification(
    p_user_id, p_event_key, p_dedupe_key, p_payload, p_entity_type,
    p_entity_id, p_route
  );
end;
$$;

revoke all on function app_core.enqueue_notification(
  uuid, text, text, jsonb, text, uuid, text
) from public;
revoke all on function app_core.enqueue_notification(
  uuid, text, text, jsonb, text, uuid, text
) from anon;
revoke all on function app_core.enqueue_notification(
  uuid, text, text, jsonb, text, uuid, text
) from authenticated;
grant execute on function app_core.enqueue_notification(
  uuid, text, text, jsonb, text, uuid, text
) to service_role;

-- ---------------------------------------------------------------------------
-- Client read APIs
-- ---------------------------------------------------------------------------

-- Authoritative unread count. Deliberately independent of which history
-- pages the Notification Center has loaded.
create or replace function app_core.unread_notification_count()
returns integer
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(count(*), 0)::integer
  from app_core.notifications n
  where n.user_id = (select auth.uid()) and n.read_at is null;
$$;

revoke all on function app_core.unread_notification_count() from public;
revoke all on function app_core.unread_notification_count() from anon;
grant execute on function app_core.unread_notification_count()
  to authenticated, service_role;

-- Marks the given notifications read, or every unread one when `p_ids` is
-- null. Server-side in a single statement so Mark All Read never becomes one
-- request per row, and returns the reconciled unread count so the badge can
-- settle in the same round trip.
create or replace function app_core.mark_notifications_read(
  p_ids uuid[] default null
)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_ids is not null and array_length(p_ids, 1) > 500 then
    raise exception 'too_many_notification_ids';
  end if;

  update app_core.notifications n
    set read_at = now()
    where n.user_id = v_user_id
      and n.read_at is null
      and (p_ids is null or n.id = any (p_ids));

  return app_core.unread_notification_count();
end;
$$;

revoke all on function app_core.mark_notifications_read(uuid[]) from public;
revoke all on function app_core.mark_notifications_read(uuid[]) from anon;
grant execute on function app_core.mark_notifications_read(uuid[])
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Delivery worker primitives
-- ---------------------------------------------------------------------------

-- Retires deliveries that have exhausted their attempt budget, including
-- rows a crashed worker left in `sending` past their lease. Without this a
-- crash between claim and result would strand a row in `sending` forever.
create or replace function app_core.reap_notification_outbox(
  p_max_attempts integer default 5,
  p_lease_seconds integer default 600
)
returns integer
language sql
security definer
set search_path = ''
as $$
  with retired as (
    update app_core.notification_outbox o
      set status = 'failed',
          permanently_failed_at = now(),
          error = 'max_attempts_exhausted',
          updated_at = now()
      where o.sent_at is null
        and o.permanently_failed_at is null
        and o.attempt_count >= greatest(p_max_attempts, 1)
        and (
          o.status in ('pending', 'retry')
          or (
            o.status = 'sending'
            and o.last_attempt_at
                < now() - make_interval(secs => greatest(p_lease_seconds, 30))
          )
        )
      returning o.id
  )
  select count(*)::integer from retired;
$$;

revoke all on function app_core.reap_notification_outbox(integer, integer)
  from public;
revoke all on function app_core.reap_notification_outbox(integer, integer)
  from anon;
revoke all on function app_core.reap_notification_outbox(integer, integer)
  from authenticated;
grant execute on function app_core.reap_notification_outbox(integer, integer)
  to service_role;

-- The previous single-argument claim could not recover leased rows and did
-- not expose the logical notification. Replaced rather than overloaded so
-- `claim_notification_outbox(batch_size := ...)` stays unambiguous.
drop function if exists app_core.claim_notification_outbox(integer);

create or replace function app_core.claim_notification_outbox(
  batch_size integer default 50,
  p_lease_seconds integer default 600,
  p_max_attempts integer default 5
)
returns table (
  id uuid,
  user_id uuid,
  device_id uuid,
  notification_id uuid,
  event_key text,
  route text,
  fcm_token text,
  platform text,
  locale text,
  timezone text,
  obligation_type text,
  obligation_id uuid,
  reminder_kind text,
  scheduled_local_date date,
  payload_snapshot jsonb,
  attempt_count integer
)
language plpgsql
set search_path = ''
as $$
begin
  return query
  with claimed as (
    select o.id
    from app_core.notification_outbox o
    join app_core.push_devices d on d.id = o.device_id
    where o.sent_at is null
      and o.permanently_failed_at is null
      and o.attempt_count < greatest(p_max_attempts, 1)
      and d.is_enabled
      and (
        (o.status in ('pending', 'retry') and o.next_attempt_at <= now())
        -- Lease recovery: a worker that claimed this row and died gets its
        -- work back once the lease expires.
        or (
          o.status = 'sending'
          and o.last_attempt_at is not null
          and o.last_attempt_at
              < now() - make_interval(secs => greatest(p_lease_seconds, 30))
        )
      )
    order by o.created_at, o.id
    limit greatest(least(batch_size, 500), 1)
    for update of o skip locked
  ), updated as (
    update app_core.notification_outbox o
      set status = 'sending',
          attempt_count = o.attempt_count + 1,
          last_attempt_at = now(),
          updated_at = now()
      from claimed
      where o.id = claimed.id
      returning o.*
  )
  select
    u.id,
    u.user_id,
    u.device_id,
    u.notification_id,
    n.event_key,
    n.route,
    d.fcm_token,
    d.platform,
    coalesce(ctx.locale, d.locale),
    coalesce(ctx.timezone, d.timezone),
    u.obligation_type,
    u.obligation_id,
    u.reminder_kind,
    u.scheduled_local_date,
    u.payload_snapshot,
    u.attempt_count
  from updated u
  join app_core.push_devices d on d.id = u.device_id
  left join app_core.notifications n on n.id = u.notification_id
  left join lateral app_core.notification_user_context(array[u.user_id]) ctx
    on true;
end;
$$;

revoke all on function app_core.claim_notification_outbox(
  integer, integer, integer
) from public;
revoke all on function app_core.claim_notification_outbox(
  integer, integer, integer
) from anon;
revoke all on function app_core.claim_notification_outbox(
  integer, integer, integer
) from authenticated;
grant execute on function app_core.claim_notification_outbox(
  integer, integer, integer
) to service_role;

-- ---------------------------------------------------------------------------
-- Legacy event mapping
-- ---------------------------------------------------------------------------

-- Existing producers speak `payload.type` + `reminder_kind`. Translate once,
-- centrally, instead of teaching every call site the new vocabulary.
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

-- Deterministic destination per event. Only routes that exist in the router
-- are produced; the client re-validates the shape before navigating.
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
-- Rewire existing producers onto the authoritative path
-- ---------------------------------------------------------------------------

-- Same signature, same call sites: the network and installment-link triggers
-- keep calling this, but it now creates one logical notification per user
-- (not one row per device) and fans out deliveries from there.
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
  v_event_key text;
begin
  v_event_key := app_private.notification_event_key_for(
    coalesce(p_payload ->> 'type', p_obligation_type), p_reminder_kind
  );
  if v_event_key is null then
    -- An unmapped producer must be loud in development rather than silently
    -- dropping a user-facing notification.
    raise exception 'unmapped_notification_event: % / %',
      p_payload ->> 'type', p_reminder_kind;
  end if;

  perform app_private.create_notification(
    p_user_id := p_user_id,
    p_event_key := v_event_key,
    -- Network and link events happen once per entity and kind, so the
    -- logical identity carries no date component: a retry on the next day
    -- still resolves to the same notification.
    p_dedupe_key := v_event_key || ':' || p_obligation_id::text,
    p_payload := p_payload,
    p_entity_id := p_obligation_id,
    p_route := app_private.notification_route_for(
      v_event_key, p_obligation_id, p_payload
    )
  );
end;
$$;

revoke execute on function app_private.enqueue_network_notification(
  uuid, text, uuid, text, jsonb
) from public, anon, authenticated;
grant execute on function app_private.enqueue_network_notification(
  uuid, text, uuid, text, jsonb
) to service_role;

-- Developer diagnostic. Still exercises the real outbox + worker + FCM path,
-- but now also lands in the Notification Center like any other event.
create or replace function app_core.enqueue_developer_test_notification(
  target_user_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := coalesce(target_user_id, (select auth.uid()));
  v_notification_id uuid;
  v_outbox_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if target_user_id is not null
     and (select auth.uid()) is not null
     and target_user_id <> (select auth.uid()) then
    raise exception 'forbidden';
  end if;

  if not exists (
    select 1 from app_core.push_devices d
    where d.user_id = v_user_id and d.is_enabled
  ) then
    raise exception 'no_enabled_push_device';
  end if;

  v_notification_id := app_private.create_notification(
    p_user_id := v_user_id,
    p_event_key := 'system.developer_test',
    -- One test notification per user per second keeps repeat taps working
    -- while still being idempotent under a retried request.
    p_dedupe_key := 'system.developer_test:'
      || to_char(date_trunc('second', now()), 'YYYYMMDDHH24MISS'),
    p_payload := jsonb_build_object(
      'type', 'developer_test', 'reminder_kind', 'due_today'
    ),
    p_route := '/home'
  );

  select o.id into v_outbox_id
    from app_core.notification_outbox o
    where o.notification_id = v_notification_id
    order by o.created_at desc
    limit 1;

  return coalesce(v_outbox_id, v_notification_id);
end;
$$;

revoke all on function app_core.enqueue_developer_test_notification(uuid)
  from public;
revoke all on function app_core.enqueue_developer_test_notification(uuid)
  from anon;
grant execute on function app_core.enqueue_developer_test_notification(uuid)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Backfill: preserve every notification the user can see today
-- ---------------------------------------------------------------------------

-- Deliveries collapse into one logical notification per
-- (user, obligation, kind, local date). The oldest row supplies created_at,
-- and read state survives if any device copy was read. Suppressed and
-- permanently failed rows were never shown and stay out of history.
with grouped as (
  select
    o.user_id,
    o.obligation_type,
    o.obligation_id,
    o.reminder_kind,
    o.scheduled_local_date,
    min(o.created_at) as created_at,
    min(o.read_at) as read_at,
    (array_agg(
      o.payload_snapshot order by o.payload_snapshot is null, o.created_at
    ))[1] as payload_snapshot
  from app_core.notification_outbox o
  where o.notification_id is null
    and o.status in ('pending', 'sending', 'retry', 'sent')
    and o.obligation_type is not null
    and o.obligation_id is not null
    and o.reminder_kind is not null
    and o.scheduled_local_date is not null
  group by 1, 2, 3, 4, 5
), resolved as (
  select
    g.*,
    app_private.notification_event_key_for(
      coalesce(g.payload_snapshot ->> 'type', g.obligation_type),
      g.reminder_kind
    ) as event_key
  from grouped g
), insertable as (
  select
    r.*,
    c.category,
    c.entity_type,
    r.event_key || ':' || r.obligation_id::text || ':'
      || r.scheduled_local_date::text as dedupe_key
  from resolved r
  join app_core.notification_event_catalog c on c.event_key = r.event_key
)
insert into app_core.notifications (
  user_id, event_key, category, entity_type, entity_id, route, payload,
  dedupe_key, created_at, read_at
)
select
  i.user_id,
  i.event_key,
  i.category,
  i.entity_type,
  i.obligation_id,
  app_private.notification_route_for(
    i.event_key, i.obligation_id, coalesce(i.payload_snapshot, '{}'::jsonb)
  ),
  coalesce(i.payload_snapshot, '{}'::jsonb)
    || jsonb_build_object('event_key', i.event_key, 'category', i.category),
  i.dedupe_key,
  i.created_at,
  i.read_at
from insertable i
on conflict (user_id, dedupe_key) do nothing;

-- Point the surviving delivery rows at their logical notification so the
-- worker and the Notification Center agree from the first run.
update app_core.notification_outbox o
  set notification_id = n.id
from app_core.notifications n
where o.notification_id is null
  and o.obligation_type is not null
  and o.obligation_id is not null
  and o.reminder_kind is not null
  and o.scheduled_local_date is not null
  and o.status in ('pending', 'sending', 'retry', 'sent')
  and n.user_id = o.user_id
  and n.dedupe_key =
    app_private.notification_event_key_for(
      coalesce(o.payload_snapshot ->> 'type', o.obligation_type),
      o.reminder_kind
    )
    || ':' || o.obligation_id::text || ':' || o.scheduled_local_date::text;

-- ---------------------------------------------------------------------------
-- Account deletion
-- ---------------------------------------------------------------------------

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
  delete from app_core.notifications where user_id = p_user_id;
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
  delete from app_finance.bnpl_purchase_payment_allocations
    where user_id = p_user_id;
  delete from app_finance.bnpl_purchase_obligations where user_id = p_user_id;
  delete from app_finance.installment_payment_allocations
    where user_id = p_user_id;
  delete from app_finance.credit_card_statement_item_allocations
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

revoke all on function app_core.delete_finance_suit_data(uuid) from public;
revoke all on function app_core.delete_finance_suit_data(uuid) from anon;
revoke all on function app_core.delete_finance_suit_data(uuid)
  from authenticated;
grant execute on function app_core.delete_finance_suit_data(uuid)
  to service_role;

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------

-- The Notification Center subscribes to inserts on its own rows. RLS still
-- applies to realtime, so a user only ever receives their own notifications.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'app_core'
      and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table app_core.notifications;
  end if;
end;
$$;

notify pgrst, 'reload schema';
