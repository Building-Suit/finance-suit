import { createClient } from "npm:@supabase/supabase-js@2.110.7";
import {
  extractSubscriptionLineItem,
  getGoogleSubscriptionPurchaseV2,
  normalizeGoogleSubscriptionStatus,
  sanitizeProviderPayload,
  sha256,
} from "../_shared/google_play.ts";

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

function supabaseAdmin() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) return null;
  return createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
      detectSessionInUrl: false,
    },
  });
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return json(405, { code: "method_not_allowed" });
  }
  const authorization = request.headers.get("authorization");
  const accessToken = authorization?.match(/^Bearer\s+([^\s]+)$/i)?.[1];
  if (!accessToken) return json(401, { code: "missing_access_token" });

  let body: VerifyBody;
  try {
    body = await request.json();
  } catch {
    return json(400, { code: "invalid_request" });
  }
  if (
    body.provider !== "google_play" || !body.productId || !body.purchaseToken
  ) {
    return json(400, { code: "invalid_purchase_payload" });
  }

  const admin = supabaseAdmin();
  if (!admin) return json(503, { code: "server_misconfigured" });
  const { data: { user }, error: userError } = await admin.auth.getUser(
    accessToken,
  );
  if (userError || !user) return json(401, { code: "invalid_access_token" });

  let providerPayload: Record<string, unknown>;
  try {
    providerPayload = await getGoogleSubscriptionPurchaseV2(body.purchaseToken);
  } catch (error) {
    const code = error instanceof Error && "kind" in error
      ? String(error.kind)
      : "provider_verification_unavailable";
    const retryable = error instanceof Error && "retryable" in error &&
      error.retryable === true;
    return json(retryable ? 503 : 400, { code: `provider_${code}` });
  }

  const lineItem = extractSubscriptionLineItem(
    providerPayload,
    body.productId,
    body.basePlanId,
  );
  const normalized = normalizeGoogleSubscriptionStatus(
    providerPayload,
    lineItem,
  );
  const productId = normalized.productId ?? body.productId;
  const basePlanId = normalized.basePlanId ?? body.basePlanId ?? null;
  const { data: price } = await admin
    .schema("app_commercial")
    .from("plan_prices")
    .select("id, plan_key")
    .eq("provider", "google_play")
    .eq("provider_product_id", productId)
    .eq("provider_base_plan_id", basePlanId)
    .eq("status", "published")
    .maybeSingle();
  if (!price) return json(400, { code: "provider_mapping_not_published" });

  const tokenHash = await sha256(body.purchaseToken);
  const subscription = {
    user_id: user.id,
    provider: "google_play",
    plan_key: price.plan_key,
    plan_price_id: price.id,
    provider_product_id: productId,
    provider_base_plan_id: basePlanId,
    provider_purchase_token_hash: tokenHash,
    provider_obfuscated_account_id:
      (providerPayload.externalAccountIdentifiers as
        | Record<string, unknown>
        | undefined)?.obfuscatedExternalAccountId ?? null,
    status: normalized.status,
    starts_at: normalized.startsAt,
    expires_at: normalized.expiresAt,
    auto_renewing: normalized.autoRenewing,
    canceled_at: normalized.canceledAt,
    last_verified_at: new Date().toISOString(),
    provider_raw_status: normalized.providerRawStatus,
    provider_payload: sanitizeProviderPayload(providerPayload),
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
    console.error(
      `google-play-billing: subscription upsert failed: ${error.message}`,
    );
    return json(500, { code: "subscription_persist_failed" });
  }

  const eventResult = await admin.schema("app_commercial").from(
    "billing_events",
  ).upsert({
    provider: "google_play",
    provider_event_id: `client:${tokenHash}:${normalized.status}:${
      data.expires_at ?? "none"
    }`,
    event_type: body.action === "restore" ? "restored" : "verified",
    subscription_id: data.id,
    user_id: user.id,
    processed_at: new Date().toISOString(),
    processing_result: "processed",
    payload: { productId, basePlanId },
  }, { onConflict: "provider,provider_event_id" });
  if (eventResult.error) return json(500, { code: "event_persist_failed" });

  const { data: entitlement } = await admin
    .schema("app_commercial")
    .rpc("resolve_effective_entitlement", { p_user_id: user.id });
  return json(200, {
    subscription: data,
    entitlement: Array.isArray(entitlement) ? entitlement[0] : entitlement,
  });
});
