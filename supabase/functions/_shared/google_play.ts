export const GOOGLE_PLAY_OAUTH_SCOPE =
  "https://www.googleapis.com/auth/androidpublisher";
export const GOOGLE_PLAY_PACKAGE_NAME = "com.buildingsuit.finance";

export type GoogleSubscriptionPurchaseV2 = Record<string, unknown>;

export class GooglePlayError extends Error {
  constructor(
    message: string,
    readonly kind:
      | "credentials_unavailable"
      | "oauth_failure"
      | "permission_denied"
      | "not_found"
      | "rate_limited"
      | "provider_server_error"
      | "malformed_response",
    readonly retryable: boolean,
  ) {
    super(message);
    this.name = "GooglePlayError";
  }
}

export async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function base64Url(buffer: ArrayBuffer): string {
  let binary = "";
  for (const byte of new Uint8Array(buffer)) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll(
    "=",
    "",
  );
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes.buffer;
}

function encodeBase64Url(value: unknown): string {
  return btoa(JSON.stringify(value))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

export async function getGooglePlayAccessToken(): Promise<string> {
  const rawCredentials = Deno.env.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON");
  if (!rawCredentials) {
    throw new GooglePlayError(
      "Google Play credentials unavailable",
      "credentials_unavailable",
      true,
    );
  }

  let credentials: { client_email?: string; private_key?: string };
  try {
    credentials = JSON.parse(rawCredentials);
  } catch {
    throw new GooglePlayError(
      "Google Play credentials are malformed",
      "credentials_unavailable",
      false,
    );
  }
  if (!credentials.client_email || !credentials.private_key) {
    throw new GooglePlayError(
      "Google Play credentials are incomplete",
      "credentials_unavailable",
      false,
    );
  }

  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${encodeBase64Url({ alg: "RS256", typ: "JWT" })}.${
    encodeBase64Url({
      iss: credentials.client_email,
      scope: GOOGLE_PLAY_OAUTH_SCOPE,
      aud: "https://oauth2.googleapis.com/token",
      exp: now + 3600,
      iat: now,
    })
  }`;
  let signature: ArrayBuffer;
  try {
    const key = await crypto.subtle.importKey(
      "pkcs8",
      pemToArrayBuffer(credentials.private_key),
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["sign"],
    );
    signature = await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      new TextEncoder().encode(unsigned),
    );
  } catch {
    throw new GooglePlayError(
      "Google Play credentials cannot sign OAuth assertion",
      "credentials_unavailable",
      false,
    );
  }

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${unsigned}.${base64Url(signature)}`,
    }),
  });
  if (!response.ok) {
    throw new GooglePlayError(
      "Google OAuth token request failed",
      "oauth_failure",
      response.status >= 500 || response.status === 429,
    );
  }
  const payload = await response.json().catch(() => null);
  if (!payload || typeof payload.access_token !== "string") {
    throw new GooglePlayError(
      "Google OAuth response is malformed",
      "oauth_failure",
      false,
    );
  }
  return payload.access_token;
}

