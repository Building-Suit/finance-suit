import { createClient } from "npm:@supabase/supabase-js@2.110.7";
import {
  RtdnAuthError,
  verifyPubSubOidcRequest,
} from "../_shared/rtdn_auth.ts";
import {
  getGoogleSubscriptionPurchaseV2,
  type GooglePlayError,
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

function eventType(code: number | undefined): string {
  const names: Record<number, string> = {
    1: "recovered",
    2: "renewed",
    3: "canceled",
    4: "purchased",
    5: "on_hold",
    6: "in_grace_period",
    7: "restarted",
    8: "price_change_confirmed",
    9: "deferred",
    10: "paused",
    11: "pause_schedule_changed",
    12: "revoked",
    13: "expired",
    17: "subscription_items_changed",
    18: "cancellation_scheduled",
    19: "price_change_updated",
    20: "pending_purchase_canceled",
    22: "price_step_up_consent_updated",
  };
  return typeof code === "number" && Number.isInteger(code) && names[code]
    ? names[code]
    : "unknown";
}

function safeRtdnPayload(
  payload: Record<string, unknown>,
  messageId: string,
  purchaseTokenHash: string | null,
) {
  const notification = payload.subscriptionNotification as
    | Record<string, unknown>
    | undefined;
  const test = payload.testNotification as Record<string, unknown> | undefined;
  return {
    packageName: payload.packageName ?? null,
    eventTimeMillis: payload.eventTimeMillis ?? null,
    version: payload.version ?? null,
    messageId,
    purchaseTokenHash,
    notificationType: typeof notification?.notificationType === "number"
      ? notification.notificationType
      : null,
    notificationVersion: notification?.version ?? test?.version ?? null,
    rootType: notification
      ? "subscriptionNotification"
      : test
      ? "testNotification"
      : "unknown",
  };
}

function adminClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  return url && key
    ? createClient(url, key, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUrl: false,
      },
    })
    : null;
}

