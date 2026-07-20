import { createClient } from "npm:@supabase/supabase-js@2.110.7";

const jsonHeaders = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return json(405, { code: "method_not_allowed" });
  }

  const authorization = request.headers.get("authorization");
  const accessToken = authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!accessToken) {
    return json(401, { code: "missing_access_token" });
  }

  let payload: { confirmation?: unknown };
  try {
    payload = await request.json();
  } catch {
    return json(400, { code: "invalid_request" });
  }
  if (payload.confirmation !== "DELETE") {
    return json(400, { code: "confirmation_required" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    console.error("delete-account: required Supabase secrets are unavailable");
    return json(500, { code: "server_misconfigured" });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
      detectSessionInUrl: false,
    },
  });

  // Never trust a user id supplied by the caller. Resolve the owner from the
  // bearer token using the Auth server, then delete only that user's Finance
  // Suit product data. The shared Auth identity belongs to other portals too.
  const {
    data: { user },
    error: userError,
  } = await admin.auth.getUser(accessToken);
  if (userError || !user) {
    return json(401, { code: "invalid_access_token" });
  }

  const lastSignInAt = Date.parse(user.last_sign_in_at ?? "");
  const fiveMinutes = 5 * 60 * 1000;
  if (
    !Number.isFinite(lastSignInAt) || Date.now() - lastSignInAt > fiveMinutes
  ) {
    return json(403, { code: "recent_reauthentication_required" });
  }

  // The database function is service-role-only and performs all deletes in one
  // transaction. It deliberately never touches auth.* or the legacy public
  // schema, so a failure cannot partially erase the shared account.
  const { error: deleteError } = await admin
    .schema("app_core")
    .rpc("delete_finance_suit_data", { p_user_id: user.id });
  if (deleteError) {
    console.error(
      `delete-account: Finance Suit deletion failed: ${deleteError.message}`,
    );
    return json(500, { code: "account_deletion_failed" });
  }

  return json(200, { deleted: true, shared_identity_retained: true });
});
