// AI card/BNPL research endpoint (task spec sections 12-21, 40, 46).
//
// Server-side only: the AI provider API key never leaves this function.
// This endpoint researches public product information and returns strict,
// backend-validated structured data — it never writes to any financial
// table, never calls a financial RPC, and never creates an account. The
// existing `save_credit_facility` RPC remains the only account-creation
// path; Flutter maps this endpoint's response into the existing Add
// Account form and submits through the existing Create handler.

import { createClient } from "npm:@supabase/supabase-js@2.110.7";
import { buildInstructions, buildResearchInput, PROMPT_VERSION } from "./prompt.ts";
import { normalizeProviderResult, validateRequest } from "./validate.ts";
import { GeminiCardResearchProvider } from "./providers/gemini.ts";
import { OpenAiCardResearchProvider } from "./providers/openai.ts";
import { ProviderError } from "./providers/types.ts";
import type { CardResearchProvider } from "./providers/types.ts";
import type { CardResearchRequest } from "./types.ts";

const jsonHeaders = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

const MAX_BODY_BYTES = 20_000;
const RATE_LIMIT_WINDOW_MINUTES = 60;
const DEFAULT_RATE_LIMIT_PER_HOUR = 20;
const CACHE_TTL_MINUTES = 15;

function buildProvider(): CardResearchProvider | { error: string } {
  const providerName = Deno.env.get("AI_CARD_RESEARCH_PROVIDER");
  const model = Deno.env.get("AI_CARD_RESEARCH_MODEL");
  if (!providerName || !model) {
    return { error: "AI_CARD_RESEARCH_PROVIDER and AI_CARD_RESEARCH_MODEL must be set" };
  }
  if (providerName === "openai") {
    const apiKey = Deno.env.get("OPENAI_API_KEY");
    if (!apiKey) return { error: "OPENAI_API_KEY is not configured" };
    return new OpenAiCardResearchProvider(apiKey, model);
  }
  if (providerName === "gemini") {
    const apiKey = Deno.env.get("GEMINI_API_KEY");
    if (!apiKey) return { error: "GEMINI_API_KEY is not configured" };
    return new GeminiCardResearchProvider(apiKey, model);
  }
  return { error: `Unknown AI_CARD_RESEARCH_PROVIDER: ${providerName}` };
}

/** Stable hash of the research-relevant request fields (excludes the
 * correlation-only requestId) for short-TTL duplicate-request caching. */
