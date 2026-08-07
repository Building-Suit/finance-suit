// The strict JSON Schema the AI provider must fill in. Built once as a
// canonical (OpenAI-dialect) schema, then adapted for Gemini's narrower
// OpenAPI-3.0 subset in `toGeminiSchema`. Keep this in lockstep with
// ProviderRawResult in types.ts and with supported_form_schema in prompt.ts.

import {
  CALCULATION_TYPES,
  CARD_FEE_TYPES,
  CONFIDENCE_LEVELS,
  FEE_FREQUENCIES,
  FIELD_STATUSES,
  INTEREST_METHODS,
  MIN_PAYMENT_METHODS,
  PERCENT_BASES,
  RATE_PERIODS,
} from "./types.ts";

// deno-lint-ignore no-explicit-any
type JsonSchema = Record<string, any>;

function nullable(schema: JsonSchema): JsonSchema {
  const type = schema.type;
  return { ...schema, type: Array.isArray(type) ? type : [type, "null"] };
}

function valueWrapper(
  valueSchema: JsonSchema,
  { withConfidence = true }: { withConfidence?: boolean } = {},
): JsonSchema {
  const properties: JsonSchema = {
    value: valueSchema,
    status: { type: "string", enum: [...FIELD_STATUSES] },
    sourceIds: { type: "array", items: { type: "string" } },
  };
  const required = ["value", "status", "sourceIds"];
  if (withConfidence) {
    properties.confidence = nullable({
      type: "string",
      enum: [...CONFIDENCE_LEVELS],
    });
    required.push("confidence");
  }
  return { type: "object", properties, required, additionalProperties: false };
}

const nullableString = nullable({ type: "string" });
const nullableInteger = nullable({ type: "integer" });

const ruleSchema: JsonSchema = {
  type: "object",
  properties: {
    feeType: { type: "string", enum: [...CARD_FEE_TYPES] },
    calculationType: { type: "string", enum: [...CALCULATION_TYPES] },
    frequency: { type: "string", enum: [...FEE_FREQUENCIES] },
    fixedAmountMinor: nullableInteger,
    percentBasisPoints: nullableInteger,
    percentBasis: nullable({ type: "string", enum: [...PERCENT_BASES] }),
    minimumMinor: nullableInteger,
    maximumMinor: nullableInteger,
    lookbackCycles: nullableInteger,
    status: { type: "string", enum: [...FIELD_STATUSES] },
    confidence: nullable({ type: "string", enum: [...CONFIDENCE_LEVELS] }),
    sourceIds: { type: "array", items: { type: "string" } },
  },
  required: [
    "feeType",
    "calculationType",
    "frequency",
    "fixedAmountMinor",
    "percentBasisPoints",
    "percentBasis",
    "minimumMinor",
    "maximumMinor",
    "lookbackCycles",
    "status",
    "confidence",
    "sourceIds",
  ],
  additionalProperties: false,
};

const tenorSchema: JsonSchema = {
  type: "object",
  properties: {
    fromMonths: { type: "integer" },
    toMonths: { type: "integer" },
    ratePercentBasisPoints: { type: "integer" },
    method: { type: "string", enum: [...INTEREST_METHODS] },
    period: { type: "string", enum: [...RATE_PERIODS] },
    status: { type: "string", enum: [...FIELD_STATUSES] },
    sourceIds: { type: "array", items: { type: "string" } },
  },
  required: [
    "fromMonths",
    "toMonths",
    "ratePercentBasisPoints",
    "method",
    "period",
    "status",
    "sourceIds",
  ],
  additionalProperties: false,
};

const sourceSchema: JsonSchema = {
  type: "object",
  properties: {
    id: { type: "string" },
    url: { type: "string" },
    title: { type: "string" },
    officialDomain: { type: "boolean" },
    publishedDate: nullableString,
    effectiveDate: nullableString,
  },
  required: [
    "id",
    "url",
    "title",
    "officialDomain",
    "publishedDate",
    "effectiveDate",
  ],
  additionalProperties: false,
};

