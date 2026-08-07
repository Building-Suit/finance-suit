import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import { normalizeProviderResult, validateRequest } from "./validate.ts";
import type { CardResearchRequest, ProviderRawResult } from "./types.ts";

const BASE_BODY = {
  requestId: "req-1",
  accountType: "credit_card",
  issuerName: "CIB",
  countryCode: "eg",
  productName: "Platinum",
};

Deno.test("validateRequest accepts a minimal valid request", () => {
  const result = validateRequest(BASE_BODY);
  assert(result.ok);
  if (result.ok) {
    assertEquals(result.value.countryCode, "EG");
    assertEquals(result.value.issuerName, "CIB");
  }
});

Deno.test("validateRequest rejects a missing issuer name", () => {
  const result = validateRequest({ ...BASE_BODY, issuerName: "  " });
  assertFalse(result.ok);
  if (!result.ok) assertEquals(result.error.code, "invalid_issuer_name");
});

Deno.test("validateRequest rejects a malformed country code", () => {
  const result = validateRequest({ ...BASE_BODY, countryCode: "Egypt" });
  assertFalse(result.ok);
  if (!result.ok) assertEquals(result.error.code, "invalid_country_code");
});

Deno.test("validateRequest rejects a non-ISO currency code", () => {
  const result = validateRequest({ ...BASE_BODY, currencyCode: "Egyptian Pound" });
  assertFalse(result.ok);
  if (!result.ok) assertEquals(result.error.code, "invalid_currency");
});

Deno.test("validateRequest rejects a non-http(s) website", () => {
  const result = validateRequest({ ...BASE_BODY, officialWebsite: "javascript:alert(1)" });
  assertFalse(result.ok);
  if (!result.ok) assertEquals(result.error.code, "invalid_website");
});

Deno.test("validateRequest redacts card-number-like sequences from notes", () => {
  const result = validateRequest({
    ...BASE_BODY,
    userNotes: "My card number is 4111 1111 1111 1111 and my fee is 750",
  });
  assert(result.ok);
  if (result.ok) {
    assert(!result.value.userNotes?.includes("4111"));
    assert(result.value.userNotes?.includes("[redacted]"));
  }
});

Deno.test("validateRequest truncates over-length notes instead of rejecting", () => {
  const result = validateRequest({ ...BASE_BODY, userNotes: "a".repeat(5000) });
  assert(result.ok);
  if (result.ok) assertEquals(result.value.userNotes?.length, 2000);
});

function baseRequest(overrides: Partial<CardResearchRequest> = {}): CardResearchRequest {
  return {
    requestId: "req-1",
    accountType: "credit_card",
    issuerName: "CIB",
    countryCode: "EG",
    officialWebsite: null,
    productName: "Platinum",
    tier: null,
    network: null,
    currencyCode: null,
    activationDate: null,
    knownCreditLimitMinor: null,
    knownStatementDay: null,
    knownDueDay: null,
    bnplTypicalTenorMonths: null,
    userNotes: null,
    selectedProductId: null,
    ...overrides,
  };
}

function wrappedValue(value: unknown, status = "verified") {
  return { value, status, confidence: "high", sourceIds: ["s1"] };
}

const RESOLVED_RAW: ProviderRawResult = {
  productMatch: {
    status: "resolved",
    issuerName: wrappedValue("CIB"),
    productName: wrappedValue("Platinum"),
    tier: wrappedValue(null, "unknown"),
    network: wrappedValue("visa"),
    currencyCode: wrappedValue("EGP"),
  },
  fields: {
    defaultDueDay: wrappedValue(17),
    statementDay: wrappedValue(24),
    minPaymentMethod: wrappedValue("percent"),
    minPaymentFixedMinor: wrappedValue(null, "unknown"),
    minPaymentBasisPoints: wrappedValue(500),
  },
  rules: [
    {
      feeType: "annual_membership",
      calculationType: "fixed",
      frequency: "annually",
      fixedAmountMinor: 70000,
      percentBasisPoints: null,
      percentBasis: null,
      minimumMinor: null,
      maximumMinor: null,
      lookbackCycles: null,
      status: "verified",
      confidence: "high",
      sourceIds: ["s1"],
    },
    {
      feeType: "foreign_transaction",
      calculationType: "percentage",
      frequency: "per_transaction",
      fixedAmountMinor: null,
      percentBasisPoints: 300,
      percentBasis: "transaction_amount",
      minimumMinor: null,
      maximumMinor: null,
      lookbackCycles: null,
      status: "verified",
      confidence: "high",
      sourceIds: ["s1"],
    },
  ],
  installmentTenors: [
    {
      fromMonths: 3,
      toMonths: 6,
      ratePercentBasisPoints: 150,
      method: "flat",
      period: "monthly",
      status: "verified",
      sourceIds: ["s1"],
    },
    // Overlaps the tier above — must be rejected by the normalizer.
    {
      fromMonths: 5,
      toMonths: 9,
      ratePercentBasisPoints: 200,
      method: "flat",
      period: "monthly",
      status: "verified",
      sourceIds: ["s1"],
    },
  ],
  sources: [
    {
      id: "s1",
      url: "https://cib.com.eg/tariff",
      title: "CIB Tariff",
      officialDomain: true,
      publishedDate: "2026-01-01",
      effectiveDate: "2026-01-01",
    },
  ],
  unresolvedRequiredFields: [],
  conflicts: [],
  unsupportedFindings: [],
};

