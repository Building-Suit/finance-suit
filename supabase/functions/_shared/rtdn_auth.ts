import { createRemoteJWKSet, jwtVerify } from "npm:jose@5.10.0";

const GOOGLE_ISSUERS = ["https://accounts.google.com", "accounts.google.com"];
const GOOGLE_CERTS = new URL("https://www.googleapis.com/oauth2/v3/certs");
const googleKeySet = createRemoteJWKSet(GOOGLE_CERTS);

export class RtdnAuthError extends Error {
  constructor(readonly code: "missing" | "invalid" | "misconfigured") {
    super(code);
  }
}

export type RtdnIdentity = { email: string; audience: string; issuer: string };
export type RtdnJwtVerifier = (
  token: string,
  key: unknown,
  options: Record<string, unknown>,
) => Promise<{ payload: Record<string, unknown> }>;

export async function verifyPubSubOidcRequest(
  request: Request,
  verify: RtdnJwtVerifier = jwtVerify as unknown as RtdnJwtVerifier,
): Promise<RtdnIdentity> {
  const audience = Deno.env.get("GOOGLE_PLAY_RTDN_EXPECTED_AUDIENCE");
  const expectedEmail = Deno.env.get(
    "GOOGLE_PLAY_RTDN_PUSH_SERVICE_ACCOUNT_EMAIL",
  );
  if (!audience || !expectedEmail) throw new RtdnAuthError("misconfigured");
  const authorization = request.headers.get("authorization");
  const match = authorization?.match(/^Bearer\s+([^\s]+)$/i);
  if (!match) throw new RtdnAuthError("missing");
  try {
    const result = await verify(match[1], googleKeySet, {
      issuer: GOOGLE_ISSUERS,
      audience,
      algorithms: ["RS256"],
    });
    const claims = result.payload;
    const email = claims.email;
    if (
      typeof email !== "string" || email !== expectedEmail ||
      claims.email_verified !== true
    ) {
      throw new RtdnAuthError("invalid");
    }
    return {
      email,
      audience,
      issuer: String(claims.iss),
    };
  } catch (error) {
    if (error instanceof RtdnAuthError) throw error;
    throw new RtdnAuthError("invalid");
  }
}