const conflictSchema: JsonSchema = {
  type: "object",
  properties: {
    field: { type: "string" },
    userValue: { type: "string" },
    officialValue: { type: "string" },
  },
  required: ["field", "userValue", "officialValue"],
  additionalProperties: false,
};

const findingSchema: JsonSchema = {
  type: "object",
  properties: {
    description: { type: "string" },
    note: { type: "string" },
  },
  required: ["description", "note"],
  additionalProperties: false,
};

const candidateSchema: JsonSchema = {
  type: "object",
  properties: {
    id: { type: "string" },
    label: { type: "string" },
  },
  required: ["id", "label"],
  additionalProperties: false,
};

export const providerResultSchema: JsonSchema = {
  type: "object",
  properties: {
    productMatch: {
      type: "object",
      properties: {
        status: {
          type: "string",
          enum: ["resolved", "ambiguous", "not_found"],
        },
        candidates: { type: "array", items: candidateSchema },
        issuerName: valueWrapper(nullableString, { withConfidence: false }),
        productName: valueWrapper(nullableString, { withConfidence: false }),
        tier: valueWrapper(nullableString, { withConfidence: false }),
        network: valueWrapper(
          nullable({
            type: "string",
            enum: ["visa", "mastercard", "other", "unknown"],
          }),
          { withConfidence: false },
        ),
        currencyCode: valueWrapper(nullableString, { withConfidence: false }),
      },
      required: [
        "status",
        "candidates",
        "issuerName",
        "productName",
        "tier",
        "network",
        "currencyCode",
      ],
      additionalProperties: false,
    },
    fields: {
      type: "object",
      properties: {
        defaultDueDay: valueWrapper(nullableInteger),
        statementDay: valueWrapper(nullableInteger),
        minPaymentMethod: valueWrapper(
          nullable({ type: "string", enum: [...MIN_PAYMENT_METHODS] }),
        ),
        minPaymentFixedMinor: valueWrapper(nullableInteger),
        minPaymentBasisPoints: valueWrapper(nullableInteger),
      },
      required: [
        "defaultDueDay",
        "statementDay",
        "minPaymentMethod",
        "minPaymentFixedMinor",
        "minPaymentBasisPoints",
      ],
      additionalProperties: false,
    },
    rules: { type: "array", items: ruleSchema },
    installmentTenors: { type: "array", items: tenorSchema },
    sources: { type: "array", items: sourceSchema },
    unresolvedRequiredFields: { type: "array", items: { type: "string" } },
    conflicts: { type: "array", items: conflictSchema },
    unsupportedFindings: { type: "array", items: findingSchema },
  },
  required: [
    "productMatch",
    "fields",
    "rules",
    "installmentTenors",
    "sources",
    "unresolvedRequiredFields",
    "conflicts",
    "unsupportedFindings",
  ],
  additionalProperties: false,
};

/**
 * Gemini's `responseSchema` is an OpenAPI-3.0 subset: no `type` arrays for
 * nullability (use `nullable: true` instead) and no `additionalProperties`.
 */
export function toGeminiSchema(schema: JsonSchema): JsonSchema {
  if (Array.isArray(schema)) {
    return schema.map(toGeminiSchema) as unknown as JsonSchema;
  }
  if (schema === null || typeof schema !== "object") return schema;

  const { additionalProperties: _drop, type, ...rest } = schema;
  const out: JsonSchema = {};
  if (Array.isArray(type)) {
    const nonNull = type.filter((t: string) => t !== "null");
    out.type = nonNull[0] ?? "string";
    if (nonNull.length !== type.length) out.nullable = true;
  } else if (type !== undefined) {
    out.type = type;
  }
  for (const [key, value] of Object.entries(rest)) {
    if (key === "properties" && value && typeof value === "object") {
      out.properties = Object.fromEntries(
        Object.entries(value as JsonSchema).map((
          [k, v],
        ) => [k, toGeminiSchema(v as JsonSchema)]),
      );
    } else if (key === "items") {
      out.items = toGeminiSchema(value as JsonSchema);
    } else {
      out[key] = value;
    }
  }
  return out;
}
