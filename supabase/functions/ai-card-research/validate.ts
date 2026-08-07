// Backend validation and normalization (task spec section 40). The AI
// provider's raw response is never trusted directly — every field is
// re-checked against enums, bounds, and account-type compatibility before
// becoming the normalized DTO Flutter receives. Invalid/unsupported values
// are downgraded to "unknown" rather than guessed or dropped silently.

import {
  CALCULATION_TYPES,
  CARD_FEE_TYPES,
  type CardResearchConflict,
  type CardResearchRequest,
  type CardResearchResult,
  CONFIDENCE_LEVELS,
  FEE_FREQUENCIES,
  FIELD_STATUSES,
  INTEREST_METHODS,
  MIN_PAYMENT_METHODS,
  PERCENT_BASES,
  type ProviderRawResult,
  RATE_PERIODS,
  type ResearchedFeeRule,
  type ResearchedTenorRate,
  type ResearchedValue,
  type ResearchSource,
} from "./types.ts";
import { PROMPT_VERSION } from "./prompt.ts";

const CREDIT_CARD_ONLY_FEE_TYPES = new Set([
  "foreign_transaction",
  "cash_advance",
  "international_cash_advance",
  "wallet_fee",
  "statement_fee",
  "installment_conversion",
]);

const ISO_COUNTRY = /^[A-Z]{2}$/;
const ISO_CURRENCY = /^[A-Z]{3}$/;
const CARD_NUMBER_LIKE = /\b(?:\d[ -]?){13,19}\b/g;
const MAX_NOTES_LENGTH = 2000;
const MAX_TEXT_FIELD_LENGTH = 120;

export interface RequestValidationError {
  code: string;
  message: string;
}

export function validateRequest(
  body: unknown,
): { ok: true; value: CardResearchRequest } | {
  ok: false;
  error: RequestValidationError;
} {
  if (typeof body !== "object" || body === null) {
    return { ok: false, error: { code: "invalid_request", message: "Body must be an object" } };
  }
  const b = body as Record<string, unknown>;

  const requestId = typeof b.requestId === "string" ? b.requestId.trim() : "";
  if (!requestId || requestId.length > 100) {
    return { ok: false, error: { code: "invalid_request_id", message: "requestId is required" } };
  }
  const accountType = b.accountType;
  if (accountType !== "credit_card" && accountType !== "bnpl") {
    return {
      ok: false,
      error: { code: "invalid_account_type", message: "accountType must be credit_card or bnpl" },
    };
  }
  const issuerName = typeof b.issuerName === "string" ? b.issuerName.trim() : "";
  if (!issuerName || issuerName.length > MAX_TEXT_FIELD_LENGTH) {
    return { ok: false, error: { code: "invalid_issuer_name", message: "issuerName is required" } };
  }
  const countryCode = typeof b.countryCode === "string"
    ? b.countryCode.trim().toUpperCase()
    : "";
  if (!ISO_COUNTRY.test(countryCode)) {
    return {
      ok: false,
      error: { code: "invalid_country_code", message: "countryCode must be an ISO 3166-1 alpha-2 code" },
    };
  }
  const productName = typeof b.productName === "string" ? b.productName.trim() : "";
  if (!productName || productName.length > MAX_TEXT_FIELD_LENGTH) {
    return {
      ok: false,
      error: { code: "invalid_product_name", message: "productName is required" },
    };
  }

  const officialWebsite = optionalString(b.officialWebsite, 300);
  if (officialWebsite) {
    try {
      const url = new URL(officialWebsite);
      if (url.protocol !== "https:" && url.protocol !== "http:") throw new Error();
    } catch {
      return { ok: false, error: { code: "invalid_website", message: "officialWebsite must be a valid URL" } };
    }
  }

  const currencyCodeRaw = typeof b.currencyCode === "string" ? b.currencyCode.trim().toUpperCase() : "";
  const currencyCode = currencyCodeRaw || null;
  if (currencyCode && !ISO_CURRENCY.test(currencyCode)) {
    return { ok: false, error: { code: "invalid_currency", message: "currencyCode must be ISO 4217" } };
  }

  const network = b.network;
  const allowedNetworks = ["visa", "mastercard", "other", "unknown"];
  if (network !== undefined && network !== null && !allowedNetworks.includes(network as string)) {
    return { ok: false, error: { code: "invalid_network", message: "invalid network" } };
  }

  const userNotesRaw = optionalString(b.userNotes, MAX_NOTES_LENGTH);
  const userNotes = userNotesRaw
    ? userNotesRaw.replace(CARD_NUMBER_LIKE, "[redacted]")
    : null;

  const knownCreditLimitMinor = optionalPositiveInt(b.knownCreditLimitMinor);
  const knownStatementDay = optionalDayOfMonth(b.knownStatementDay);
  const knownDueDay = optionalDayOfMonth(b.knownDueDay);
  const bnplTypicalTenorMonths = optionalPositiveInt(b.bnplTypicalTenorMonths, 120);

  return {
    ok: true,
    value: {
      requestId,
      accountType,
      issuerName,
      countryCode,
      officialWebsite,
      productName,
      tier: optionalString(b.tier, MAX_TEXT_FIELD_LENGTH),
      network: (network as CardResearchRequest["network"]) ?? null,
      currencyCode,
      activationDate: optionalString(b.activationDate, 32),
      knownCreditLimitMinor,
      knownStatementDay,
      knownDueDay,
      bnplTypicalTenorMonths,
      userNotes,
      selectedProductId: optionalString(b.selectedProductId, 100),
    },
  };
}

