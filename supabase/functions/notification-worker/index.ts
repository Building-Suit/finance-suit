import { createClient } from "npm:@supabase/supabase-js@2.110.7";

const CHANNEL_ID = "finance_due_reminders";
const MAX_ATTEMPTS = 5;
const BATCH_SIZE = 50;
const SEND_HOUR_LOCAL = 9;
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

interface DeviceRow {
  id: string;
  user_id: string;
  fcm_token: string;
  platform: string;
  locale: string | null;
  timezone: string | null;
}

interface PreferenceRow {
  user_id: string;
  due_reminders_enabled?: boolean;
  overdue_reminders_enabled?: boolean;
  payment_confirmations_enabled?: boolean;
  show_amounts?: boolean;
}

interface FacilityRow {
  account_id: string;
  user_id: string;
  name: string | null;
  account_type: string;
  currency_code: string;
  reminder_lead_days: number | null;
  is_archived?: boolean;
  facility_status?: string | null;
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

interface ClaimedRow {
  id: string;
  user_id: string;
  device_id: string;
  fcm_token: string;
  platform: string;
  locale: string | null;
  timezone: string | null;
  obligation_type: string;
  obligation_id: string;
  reminder_kind: string;
  scheduled_local_date: string;
  payload_snapshot: Record<string, unknown> | null;
  attempt_count: number;
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

function localParts(timezone: string): { date: string; hour: number } {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    hour12: false,
  }).formatToParts(new Date());
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? "";
  return {
    date: `${get("year")}-${get("month")}-${get("day")}`,
    hour: Number(get("hour")),
  };
}

function dayDiff(fromIso: string, toIso: string): number {
  const from = Date.parse(`${fromIso}T00:00:00Z`);
  const to = Date.parse(`${toIso}T00:00:00Z`);
  return Math.round((to - from) / 86_400_000);
}

function isArabic(locale: string | null | undefined): boolean {
  return (locale ?? "").toLowerCase().startsWith("ar");
}

function formatAmount(
  minor: number,
  currency: string,
  locale: string | null,
): string {
  return new Intl.NumberFormat(isArabic(locale) ? "ar-EG" : "en-EG", {
    style: "currency",
    currency,
    maximumFractionDigits: 2,
  }).format(minor / 100);
}

function formatDate(iso: string, locale: string | null): string {
  const date = new Date(`${iso}T12:00:00Z`);
  return new Intl.DateTimeFormat(isArabic(locale) ? "ar-EG" : "en-GB", {
    day: "numeric",
    month: "short",
  }).format(date);
}

