import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { OpenAiCardResearchProvider } from "./openai.ts";
import { GeminiCardResearchProvider } from "./gemini.ts";
import { ProviderError } from "./types.ts";

function withMockFetch<T>(
  handler: (input: string | URL | Request, init?: RequestInit) => Promise<Response> | Response,
  run: () => Promise<T>,
): Promise<T> {
  const original = globalThis.fetch;
  // deno-lint-ignore no-explicit-any
  globalThis.fetch = handler as any;
  return run().finally(() => {
    globalThis.fetch = original;
  });
}

const SAMPLE_RESULT = {
  productMatch: { status: "resolved" },
  fields: {},
  rules: [],
  installmentTenors: [],
  sources: [],
  unresolvedRequiredFields: [],
  conflicts: [],
  unsupportedFindings: [],
};

Deno.test("OpenAiCardResearchProvider extracts structured JSON from output_text", async () => {
  const provider = new OpenAiCardResearchProvider("test-key", "gpt-test");
  const result = await withMockFetch(
    () =>
      new Response(
        JSON.stringify({ output_text: JSON.stringify(SAMPLE_RESULT) }),
        { status: 200 },
      ),
    () => provider.researchProduct("instructions", "input"),
  );
  assertEquals(result.productMatch.status, "resolved");
});

Deno.test("OpenAiCardResearchProvider extracts structured JSON from the output array", async () => {
  const provider = new OpenAiCardResearchProvider("test-key", "gpt-test");
  const result = await withMockFetch(
    () =>
      new Response(
        JSON.stringify({
          output: [
            { type: "web_search_call" },
            {
              type: "message",
              content: [{ type: "output_text", text: JSON.stringify(SAMPLE_RESULT) }],
            },
          ],
        }),
        { status: 200 },
      ),
    () => provider.researchProduct("instructions", "input"),
  );
  assertEquals(result.productMatch.status, "resolved");
});

Deno.test("OpenAiCardResearchProvider maps 401 to provider_auth_failed", async () => {
  const provider = new OpenAiCardResearchProvider("bad-key", "gpt-test");
  await withMockFetch(
    () => new Response("unauthorized", { status: 401 }),
    async () => {
      const error = await assertRejects(
        () => provider.researchProduct("i", "in"),
        ProviderError,
      );
      assertEquals((error as ProviderError).code, "provider_auth_failed");
    },
  );
});

Deno.test("OpenAiCardResearchProvider maps 429 to provider_rate_limited", async () => {
  const provider = new OpenAiCardResearchProvider("key", "gpt-test");
  await withMockFetch(
    () => new Response("slow down", { status: 429 }),
    async () => {
      const error = await assertRejects(
        () => provider.researchProduct("i", "in"),
        ProviderError,
      );
      assertEquals((error as ProviderError).code, "provider_rate_limited");
    },
  );
});

Deno.test("OpenAiCardResearchProvider rejects malformed JSON output", async () => {
  const provider = new OpenAiCardResearchProvider("key", "gpt-test");
  await withMockFetch(
    () => new Response(JSON.stringify({ output_text: "not json at all" }), { status: 200 }),
    async () => {
      const error = await assertRejects(
        () => provider.researchProduct("i", "in"),
        ProviderError,
      );
      assertEquals((error as ProviderError).code, "malformed_provider_output");
    },
  );
});

Deno.test("OpenAiCardResearchProvider strips a markdown fence if present", async () => {
  const provider = new OpenAiCardResearchProvider("key", "gpt-test");
  const fenced = "```json\n" + JSON.stringify(SAMPLE_RESULT) + "\n```";
  const result = await withMockFetch(
    () => new Response(JSON.stringify({ output_text: fenced }), { status: 200 }),
    () => provider.researchProduct("i", "in"),
  );
  assertEquals(result.productMatch.status, "resolved");
});

Deno.test("GeminiCardResearchProvider extracts structured JSON from candidate parts", async () => {
  const provider = new GeminiCardResearchProvider("test-key", "gemini-test");
  const result = await withMockFetch(
    () =>
      new Response(
        JSON.stringify({
          candidates: [
            { content: { parts: [{ text: JSON.stringify(SAMPLE_RESULT) }] } },
          ],
        }),
        { status: 200 },
      ),
    () => provider.researchProduct("instructions", "input"),
  );
  assertEquals(result.productMatch.status, "resolved");
});

Deno.test("GeminiCardResearchProvider maps 403 to provider_auth_failed", async () => {
  const provider = new GeminiCardResearchProvider("bad-key", "gemini-test");
  await withMockFetch(
    () => new Response("forbidden", { status: 403 }),
    async () => {
      const error = await assertRejects(
        () => provider.researchProduct("i", "in"),
        ProviderError,
      );
      assertEquals((error as ProviderError).code, "provider_auth_failed");
    },
  );
});

Deno.test("GeminiCardResearchProvider surfaces provider_unavailable on 5xx", async () => {
  const provider = new GeminiCardResearchProvider("key", "gemini-test");
  await withMockFetch(
    () => new Response("boom", { status: 503 }),
    async () => {
      const error = await assertRejects(
        () => provider.researchProduct("i", "in"),
        ProviderError,
      );
      assertEquals((error as ProviderError).code, "provider_unavailable");
    },
  );
});
