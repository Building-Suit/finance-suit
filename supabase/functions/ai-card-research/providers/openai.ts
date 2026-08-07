// OpenAI adapter — Responses API with the built-in web_search tool and
// strict JSON-Schema structured output (text.format). Verified against
// OpenAI's Responses API + Structured Outputs guides as of Aug 2026: the
// two are independent request parameters (`tools` and `text.format`) and
// combine in one call. Re-check developers.openai.com/api/docs if OpenAI
// changes this shape — do not assume it is frozen.

import { providerResultSchema } from "../schema.ts";
import type { ProviderRawResult } from "../types.ts";
import { parseJsonLoose, ProviderError } from "./types.ts";
import type { CardResearchProvider } from "./types.ts";

const RESPONSES_URL = "https://api.openai.com/v1/responses";

export class OpenAiCardResearchProvider implements CardResearchProvider {
  readonly name = "openai";
  readonly model: string;
  private readonly apiKey: string;

  constructor(apiKey: string, model: string) {
    this.apiKey = apiKey;
    this.model = model;
  }

  async researchProduct(
    instructions: string,
    input: string,
  ): Promise<ProviderRawResult> {
    const body = {
      model: this.model,
      instructions,
      input,
      tools: [{ type: "web_search" }],
      text: {
        format: {
          type: "json_schema",
          name: "card_research_result",
          schema: providerResultSchema,
          strict: true,
        },
      },
    };

    let response: Response;
    try {
      response = await fetch(RESPONSES_URL, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${this.apiKey}`,
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(45_000),
      });
    } catch (error) {
      if (error instanceof DOMException && error.name === "TimeoutError") {
        throw new ProviderError("provider_timeout", "OpenAI request timed out");
      }
      throw new ProviderError(
        "provider_unavailable",
        `OpenAI request failed: ${(error as Error).message}`,
      );
    }

    if (response.status === 401 || response.status === 403) {
      throw new ProviderError("provider_auth_failed", "OpenAI rejected the API key");
    }
    if (response.status === 429) {
      throw new ProviderError("provider_rate_limited", "OpenAI rate limit hit");
    }
    if (!response.ok) {
      const text = await response.text().catch(() => "");
      throw new ProviderError(
        "provider_unavailable",
        `OpenAI returned ${response.status}: ${text.slice(0, 300)}`,
      );
    }

    // deno-lint-ignore no-explicit-any
    const payload: any = await response.json();
    const outputText = extractOutputText(payload);
    if (!outputText) {
      throw new ProviderError(
        "malformed_provider_output",
        "OpenAI response contained no output text",
      );
    }
    return parseJsonLoose(outputText) as ProviderRawResult;
  }
}

// deno-lint-ignore no-explicit-any
function extractOutputText(payload: any): string | null {
  if (typeof payload?.output_text === "string" && payload.output_text) {
    return payload.output_text;
  }
  const output = Array.isArray(payload?.output) ? payload.output : [];
  for (const item of output) {
    if (item?.type !== "message") continue;
    const content = Array.isArray(item.content) ? item.content : [];
    for (const part of content) {
      if (part?.type === "output_text" && typeof part.text === "string") {
        return part.text;
      }
    }
  }
  return null;
}