function compose(
  payload: Record<string, unknown>,
  locale: string | null,
): { title: string; body: string } {
  const ar = isArabic(locale);
  const kind = payload.reminder_kind as string;
  const type = payload.type as string;
  const accountName = String(
    payload.account_name ?? (ar ? "الحساب" : "Account"),
  );
  const dueOn = String(payload.due_on ?? "");
  const amount = payload.amount_text ? String(payload.amount_text) : null;

  if (type === "developer_test") {
    return ar
      ? {
        title: "اختبار إشعارات Finance Suit",
        body: "إذا ظهر هذا التنبيه، فإشعارات هذا الهاتف تعمل.",
      }
      : {
        title: "Finance Suit notification test",
        body: "If you see this, alerts are working on this phone.",
      };
  }

  if (type.startsWith("network_")) {
    const name = String(
      payload.counterparty_name ?? (ar ? "شخص ما" : "Someone"),
    );
    const amount = payload.amount_text ? String(payload.amount_text) : null;
    switch (type) {
      case "network_add_request":
        return ar
          ? {
            title: "طلب إضافة جديد",
            body: `${name} يريد إضافتك إلى شبكته في Finance Suit.`,
          }
          : {
            title: "New add request",
            body: `${name} wants to add you to their Finance Suit network.`,
          };
      case "network_add_request_accepted":
        return ar
          ? { title: "تم قبول الطلب", body: `${name} الآن في شبكتك.` }
          : { title: "Request accepted", body: `${name} is now in your network.` };
      case "network_transfer_pending":
        return ar
          ? {
            title: "طلب تحويل جديد",
            body: amount
              ? `${name} أرسل لك ${amount}.`
              : `${name} أرسل لك طلب تحويل.`,
          }
          : {
            title: "New transfer request",
            body: amount
              ? `${name} sent you ${amount}.`
              : `${name} sent you a transfer request.`,
          };
      case "network_transfer_accepted":
        return ar
          ? {
            title: "تم قبول التحويل",
            body: amount
              ? `${name} قبل تحويلك بمبلغ ${amount}.`
              : `${name} قبل تحويلك.`,
          }
          : {
            title: "Transfer accepted",
            body: amount
              ? `${name} accepted your ${amount} transfer.`
              : `${name} accepted your transfer.`,
          };
      default:
        return ar
          ? { title: "تم رفض التحويل", body: `${name} رفض تحويلك.` }
          : { title: "Transfer declined", body: `${name} declined your transfer.` };
    }
  }

  if (type.startsWith("installment_link_")) {
    const name = String(
      payload.counterparty_name ?? (ar ? "شخص ما" : "Someone"),
    );
    const planTitle = payload.plan_title ? String(payload.plan_title) : null;
    switch (type) {
      case "installment_link_request":
        return ar
          ? {
            title: "طلب ربط قسط",
            body: `${name} يريد ربط قسط بك. راجع التفاصيل قبل القبول.`,
          }
          : {
            title: "Installment link request",
            body:
              `${name} wants to link an installment to you. Review the details before accepting.`,
          };
      case "installment_link_accepted":
        return ar
          ? {
            title: "تم قبول ربط القسط",
            body: planTitle
              ? `${name} قبل ربط قسط ${planTitle}.`
              : `${name} قبل ربط القسط.`,
          }
          : {
            title: "Installment link accepted",
            body: planTitle
              ? `${name} accepted the ${planTitle} installment link.`
              : `${name} accepted the installment link.`,
          };
      default:
        return ar
          ? {
            title: "تم رفض ربط القسط",
            body: planTitle
              ? `${name} رفض ربط قسط ${planTitle}.`
              : `${name} رفض ربط القسط.`,
          }
          : {
            title: "Installment link declined",
            body: planTitle
              ? `${name} declined the ${planTitle} installment link.`
              : `${name} declined the installment link.`,
          };
    }
  }

  if (type === "facility_payment_confirmation") {
    return ar
      ? {
        title: "تم تسجيل دفعة",
        body: amount
          ? `تم تسجيل دفعة ${amount} على ${accountName}.`
          : `تم تسجيل دفعة على ${accountName}.`,
      }
      : {
        title: "Payment recorded",
        body: amount
          ? `${amount} was recorded for ${accountName}.`
          : `A payment was recorded for ${accountName}.`,
      };
  }

  const label = type === "bnpl_due"
    ? (ar ? "دفعة اشتر الآن وادفع لاحقا" : "BNPL payment")
    : type === "installment_due"
    ? (ar ? "قسط" : "Installment")
    : (ar ? "دفعة بطاقة ائتمان" : "Credit Card payment");
  const dateText = dueOn ? formatDate(dueOn, locale) : "";
  if (ar) {
    const title = kind === "overdue"
      ? `${label} متأخرة`
      : kind === "due_today"
      ? `${label} مستحقة اليوم`
      : `${label} مستحقة قريبا`;
    const body = amount
      ? `${amount} مستحقة على ${accountName}${
        dateText ? ` يوم ${dateText}` : ""
      }.`
      : `${accountName}${
        dateText ? ` مستحق يوم ${dateText}` : " عليه دفعة مستحقة"
      }.`;
    return { title, body };
  }
  const title = kind === "overdue"
    ? `${label} overdue`
    : kind === "due_today"
    ? `${label} due today`
    : `${label} due soon`;
  const body = amount
    ? `${amount} is due for ${accountName}${dateText ? ` on ${dateText}` : ""}.`
    : `${accountName}${
      dateText ? ` is due on ${dateText}` : " has a payment due"
    }.`;
  return { title, body };
}

