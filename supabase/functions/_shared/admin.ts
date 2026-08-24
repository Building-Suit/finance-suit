import {
  createClient,
  type SupabaseClient,
} from "npm:@supabase/supabase-js@2.110.7";

export const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, x-client-info, apikey, content-type, x-request-id",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-max-age": "86400",
};

export function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

export type AdminContext = {
  admin: SupabaseClient;
  actorUserId: string;
  correlationId: string | null;
};

export async function authorizeSuperAdmin(
  request: Request,
): Promise<AdminContext | Response> {
  const accessToken = request.headers.get("authorization")?.match(
    /^Bearer\s+(.+)$/i,
  )?.[1];
  if (!accessToken) return json(401, { code: "missing_access_token" });
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json(500, { code: "server_misconfigured" });
  }
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
      detectSessionInUrl: false,
    },
  });
  const { data: { user }, error } = await admin.auth.getUser(accessToken);
  if (error || !user) return json(401, { code: "invalid_access_token" });
  const { data: adminRow } = await admin.schema("app_commercial").from(
    "platform_admins",
  ).select("role,status").eq("user_id", user.id).eq("status", "active").eq(
    "role",
    "super_admin",
  ).maybeSingle();
  if (!adminRow) return json(403, { code: "super_admin_required" });
  return {
    admin,
    actorUserId: user.id,
    correlationId: request.headers.get("x-request-id"),
  };
}

export async function auditMutation(
  context: AdminContext,
  action: string,
  targetType: string,
  targetId: string | null,
  beforeState: unknown,
  afterState: unknown,
  reason: string,
) {
  const { error } = await context.admin.schema("app_commercial").rpc(
    "audit_commercial_mutation",
    {
      p_actor_user_id: context.actorUserId,
      p_action: action,
      p_target_type: targetType,
      p_target_id: targetId,
      p_before_state: beforeState,
      p_after_state: afterState,
      p_reason: reason,
      p_correlation_id: context.correlationId,
    },
  );
  if (error) throw error;
}

export function adminError(error: unknown): Response {
  const message = error instanceof Error
    ? error.message
    : String(error || "unknown_error");
  const known = [
    "reason_required",
    "invalid_",
    "not_found",
    "forbidden",
    "locked",
    "guard",
    "missing",
    "not_finished",
  ];
  if (known.some((token) => message.includes(token))) {
    const code = message.match(/[a-z][a-z0-9_]+/)?.[0] || "invalid_request";
    return json(
      message.includes("not_found")
        ? 404
        : message.includes("locked") || message.includes("guard")
        ? 409
        : 400,
      { code },
    );
  }
  console.error(`admin operation failed: ${message}`);
  return json(500, { code: "admin_operation_failed" });
}
