// Shared types for the AI card/BNPL research Edge Function. These mirror
// the Dart enums in lib/core/domain/db_enums.dart exactly (dbValue strings)
// so the normalized DTO returned to Flutter needs no re-mapping there.

export type AccountTypeWire = "credit_card" | "bnpl";

export type NetworkWire = "visa" | "mastercard" | "other" | "unknown";

/** Mirrors CardFeeType.dbValue. */
export const CARD_FEE_TYPES = [
  "annual_membership",
  "insurance",
  "administration",
  "stamp_tax",
  "foreign_transaction",
  "cash_advance",
  "international_cash_advance",
  "wallet_fee",
  "statement_fee",
  "early_settlement",
  "late_payment",
  "over_limit",
  "installment_conversion",
  "other",
] as const;
export type CardFeeTypeWire = (typeof CARD_FEE_TYPES)[number];

/** Mirrors CardRuleCalculationType.dbValue. "manual" is never returned by AI. */
export const CALCULATION_TYPES = [
  "fixed",
  "percentage",
  "fixed_plus_percentage",
] as const;
export type CalculationTypeWire = (typeof CALCULATION_TYPES)[number];

/** Mirrors FeeFrequency.dbValue. */
export const FEE_FREQUENCIES = [
  "once",
  "monthly",
  "quarterly",
  "annually",
  "per_transaction",
] as const;
export type FeeFrequencyWire = (typeof FEE_FREQUENCIES)[number];

/** Mirrors FeePercentBasis.dbValue. */
export const PERCENT_BASES = [
  "statement_balance",
  "outstanding_balance",
  "credit_limit",
  "transaction_amount",
  "highest_statement_due_lookback",
  "remaining_principal",
  "remaining_outstanding",
] as const;
export type PercentBasisWire = (typeof PERCENT_BASES)[number];

/** Mirrors MinPaymentMethod.dbValue. */
export const MIN_PAYMENT_METHODS = [
  "full",
  "fixed",
  "percent",
  "greater_of",
] as const;
export type MinPaymentMethodWire = (typeof MIN_PAYMENT_METHODS)[number];

/** Mirrors InterestMethod.dbValue. */
export const INTEREST_METHODS = ["flat", "reducing"] as const;
export type InterestMethodWire = (typeof INTEREST_METHODS)[number];

/** Mirrors InterestRatePeriod.dbValue. */
export const RATE_PERIODS = ["monthly", "annual"] as const;
export type RatePeriodWire = (typeof RATE_PERIODS)[number];

/**
 * Confidence/provenance a researched value carries. Never conflate
 * "unknown" with a fabricated zero — see CLAUDE.md money rules and task
 * spec section 19 ("No invention").
 */
export const FIELD_STATUSES = [
  "verified",
  "user_provided",
  "probable",
  "conflicting",
  "unknown",
  "not_applicable",
] as const;
export type FieldStatus = (typeof FIELD_STATUSES)[number];

export const CONFIDENCE_LEVELS = ["high", "medium", "low"] as const;
export type ConfidenceLevel = (typeof CONFIDENCE_LEVELS)[number];

export interface ResearchedValue<T> {
  value: T | null;
  status: FieldStatus;
  confidence: ConfidenceLevel | null;
  sourceIds: string[];
}

/** Inbound request body from Flutter. */
export interface CardResearchRequest {
  requestId: string;
  accountType: AccountTypeWire;
  issuerName: string;
  countryCode: string;
  officialWebsite?: string | null;
  productName: string;
  tier?: string | null;
  network?: NetworkWire | null;
  currencyCode?: string | null;
  activationDate?: string | null;
  knownCreditLimitMinor?: number | null;
  knownStatementDay?: number | null;
  knownDueDay?: number | null;
  bnplTypicalTenorMonths?: number | null;
  userNotes?: string | null;
  selectedProductId?: string | null;
}

export interface ProductCandidate {
  id: string;
  label: string;
}

export interface ResearchSource {
  id: string;
  url: string;
  title: string;
  officialDomain: boolean;
  publishedDate: string | null;
  effectiveDate: string | null;
}

export interface ResearchedFeeRule {
  feeType: CardFeeTypeWire;
  calculationType: CalculationTypeWire;
  frequency: FeeFrequencyWire;
  fixedAmountMinor: number | null;
  percentBasisPoints: number | null;
  percentBasis: PercentBasisWire | null;
  minimumMinor: number | null;
  maximumMinor: number | null;
  lookbackCycles: number | null;
  status: FieldStatus;
  confidence: ConfidenceLevel | null;
  sourceIds: string[];
}

export interface ResearchedTenorRate {
  fromMonths: number;
  toMonths: number;
  ratePercentBasisPoints: number;
  method: InterestMethodWire;
  period: RatePeriodWire;
  status: FieldStatus;
  sourceIds: string[];
}

export interface CardResearchConflict {
  field: string;
  userValue: string;
  officialValue: string;
}

export interface UnsupportedFinding {
  description: string;
  note: string;
}

export type ResearchStatus =
  | "resolved"
  | "ambiguous"
  | "insufficient_information"
  | "error";

/** Normalized DTO returned to Flutter — the only thing the client ever sees. */
export interface CardResearchResult {
  requestId: string;
  status: ResearchStatus;
  errorMessage: string | null;
  candidates: ProductCandidate[];
  product: {
    issuerName: ResearchedValue<string>;
    productName: ResearchedValue<string>;
    tier: ResearchedValue<string>;
    network: ResearchedValue<NetworkWire>;
    currencyCode: ResearchedValue<string>;
  };
  accountForm: {
    suggestedName: ResearchedValue<string>;
    creditLimitMinor: ResearchedValue<number>;
    defaultDueDay: ResearchedValue<number>;
    statementDay: ResearchedValue<number>;
    minPaymentMethod: ResearchedValue<MinPaymentMethodWire>;
    minPaymentFixedMinor: ResearchedValue<number>;
    minPaymentBasisPoints: ResearchedValue<number>;
  };
  rules: ResearchedFeeRule[];
  installmentTenors: ResearchedTenorRate[];
  sources: ResearchSource[];
  unresolvedRequiredFields: string[];
  conflicts: CardResearchConflict[];
  unsupportedFindings: UnsupportedFinding[];
  metadata: {
    provider: string;
    model: string;
    promptVersion: string;
    researchedAt: string;
  };
}

/** Raw shape requested from the AI provider, before backend validation. */
export interface ProviderRawResult {
  productMatch: {
    status: "resolved" | "ambiguous" | "not_found";
    candidates?: { id: string; label: string }[];
    issuerName?: unknown;
    productName?: unknown;
    tier?: unknown;
    network?: unknown;
    currencyCode?: unknown;
  };
  fields?: {
    defaultDueDay?: unknown;
    statementDay?: unknown;
    minPaymentMethod?: unknown;
    minPaymentFixedMinor?: unknown;
    minPaymentBasisPoints?: unknown;
  };
  rules?: unknown[];
  installmentTenors?: unknown[];
  sources?: unknown[];
  unresolvedRequiredFields?: unknown[];
  conflicts?: unknown[];
  unsupportedFindings?: unknown[];
}
