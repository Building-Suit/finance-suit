import { createClient } from "npm:@supabase/supabase-js@2.110.7";

const jsonHeaders = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function eventType(code: number | undefined): string {
  switch (code) {
    case 1:
      return "recovered";
    case 2:
      return "renewed";
    case 3:
      return "canceled";
    case 4:
      return "purchased";
    case 5:
      return "on_hold";
    case 6:
      return "in_grace_period";
    case 7:
      return "restarted";
    case 8:
      return "price_change_confirmed";
    case 9:
      return "deferred";
    case 10:
      return "paused";
    case 11:
      return "pause_schedule_changed";
    case 12:
      return "revoked";
    case 13:
      return "expired";
    case 20:
      return "pending_purchase_canceled";
    default:
      return "unknown";
  }
}

function statusFromEvent(type: string): string | null {
  switch (type) {
    case "purchased":
    case "renewed":
    case "recovered":
    case "restarted":
      return "active";
    case "in_grace_period":
      return "in_grace_period";
    case "on_hold":
      return "on_hold";
    case "paused":
      return "paused";
    case "canceled":
      return "canceled";
    case "revoked":
      return "revoked";
    case "expired":
    case "pending_purchase_canceled":
      return "expired";
    default:
      return null;
  }
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return json(405, { code: "method_not_allowed" });

  const expectedToken = Deno.env.get("GOOGLE_PLAY_RTDN_SHARED_SECRET");
  if (expectedToken) {
    const actual = request.headers.get("x-finance-suit-rtdn-secret");
    if (actual !== expectedToken) return json(401, { code: "invalid_rtdn_secret" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    console.error("google-play-rtdn: Supabase service role unavailable");
    return json(500, { code: "server_misconfigured" });
  }

  let envelope: Record<string, unknown>;
  try {
    envelope = await request.json();
  } catch {
    return json(400, { code: "invalid_request" });
  }

  const message = envelope.message as Record<string, unknown> | undefined;
  const eventId = String(message?.messageId ?? envelope.messageId ?? crypto.randomUUID());
  const data = typeof message?.data === "string"
    ? JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(message.data), (c) => c.charCodeAt(0))))
    : envelope;
  const subscriptionNotification = data.subscriptionNotification ?? {};
  const notificationType = Number(subscriptionNotification.notificationType);
  const type = eventType(Number.isFinite(notificationType) ? notificationType : undefined);
  const token = String(subscriptionNotification.purchaseToken ?? "");
  const tokenHash = token ? await sha256(token) : null;

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
  });

  const { data: existing } = tokenHash
    ? await admin
      .schema("app_commercial")
      .from("paid_subscriptions")
      .select("id,user_id")
      .eq("provider", "google_play")
      .eq("provider_purchase_token_hash", tokenHash)
      .maybeSingle()
    : { data: null };

  const { error } = await admin.schema("app_commercial").from("billing_events").upsert({
    provider: "google_play",
    provider_event_id: eventId,
    event_type: type,
    subscription_id: existing?.id ?? null,
    user_id: existing?.user_id ?? null,
    processed_at: new Date().toISOString(),
    processing_result: existing ? "processed" : "stored_unmatched",
    payload: data,
  }, { onConflict: "provider,provider_event_id" });
  if (error) {
    console.error(`google-play-rtdn: event persist failed: ${error.message}`);
    return json(500, { code: "event_persist_failed" });
  }

  const status = statusFromEvent(type);
  if (existing?.id && status) {
    await admin.schema("app_commercial").from("paid_subscriptions").update({
      status,
      last_verified_at: new Date().toISOString(),
      provider_raw_status: type,
    }).eq("id", existing.id);
  }

  return json(200, { processed: true, eventType: type, matched: Boolean(existing) });
});