export async function getGoogleSubscriptionPurchaseV2(
  purchaseToken: string,
): Promise<GoogleSubscriptionPurchaseV2> {
  const packageName = Deno.env.get("GOOGLE_PLAY_PACKAGE_NAME") ??
    GOOGLE_PLAY_PACKAGE_NAME;
  const accessToken = await getGooglePlayAccessToken();
  const response = await fetch(
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${packageName}/purchases/subscriptionsv2/tokens/${
      encodeURIComponent(purchaseToken)
    }`,
    { headers: { authorization: `Bearer ${accessToken}` } },
  );
  const payload = await response.json().catch(() => null);
  if (!response.ok) {
    const kind = response.status === 401 || response.status === 403
      ? "permission_denied"
      : response.status === 404
      ? "not_found"
      : response.status === 429
      ? "rate_limited"
      : response.status >= 500
      ? "provider_server_error"
      : "malformed_response";
    throw new GooglePlayError(
      "Google subscription lookup failed",
      kind,
      kind === "rate_limited" || kind === "provider_server_error",
    );
  }
  if (
    !payload || typeof payload !== "object" ||
    typeof payload.subscriptionState !== "string" ||
    !Array.isArray(payload.lineItems)
  ) {
    throw new GooglePlayError(
      "Google subscription response is malformed",
      "malformed_response",
      false,
    );
  }
  return payload as GoogleSubscriptionPurchaseV2;
}

export type NormalizedGoogleSubscription = {
  status:
    | "pending"
    | "active"
    | "in_grace_period"
    | "on_hold"
    | "paused"
    | "canceled"
    | "expired"
    | "revoked"
    | "verification_failed";
  startsAt: string | null;
  expiresAt: string | null;
  autoRenewing: boolean | null;
  canceledAt: string | null;
  productId: string | null;
  basePlanId: string | null;
  providerRawStatus: string;
};

export function extractSubscriptionLineItem(
  payload: GoogleSubscriptionPurchaseV2,
  productId?: string | null,
  basePlanId?: string | null,
): Record<string, unknown> | null {
  const items = payload.lineItems as Array<Record<string, unknown>>;
  const selected = items.find((item) => {
    const offer = item.offerDetails as Record<string, unknown> | undefined;
    return (!productId || item.productId === productId) &&
      (!basePlanId || offer?.basePlanId === basePlanId);
  });
  if (selected) return selected;
  return productId || basePlanId ? null : items[0] ?? null;
}

export function normalizeGoogleSubscriptionStatus(
  payload: GoogleSubscriptionPurchaseV2,
  lineItem = extractSubscriptionLineItem(payload),
  now = new Date(),
): NormalizedGoogleSubscription {
  const expiresAt = typeof lineItem?.expiryTime === "string"
    ? new Date(lineItem.expiryTime)
    : null;
  const raw = typeof payload.subscriptionState === "string"
    ? payload.subscriptionState
    : "";
  let status: NormalizedGoogleSubscription["status"];
  switch (raw) {
    case "SUBSCRIPTION_STATE_PENDING":
      status = "pending";
      break;
    case "SUBSCRIPTION_STATE_ACTIVE":
      status = "active";
      break;
    case "SUBSCRIPTION_STATE_IN_GRACE_PERIOD":
      status = "in_grace_period";
      break;
    case "SUBSCRIPTION_STATE_ON_HOLD":
      status = "on_hold";
      break;
    case "SUBSCRIPTION_STATE_PAUSED":
      status = "paused";
      break;
    case "SUBSCRIPTION_STATE_CANCELED":
      status = expiresAt && expiresAt > now ? "canceled" : "expired";
      break;
    case "SUBSCRIPTION_STATE_EXPIRED":
      status = "expired";
      break;
    default:
      status = "verification_failed";
  }
  const cancellation = payload.canceledStateContext as
    | Record<string, unknown>
    | undefined;
  const offer = lineItem?.offerDetails as Record<string, unknown> | undefined;
  const autoRenew = lineItem?.autoRenewingPlan as
    | Record<string, unknown>
    | undefined;
  return {
    status,
    startsAt: typeof payload.startTime === "string" ? payload.startTime : null,
    expiresAt: expiresAt && !Number.isNaN(expiresAt.getTime())
      ? expiresAt.toISOString()
      : null,
    autoRenewing: typeof autoRenew?.autoRenewEnabled === "boolean"
      ? autoRenew.autoRenewEnabled
      : null,
    canceledAt: cancellation
      ? (typeof payload.startTime === "string"
        ? payload.startTime
        : now.toISOString())
      : null,
    productId: typeof lineItem?.productId === "string"
      ? lineItem.productId
      : null,
    basePlanId: typeof offer?.basePlanId === "string" ? offer.basePlanId : null,
    providerRawStatus: raw,
  };
}

export function sanitizeProviderPayload(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sanitizeProviderPayload);
  if (!value || typeof value !== "object") return value;
  const result: Record<string, unknown> = {};
  for (const [key, child] of Object.entries(value)) {
    if (/purchaseToken/i.test(key)) continue;
    result[key] = sanitizeProviderPayload(child);
  }
  return result;
}
