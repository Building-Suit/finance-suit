import { createClient } from "npm:@supabase/supabase-js@2.110.7";
import {
  addDays,
  backoff,
  type ClaimedRow,
  compose,
  dayDiff,
  eventKeyFor,
  fcmData,
  formatAmount,
  localParts,
} from "./compose.ts";

const CHANNEL_ID = "finance_due_reminders";
const MAX_ATTEMPTS = 5;
const BATCH_SIZE = 50;
// A claim older than this is assumed to belong to a worker that died before
// recording a result, and becomes claimable again.
const CLAIM_LEASE_SECONDS = 600;
const SEND_HOUR_LOCAL = 9;
// Obligations are only inspected inside the reminder window: the longest
// supported lead plus one day of overdue.
const MAX_LEAD_DAYS = 30;
// Upper bound on logical notifications created per invocation. Reaching it is
// logged rather than silently truncating the run.
const MATERIALIZE_LIMIT = 500;
const FIREBASE_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const GOOGLE_TOKEN_URI = "https://oauth2.googleapis.com/token";

const jsonHeaders = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};

// The repo does not generate Edge Function database types. Keep the Supabase
// client untyped at this boundary and validate the selected row shapes below.
// deno-lint-ignore no-explicit-any
type SupabaseClient = any;

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
}

interface UserContext {
  user_id: string;
  timezone: string;
  locale: string;
}

interface FacilityRow {
  account_id: string;
  user_id: string;
  name: string | null;
  account_type: string;
  currency_code: string;
  reminder_lead_days: number | null;
}

interface Obligation {
  type: "credit_card_statement_due" | "installment_due" | "bnpl_due";
  id: string;
  userId: string;
  accountId: string;
  accountName: string;
  amountMinor: number;
  currencyCode: string;
  dueOn: string;
}

let cachedOAuth: { token: string; expiresAt: number } | null = null;

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

function serviceRoleKey(): string | null {
  const secretKeys = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (secretKeys) {
    try {
      const parsed = JSON.parse(secretKeys) as Record<string, string>;
      const key = parsed.default ?? Object.values(parsed)[0] ?? null;
      if (key) return key;
    } catch {
      // Hosted projects may expose a different platform secret shape. Fall
      // through to the explicit Finance Suit fallback secret below.
    }
  }
  return Deno.env.get("FINANCE_SUPABASE_SERVICE_ROLE_KEY") ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? null;
}

function buildClient(schema: string): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const key = serviceRoleKey();
  if (!url || !key) throw new Error("supabase_service_key_missing");
  return createClient(url, key, {
    db: { schema },
    auth: { persistSession: false },
  });
}

function loadServiceAccount(): ServiceAccount {
  const encoded = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON_B64");
  if (!encoded) throw new Error("firebase_service_account_missing");
  let decoded: string;
  try {
    decoded = new TextDecoder().decode(
      Uint8Array.from(atob(encoded), (c) => c.charCodeAt(0)),
    );
  } catch {
    throw new Error("firebase_service_account_base64_invalid");
  }
  const account = JSON.parse(decoded) as ServiceAccount;
  if (
    !account.project_id || !account.client_email || !account.private_key ||
    !(account.token_uri ?? GOOGLE_TOKEN_URI)
  ) {
    throw new Error("firebase_service_account_invalid");
  }
  return account;
}

