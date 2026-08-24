import {
  type AdminContext,
  adminError,
  auditMutation,
  authorizeSuperAdmin,
  corsHeaders,
  json,
} from "../_shared/admin.ts";
import { requireReason } from "../_shared/adminValidation.ts";

type Body = Record<string, unknown>;
function result<T>(value: { data: T; error: unknown }): T {
  if (value.error) throw value.error;
  return value.data;
}

async function handle(
  context: AdminContext,
  body: Body,
): Promise<Record<string, unknown>> {
  switch (body.action) {
    case "health":
      return result(
        await context.admin.schema("app_core").rpc("admin_notification_health"),
      ) as Record<string, unknown>;
    case "send_test_notification": {
      const reason = requireReason(body.reason);
      const outboxId = result(
        await context.admin.schema("app_core").rpc(
          "enqueue_developer_test_notification",
          { target_user_id: context.actorUserId },
        ),
      );
      await auditMutation(
        context,
        "send_test_notification_to_self",
        "notification_outbox",
        String(outboxId),
        null,
        { outbox_id: outboxId, target_user_id: context.actorUserId },
        reason,
      );
      return { outboxId };
    }
    default:
      throw new Error("invalid_action");
  }
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json(405, { code: "method_not_allowed" });
  }
  const context = await authorizeSuperAdmin(request);
  if (context instanceof Response) return context;
  let body: Body;
  try {
    body = await request.json();
  } catch {
    return json(400, { code: "invalid_request" });
  }
  try {
    return json(200, await handle(context, body));
  } catch (error) {
    return adminError(error);
  }
});
