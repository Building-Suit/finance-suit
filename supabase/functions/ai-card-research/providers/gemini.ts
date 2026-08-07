// Gemini adapter — generateContent with Google Search grounding and
// schema-constrained structured output. As of Aug 2026, combining
// Grounding with Google Search and responseSchema in one call is a Gemini
// 3-series capability (see ai.google.dev/gemini-api/docs/structured-output
// and the Gemini 3 API update notes) — re-check those docs if Google
// changes the shape or moves this behind a different endpoint.

import { providerResultSchema, toGeminiSchema } from "../schema.ts";
import type { ProviderRawResult } from "../types.ts";
import { parseJsonLoose, ProviderError } from "./types.ts";
import type { CardResearchProvider } from "./types.ts";

export class GeminiCardResearchProvider implements CardResearchProvider {
  readonly name = "gemini";
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
    const url =
      `https://generativelanguage.googleapis.com/v1beta/models/${this.model}:generateContent`;
    const body = {
      systemInstruction: { parts: [{ text: instructions }] },
      contents: [{ role: "user", parts: [{ text: input }] }],
      tools: [{ googleSearch: {} }],
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: toGeminiSchema(providerResultSchema),
      },
    };

    let response: Response;
    try {
      response = await fetch(url, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-goog-api-key": this.apiKey,
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(45_000),
      });
    } catch (error) {
      if (error instanceof DOMException && error.name === "TimeoutError") {
        throw new ProviderError("provider_timeout", "Gemini request timed out");
      }
      throw new ProviderError(
        "provider_unavailable",
        `Gemini request failed: ${(error as Error).message}`,
      );
    }

    if (response.status === 401 || response.status === 403) {
      throw new ProviderError("provider_auth_failed", "Gemini rejected the API key");
    }
    if (response.status === 429) {
      throw new ProviderError("provider_rate_limited", "Gemini rate limit hit");
    }
    if (!response.ok) {
      const text = await response.text().catch(() => "");
      throw new ProviderError(
        "provider_unavailable",
        `Gemini returned ${response.status}: ${text.slice(0, 300)}`,
      );
    }

    // deno-lint-ignore no-explicit-any
    const payload: any = await response.json();
    const text = payload?.candidates?.[0]?.content?.parts
      ?.map((part: { text?: string }) => part?.text ?? "")
      ?.join("") ?? "";
    if (!text) {
      throw new ProviderError(
        "malformed_provider_output",
        "Gemini response contained no output text",
      );
    }
    return parseJsonLoose(text) as ProviderRawResult;
  }
}
