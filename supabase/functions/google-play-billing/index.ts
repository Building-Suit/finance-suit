import { createClient } from "npm:@supabase/supabase-js@2.110.7";

const jsonHeaders = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

type VerifyBody = {
  action?: "verify_purchase" | "restore";
  provider?: "google_play";
  productId?: string;
  basePlanId?: string;
  purchaseToken?: string;
};

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function googleAccessToken(): Promise<string | null> {
  const rawCredentials = Deno.env.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON");
  if (!rawCredentials) return null;
  const credentials = JSON.parse(rawCredentials);
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claim = {
    iss: credentials.client_email,
    scope: "https://www.googleapis.com/auth/androidpublisher",
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now,
  };
  const enc = (input: unknown) =>
    btoa(JSON.stringify(input)).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
  const unsigned = `${enc(header)}.${enc(claim)}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(credentials.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${base64Url(signature)}`;
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!response.ok) return null;
  const payload = await response.json();
  return typeof payload.access_token === "string" ? payload.access_token : null;
}

function base64Url(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binary = "";
  bytes.forEach((b) => binary += String.fromCharCode(b));
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

function normalizeStatus(state: string | undefined, expiresAt: Date | null): string {
  if (state === "SUBSCRIPTION_STATE_PENDING") return "pending";
  if (state === "SUBSCRIPTION_STATE_IN_GRACE_PERIOD") return "in_grace_period";
  if (state === "SUBSCRIPTION_STATE_ON_HOLD") return "on_hold";
  if (state === "SUBSCRIPTION_STATE_PAUSED") return "paused";
  if (state === "SUBSCRIPTION_STATE_CANCELED") {
    return expiresAt && expiresAt > new Date() ? "canceled" : "expired";
  }
  if (state === "SUBSCRIPTION_STATE_EXPIRED") return "expired";
  if (state === "SUBSCRIPTION_STATE_ACTIVE") return "active";
  return "verification_failed";
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return json(405, { code: "method_not_allowed" });

  const authorization = request.headers.get("authorization");
  const accessToken = authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!accessToken) return json(401, { code: "missing_access_token" });

  let body: VerifyBody;
  try {
    body = await request.json();
  } catch {
    return json(400, { code: "invalid_request" });
  }
  if (body.provider !== "google_play" || !body.productId || !body.purchaseToken) {
    return json(400, { code: "invalid_purchase_payload" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const packageName = Deno.env.get("GOOGLE_PLAY_PACKAGE_NAME") ?? "com.buildingsuit.finance";
  if (!supabaseUrl || !serviceRoleKey) {
    console.error("google-play-billing: Supabase service role unavailable");
    return json(500, { code: "server_misconfigured" });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
  });
  const { data: { user }, error: userError } = await admin.auth.getUser(accessToken);
  if (userError || !user) return json(401, { code: "invalid_access_token" });

  const googleToken = await googleAccessToken();
  if (!googleToken) {
    console.error("google-play-billing: Google Play credentials unavailable");
    return json(503, { code: "provider_verification_unavailable" });
  }

  const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${packageName}/purchases/subscriptionsv2/tokens/${encodeURIComponent(body.purchaseToken)}`;
  const providerResponse = await fetch(url, {
    headers: { authorization: `Bearer ${googleToken}` },
  });
  const providerPayload = await providerResponse.json().catch(() => ({}));
  if (!providerResponse.ok) {
    console.error(`google-play-billing: verify failed ${providerResponse.status}`);
    return json(400, { code: "provider_purchase_invalid" });
  }

  const lineItem = Array.isArray(providerPayload.lineItems)
    ? providerPayload.lineItems[0]
    : null;
  const expiryIso = lineItem?.expiryTime;
  const expiresAt = typeof expiryIso === "string" ? new Date(expiryIso) : null;
  const status = normalizeStatus(providerPayload.subscriptionState, expiresAt);
  const autoRenewing = lineItem?.autoRenewingPlan?.autoRenewEnabled;
  const basePlanId = body.basePlanId ?? lineItem?.offerDetails?.basePlanId ?? null;
  const tokenHash = await sha256(body.purchaseToken);

  const { data: price } = await admin
    .schema("app_commercial")
    .from("plan_prices")
    .select("id, plan_key")
    .eq("provider", "google_play")
    .eq("provider_product_id", body.productId)
    .eq("provider_base_plan_id", basePlanId)
    .eq("status", "published")
    .maybeSingle();

  if (!price) return json(400, { code: "provider_mapping_not_published" });

  const subscription = {
    user_id: user.id,
    provider: "google_play",
    plan_key: price.plan_key,
    plan_price_id: price.id,
    provider_product_id: body.productId,
    provider_base_plan_id: basePlanId,
    provider_purchase_token_hash: tokenHash,
    provider_obfuscated_account_id: providerPayload.externalAccountIdentifiers?.obfuscatedExternalAccountId ?? null,
    status,
    starts_at: providerPayload.startTime ?? null,
    expires_at: expiresAt?.toISOString() ?? null,
    auto_renewing: typeof autoRenewing === "boolean" ? autoRenewing : null,
    canceled_at: status === "canceled" ? new Date().toISOString() : null,
    last_verified_at: new Date().toISOString(),
    provider_raw_status: providerPayload.subscriptionState ?? null,
    provider_payload: providerPayload,
  };

  const { data, error } = await admin
    .schema("app_commercial")
    .from("paid_subscriptions")
    .upsert(subscription, {
      onConflict: "provider,provider_purchase_token_hash",
    })
    .select("id,status,expires_at,auto_renewing,provider_base_plan_id")
    .single();
  if (error) {
    console.error(`google-play-billing: subscription upsert failed: ${error.message}`);
    return json(500, { code: "subscription_persist_failed" });
  }

  await admin.schema("app_commercial").from("billing_events").upsert({
    provider: "google_play",
    provider_event_id: `client:${tokenHash}:${status}:${data.expires_at ?? "none"}`,
    event_type: body.action === "restore" ? "restored" : "verified",
    subscription_id: data.id,
    user_id: user.id,
    processed_at: new Date().toISOString(),
    processing_result: "processed",
    payload: { productId: body.productId, basePlanId },
  }, { onConflict: "provider,provider_event_id" });

  const { data: entitlement } = await admin
    .schema("app_commercial")
    .rpc("resolve_effective_entitlement", { p_user_id: user.id });

  return json(200, {
    subscription: data,
    entitlement: Array.isArray(entitlement) ? entitlement[0] : entitlement,
  });
});
