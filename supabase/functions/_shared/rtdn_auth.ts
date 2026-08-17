import { createRemoteJWKSet, jwtVerify } from "npm:jose@5.10.0";

const GOOGLE_ISSUERS = ["https://accounts.google.com", "accounts.google.com"];
const GOOGLE_CERTS = new URL("https://www.googleapis.com/oauth2/v3/certs");
const googleKeySet = createRemoteJWKSet(GOOGLE_CERTS);

export type RtdnAuthFailureReason =
  | "missing_authorization"
  | "malformed_authorization_header"
  | "jwt_malformed"
  | "jwt_signature_failure"
  | "jwt_issuer_mismatch"
  | "jwt_audience_mismatch"
  | "jwt_email_mismatch"
  | "jwt_email_not_verified"
  | "jwt_expired"
  | "unknown_jwt_validation_failure"
  | "missing_expected_audience"
  | "missing_expected_email";

export class RtdnAuthError extends Error {
  constructor(
    readonly code: "missing" | "invalid" | "misconfigured",
    readonly reason?: RtdnAuthFailureReason,
  ) {
    super(code);
  }
}

export type RtdnIdentity = { email: string; audience: string; issuer: string };
export type RtdnJwtVerifier = (
  token: string,
  key: unknown,
  options: Record<string, unknown>,
) => Promise<{ payload: Record<string, unknown> }>;
export type RtdnAuthLogger = (entry: Record<string, unknown>) => void;

const MAX_LOGGED_CLAIM_LENGTH = 200;

function sanitizeClaimValue(value: unknown): unknown {
  if (typeof value === "string") return value.slice(0, MAX_LOGGED_CLAIM_LENGTH);
  if (typeof value === "number" || typeof value === "boolean") return value;
  if (value === null || value === undefined) return null;
  if (Array.isArray(value)) {
    return value.slice(0, 5).map((entry) => sanitizeClaimValue(entry));
  }
  return `<${typeof value}>`;
}

// Diagnostics only: the payload is read without any signature check, so these
// claims must never influence the authorization decision. That decision is made
// exclusively by `jwtVerify()` plus the verified-claim checks below.
function decodeUnverifiedClaims(
  token: string,
): Record<string, unknown> | null {
  try {
    const segments = token.split(".");
    if (segments.length !== 3) return null;
    const normalized = segments[1].replaceAll("-", "+").replaceAll("_", "/");
    const padded = normalized +
      "=".repeat((4 - (normalized.length % 4)) % 4);
    const bytes = Uint8Array.from(
      atob(padded),
      (character) => character.charCodeAt(0),
    );
    const decoded = JSON.parse(new TextDecoder().decode(bytes));
    return decoded && typeof decoded === "object" && !Array.isArray(decoded)
      ? decoded as Record<string, unknown>
      : null;
  } catch {
    return null;
  }
}

function joseFailureReason(
  error: Record<string, unknown>,
): RtdnAuthFailureReason {
  switch (error.code) {
    case "ERR_JWT_EXPIRED":
      return "jwt_expired";
    case "ERR_JWT_CLAIM_VALIDATION_FAILED":
      if (error.claim === "iss") return "jwt_issuer_mismatch";
      if (error.claim === "aud") return "jwt_audience_mismatch";
      return "unknown_jwt_validation_failure";
    case "ERR_JWS_SIGNATURE_VERIFICATION_FAILED":
    case "ERR_JWKS_NO_MATCHING_KEY":
    case "ERR_JWKS_MULTIPLE_MATCHING_KEYS":
    case "ERR_JOSE_ALG_NOT_ALLOWED":
      return "jwt_signature_failure";
    case "ERR_JWS_INVALID":
    case "ERR_JWT_INVALID":
      return "jwt_malformed";
    default:
      return "unknown_jwt_validation_failure";
  }
}

const defaultLogger: RtdnAuthLogger = (entry) => {
  console.error(JSON.stringify(entry));
};

export async function verifyPubSubOidcRequest(
  request: Request,
  verify: RtdnJwtVerifier = jwtVerify as unknown as RtdnJwtVerifier,
  log: RtdnAuthLogger = defaultLogger,
): Promise<RtdnIdentity> {
  const audience = Deno.env.get("GOOGLE_PLAY_RTDN_EXPECTED_AUDIENCE");
  const expectedEmail = Deno.env.get(
    "GOOGLE_PLAY_RTDN_PUSH_SERVICE_ACCOUNT_EMAIL",
  );

  // Never log the Authorization header or the JWT itself; claim values are
  // JSON-encoded downstream so stray whitespace and quotes stay visible.
  const logFailure = (
    reason: RtdnAuthFailureReason,
    extra: Record<string, unknown> = {},
  ) => {
    try {
      log({
        event: "rtdn_auth_failure",
        reason,
        expectedAudience: sanitizeClaimValue(audience ?? null),
        expectedEmail: sanitizeClaimValue(expectedEmail ?? null),
        ...extra,
      });
    } catch {
      // Diagnostics must never break request handling.
    }
  };

  if (!audience || !expectedEmail) {
    logFailure(
      !audience ? "missing_expected_audience" : "missing_expected_email",
    );
    throw new RtdnAuthError(
      "misconfigured",
      !audience ? "missing_expected_audience" : "missing_expected_email",
    );
  }
  const authorization = request.headers.get("authorization");
  const match = authorization?.match(/^Bearer\s+([^\s]+)$/i);
  if (!match) {
    const reason: RtdnAuthFailureReason = authorization
      ? "malformed_authorization_header"
      : "missing_authorization";
    logFailure(reason);
    throw new RtdnAuthError("missing", reason);
  }

  const claimDiagnostics = () => {
    const claims = decodeUnverifiedClaims(match[1]);
    return {
      receivedIssuer: sanitizeClaimValue(claims?.iss),
      receivedAudience: sanitizeClaimValue(claims?.aud),
      receivedEmail: sanitizeClaimValue(claims?.email),
      receivedEmailVerified: sanitizeClaimValue(claims?.email_verified),
      receivedExpiry: sanitizeClaimValue(claims?.exp),
      receivedIssuedAt: sanitizeClaimValue(claims?.iat),
    };
  };

  try {
    const result = await verify(match[1], googleKeySet, {
      issuer: GOOGLE_ISSUERS,
      audience,
      algorithms: ["RS256"],
    });
    const claims = result.payload;
    const email = claims.email;
    if (typeof email !== "string" || email !== expectedEmail) {
      throw new RtdnAuthError("invalid", "jwt_email_mismatch");
    }
    if (claims.email_verified !== true) {
      throw new RtdnAuthError("invalid", "jwt_email_not_verified");
    }
    return {
      email,
      audience,
      issuer: String(claims.iss),
    };
  } catch (error) {
    if (error instanceof RtdnAuthError) {
      logFailure(error.reason ?? "unknown_jwt_validation_failure", {
        ...claimDiagnostics(),
      });
      throw error;
    }
    const joseError =
      (error && typeof error === "object" ? error : {}) as Record<
        string,
        unknown
      >;
    const reason = joseFailureReason(joseError);
    logFailure(reason, {
      ...claimDiagnostics(),
      joseErrorName: sanitizeClaimValue(joseError.name),
      joseErrorCode: sanitizeClaimValue(joseError.code),
      joseErrorClaim: sanitizeClaimValue(joseError.claim),
      joseErrorMessage: sanitizeClaimValue(joseError.message),
    });
    throw new RtdnAuthError("invalid", reason);
  }
}