function optionalString(value: unknown, maxLength: number): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  return trimmed.length > maxLength ? trimmed.slice(0, maxLength) : trimmed;
}

function optionalPositiveInt(value: unknown, max = 1_000_000_000): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  const int = Math.round(value);
  return int > 0 && int <= max ? int : null;
}

function optionalDayOfMonth(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  const int = Math.round(value);
  return int >= 1 && int <= 28 ? int : null;
}

function isIsoDate(value: unknown): value is string {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value);
}

function statusOrUnknown(value: unknown): (typeof FIELD_STATUSES)[number] {
  return typeof value === "string" && (FIELD_STATUSES as readonly string[]).includes(value)
    ? (value as (typeof FIELD_STATUSES)[number])
    : "unknown";
}

function confidenceOrNull(value: unknown): (typeof CONFIDENCE_LEVELS)[number] | null {
  return typeof value === "string" && (CONFIDENCE_LEVELS as readonly string[]).includes(value)
    ? (value as (typeof CONFIDENCE_LEVELS)[number])
    : null;
}

function sourceIdsOf(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((v): v is string => typeof v === "string").slice(0, 10);
}

function wrapped<T>(
  raw: unknown,
  extractValue: (v: unknown) => T | null,
): ResearchedValue<T> {
  const obj = (typeof raw === "object" && raw !== null) ? raw as Record<string, unknown> : {};
  const status = statusOrUnknown(obj.status);
  const value = status === "unknown" || status === "not_applicable"
    ? null
    : extractValue(obj.value);
  return {
    value,
    status: value === null && (status === "verified" || status === "user_provided")
      ? "unknown"
      : status,
    confidence: confidenceOrNull(obj.confidence),
    sourceIds: sourceIdsOf(obj.sourceIds),
  };
}

function asString(v: unknown): string | null {
  return typeof v === "string" && v.trim() ? v.trim().slice(0, 200) : null;
}

function asEnum<T extends string>(allowed: readonly T[]) {
  return (v: unknown): T | null =>
    typeof v === "string" && (allowed as readonly string[]).includes(v) ? (v as T) : null;
}

function asInt(min: number, max: number) {
  return (v: unknown): number | null => {
    if (typeof v !== "number" || !Number.isFinite(v)) return null;
    const int = Math.round(v);
    return int >= min && int <= max ? int : null;
  };
}

