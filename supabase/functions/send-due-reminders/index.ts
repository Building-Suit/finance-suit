// Sends installment and credit-card statement due reminders through
// Firebase Cloud Messaging (HTTP v1).
//
// Invoked on a schedule (pg_cron + pg_net) or manually with the service
// role key. All composition happens here server-side:
//   - reminder timing follows each facility's reminder_lead_days,
//   - user preferences (app_core.notification_preferences) are honored,
//   - amounts are included ONLY when show_amounts is true — the default
//     notification text never contains balances,
//   - the notification_outbox unique key makes every (device, obligation,
//     kind, local date) send exactly-once, so re-runs are safe.
//
// Required secrets (set with `supabase secrets set`):
//   FIREBASE_SERVICE_ACCOUNT — full service-account JSON for the Firebase
//   project (never shipped to clients; lives only in Edge Function env).

import { createClient } from "npm:@supabase/supabase-js@2.110.7";

const jsonHeaders = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

// ---------------------------------------------------------------------------
// Google OAuth2 (JWT bearer) for the FCM v1 API
// ---------------------------------------------------------------------------

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
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlEncode(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64UrlEncode(JSON.stringify({
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
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
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!response.ok) {
    throw new Error(`oauth_token_failed: ${response.status}`);
  }
  const payload = await response.json();
  return payload.access_token as string;
}

// ---------------------------------------------------------------------------
// Date helpers: business dates in the device's timezone
// ---------------------------------------------------------------------------

function localDateFor(timezone: string): string {
  try {
    return new Intl.DateTimeFormat("en-CA", {
      timeZone: timezone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(new Date());
  } catch {
    return new Intl.DateTimeFormat("en-CA", {
      timeZone: "Africa/Cairo",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(new Date());
  }
}

function dayDiff(fromIso: string, toIso: string): number {
  const from = Date.parse(`${fromIso}T00:00:00Z`);
  const to = Date.parse(`${toIso}T00:00:00Z`);
  return Math.round((to - from) / 86_400_000);
}

/** Overdue nag schedule: not every day, but never silently forgotten. */
const overdueReminderDays = new Set([1, 2, 3, 5, 7, 10, 14, 21, 30, 45, 60]);

function formatAmount(minor: number, currency: string): string {
  const major = minor / 100;
  return `${currency} ${
    major.toLocaleString("en-US", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    })
  }`;
}

interface Obligation {
  type: "installment_due" | "statement_due";
  id: string;
  userId: string;
  title: string;
  dueOn: string;
  remainingMinor: number;
  currency: string;
  accountId: string;
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return json(405, { code: "method_not_allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const rawAccount = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!supabaseUrl || !serviceRoleKey) {
    return json(500, { code: "server_misconfigured" });
  }
  if (!rawAccount) {
    return json(500, { code: "firebase_not_configured" });
  }

  // Only the service role (cron) may trigger a broadcast run.
  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization.includes(serviceRoleKey)) {
    return json(401, { code: "not_authorized" });
  }

  let account: ServiceAccount;
  try {
    account = JSON.parse(rawAccount) as ServiceAccount;
  } catch {
    return json(500, { code: "firebase_account_invalid" });
  }

  const core = createClient(supabaseUrl, serviceRoleKey, {
    db: { schema: "app_core" },
    auth: { persistSession: false },
  });
  const finance = createClient(supabaseUrl, serviceRoleKey, {
    db: { schema: "app_finance" },
    auth: { persistSession: false },
  });

  // 1. Every enabled device, grouped per user.
  const { data: devices, error: devicesError } = await core
    .from("push_devices")
    .select("id, user_id, fcm_token, timezone, locale")
    .eq("is_enabled", true);
  if (devicesError) {
    return json(500, { code: "devices_query_failed" });
  }
  if (!devices || devices.length === 0) {
    return json(200, { sent: 0, reason: "no_devices" });
  }
  const userIds = [...new Set(devices.map((d) => d.user_id as string))];

  // 2. Preferences and per-facility reminder lead days.
  const { data: prefRows } = await core
    .from("notification_preferences")
    .select("*")
    .in("user_id", userIds);
  const prefs = new Map(
    (prefRows ?? []).map((row) => [row.user_id as string, row]),
  );

  const { data: facilities } = await finance
    .from("credit_facility_summaries")
    .select("account_id, user_id, reminder_lead_days, name")
    .in("user_id", userIds);
  const leadDays = new Map(
    (facilities ?? []).map((f) => [
      f.account_id as string,
      (f.reminder_lead_days as number) ?? 3,
    ]),
  );
  const facilityNames = new Map(
    (facilities ?? []).map((f) => [f.account_id as string, f.name as string]),
  );

  // 3. Open obligations: unpaid installment dues and closed statements.
  const { data: dueRows } = await finance
    .from("installment_due_statuses")
    .select(
      "id, user_id, account_id, plan_title, due_on, remaining_minor, currency_code, plan_status",
    )
    .in("user_id", userIds)
    .eq("plan_status", "active")
    .gt("remaining_minor", 0);
  const { data: statementRows } = await finance
    .from("credit_card_statement_summaries")
    .select(
      "id, user_id, account_id, cycle_close, due_on, remaining_minor, currency_code",
    )
    .in("user_id", userIds)
    .gt("remaining_minor", 0);

  const obligations: Obligation[] = [
    ...(dueRows ?? []).map((row) => ({
      type: "installment_due" as const,
      id: row.id as string,
      userId: row.user_id as string,
      title: row.plan_title as string,
      dueOn: row.due_on as string,
      remainingMinor: row.remaining_minor as number,
      currency: row.currency_code as string,
      accountId: row.account_id as string,
    })),
    ...(statementRows ?? [])
      // A statement becomes an obligation only after its cycle closes.
      .filter((row) =>
        (row.cycle_close as string) < localDateFor("Africa/Cairo")
      )
      .map((row) => ({
        type: "statement_due" as const,
        id: row.id as string,
        userId: row.user_id as string,
        title: facilityNames.get(row.account_id as string) ?? "Credit card",
        dueOn: row.due_on as string,
        remainingMinor: row.remaining_minor as number,
        currency: row.currency_code as string,
        accountId: row.account_id as string,
      })),
  ];
  if (obligations.length === 0) {
    return json(200, { sent: 0, reason: "nothing_due" });
  }

  const accessToken = await fetchAccessToken(account);
  const fcmEndpoint =
    `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`;

  let sent = 0;
  let skipped = 0;
  let failed = 0;

  for (const device of devices) {
    const userObligations = obligations.filter((o) =>
      o.userId === device.user_id
    );
    if (userObligations.length === 0) continue;
    const userPrefs = prefs.get(device.user_id as string);
    const dueEnabled = userPrefs?.due_reminders_enabled ?? true;
    const overdueEnabled = userPrefs?.overdue_reminders_enabled ?? true;
    const showAmounts = userPrefs?.show_amounts ?? false;
    const today = localDateFor((device.timezone as string) ?? "Africa/Cairo");

    for (const obligation of userObligations) {
      const diff = dayDiff(today, obligation.dueOn);
      const lead = leadDays.get(obligation.accountId) ?? 3;

      let kind: string | null = null;
      if (diff === lead && lead > 0 && dueEnabled) kind = "lead";
      else if (diff === 1 && dueEnabled) kind = "due_tomorrow";
      else if (diff === 0 && dueEnabled) kind = "due_today";
      else if (diff < 0 && overdueEnabled && overdueReminderDays.has(-diff)) {
        kind = "overdue";
      }
      if (!kind) {
        skipped++;
        continue;
      }

      // Exactly-once per (device, obligation, kind, local date).
      const { error: outboxError } = await core
        .from("notification_outbox")
        .insert({
          user_id: obligation.userId,
          device_id: device.id,
          obligation_type: obligation.type,
          obligation_id: obligation.id,
          reminder_kind: kind,
          scheduled_local_date: today,
        });
      if (outboxError) {
        // 23505 duplicate: already sent today by an earlier run.
        skipped++;
        continue;
      }

      const amountText = showAmounts
        ? ` — ${formatAmount(obligation.remainingMinor, obligation.currency)}`
        : "";
      const title = kind === "overdue"
        ? "Payment overdue"
        : kind === "due_today"
        ? "Payment due today"
        : kind === "due_tomorrow"
        ? "Payment due tomorrow"
        : "Upcoming payment";
      const body = obligation.type === "statement_due"
        ? `${obligation.title}: statement due ${obligation.dueOn}${amountText}`
        : `${obligation.title}: installment due ${obligation.dueOn}${amountText}`;

      const response = await fetch(fcmEndpoint, {
        method: "POST",
        headers: {
          authorization: `Bearer ${accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token: device.fcm_token,
            notification: { title, body },
            data: {
              obligation_type: obligation.type,
              obligation_id: obligation.id,
              account_id: obligation.accountId,
            },
            android: {
              notification: { channel_id: "finance_suit_reminders" },
            },
          },
        }),
      });

      if (response.ok) {
        sent++;
        await core
          .from("notification_outbox")
          .update({ sent_at: new Date().toISOString() })
          .eq("user_id", obligation.userId)
          .eq("device_id", device.id)
          .eq("obligation_type", obligation.type)
          .eq("obligation_id", obligation.id)
          .eq("reminder_kind", kind)
          .eq("scheduled_local_date", today);
      } else {
        failed++;
        const errorText = (await response.text()).slice(0, 500);
        await core
          .from("notification_outbox")
          .update({ error: `fcm_${response.status}` })
          .eq("user_id", obligation.userId)
          .eq("device_id", device.id)
          .eq("obligation_type", obligation.type)
          .eq("obligation_id", obligation.id)
          .eq("reminder_kind", kind)
          .eq("scheduled_local_date", today);
        // Stale or revoked tokens are disabled so future runs skip them.
        if (
          response.status === 404 ||
          errorText.includes("UNREGISTERED") ||
          errorText.includes("INVALID_ARGUMENT")
        ) {
          await core
            .from("push_devices")
            .update({ is_enabled: false })
            .eq("id", device.id);
        }
      }
    }
  }

  return json(200, { sent, skipped, failed });
});