async function updateEvent(
  admin: ReturnType<typeof adminClient>,
  messageId: string,
  values: Record<string, unknown>,
) {
  if (!admin) return new Error("admin client unavailable");
  const { error } = await admin.schema("app_commercial").from("billing_events")
    .update(values).eq("provider", "google_play").eq(
      "provider_event_id",
      messageId,
    );
  return error;
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return json(405, { code: "method_not_allowed" });
  }
  try {
    await verifyPubSubOidcRequest(request);
  } catch (error) {
    if (error instanceof RtdnAuthError && error.code === "misconfigured") {
      return json(503, { code: "server_misconfigured" });
    }
    return json(
      error instanceof RtdnAuthError && error.code === "invalid" ? 403 : 401,
      { code: "invalid_pubsub_oidc" },
    );
  }

  const admin = adminClient();
  if (!admin) return json(503, { code: "server_misconfigured" });
  let envelope: Record<string, unknown>;
  try {
    envelope = await request.json();
  } catch {
    return json(400, { code: "invalid_json" });
  }
  const message = envelope.message;
  if (!message || typeof message !== "object") {
    return json(400, { code: "missing_message" });
  }
  const pubsubMessage = message as Record<string, unknown>;
  const messageId = typeof pubsubMessage.messageId === "string" &&
      pubsubMessage.messageId.length > 0
    ? pubsubMessage.messageId
    : null;
  if (!messageId) return json(400, { code: "missing_message_id" });
  if (
    typeof pubsubMessage.data !== "string" ||
    !/^[A-Za-z0-9+/]*={0,2}$/.test(pubsubMessage.data)
  ) {
    return json(400, { code: "invalid_base64" });
  }

  let payload: Record<string, unknown>;
  try {
    const bytes = Uint8Array.from(
      atob(pubsubMessage.data),
      (character) => character.charCodeAt(0),
    );
    const decoded = JSON.parse(new TextDecoder().decode(bytes));
    if (!decoded || typeof decoded !== "object" || Array.isArray(decoded)) {
      throw new Error("not an object");
    }
    payload = decoded as Record<string, unknown>;
  } catch {
    return json(400, { code: "invalid_rtdn_payload" });
  }
  if (
    payload.packageName !==
      (Deno.env.get("GOOGLE_PLAY_PACKAGE_NAME") ?? "com.buildingsuit.finance")
  ) {
    return json(200, { processed: false, result: "wrong_package" });
  }
  const testNotification = payload.testNotification;
  const subscriptionNotification = payload.subscriptionNotification as
    | Record<string, unknown>
    | undefined;
  if (
    (!testNotification || typeof testNotification !== "object") &&
    !subscriptionNotification
  ) {
    return json(200, { processed: false, result: "unsupported_notification" });
  }
  const token = typeof subscriptionNotification?.purchaseToken === "string"
    ? subscriptionNotification.purchaseToken
    : null;
  const tokenHash = token ? await sha256(token) : null;
  const safePayload = safeRtdnPayload(payload, messageId, tokenHash);
  const eventName = testNotification
    ? "rtdn_test"
    : eventType(Number(subscriptionNotification?.notificationType));

  const { data: prior } = await admin.schema("app_commercial").from(
    "billing_events",
  )
    .select("id,processing_result,subscription_id,user_id")
    .eq("provider", "google_play").eq("provider_event_id", messageId)
    .maybeSingle();
  if (
    prior &&
    [
      "processed",
      "ignored_test",
      "verified_unmatched",
      "provider_mapping_not_published",
      "verification_permanent_failure",
    ].includes(prior.processing_result)
  ) {
    return json(200, { processed: true, duplicate: true });
  }
  const { error: receivedError } = await admin.schema("app_commercial").from(
    "billing_events",
  ).upsert({
    provider: "google_play",
    provider_event_id: messageId,
    event_type: eventName,
    subscription_id: prior?.subscription_id ?? null,
    user_id: prior?.user_id ?? null,
    processing_result: "received",
    payload: safePayload,
  }, { onConflict: "provider,provider_event_id" });
  if (receivedError) return json(500, { code: "event_persist_failed" });
  if (testNotification) {
    const error = await updateEvent(admin, messageId, {
      processed_at: new Date().toISOString(),
      processing_result: "ignored_test",
      payload: safePayload,
    });
    return error
      ? json(500, { code: "event_persist_failed" })
      : json(200, { processed: true, testNotification: true });
  }
  if (!token) {
    const error = await updateEvent(admin, messageId, {
      processed_at: new Date().toISOString(),
      processing_result: "verification_permanent_failure",
    });
    return error
      ? json(500, { code: "event_persist_failed" })
      : json(200, { processed: false, result: "missing_purchase_token" });
  }

  let providerPayload: Record<string, unknown>;
  try {
    providerPayload = await getGoogleSubscriptionPurchaseV2(token);
  } catch (error) {
    const providerError = error as GooglePlayError;
    const result = providerError?.retryable
      ? "verification_retryable_failure"
      : "verification_permanent_failure";
    const persistError = await updateEvent(admin, messageId, {
      processed_at: providerError?.retryable ? null : new Date().toISOString(),
      processing_result: result,
    });
    if (persistError) return json(500, { code: "event_persist_failed" });
    return json(providerError?.retryable ? 503 : 200, {
      processed: false,
      result,
    });
  }

  const lineItems = providerPayload.lineItems as Array<Record<string, unknown>>;
  const { data: publishedMappings, error: mappingError } = await admin
    .schema("app_commercial")
    .from("plan_prices")
    .select("id,plan_key,provider_product_id,provider_base_plan_id")
    .eq("provider", "google_play")
    .eq("status", "published");
  if (mappingError) return json(500, { code: "mapping_lookup_failed" });
  const mappedItems = lineItems.filter((item) => {
    const offer = item.offerDetails as Record<string, unknown> | undefined;
    return publishedMappings?.some((mapping) =>
      mapping.provider_product_id === item.productId &&
      mapping.provider_base_plan_id === offer?.basePlanId
    );
  });
  const lineItem = mappedItems.length === 1
    ? mappedItems[0]
    : mappedItems.sort((left, right) =>
      String(right.expiryTime ?? "").localeCompare(
        String(left.expiryTime ?? ""),
      ) ||
      String(left.productId ?? "").localeCompare(String(right.productId ?? ""))
    )[0] ?? null;
  const normalized = normalizeGoogleSubscriptionStatus(
    providerPayload,
    lineItem,
  );
  const productId = normalized.productId;
  const basePlanId = normalized.basePlanId;
  const price = publishedMappings?.find((mapping) =>
    mapping.provider_product_id === productId &&
    mapping.provider_base_plan_id === basePlanId
  ) ?? null;
  if (!price || !productId || !basePlanId) {
    const error = await updateEvent(admin, messageId, {
      processed_at: new Date().toISOString(),
      processing_result: "provider_mapping_not_published",
      payload: safePayload,
    });
    return error ? json(500, { code: "event_persist_failed" }) : json(200, {
      processed: true,
      result: "provider_mapping_not_published",
    });
  }

  const { data: existing } = await admin.schema("app_commercial").from(
    "paid_subscriptions",
  )
    .select("id,user_id").eq("provider", "google_play").eq(
      "provider_purchase_token_hash",
      tokenHash,
    ).maybeSingle();
  if (!existing) {
    const error = await updateEvent(admin, messageId, {
      processed_at: new Date().toISOString(),
      processing_result: "verified_unmatched",
      payload: safePayload,
    });
    return error
      ? json(500, { code: "event_persist_failed" })
      : json(200, { processed: true, result: "verified_unmatched" });
  }
  const { error: subscriptionError } = await admin.schema("app_commercial")
    .from("paid_subscriptions").update({
      plan_key: price.plan_key,
      plan_price_id: price.id,
      provider_product_id: productId,
      provider_base_plan_id: basePlanId,
      status: normalized.status,
      starts_at: normalized.startsAt,
      expires_at: normalized.expiresAt,
      auto_renewing: normalized.autoRenewing,
      canceled_at: normalized.canceledAt,
      last_verified_at: new Date().toISOString(),
      provider_raw_status: normalized.providerRawStatus,
      provider_payload: sanitizeProviderPayload(providerPayload),
    }).eq("id", existing.id);
  if (subscriptionError) {
    return json(500, { code: "subscription_persist_failed" });
  }
  const eventError = await updateEvent(admin, messageId, {
    subscription_id: existing.id,
    user_id: existing.user_id,
    processed_at: new Date().toISOString(),
    processing_result: "processed",
    payload: safePayload,
  });
  return eventError
    ? json(500, { code: "event_persist_failed" })
    : json(200, { processed: true, matched: true, eventType: eventName });
});