Deno.test("normalizeProviderResult maps a resolved result end-to-end", () => {
  const result = normalizeProviderResult(RESOLVED_RAW, baseRequest(), {
    provider: "openai",
    model: "gpt-test",
  });
  assertEquals(result.status, "resolved");
  assertEquals(result.product.issuerName.value, "CIB");
  assertEquals(result.accountForm.suggestedName.value, "CIB Platinum");
  assertEquals(result.accountForm.suggestedName.status, "verified");
  assertEquals(result.rules.length, 2);
  // Overlapping tenor tier is dropped; only the first survives.
  assertEquals(result.installmentTenors.length, 1);
  assertEquals(result.installmentTenors[0].toMonths, 6);
});

Deno.test("normalizeProviderResult never accepts a credit limit from the provider", () => {
  const result = normalizeProviderResult(RESOLVED_RAW, baseRequest(), {
    provider: "openai",
    model: "gpt-test",
  });
  assertEquals(result.accountForm.creditLimitMinor.status, "unknown");
  assertEquals(result.accountForm.creditLimitMinor.value, null);
});

Deno.test("normalizeProviderResult echoes a user-provided credit limit as user_provided", () => {
  const result = normalizeProviderResult(
    RESOLVED_RAW,
    baseRequest({ knownCreditLimitMinor: 5_000_000 }),
    { provider: "openai", model: "gpt-test" },
  );
  assertEquals(result.accountForm.creditLimitMinor.status, "user_provided");
  assertEquals(result.accountForm.creditLimitMinor.value, 5_000_000);
});

Deno.test("normalizeProviderResult drops credit-card-only fee types for BNPL", () => {
  const result = normalizeProviderResult(
    RESOLVED_RAW,
    baseRequest({ accountType: "bnpl" }),
    { provider: "openai", model: "gpt-test" },
  );
  assertEquals(result.accountForm.statementDay.status, "not_applicable");
  assertEquals(result.accountForm.minPaymentMethod.status, "not_applicable");
  assert(result.rules.every((r) => r.feeType !== "foreign_transaction"));
});

Deno.test("normalizeProviderResult surfaces ambiguous candidates without resolving", () => {
  const raw: ProviderRawResult = {
    productMatch: {
      status: "ambiguous",
      candidates: [
        { id: "c1", label: "Platinum" },
        { id: "c2", label: "Platinum Cashback" },
      ],
    },
  };
  const result = normalizeProviderResult(raw, baseRequest(), {
    provider: "openai",
    model: "gpt-test",
  });
  assertEquals(result.status, "ambiguous");
  assertEquals(result.candidates.length, 2);
  assertEquals(result.rules.length, 0);
});

Deno.test("normalizeProviderResult reports insufficient information on not_found", () => {
  const raw: ProviderRawResult = { productMatch: { status: "not_found" } };
  const result = normalizeProviderResult(raw, baseRequest(), {
    provider: "gemini",
    model: "gemini-test",
  });
  assertEquals(result.status, "insufficient_information");
});

Deno.test("normalizeProviderResult rejects a rule where minimum exceeds maximum", () => {
  const raw: ProviderRawResult = {
    ...RESOLVED_RAW,
    rules: [
      {
        feeType: "wallet_fee",
        calculationType: "percentage",
        frequency: "per_transaction",
        fixedAmountMinor: null,
        percentBasisPoints: 100,
        percentBasis: "transaction_amount",
        minimumMinor: 10000,
        maximumMinor: 5000,
        lookbackCycles: null,
        status: "verified",
        confidence: "high",
        sourceIds: ["s1"],
      },
    ],
  };
  const result = normalizeProviderResult(raw, baseRequest(), {
    provider: "openai",
    model: "gpt-test",
  });
  assertEquals(result.rules.length, 0);
});

Deno.test("normalizeProviderResult restricts sourceIds to declared sources", () => {
  const raw: ProviderRawResult = {
    ...RESOLVED_RAW,
    rules: [
      {
        feeType: "annual_membership",
        calculationType: "fixed",
        frequency: "annually",
        fixedAmountMinor: 70000,
        percentBasisPoints: null,
        percentBasis: null,
        minimumMinor: null,
        maximumMinor: null,
        lookbackCycles: null,
        status: "verified",
        confidence: "high",
        sourceIds: ["s1", "s-unknown"],
      },
    ],
  };
  const result = normalizeProviderResult(raw, baseRequest(), {
    provider: "openai",
    model: "gpt-test",
  });
  assertEquals(result.rules[0].sourceIds, ["s1"]);
});
