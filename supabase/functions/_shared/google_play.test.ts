import {
  normalizeGoogleSubscriptionStatus,
  sanitizeProviderPayload,
} from "./google_play.ts";

function purchase(state: string, expiryTime = "2030-01-01T00:00:00Z") {
  return {
    subscriptionState: state,
    startTime: "2026-01-01T00:00:00Z",
    lineItems: [{
      productId: "finance_suit_pro",
      expiryTime,
      offerDetails: { basePlanId: "pro-monthly-egp" },
      autoRenewingPlan: { autoRenewEnabled: true },
    }],
  };
}

Deno.test("Google API state, not RTDN type, determines normalized status", () => {
  const renewedNotificationWithOnHold = purchase("SUBSCRIPTION_STATE_ON_HOLD");
  const result = normalizeGoogleSubscriptionStatus(
    renewedNotificationWithOnHold,
  );
  if (result.status !== "on_hold") {
    throw new Error(`expected on_hold, got ${result.status}`);
  }
});

Deno.test("canceled subscription remains canceled until verified expiry", () => {
  const result = normalizeGoogleSubscriptionStatus(
    purchase("SUBSCRIPTION_STATE_CANCELED"),
  );
  if (result.status !== "canceled") {
    throw new Error(`expected canceled, got ${result.status}`);
  }
});

Deno.test("canceled subscription becomes expired after verified expiry", () => {
  const result = normalizeGoogleSubscriptionStatus(
    purchase("SUBSCRIPTION_STATE_CANCELED", "2020-01-01T00:00:00Z"),
  );
  if (result.status !== "expired") {
    throw new Error(`expected expired, got ${result.status}`);
  }
});

Deno.test("provider payload sanitizer removes purchase tokens recursively", () => {
  const result = sanitizeProviderPayload({
    purchaseToken: "secret",
    nested: { purchaseToken: "secret", safe: "value" },
  }) as Record<string, unknown>;
  if ("purchaseToken" in result) throw new Error("root token was retained");
  if ((result.nested as Record<string, unknown>).purchaseToken) {
    throw new Error("nested token was retained");
  }
  if ((result.nested as Record<string, unknown>).safe !== "value") {
    throw new Error("safe value was removed");
  }
});