export function normalizeProviderResult(
  raw: ProviderRawResult,
  request: CardResearchRequest,
  meta: { provider: string; model: string },
): CardResearchResult {
  const productMatch = raw.productMatch ?? { status: "not_found" };
  const matchStatus = productMatch.status;

  if (matchStatus === "ambiguous") {
    const candidates = Array.isArray(productMatch.candidates)
      ? productMatch.candidates
        .filter((c): c is { id: string; label: string } =>
          typeof c?.id === "string" && typeof c?.label === "string"
        )
        .slice(0, 5)
      : [];
    return emptyResult(request, meta, {
      status: "ambiguous",
      candidates,
    });
  }
  if (matchStatus === "not_found") {
    return emptyResult(request, meta, {
      status: "insufficient_information",
      errorMessage: "No confident product match was found from official sources.",
    });
  }
  if (matchStatus !== "resolved") {
    return emptyResult(request, meta, {
      status: "error",
      errorMessage: "Provider returned an unrecognized product match status.",
    });
  }

  const sources = normalizeSources(raw.sources);
  const validSourceIds = new Set(sources.map((s) => s.id));
  const restrictSourceIds = (ids: string[]) => ids.filter((id) => validSourceIds.has(id));

  const rules = normalizeRules(raw.rules, request.accountType, restrictSourceIds);
  const installmentTenors = normalizeTenors(raw.installmentTenors, restrictSourceIds);
  const conflicts = normalizeConflicts(raw.conflicts);
  const unsupportedFindings = Array.isArray(raw.unsupportedFindings)
    ? raw.unsupportedFindings
      .filter((f): f is { description: string; note: string } =>
        typeof (f as { description?: unknown })?.description === "string"
      )
      .slice(0, 20)
      .map((f) => ({
        description: (f.description as string).slice(0, 300),
        note: typeof f.note === "string" ? f.note.slice(0, 300) : "",
      }))
    : [];

  const fields = raw.fields ?? {};
  const product = {
    issuerName: wrapped(productMatch.issuerName, asString),
    productName: wrapped(productMatch.productName, asString),
    tier: wrapped(productMatch.tier, asString),
    network: wrapped(productMatch.network, asEnum(["visa", "mastercard", "other", "unknown"] as const)),
    currencyCode: wrapped(
      productMatch.currencyCode,
      (v) => (typeof v === "string" && ISO_CURRENCY.test(v.toUpperCase()) ? v.toUpperCase() : null),
    ),
  };
  const suggestedName = synthesizeName(product);

  return {
    requestId: request.requestId,
    status: "resolved",
    errorMessage: null,
    candidates: [],
    product,
    accountForm: {
      // Credit limit is never accepted from the provider — only echoed
      // back from what the user explicitly typed in the AI sheet. See
      // task spec section 33: personal limits cannot be researched.
      suggestedName,
      creditLimitMinor: request.knownCreditLimitMinor != null
        ? {
          value: request.knownCreditLimitMinor,
          status: "user_provided",
          confidence: "high",
          sourceIds: [],
        }
        : { value: null, status: "unknown", confidence: null, sourceIds: [] },
      defaultDueDay: request.knownDueDay != null
        ? { value: request.knownDueDay, status: "user_provided", confidence: "high", sourceIds: [] }
        : wrapped(fields.defaultDueDay, asInt(1, 28)),
      statementDay: request.accountType === "bnpl"
        ? { value: null, status: "not_applicable", confidence: null, sourceIds: [] }
        : request.knownStatementDay != null
        ? { value: request.knownStatementDay, status: "user_provided", confidence: "high", sourceIds: [] }
        : wrapped(fields.statementDay, asInt(1, 28)),
      minPaymentMethod: request.accountType === "bnpl"
        ? { value: null, status: "not_applicable", confidence: null, sourceIds: [] }
        : wrapped(fields.minPaymentMethod, asEnum(MIN_PAYMENT_METHODS)),
      minPaymentFixedMinor: request.accountType === "bnpl"
        ? { value: null, status: "not_applicable", confidence: null, sourceIds: [] }
        : wrapped(fields.minPaymentFixedMinor, asInt(0, 1_000_000_000)),
      minPaymentBasisPoints: request.accountType === "bnpl"
        ? { value: null, status: "not_applicable", confidence: null, sourceIds: [] }
        : wrapped(fields.minPaymentBasisPoints, asInt(1, 10_000)),
    },
    rules,
    installmentTenors,
    sources,
    unresolvedRequiredFields: Array.isArray(raw.unresolvedRequiredFields)
      ? raw.unresolvedRequiredFields.filter((f): f is string => typeof f === "string").slice(0, 20)
      : [],
    conflicts,
    unsupportedFindings,
    metadata: {
      provider: meta.provider,
      model: meta.model,
      promptVersion: PROMPT_VERSION,
      researchedAt: new Date().toISOString(),
    },
  };
}

