-- Complete Finance Suit push notification pipeline.
--
-- This migration is intentionally forward-only: it keeps the existing
-- notification tables and idempotency key, but adds the secure ownership and
-- delivery-state primitives required by the FCM worker.

create extension if not exists pg_net;
create extension if not exists pg_cron;

-- One active app-install token belongs to one Finance Suit user at a time.
-- Production had no rows when this migration was authored; the cleanup keeps
-- local/dev databases with accidental duplicates migratable.
with ranked as (
  select id, row_number() over (
    partition by fcm_token
    order by is_enabled desc, last_seen_at desc, updated_at desc, created_at desc
  ) as rn
  from app_core.push_devices
)
delete from app_core.push_devices d
using ranked r
where d.id = r.id and r.rn > 1;

alter table app_core.push_devices
  drop constraint if exists push_devices_token_unique;

alter table app_core.push_devices
  add constraint push_devices_token_global_unique unique (fcm_token);

create index if not exists idx_push_devices_token_enabled
  on app_core.push_devices (fcm_token, is_enabled);

alter table app_core.notification_outbox
  drop constraint if exists notification_outbox_obligation_type_check,
  drop constraint if exists notification_outbox_reminder_kind_check;

alter table app_core.notification_outbox
  add constraint notification_outbox_obligation_type_check check (
    obligation_type in (
      'credit_card_statement_due',
      'installment_due',
      'bnpl_due',
      'facility_payment',
      'statement_due',
      'payment',
      'plan',
      'general'
    )
  ),
  add constraint notification_outbox_reminder_kind_check check (
    reminder_kind in (
      'due_soon',
      'due_today',
      'overdue',
      'payment_confirmation',
      'lead',
      'due_tomorrow',
      'payment_success',
      'plan_completed',
      'near_limit'
    )
  );

alter table app_core.notification_outbox
  add column if not exists status text not null default 'pending',
  add column if not exists attempt_count integer not null default 0
    check (attempt_count >= 0),
  add column if not exists last_attempt_at timestamptz,
  add column if not exists next_attempt_at timestamptz not null default now(),
  add column if not exists permanently_failed_at timestamptz,
  add column if not exists fcm_message_id text,
  add column if not exists payload_snapshot jsonb,
  add column if not exists updated_at timestamptz not null default now();

alter table app_core.notification_outbox
  drop constraint if exists notification_outbox_status_check;

alter table app_core.notification_outbox
  add constraint notification_outbox_status_check check (
    status in ('pending', 'sending', 'sent', 'retry', 'failed', 'suppressed')
  );

create index if not exists idx_notification_outbox_claim
  on app_core.notification_outbox (status, next_attempt_at, created_at)
  where sent_at is null and permanently_failed_at is null;

create index if not exists idx_notification_outbox_device
  on app_core.notification_outbox (device_id, status, created_at);

