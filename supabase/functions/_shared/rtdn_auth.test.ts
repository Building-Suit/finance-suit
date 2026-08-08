import {
  RtdnAuthError,
  type RtdnJwtVerifier,
  verifyPubSubOidcRequest,
} from "./rtdn_auth.ts";

const request = (authorization?: string) =>
  new Request("https://example.test", {
    headers: authorization ? { authorization } : undefined,
  });

const validClaims = {
  email: "push@example.iam.gserviceaccount.com",
  email_verified: true,
  iss: "https://accounts.google.com",
};

function configure() {
  Deno.env.set(
    "GOOGLE_PLAY_RTDN_EXPECTED_AUDIENCE",
    "https://example.test/rtdn",
  );
  Deno.env.set(
    "GOOGLE_PLAY_RTDN_PUSH_SERVICE_ACCOUNT_EMAIL",
    validClaims.email,
  );
}

Deno.test("RTDN rejects missing bearer authentication", async () => {
  configure();
  try {
    await verifyPubSubOidcRequest(request());
    throw new Error("expected rejection");
  } catch (error) {
    if (!(error instanceof RtdnAuthError) || error.code !== "missing") {
      throw error;
    }
  }
});

Deno.test("RTDN rejects a verifier failure", async () => {
  configure();
  const verifier: RtdnJwtVerifier = async () => {
    throw new Error("bad signature");
  };
  try {
    await verifyPubSubOidcRequest(request("Bearer malformed"), verifier);
    throw new Error("expected rejection");
  } catch (error) {
    if (!(error instanceof RtdnAuthError) || error.code !== "invalid") {
      throw error;
    }
  }
});

Deno.test("RTDN accepts only the configured Google identity", async () => {
  configure();
  const verifier: RtdnJwtVerifier = async (_token, _key, options) => {
    const audiences = options.audience;
    if (audiences !== "https://example.test/rtdn") {
      throw new Error("wrong audience");
    }
    return { payload: validClaims };
  };
  const identity = await verifyPubSubOidcRequest(
    request("Bearer valid"),
    verifier,
  );
  if (identity.email !== validClaims.email) {
    throw new Error("identity email mismatch");
  }
});

Deno.test("RTDN rejects an unverified or wrong service identity", async () => {
  configure();
  const verifier: RtdnJwtVerifier = async () => ({
    payload: {
      ...validClaims,
      email: "other@example.com",
      email_verified: false,
    },
  });
  try {
    await verifyPubSubOidcRequest(request("Bearer valid"), verifier);
    throw new Error("expected rejection");
  } catch (error) {
    if (!(error instanceof RtdnAuthError) || error.code !== "invalid") {
      throw error;
    }
  }
});