function synthesizeName(product: CardResearchResult["product"]): ResearchedValue<string> {
  const eligible = (v: ResearchedValue<string>) =>
    (v.status === "verified" || v.status === "user_provided") && v.value;
  const parts = [product.issuerName, product.productName, product.tier]
    .filter(eligible)
    .map((v) => v.value as string);
  if (!parts.length) return { value: null, status: "unknown", confidence: null, sourceIds: [] };
  const sourceIds = [product.issuerName, product.productName, product.tier]
    .filter(eligible)
    .flatMap((v) => v.sourceIds);
  const confidences = [product.issuerName, product.productName, product.tier]
    .filter(eligible)
    .map((v) => v.confidence);
  return {
    value: parts.join(" ").slice(0, 80),
    status: parts.length >= 2 ? "verified" : "probable",
    confidence: confidences.includes("low") ? "low" : confidences.includes("medium") ? "medium" : "high",
    sourceIds: Array.from(new Set(sourceIds)),
  };
}

function normalizeSources(raw: unknown): ResearchSource[] {
  if (!Array.isArray(raw)) return [];
  const seen = new Set<string>();
  const out: ResearchSource[] = [];
  for (const item of raw) {
    if (typeof item !== "object" || item === null) continue;
    const r = item as Record<string, unknown>;
    const id = asString(r.id);
    const url = asString(r.url);
    const title = asString(r.title);
    if (!id || !url || !title || seen.has(id)) continue;
    try {
      new URL(url);
    } catch {
      continue;
    }
    seen.add(id);
    out.push({
      id,
      url,
      title,
      officialDomain: r.officialDomain === true,
      publishedDate: isIsoDate(r.publishedDate) ? r.publishedDate : null,
      effectiveDate: isIsoDate(r.effectiveDate) ? r.effectiveDate : null,
    });
    if (out.length >= 30) break;
  }
  return out;
}

function normalizeRules(
  raw: unknown,
  accountType: CardResearchRequest["accountType"],
  restrictSourceIds: (ids: string[]) => string[],
): ResearchedFeeRule[] {
  if (!Array.isArray(raw)) return [];
  const out: ResearchedFeeRule[] = [];
  for (const item of raw) {
    if (typeof item !== "object" || item === null) continue;
    const r = item as Record<string, unknown>;
    const feeType = asEnum(CARD_FEE_TYPES)(r.feeType);
    if (!feeType) continue;
    if (accountType === "bnpl" && CREDIT_CARD_ONLY_FEE_TYPES.has(feeType)) continue;
    const calculationType = asEnum(CALCULATION_TYPES)(r.calculationType);
    const frequency = asEnum(FEE_FREQUENCIES)(r.frequency);
    if (!calculationType || !frequency) continue;
    let status = statusOrUnknown(r.status);

    const fixedAmountMinor = asInt(0, 1_000_000_000)(r.fixedAmountMinor);
    const percentBasisPoints = asInt(1, 10_000)(r.percentBasisPoints);
    const percentBasis = asEnum(PERCENT_BASES)(r.percentBasis);
    const minimumMinor = asInt(0, 1_000_000_000)(r.minimumMinor);
    const maximumMinor = asInt(0, 1_000_000_000)(r.maximumMinor);
    if (minimumMinor != null && maximumMinor != null && minimumMinor > maximumMinor) continue;

    const hasFixed = fixedAmountMinor != null;
    const hasPercent = percentBasisPoints != null && percentBasis != null;
    if (calculationType === "fixed" && !hasFixed) status = "unknown";
    if (calculationType === "percentage" && !hasPercent) status = "unknown";
    if (calculationType === "fixed_plus_percentage" && !(hasFixed && hasPercent)) status = "unknown";
    if (status === "unknown") continue;

    out.push({
      feeType,
      calculationType,
      frequency,
      fixedAmountMinor,
      percentBasisPoints,
      percentBasis,
      minimumMinor,
      maximumMinor,
      lookbackCycles: asInt(1, 60)(r.lookbackCycles),
      status,
      confidence: confidenceOrNull(r.confidence),
      sourceIds: restrictSourceIds(sourceIdsOf(r.sourceIds)),
    });
    if (out.length >= 30) break;
  }
  return out;
}