create or replace function app_core.register_push_device(
  p_fcm_token text,
  p_platform text,
  p_app_version text default null,
  p_locale text default null,
  p_timezone text default 'Africa/Cairo'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_timezone text := coalesce(nullif(p_timezone, ''), 'Africa/Cairo');
  v_device_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_fcm_token is null or char_length(p_fcm_token) < 8
      or char_length(p_fcm_token) > 4096 then
    raise exception 'invalid_fcm_token';
  end if;
  if p_platform not in ('android', 'ios', 'web') then
    raise exception 'invalid_platform';
  end if;
  if p_app_version is not null and char_length(p_app_version) > 40 then
    raise exception 'invalid_app_version';
  end if;
  if p_locale is not null and char_length(p_locale) > 20 then
    raise exception 'invalid_locale';
  end if;
  if char_length(v_timezone) > 64 or not exists (
    select 1 from pg_catalog.pg_timezone_names where name = v_timezone
  ) then
    raise exception 'invalid_timezone';
  end if;

  insert into app_core.push_devices (
    user_id, fcm_token, platform, app_version, locale, timezone, is_enabled,
    last_seen_at
  ) values (
    v_user_id, p_fcm_token, p_platform, p_app_version, p_locale, v_timezone,
    true, now()
  )
  on conflict (fcm_token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        app_version = excluded.app_version,
        locale = excluded.locale,
        timezone = excluded.timezone,
        is_enabled = true,
        last_seen_at = now(),
        updated_at = now()
  returning id into v_device_id;

  insert into app_core.notification_preferences (user_id)
  values (v_user_id)
  on conflict (user_id) do nothing;

  return v_device_id;
end;
$$;

revoke all on function app_core.register_push_device(
  text, text, text, text, text
) from public;
grant execute on function app_core.register_push_device(
  text, text, text, text, text
) to authenticated;

create or replace function app_core.disable_push_device(fcm_token text)
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
  update app_core.push_devices
    set is_enabled = false, updated_at = now(), last_seen_at = now()
    where user_id = v_user_id and push_devices.fcm_token = $1;
end;
$$;

revoke all on function app_core.disable_push_device(text) from public;
grant execute on function app_core.disable_push_device(text) to authenticated;

create or replace function app_core.claim_notification_outbox(
  batch_size integer default 50
)
returns table (
  id uuid,
  user_id uuid,
  device_id uuid,
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
      and o.status in ('pending', 'retry')
      and o.next_attempt_at <= now()
      and d.is_enabled
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
    d.fcm_token,
    d.platform,
    d.locale,
    d.timezone,
    u.obligation_type,
    u.obligation_id,
    u.reminder_kind,
    u.scheduled_local_date,
    u.payload_snapshot,
    u.attempt_count
  from updated u
  join app_core.push_devices d on d.id = u.device_id;
end;
$$;

revoke all on function app_core.claim_notification_outbox(integer) from public;
grant execute on function app_core.claim_notification_outbox(integer)
  to service_role;

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
  v_device record;
  v_outbox_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select d.* into v_device
    from app_core.push_devices d
    where d.user_id = v_user_id and d.is_enabled
    order by d.last_seen_at desc
    limit 1;

  if v_device is null then
    raise exception 'no_enabled_push_device';
  end if;

  insert into app_core.notification_outbox (
    user_id, device_id, obligation_type, obligation_id, reminder_kind,
    scheduled_local_date, status, next_attempt_at, payload_snapshot
  ) values (
    v_user_id,
    v_device.id,
    'general',
    gen_random_uuid(),
    'due_today',
    ((now() at time zone v_device.timezone)::date),
    'pending',
    now(),
    jsonb_build_object(
      'type', 'developer_test',
      'reminder_kind', 'due_today'
    )
  )
  returning id into v_outbox_id;

  return v_outbox_id;
end;
$$;

revoke all on function app_core.enqueue_developer_test_notification(uuid)
  from public;
grant execute on function app_core.enqueue_developer_test_notification(uuid)
  to authenticated, service_role;

-- Supabase Cron -> Edge Function. Values are read from Vault at runtime:
--   project_url:      https://kedjrbwnznvfqlzszawa.supabase.co
--   publishable_key:  the project's publishable/anon key
-- The Edge Function verifies the platform JWT and uses service credentials
-- available only inside the Edge Runtime.
select cron.unschedule('finance-notification-worker-every-5-minutes')
where exists (
  select 1 from cron.job
  where jobname = 'finance-notification-worker-every-5-minutes'
);

select cron.schedule(
  'finance-notification-worker-every-5-minutes',
  '*/5 * * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets
            where name = 'project_url') || '/functions/v1/notification-worker',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', (select decrypted_secret from vault.decrypted_secrets
                 where name = 'publishable_key'),
      'Authorization', 'Bearer ' || (
        select decrypted_secret from vault.decrypted_secrets
        where name = 'publishable_key'
      )
    ),
    body := jsonb_build_object('scheduled_at', now())
  ) as request_id;
  $$
);