function base64UrlEncode(data: Uint8Array | string): string {
  const bytes = typeof data === "string"
    ? new TextEncoder().encode(data)
    : data;
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(
    /=+$/,
    "",
  );
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

async function fetchAccessToken(account: ServiceAccount): Promise<string> {
  if (cachedOAuth && cachedOAuth.expiresAt - Date.now() > 60_000) {
    return cachedOAuth.token;
  }
  const now = Math.floor(Date.now() / 1000);
  const tokenUri = account.token_uri ?? GOOGLE_TOKEN_URI;
  const header = base64UrlEncode(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64UrlEncode(JSON.stringify({
    iss: account.client_email,
    scope: FIREBASE_SCOPE,
    aud: tokenUri,
    iat: now,
    exp: now + 3600,
  }));
  const key = await importPrivateKey(account.private_key);
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  const assertion = `${header}.${claims}.${
    base64UrlEncode(new Uint8Array(signature))
  }`;
  const response = await fetch(tokenUri, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!response.ok) throw new Error(`oauth_token_failed_${response.status}`);
  const payload = await response.json();
  cachedOAuth = {
    token: payload.access_token as string,
    expiresAt: Date.now() + ((payload.expires_in as number ?? 3600) * 1000),
  };
  return cachedOAuth.token;
}
async function loadUserContexts(
  core: SupabaseClient,
  userIds: string[],
): Promise<Map<string, UserContext>> {
  if (!userIds.length) return new Map();
  const { data, error } = await core.rpc("notification_user_context", {
    p_user_ids: userIds,
  });
  if (error) throw error;
  return new Map(
    ((data ?? []) as UserContext[]).map((row) => [row.user_id, row]),
  );
}

/// Turns finance state into logical notifications. Every write goes through
/// `enqueue_notification`, so preferences, the event catalog, deduplication
/// and per-device fan-out are enforced in one place.
async function materialize(
  core: SupabaseClient,
  finance: SupabaseClient,
): Promise<{ created: number; capped: boolean }> {
  const todayUtc = new Date().toISOString().slice(0, 10);
  // Widened by a day on each side so users whose local date is ahead of or
  // behind UTC are still inside the window.
  const windowStart = addDays(todayUtc, -3);
  const windowEnd = addDays(todayUtc, MAX_LEAD_DAYS + 1);

  const { data: statements, error: statementsError } = await finance
    .from("credit_card_statement_summaries")
    .select(
      "id, user_id, account_id, due_on, total_remaining_minor, remaining_minor, currency_code, obligation_status",
    )
    .gt("total_remaining_minor", 0)
    .gte("due_on", windowStart)
    .lte("due_on", windowEnd);
  if (statementsError) throw statementsError;

  const { data: dues, error: duesError } = await finance
    .from("installment_due_statuses")
    .select(
      "id, user_id, account_id, due_on, remaining_minor, currency_code, plan_status, is_presettled",
    )
    .eq("plan_status", "active")
    .eq("is_presettled", false)
    .gt("remaining_minor", 0)
    .gte("due_on", windowStart)
    .lte("due_on", windowEnd);
  if (duesError) throw duesError;

  const statementRows = ((statements ?? []) as Record<string, unknown>[])
    .filter((row) =>
      row.obligation_status !== "paid" && row.obligation_status !== "open"
    );
  const dueRows = (dues ?? []) as Record<string, unknown>[];

  const userIds = [
    ...new Set(
      [...statementRows, ...dueRows].map((row) => row.user_id as string),
    ),
  ];
  if (!userIds.length) return { created: 0, capped: false };

  const contexts = await loadUserContexts(core, userIds);

  const { data: facilities } = await finance
    .from("credit_facility_summaries")
    .select(
      "account_id, user_id, name, account_type, currency_code, reminder_lead_days",
    )
    .in("user_id", userIds);
  const facilityById = new Map(
    ((facilities ?? []) as FacilityRow[]).map((f) => [f.account_id, f]),
  );

  const obligations: Obligation[] = [
    ...statementRows.map((row) => {
      const facility = facilityById.get(row.account_id as string);
      return {
        type: "credit_card_statement_due" as const,
        id: row.id as string,
        userId: row.user_id as string,
        accountId: row.account_id as string,
        accountName: facility?.name ?? "Credit card",
        amountMinor: Number(
          row.total_remaining_minor ?? row.remaining_minor ?? 0,
        ),
        currencyCode: row.currency_code as string,
        dueOn: row.due_on as string,
      };
    }),
    ...dueRows.map((row) => {
      const facility = facilityById.get(row.account_id as string);
      const isBnpl = facility?.account_type === "bnpl";
      return {
        type: isBnpl ? "bnpl_due" as const : "installment_due" as const,
        id: row.id as string,
        userId: row.user_id as string,
        accountId: row.account_id as string,
        accountName: facility?.name ?? (isBnpl ? "BNPL" : "Installment"),
        amountMinor: Number(row.remaining_minor ?? 0),
        currencyCode: row.currency_code as string,
        dueOn: row.due_on as string,
      };
    }),
  ];

  const showAmounts = await loadShowAmounts(core, userIds);

  let created = 0;
  let capped = false;
  for (const obligation of obligations) {
    if (created >= MATERIALIZE_LIMIT) {
      capped = true;
      break;
    }
    const context = contexts.get(obligation.userId);
    const timezone = context?.timezone ?? "Africa/Cairo";
    const locale = context?.locale ?? "en";
    const { date: localDate, hour } = localParts(timezone);
    if (hour < SEND_HOUR_LOCAL) continue;

    const diff = dayDiff(localDate, obligation.dueOn);
    const lead = facilityById.get(obligation.accountId)?.reminder_lead_days ??
      3;
    let kind: "due_soon" | "due_today" | "overdue" | null = null;
    if (diff === lead && lead > 0) kind = "due_soon";
    else if (diff === 0) kind = "due_today";
    else if (diff === -1) kind = "overdue";
    if (!kind) continue;

    const eventKey = eventKeyFor(obligation.type, kind);
    if (!eventKey) continue;

    const notificationId = await enqueue(core, {
      userId: obligation.userId,
      eventKey,
      // The due *instance* is the logical identity, not the day the
      // scheduler happened to run: rerunning the scheduler cannot duplicate,
      // and moving the due date legitimately produces a new reminder.
      dedupeKey: `${eventKey}:${obligation.id}:${obligation.dueOn}`,
      payload: {
        type: obligation.type,
        reminder_kind: kind,
        obligation_id: obligation.id,
        account_id: obligation.accountId,
        account_name: obligation.accountName,
        due_on: obligation.dueOn,
        // Raw minor units drive the in-app Notification Center, which renders
        // them through the app's existing money-privacy control.
        amount_minor: obligation.amountMinor,
        currency_code: obligation.currencyCode,
        // Pre-rendered text is what reaches the lock screen, so it exists
        // only when the recipient opted into amounts in notifications.
        amount_text: showAmounts.get(obligation.userId)
          ? formatAmount(
            obligation.amountMinor,
            obligation.currencyCode,
            locale,
          )
          : null,
      },
      entityId: obligation.id,
      route: `/money/facilities/${obligation.accountId}`,
    });
    if (notificationId) created++;
  }

  const confirmations = await materializePaymentConfirmations(
    core,
    finance,
    contexts,
    showAmounts,
  );
  return { created: created + confirmations, capped };
}

async function loadShowAmounts(
  core: SupabaseClient,
  userIds: string[],
): Promise<Map<string, boolean>> {
  const { data } = await core
    .from("notification_preferences")
    .select("user_id, show_amounts")
    .in("user_id", userIds);
  return new Map(
    ((data ?? []) as { user_id: string; show_amounts: boolean | null }[])
      .map((row) => [row.user_id, row.show_amounts === true]),
  );
}

async function materializePaymentConfirmations(
  core: SupabaseClient,
  finance: SupabaseClient,
  contexts: Map<string, UserContext>,
  showAmounts: Map<string, boolean>,
): Promise<number> {
  const { data: payments } = await finance
    .from("financial_transactions")
    .select(
      "id, user_id, destination_account_id, amount_minor, currency_code, created_at",
    )
    .eq("transaction_kind", "transfer")
    .not("destination_account_id", "is", null)
    .gte("created_at", new Date(Date.now() - 24 * 60 * 60_000).toISOString())
    .order("created_at", { ascending: false })
    .limit(200);

  const rows = (payments ?? []) as Record<string, unknown>[];
  if (!rows.length) return 0;

  const accountIds = [
    ...new Set(rows.map((p) => p.destination_account_id as string)),
  ];
  const { data: facilities } = await finance
    .from("credit_facility_summaries")
    .select("account_id, user_id, name")
    .in("account_id", accountIds);
  const facilityById = new Map(
    ((facilities ?? []) as FacilityRow[]).map((f) => [f.account_id, f]),
  );

  const missingContexts = [
    ...new Set(
      rows.map((p) => p.user_id as string).filter((id) => !contexts.has(id)),
    ),
  ];
  if (missingContexts.length) {
    for (const [id, ctx] of await loadUserContexts(core, missingContexts)) {
      contexts.set(id, ctx);
    }
  }

  let created = 0;
  for (const payment of rows) {
    const accountId = payment.destination_account_id as string;
    const facility = facilityById.get(accountId);
    if (!facility) continue;
    const userId = payment.user_id as string;
    if (facility.user_id !== userId) continue;
    const locale = contexts.get(userId)?.locale ?? "en";

    const notificationId = await enqueue(core, {
      userId,
      eventKey: "facility.payment_recorded",
      // Keyed on the payment alone. Including a local date here used to let
      // a payment recorded near midnight notify twice.
      dedupeKey: `facility.payment_recorded:${payment.id}`,
      payload: {
        type: "facility_payment_confirmation",
        reminder_kind: "payment_confirmation",
        obligation_id: payment.id,
        account_id: accountId,
        account_name: facility.name ?? "Credit facility",
        amount_minor: Number(payment.amount_minor ?? 0),
        currency_code: payment.currency_code,
        amount_text: showAmounts.get(userId)
          ? formatAmount(
            Number(payment.amount_minor ?? 0),
            payment.currency_code as string,
            locale,
          )
          : null,
      },
      entityId: payment.id as string,
      route: `/money/facilities/${accountId}`,
    });
    if (notificationId) created++;
  }
  return created;
}

async function enqueue(core: SupabaseClient, input: {
  userId: string;
  eventKey: string;
  dedupeKey: string;
  payload: Record<string, unknown>;
  entityId?: string | null;
  route?: string | null;
}): Promise<string | null> {
  const { data, error } = await core.rpc("enqueue_notification", {
    p_user_id: input.userId,
    p_event_key: input.eventKey,
    p_dedupe_key: input.dedupeKey,
    p_payload: input.payload,
    p_entity_type: null,
    p_entity_id: input.entityId ?? null,
    p_route: input.route ?? null,
  });
  if (error) {
    // A preference-suppressed or already-created notification returns null
    // rather than an error, so anything here is a real fault worth surfacing.
    console.error(JSON.stringify({
      stage: "enqueue",
      event_key: input.eventKey,
      code: error.code ?? null,
      message: String(error.message ?? "").slice(0, 200),
    }));
    return null;
  }
  return (data as string | null) ?? null;
}

async function sendClaimed(
  core: SupabaseClient,
  finance: SupabaseClient,
  account: ServiceAccount,
  invocationId: string,
): Promise<
  { sent: number; retry: number; failed: number; suppressed: number }
> {
  const { data, error } = await core.rpc("claim_notification_outbox", {
    batch_size: BATCH_SIZE,
    p_lease_seconds: CLAIM_LEASE_SECONDS,
    p_max_attempts: MAX_ATTEMPTS,
  });
  if (error) throw error;

  const rows = (data ?? []) as ClaimedRow[];
  if (!rows.length) return { sent: 0, retry: 0, failed: 0, suppressed: 0 };
  const accessToken = await fetchAccessToken(account);
  const endpoint =
    `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`;
  let sent = 0;
  let retry = 0;
  let failed = 0;
  let suppressed = 0;

  const eligibility = await eligibilityFor(core, finance, rows);

  for (const row of rows) {
    const payload = row.payload_snapshot ?? {};
    if (eligibility.get(row.id) !== true) {
      suppressed++;
      await core.from("notification_outbox").update({
        status: "suppressed",
        error: "stale_or_disabled",
        updated_at: new Date().toISOString(),
      }).eq("id", row.id);
      continue;
    }
    const notification = compose(row.event_key, payload, row.locale);
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        authorization: `Bearer ${accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: row.fcm_token,
          notification,
          android: {
            priority: "high",
            notification: { channel_id: CHANNEL_ID },
          },
          data: fcmData(row, payload),
        },
      }),
    });

    if (response.ok) {
      const body = await response.json();
      sent++;
      await core.from("notification_outbox").update({
        status: "sent",
        sent_at: new Date().toISOString(),
        fcm_message_id: body.name ?? null,
        error: null,
        updated_at: new Date().toISOString(),
      }).eq("id", row.id);
      continue;
    }

    const errorText = (await response.text()).slice(0, 500);
    const permanentToken = response.status === 404 ||
      errorText.includes("UNREGISTERED") ||
      errorText.includes("INVALID_ARGUMENT");
    const transient = response.status === 429 || response.status === 500 ||
      response.status === 503;

    // Only the sanitized provider status is stored or logged; the FCM token
    // and the authorization header never appear in either.
    console.error(JSON.stringify({
      invocationId,
      stage: "fcm",
      outbox_id: row.id,
      notification_id: row.notification_id,
      event_key: row.event_key,
      attempt: row.attempt_count,
      status: response.status,
      classification: permanentToken
        ? "permanent_token"
        : transient
        ? "transient"
        : "permanent",
    }));

    if (permanentToken) {
      failed++;
      // A retired token must stop consuming attempts across every queued
      // delivery for that device, not just this one.
      await core.from("push_devices").update({ is_enabled: false }).eq(
        "id",
        row.device_id,
      );
      await core.from("notification_outbox").update({
        status: "failed",
        permanently_failed_at: new Date().toISOString(),
        error: `fcm_permanent_${response.status}`,
        updated_at: new Date().toISOString(),
      }).eq("id", row.id);
    } else if (transient && row.attempt_count < MAX_ATTEMPTS) {
      retry++;
      await core.from("notification_outbox").update({
        status: "retry",
        next_attempt_at: backoff(row.attempt_count),
        error: `fcm_transient_${response.status}`,
        updated_at: new Date().toISOString(),
      }).eq("id", row.id);
    } else {
      failed++;
      await core.from("notification_outbox").update({
        status: "failed",
        permanently_failed_at: new Date().toISOString(),
        error: `fcm_failed_${response.status}`,
        updated_at: new Date().toISOString(),
      }).eq("id", row.id);
    }
  }
  return { sent, retry, failed, suppressed };
}

/// Batched staleness check for a claimed page: an obligation settled between
/// enqueue and send must not produce a push. Returns outbox id -> eligible.
async function eligibilityFor(
  core: SupabaseClient,
  finance: SupabaseClient,
  rows: ClaimedRow[],
): Promise<Map<string, boolean>> {
  const result = new Map<string, boolean>();
  const deviceIds = [...new Set(rows.map((r) => r.device_id))];
  const { data: devices } = await core
    .from("push_devices")
    .select("id, is_enabled")
    .in("id", deviceIds);
  const enabledDevices = new Set(
    ((devices ?? []) as { id: string; is_enabled: boolean }[])
      .filter((d) => d.is_enabled).map((d) => d.id),
  );

  const keyOf = (row: ClaimedRow) =>
    row.event_key ??
      eventKeyFor(
        row.payload_snapshot?.type as string,
        row.reminder_kind ?? undefined,
      );

  const entityOf = (row: ClaimedRow) =>
    (row.payload_snapshot?.obligation_id as string) ?? row.obligation_id;

  const statementIds = new Set<string>();
  const dueIds = new Set<string>();
  const transferIds = new Set<string>();
  for (const row of rows) {
    const key = keyOf(row);
    const entity = entityOf(row);
    if (!key || !entity) continue;
    if (key.startsWith("credit_card.")) statementIds.add(entity);
    else if (key.startsWith("installment.") || key.startsWith("bnpl.")) {
      dueIds.add(entity);
    } else if (key === "network.transfer_received") transferIds.add(entity);
  }

  const statementState = new Map<string, Record<string, unknown>>();
  if (statementIds.size) {
    const { data } = await finance
      .from("credit_card_statement_summaries")
      .select("id, total_remaining_minor, obligation_status")
      .in("id", [...statementIds]);
    for (const row of (data ?? []) as Record<string, unknown>[]) {
      statementState.set(row.id as string, row);
    }
  }

  const dueState = new Map<string, Record<string, unknown>>();
  if (dueIds.size) {
    const { data } = await finance
      .from("installment_due_statuses")
      .select("id, remaining_minor, plan_status, is_presettled")
      .in("id", [...dueIds]);
    for (const row of (data ?? []) as Record<string, unknown>[]) {
      dueState.set(row.id as string, row);
    }
  }

  const transferState = new Map<string, string>();
  if (transferIds.size) {
    const { data } = await finance
      .from("network_transfers")
      .select("id, status")
      .in("id", [...transferIds]);
    for (const row of (data ?? []) as Record<string, unknown>[]) {
      transferState.set(row.id as string, String(row.status));
    }
  }

  for (const row of rows) {
    if (!enabledDevices.has(row.device_id)) {
      result.set(row.id, false);
      continue;
    }
    const key = keyOf(row);
    const entity = entityOf(row);
    if (key === "system.developer_test") {
      result.set(row.id, true);
      continue;
    }
    if (!key || !entity) {
      result.set(row.id, true);
      continue;
    }
    if (key.startsWith("credit_card.")) {
      const state = statementState.get(entity);
      result.set(
        row.id,
        Number(state?.total_remaining_minor ?? 0) > 0 &&
          !["paid", "open"].includes(String(state?.obligation_status ?? "")),
      );
      continue;
    }
    if (key.startsWith("installment.") || key.startsWith("bnpl.")) {
      const state = dueState.get(entity);
      result.set(
        row.id,
        Number(state?.remaining_minor ?? 0) > 0 &&
          state?.plan_status === "active" &&
          state?.is_presettled !== true,
      );
      continue;
    }
    if (key === "network.transfer_received") {
      // A transfer decided before the push went out no longer needs one.
      result.set(row.id, transferState.get(entity) === "pending");
      continue;
    }
    result.set(row.id, true);
  }
  return result;
}

Deno.serve(async (request) => {
  const started = Date.now();
  const invocationId = crypto.randomUUID();
  if (request.method !== "POST") {
    return json(405, { code: "method_not_allowed" });
  }

  try {
    const core = buildClient("app_core");
    const finance = buildClient("app_finance");
    const account = loadServiceAccount();

    // Retire deliveries past their attempt budget first, including any a
    // crashed worker left in `sending`, so nothing accumulates as a zombie.
    const { data: reaped } = await core.rpc("reap_notification_outbox", {
      p_max_attempts: MAX_ATTEMPTS,
      p_lease_seconds: CLAIM_LEASE_SECONDS,
    });

    const { created, capped } = await materialize(core, finance);
    const delivery = await sendClaimed(core, finance, account, invocationId);
    const result = {
      invocationId,
      materialized: created,
      materializeCapped: capped,
      reaped: reaped ?? 0,
      claimed: delivery.sent + delivery.retry + delivery.failed +
        delivery.suppressed,
      ...delivery,
      durationMs: Date.now() - started,
    };
    if (capped) {
      console.warn(JSON.stringify({
        invocationId,
        warning: "materialize_limit_reached",
        limit: MATERIALIZE_LIMIT,
      }));
    }
    console.log(JSON.stringify(result));
    return json(200, result);
  } catch (error) {
    const message = error instanceof Error ? error.message : "unknown_error";
    console.error(JSON.stringify({
      invocationId,
      error: message,
      durationMs: Date.now() - started,
    }));
    return json(500, { code: message, invocationId });
  }
});
