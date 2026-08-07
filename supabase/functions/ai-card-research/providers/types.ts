import type { ProviderRawResult } from "../types.ts";

export interface CardResearchProvider {
  readonly name: string;
  readonly model: string;
  researchProduct(
    instructions: string,
    input: string,
  ): Promise<ProviderRawResult>;
}

export class ProviderError extends Error {
  readonly code: string;
  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

/** Best-effort extraction of a JSON object from provider text output, in
 * case a model wraps it in a markdown fence despite being told not to. */
export function parseJsonLoose(text: string): unknown {
  const trimmed = text.trim();
  try {
    return JSON.parse(trimmed);
  } catch {
    const fenced = trimmed.match(/```(?:json)?\s*([\s\S]*?)\s*```/i);
    if (fenced) {
      return JSON.parse(fenced[1]);
    }
    throw new ProviderError(
      "malformed_provider_output",
      "Provider did not return valid JSON",
    );
  }
}