async function hashRequest(request: CardResearchRequest): Promise<string> {
  const material = JSON.stringify({
    accountType: request.accountType,
    issuerName: request.issuerName.toLowerCase(),
    countryCode: request.countryCode,
    officialWebsite: request.officialWebsite,
    productName: request.productName.toLowerCase(),
    tier: request.tier?.toLowerCase() ?? null,
    network: request.network,
    currencyCode: request.currencyCode,
    activationDate: request.activationDate,
    knownStatementDay: request.knownStatementDay,
    knownDueDay: request.knownDueDay,
    bnplTypicalTenorMonths: request.bnplTypicalTenorMonths,
    userNotes: request.userNotes,
    selectedProductId: request.selectedProductId,
  });
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(material),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return json(405, { code: "method_not_allowed" });
  }

  const authorization = request.headers.get("authorization");
  if (!authorization) {
    return json(401, { code: "missing_access_token" });
  }

  const rawBody = await request.text();
  if (rawBody.length > MAX_BODY_BYTES) {
    return json(413, { code: "request_too_large" });
  }
  let parsedBody: unknown;
  try {
    parsedBody = JSON.parse(rawBody);
  } catch {
    return json(400, { code: "invalid_request" });
  }
  const validated = validateRequest(parsedBody);
  if (!validated.ok) {
    return json(400, { code: validated.error.code, message: validated.error.message });
  }
  const cardRequest = validated.value;

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !anonKey) {
    console.error("ai-card-research: required Supabase secrets are unavailable");
    return json(500, { code: "server_misconfigured" });
  }

  // Client scoped to the caller's own JWT so RLS enforces per-user isolation
  // automatically — this function never uses the service-role key.
  const supabase = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
  });

  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser();
  if (userError || !user) {
    return json(401, { code: "invalid_access_token" });
  }

  const rateLimit = Number(Deno.env.get("AI_CARD_RESEARCH_RATE_LIMIT_PER_HOUR")) ||
    DEFAULT_RATE_LIMIT_PER_HOUR;
  const windowStart = new Date(Date.now() - RATE_LIMIT_WINDOW_MINUTES * 60_000).toISOString();
  const { count: recentCount, error: rateError } = await supabase
    .schema("app_finance")
    .from("ai_card_research_requests")
    .select("id", { count: "exact", head: true })
    .gte("created_at", windowStart);
  if (rateError) {
    console.error(`ai-card-research: rate limit lookup failed: ${rateError.message}`);
  } else if ((recentCount ?? 0) >= rateLimit) {
    return json(429, { code: "rate_limited" });
  }

  const requestHash = await hashRequest(cardRequest);
  const cacheWindowStart = new Date(Date.now() - CACHE_TTL_MINUTES * 60_000).toISOString();
  const { data: cached } = await supabase
    .schema("app_finance")
    .from("ai_card_research_requests")
    .select("normalized_result")
    .eq("request_hash", requestHash)
    .eq("status", "completed")
    .gte("created_at", cacheWindowStart)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (cached?.normalized_result) {
    const result = cached.normalized_result as Record<string, unknown>;
    return json(200, { ...result, requestId: cardRequest.requestId });
  }

  const provider = buildProvider();
  if ("error" in provider) {
    console.error(`ai-card-research: ${provider.error}`);
    return json(500, { code: "server_misconfigured" });
  }

  const instructions = buildInstructions(cardRequest.accountType);
  const input = buildResearchInput(cardRequest);

  try {
    const raw = await provider.researchProduct(instructions, input);
    const normalized = normalizeProviderResult(raw, cardRequest, {
      provider: provider.name,
      model: provider.model,
    });

    const { error: insertError } = await supabase
      .schema("app_finance")
      .from("ai_card_research_requests")
      .insert({
        request_id: cardRequest.requestId,
        account_type: cardRequest.accountType,
        request_hash: requestHash,
        provider: provider.name,
        model: provider.model,
        prompt_version: PROMPT_VERSION,
        status: "completed",
        normalized_result: normalized,
        completed_at: new Date().toISOString(),
      });
    if (insertError) {
      console.error(`ai-card-research: failed to persist request metadata: ${insertError.message}`);
    }

    return json(200, normalized as unknown as Record<string, unknown>);
  } catch (error) {
    const providerError = error instanceof ProviderError
      ? error
      : new ProviderError("unknown_error", (error as Error).message ?? "Unknown error");

    await supabase
      .schema("app_finance")
      .from("ai_card_research_requests")
      .insert({
        request_id: cardRequest.requestId,
        account_type: cardRequest.accountType,
        request_hash: requestHash,
        provider: provider.name,
        model: provider.model,
        prompt_version: PROMPT_VERSION,
        status: "failed",
        error_message: providerError.message.slice(0, 500),
        completed_at: new Date().toISOString(),
      })
      .then(({ error: e }) => {
        if (e) console.error(`ai-card-research: failed to persist failure metadata: ${e.message}`);
      });

    console.error(`ai-card-research: ${providerError.code}: ${providerError.message}`);
    const status = providerError.code === "provider_rate_limited"
      ? 429
      : providerError.code === "provider_auth_failed"
      ? 502
      : providerError.code === "provider_timeout"
      ? 504
      : 502;
    return json(status, {
      code: providerError.code,
      message: "We couldn't find enough reliable information right now.",
    });
  }
});