function normalizeTenors(
  raw: unknown,
  restrictSourceIds: (ids: string[]) => string[],
): ResearchedTenorRate[] {
  if (!Array.isArray(raw)) return [];
  const out: ResearchedTenorRate[] = [];
  const ranges: [number, number][] = [];
  for (const item of raw) {
    if (typeof item !== "object" || item === null) continue;
    const r = item as Record<string, unknown>;
    const fromMonths = asInt(1, 120)(r.fromMonths);
    const toMonths = asInt(1, 120)(r.toMonths);
    const rate = asInt(0, 100_00)(r.ratePercentBasisPoints);
    const method = asEnum(INTEREST_METHODS)(r.method);
    const period = asEnum(RATE_PERIODS)(r.period);
    const status = statusOrUnknown(r.status);
    if (
      fromMonths == null || toMonths == null || fromMonths > toMonths ||
      rate == null || !method || !period ||
      (status !== "verified" && status !== "user_provided")
    ) {
      continue;
    }
    if (ranges.some(([f, t]) => fromMonths <= t && f <= toMonths)) continue;
    ranges.push([fromMonths, toMonths]);
    out.push({
      fromMonths,
      toMonths,
      ratePercentBasisPoints: rate,
      method,
      period,
      status,
      sourceIds: restrictSourceIds(sourceIdsOf(r.sourceIds)),
    });
    if (out.length >= 20) break;
  }
  return out;
}

function normalizeConflicts(raw: unknown): CardResearchConflict[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .filter((c): c is Record<string, unknown> => typeof c === "object" && c !== null)
    .map((c) => ({
      field: asString(c.field) ?? "unknown_field",
      userValue: asString(c.userValue) ?? "",
      officialValue: asString(c.officialValue) ?? "",
    }))
    .filter((c) => c.userValue && c.officialValue)
    .slice(0, 20);
}

function emptyResult(
  request: CardResearchRequest,
  meta: { provider: string; model: string },
  overrides: Partial<CardResearchResult>,
): CardResearchResult {
  const emptyValue = <T>(): ResearchedValue<T> => ({
    value: null,
    status: "unknown",
    confidence: null,
    sourceIds: [],
  });
  return {
    requestId: request.requestId,
    status: "error",
    errorMessage: null,
    candidates: [],
    product: {
      issuerName: emptyValue(),
      productName: emptyValue(),
      tier: emptyValue(),
      network: emptyValue(),
      currencyCode: emptyValue(),
    },
    accountForm: {
      suggestedName: emptyValue(),
      creditLimitMinor: emptyValue(),
      defaultDueDay: emptyValue(),
      statementDay: emptyValue(),
      minPaymentMethod: emptyValue(),
      minPaymentFixedMinor: emptyValue(),
      minPaymentBasisPoints: emptyValue(),
    },
    rules: [],
    installmentTenors: [],
    sources: [],
    unresolvedRequiredFields: [],
    conflicts: [],
    unsupportedFindings: [],
    metadata: {
      provider: meta.provider,
      model: meta.model,
      promptVersion: PROMPT_VERSION,
      researchedAt: new Date().toISOString(),
    },
    ...overrides,
  };
}
