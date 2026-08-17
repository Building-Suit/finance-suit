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

function base64Url(value: unknown): string {
  return btoa(JSON.stringify(value))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

// Structurally valid JWT with an unverifiable signature: enough for the
// diagnostics decoder, never enough for jwtVerify.
function unsignedToken(claims: Record<string, unknown>): string {
  return `${base64Url({ alg: "RS256", typ: "JWT" })}.${
    base64Url(claims)
  }.c2lnbmF0dXJl`;
}

async function expectRejection(
  authorization: string | undefined,
  verifier: RtdnJwtVerifier,
  expectedCode: "missing" | "invalid" | "misconfigured",
  expectedReason: string,
): Promise<Record<string, unknown>[]> {
  const entries: Record<string, unknown>[] = [];
  try {
    await verifyPubSubOidcRequest(
      request(authorization),
      verifier,
      (entry) => entries.push(entry),
    );
    throw new Error("expected rejection");
  } catch (error) {
    if (
      !(error instanceof RtdnAuthError) || error.code !== expectedCode ||
      error.reason !== expectedReason
    ) {
      throw error;
    }
  }
  if (entries.length !== 1 || entries[0].reason !== expectedReason) {
    throw new Error(
      `expected one ${expectedReason} log entry, got ${
        JSON.stringify(entries)
      }`,
    );
  }
  return entries;
}

const rejectingVerifier: RtdnJwtVerifier = () =>
  Promise.reject(new Error("must not be called"));

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
  const verifier: RtdnJwtVerifier = () =>
    Promise.reject(new Error("bad signature"));
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
  const verifier: RtdnJwtVerifier = (_token, _key, options) => {
    const audiences = options.audience;
    if (audiences !== "https://example.test/rtdn") {
      throw new Error("wrong audience");
    }
    return Promise.resolve({ payload: validClaims });
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
  const verifier: RtdnJwtVerifier = () =>
    Promise.resolve({
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

Deno.test("RTDN logs missing_authorization without a header", async () => {
  configure();
  await expectRejection(
    undefined,
    rejectingVerifier,
    "missing",
    "missing_authorization",
  );
});

Deno.test("RTDN logs malformed_authorization_header", async () => {
  configure();
  await expectRejection(
    "Basic something",
    rejectingVerifier,
    "missing",
    "malformed_authorization_header",
  );
});

Deno.test("RTDN logs missing expected audience as misconfigured", async () => {
  configure();
  Deno.env.delete("GOOGLE_PLAY_RTDN_EXPECTED_AUDIENCE");
  try {
    await expectRejection(
      "Bearer valid",
      rejectingVerifier,
      "misconfigured",
      "missing_expected_audience",
    );
  } finally {
    configure();
  }
});

Deno.test("RTDN maps jose audience failures to jwt_audience_mismatch", async () => {
  configure();
  const token = unsignedToken({
    ...validClaims,
    aud: "https://example.test/rtdn/",
  });
  const verifier: RtdnJwtVerifier = () =>
    Promise.reject(Object.assign(
      new Error('unexpected "aud" claim value'),
      {
        name: "JWTClaimValidationFailed",
        code: "ERR_JWT_CLAIM_VALIDATION_FAILED",
        claim: "aud",
      },
    ));
  const entries = await expectRejection(
    `Bearer ${token}`,
    verifier,
    "invalid",
    "jwt_audience_mismatch",
  );
  const entry = entries[0];
  if (entry.receivedAudience !== "https://example.test/rtdn/") {
    throw new Error("expected the unverified audience claim in diagnostics");
  }
  if (entry.expectedAudience !== "https://example.test/rtdn") {
    throw new Error("expected the configured audience in diagnostics");
  }
  if (JSON.stringify(entry).includes(token)) {
    throw new Error("diagnostics must never contain the JWT");
  }
});

Deno.test("RTDN maps jose issuer failures to jwt_issuer_mismatch", async () => {
  configure();
  const verifier: RtdnJwtVerifier = () =>
    Promise.reject(Object.assign(new Error('unexpected "iss" claim value'), {
      code: "ERR_JWT_CLAIM_VALIDATION_FAILED",
      claim: "iss",
    }));
  await expectRejection(
    "Bearer valid",
    verifier,
    "invalid",
    "jwt_issuer_mismatch",
  );
});

Deno.test("RTDN maps jose expiry failures to jwt_expired", async () => {
  configure();
  const verifier: RtdnJwtVerifier = () =>
    Promise.reject(Object.assign(new Error("token expired"), {
      code: "ERR_JWT_EXPIRED",
      claim: "exp",
    }));
  await expectRejection("Bearer valid", verifier, "invalid", "jwt_expired");
});

Deno.test("RTDN maps signature failures to jwt_signature_failure", async () => {
  configure();
  for (
    const code of [
      "ERR_JWS_SIGNATURE_VERIFICATION_FAILED",
      "ERR_JWKS_NO_MATCHING_KEY",
    ]
  ) {
    const verifier: RtdnJwtVerifier = () =>
      Promise.reject(
        Object.assign(new Error("signature verification failed"), { code }),
      );
    await expectRejection(
      "Bearer valid",
      verifier,
      "invalid",
      "jwt_signature_failure",
    );
  }
});

Deno.test("RTDN maps unrecognized verifier errors to unknown", async () => {
  configure();
  const verifier: RtdnJwtVerifier = () =>
    Promise.reject(new Error("fetch failed"));
  await expectRejection(
    "Bearer valid",
    verifier,
    "invalid",
    "unknown_jwt_validation_failure",
  );
});

Deno.test("RTDN logs jwt_email_mismatch with received identity", async () => {
  configure();
  const token = unsignedToken({
    ...validClaims,
    email: "wrong@example.iam.gserviceaccount.com",
  });
  const verifier: RtdnJwtVerifier = () =>
    Promise.resolve({
      payload: {
        ...validClaims,
        email: "wrong@example.iam.gserviceaccount.com",
      },
    });
  const entries = await expectRejection(
    `Bearer ${token}`,
    verifier,
    "invalid",
    "jwt_email_mismatch",
  );
  if (entries[0].receivedEmail !== "wrong@example.iam.gserviceaccount.com") {
    throw new Error("expected the received email claim in diagnostics");
  }
});

Deno.test("RTDN logs jwt_email_not_verified", async () => {
  configure();
  const verifier: RtdnJwtVerifier = () =>
    Promise.resolve({
      payload: { ...validClaims, email_verified: false },
    });
  await expectRejection(
    "Bearer valid",
    verifier,
    "invalid",
    "jwt_email_not_verified",
  );
});

Deno.test("RTDN keeps authorization independent of unverified claims", async () => {
  configure();
  // A token whose unverified payload matches every expectation must still be
  // rejected when cryptographic verification fails.
  const token = unsignedToken({
    ...validClaims,
    aud: "https://example.test/rtdn",
  });
  const verifier: RtdnJwtVerifier = () =>
    Promise.reject(Object.assign(new Error("signature verification failed"), {
      code: "ERR_JWS_SIGNATURE_VERIFICATION_FAILED",
    }));
  await expectRejection(
    `Bearer ${token}`,
    verifier,
    "invalid",
    "jwt_signature_failure",
  );
});