function backoff(attempt: number): string {
  const minutes = [1, 5, 15, 60][Math.min(Math.max(attempt - 1, 0), 3)];
  return new Date(Date.now() + minutes * 60_000).toISOString();
}

function fcmData(payload: Record<string, unknown>): Record<string, string> {
  return {
    type: String(payload.type ?? "unknown"),
    obligation_id: String(payload.obligation_id ?? ""),
    account_id: String(payload.account_id ?? ""),
    reminder_kind: String(payload.reminder_kind ?? ""),
  };
}

async function materialize(
  core: SupabaseClient,
  finance: SupabaseClient,
): Promise<number> {
  const { data: devices, error: devicesError } = await core
    .from("push_devices")
    .select("id, user_id, fcm_token, platform, locale, timezone")
    .eq("is_enabled", true);
  if (devicesError) throw devicesError;
  if (!devices?.length) return 0;

  const typedDevices = devices as DeviceRow[];
  const userIds = [...new Set(typedDevices.map((d) => d.user_id))];
  const { data: preferenceRows } = await core
    .from("notification_preferences")
    .select("*")
    .in("user_id", userIds);
  const preferences = new Map(
    ((preferenceRows ?? []) as PreferenceRow[]).map((p) => [p.user_id, p]),
  );

  const { data: facilities } = await finance
    .from("credit_facility_summaries")
    .select(
      "account_id, user_id, name, account_type, currency_code, reminder_lead_days, is_archived, facility_status",
    )
    .in("user_id", userIds);
  const facilityById = new Map(
    ((facilities ?? []) as FacilityRow[]).map((f) => [f.account_id, f]),
  );

  const { data: statements } = await finance
    .from("credit_card_statement_summaries")
    .select(
      "id, user_id, account_id, due_on, cycle_close, total_remaining_minor, remaining_minor, currency_code, obligation_status",
    )
    .in("user_id", userIds)
    .gt("total_remaining_minor", 0);

  const { data: dues } = await finance
    .from("installment_due_statuses")
    .select(
      "id, user_id, account_id, due_on, remaining_minor, currency_code, plan_status, is_presettled",
    )
    .in("user_id", userIds)
    .eq("plan_status", "active")
    .eq("is_presettled", false)
    .gt("remaining_minor", 0);

  const obligations: Obligation[] = [
    ...((statements ?? []) as Record<string, unknown>[])
      .filter((row) =>
        row.obligation_status !== "paid" && row.obligation_status !== "open"
      )
      .map((row) => {
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
    ...((dues ?? []) as Record<string, unknown>[]).map((row) => {
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

  let created = 0;
  for (const device of typedDevices) {
    const timezone = device.timezone ?? "Africa/Cairo";
    const { date: localDate, hour } = localParts(timezone);
    const prefs = preferences.get(device.user_id);
    const dueEnabled = prefs?.due_reminders_enabled ?? true;
    const overdueEnabled = prefs?.overdue_reminders_enabled ?? true;
    if (hour < SEND_HOUR_LOCAL) continue;

    for (
      const obligation of obligations.filter((o) => o.userId === device.user_id)
    ) {
      const diff = dayDiff(localDate, obligation.dueOn);
      const facility = facilityById.get(obligation.accountId);
      const lead = facility?.reminder_lead_days ?? 3;
      let kind: "due_soon" | "due_today" | "overdue" | null = null;
      if (diff === lead && lead > 0 && dueEnabled) kind = "due_soon";
      else if (diff === 0 && dueEnabled) kind = "due_today";
      else if (diff === -1 && overdueEnabled) kind = "overdue";
      if (!kind) continue;

      const showAmounts = prefs?.show_amounts ?? false;
      const payload = {
        type: obligation.type,
        obligation_id: obligation.id,
        account_id: obligation.accountId,
        account_name: obligation.accountName,
        reminder_kind: kind,
        due_on: obligation.dueOn,
        amount_text: showAmounts
          ? formatAmount(
            obligation.amountMinor,
            obligation.currencyCode,
            device.locale,
          )
          : null,
      };
      const { error } = await core.from("notification_outbox").insert({
        user_id: obligation.userId,
        device_id: device.id,
        obligation_type: obligation.type,
        obligation_id: obligation.id,
        reminder_kind: kind,
        scheduled_local_date: localDate,
        status: "pending",
        next_attempt_at: new Date().toISOString(),
        payload_snapshot: payload,
      });
      if (!error) created++;
      else if (error.code !== "23505") throw error;
    }
  }

  await materializePaymentConfirmations(
    core,
    finance,
    typedDevices,
    preferences,
    facilityById,
  );
  return created;
}

async function materializePaymentConfirmations(
  core: SupabaseClient,
  finance: SupabaseClient,
  devices: DeviceRow[],
  preferences: Map<string, PreferenceRow>,
  facilityById: Map<string, FacilityRow>,
): Promise<void> {
  const userIds = [...new Set(devices.map((d) => d.user_id))];
  const { data: payments } = await finance
    .from("financial_transactions")
    .select(
      "id, user_id, destination_account_id, amount_minor, currency_code, created_at",
    )
    .in("user_id", userIds)
    .eq("transaction_kind", "transfer")
    .not("destination_account_id", "is", null)
    .gte("created_at", new Date(Date.now() - 24 * 60 * 60_000).toISOString())
    .order("created_at", { ascending: false })
    .limit(100);

  for (const payment of (payments ?? []) as Record<string, unknown>[]) {
    const accountId = payment.destination_account_id as string;
    const facility = facilityById.get(accountId);
    if (!facility) continue;
    const prefs = preferences.get(payment.user_id as string);
    if ((prefs?.payment_confirmations_enabled ?? true) !== true) continue;
    const paymentDevices = devices.filter((d) => d.user_id === payment.user_id);
    for (const device of paymentDevices) {
      const payload = {
        type: "facility_payment_confirmation",
        obligation_id: payment.id,
        account_id: accountId,
        account_name: facility.name ?? "Credit facility",
        reminder_kind: "payment_confirmation",
        amount_text: (prefs?.show_amounts ?? false)
          ? formatAmount(
            Number(payment.amount_minor ?? 0),
            payment.currency_code as string,
            device.locale,
          )
          : null,
      };
      await core.from("notification_outbox").insert({
        user_id: payment.user_id,
        device_id: device.id,
        obligation_type: "facility_payment",
        obligation_id: payment.id,
        reminder_kind: "payment_confirmation",
        scheduled_local_date:
          localParts(device.timezone ?? "Africa/Cairo").date,
        status: "pending",
        next_attempt_at: new Date().toISOString(),
        payload_snapshot: payload,
      });
    }
  }
}

async function sendClaimed(
  core: SupabaseClient,
  finance: SupabaseClient,
  account: ServiceAccount,
): Promise<
  { sent: number; retry: number; failed: number; suppressed: number }
> {
  const { data, error } = await core.rpc("claim_notification_outbox", {
    batch_size: BATCH_SIZE,
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

  for (const row of rows) {
    const payload = row.payload_snapshot ?? {};
    if (!(await stillEligible(core, finance, row))) {
      suppressed++;
      await core.from("notification_outbox").update({
        status: "suppressed",
        error: "stale_or_disabled",
      }).eq("id", row.id);
      continue;
    }
    const notification = compose(payload, row.locale);
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
          data: fcmData(payload),
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
      }).eq("id", row.id);
      continue;
    }

    const errorText = (await response.text()).slice(0, 500);
    const permanentToken = response.status === 404 ||
      errorText.includes("UNREGISTERED") ||
      errorText.includes("INVALID_ARGUMENT");
    const transient = response.status === 429 || response.status === 500 ||
      response.status === 503;

    if (permanentToken) {
      failed++;
      await core.from("push_devices").update({ is_enabled: false }).eq(
        "id",
        row.device_id,
      );
      await core.from("notification_outbox").update({
        status: "failed",
        permanently_failed_at: new Date().toISOString(),
        error: `fcm_permanent_${response.status}`,
      }).eq("id", row.id);
    } else if (transient && row.attempt_count < MAX_ATTEMPTS) {
      retry++;
      await core.from("notification_outbox").update({
        status: "retry",
        next_attempt_at: backoff(row.attempt_count),
        error: `fcm_transient_${response.status}`,
      }).eq("id", row.id);
    } else {
      failed++;
      await core.from("notification_outbox").update({
        status: "failed",
        permanently_failed_at: new Date().toISOString(),
        error: `fcm_failed_${response.status}`,
      }).eq("id", row.id);
    }
  }
  return { sent, retry, failed, suppressed };
}

async function stillEligible(
  core: SupabaseClient,
  finance: SupabaseClient,
  row: ClaimedRow,
): Promise<boolean> {
  if (row.payload_snapshot?.type === "developer_test") return true;

  const { data: device } = await core
    .from("push_devices")
    .select("is_enabled")
    .eq("id", row.device_id)
    .maybeSingle();
  if (device?.is_enabled !== true) return false;

  const { data: prefs } = await core
    .from("notification_preferences")
    .select(
      "due_reminders_enabled, overdue_reminders_enabled, payment_confirmations_enabled",
    )
    .eq("user_id", row.user_id)
    .maybeSingle();
  if (
    row.reminder_kind === "overdue" &&
    prefs?.overdue_reminders_enabled === false
  ) {
    return false;
  }
  if (row.reminder_kind === "payment_confirmation") {
    return prefs?.payment_confirmations_enabled !== false;
  }
  if (prefs?.due_reminders_enabled === false) return false;

  if (row.obligation_type === "credit_card_statement_due") {
    const { data } = await finance
      .from("credit_card_statement_summaries")
      .select("total_remaining_minor, obligation_status")
      .eq("id", row.obligation_id)
      .maybeSingle();
    return Number(data?.total_remaining_minor ?? 0) > 0 &&
      !["paid", "open"].includes(String(data?.obligation_status ?? ""));
  }
  if (
    row.obligation_type === "network_transfer" &&
    row.reminder_kind === "network_transfer_pending"
  ) {
    // A transfer decided before the push went out no longer needs one.
    const { data } = await finance
      .from("network_transfers")
      .select("status")
      .eq("id", row.obligation_id)
      .maybeSingle();
    return data?.status === "pending";
  }
  if (
    row.obligation_type === "installment_due" ||
    row.obligation_type === "bnpl_due"
  ) {
    const { data } = await finance
      .from("installment_due_statuses")
      .select("remaining_minor, plan_status, is_presettled")
      .eq("id", row.obligation_id)
      .maybeSingle();
    return Number(data?.remaining_minor ?? 0) > 0 &&
      data?.plan_status === "active" &&
      data?.is_presettled !== true;
  }
  return true;
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
    const materialized = await materialize(core, finance);
    const delivery = await sendClaimed(core, finance, account);
    const result = {
      invocationId,
      materialized,
      claimed: delivery.sent + delivery.retry + delivery.failed +
        delivery.suppressed,
      ...delivery,
      durationMs: Date.now() - started,
    };
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
