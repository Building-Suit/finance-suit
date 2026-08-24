import {
  type AdminContext,
  adminError,
  auditMutation,
  authorizeSuperAdmin,
  corsHeaders,
  json,
} from "../_shared/admin.ts";
import {
  enumValue,
  integer,
  pageOf,
  redact,
  requireReason,
  uuid,
} from "../_shared/adminValidation.ts";

type Body = Record<string, unknown>;
function result<T>(value: { data: T; error: unknown }): T {
  if (value.error) throw value.error;
  return value.data;
}

async function handle(
  context: AdminContext,
  body: Body,
): Promise<Record<string, unknown>> {
  const { admin, actorUserId } = context;
  switch (body.action) {
    case "overview": {
      const [summaryResult, contractResult, configResult, runsResult] =
        await Promise.all([
          admin.schema("app_finance").rpc("catalog_status_summary"),
          admin.schema("app_finance").rpc("get_catalog_research_contract"),
          admin.schema("app_finance").rpc("admin_catalog_configuration"),
          admin.schema("app_finance").rpc("admin_catalog_runs", {
            p_offset: 0,
            p_limit: 1,
          }),
        ]);
      const raw = result(summaryResult) as Record<string, unknown>;
      const runs = result(runsResult) as Record<string, unknown>;
      return {
        summary: {
          ...raw,
          active_products: raw.activeProducts,
          due_or_stale: raw.staleProducts,
          queued: raw.queued,
          leased: raw.leased,
          failed: raw.failed,
        },
        contract: result(contractResult),
        configuration: result(configResult),
        latestRun: (runs.runs as unknown[])?.[0] ?? null,
      };
    }
    case "products": {
      const { page, pageSize } = pageOf(body);
      const status = body.status
        ? enumValue(
          body.status,
          ["active", "retired"] as const,
          "invalid_product_status",
        )
        : null;
      return result(
        await admin.schema("app_finance").rpc("admin_catalog_products", {
          p_query: String(body.query ?? "").trim().slice(0, 160),
          p_status: status,
          p_offset: page * pageSize,
          p_limit: pageSize,
        }),
      ) as Record<string, unknown>;
    }
    case "product_detail": {
      const detail = result(
        await admin.schema("app_finance").rpc("admin_catalog_product_detail", {
          p_product_id: uuid(body.productId, "invalid_product_id"),
        }),
      );
      if (!detail) throw new Error("product_not_found");
      return redact(detail) as Record<string, unknown>;
    }
    case "queue": {
      const { page, pageSize } = pageOf(body);
      const status = body.status
        ? enumValue(
          body.status,
          ["queued", "leased", "completed", "failed"] as const,
          "invalid_queue_status",
        )
        : null;
      return result(
        await admin.schema("app_finance").rpc("admin_catalog_queue", {
          p_status: status,
          p_offset: page * pageSize,
          p_limit: pageSize,
        }),
      ) as Record<string, unknown>;
    }
    case "runs": {
      const { page, pageSize } = pageOf(body);
      return result(
        await admin.schema("app_finance").rpc("admin_catalog_runs", {
          p_offset: page * pageSize,
          p_limit: pageSize,
        }),
      ) as Record<string, unknown>;
    }
    case "enqueue_due": {
      const reason = requireReason(body.reason);
      const before = result(
        await admin.schema("app_finance").rpc("catalog_status_summary"),
      );
      const queued = result(
        await admin.schema("app_finance").rpc("enqueue_due_catalog_research"),
      );
      const after = result(
        await admin.schema("app_finance").rpc("catalog_status_summary"),
      );
      await auditMutation(
        context,
        "enqueue_due_catalog_research",
        "catalog_research_queue",
        null,
        before,
        after,
        reason,
      );
      return { result: queued };
    }
    case "requeue": {
      const item = result(
        await admin.schema("app_finance").rpc(
          "admin_requeue_catalog_research",
          {
            p_actor_user_id: actorUserId,
            p_queue_item_id: uuid(body.queueItemId, "invalid_queue_item_id"),
            p_reason: requireReason(body.reason),
          },
        ),
      );
      return { item };
    }
    case "update_config": {
      const config = body.value as Record<string, unknown>;
      if (!config || typeof config !== "object" || Array.isArray(config)) {
        throw new Error("invalid_catalog_configuration");
      }
      const updated = result(
        await admin.schema("app_finance").rpc(
          "update_catalog_configuration_admin",
          {
            p_actor_user_id: actorUserId,
            p_freshness_days: integer(
              config.freshnessDays,
              1,
              365,
              "invalid_freshness_days",
            ),
            p_curator_batch_size: integer(
              config.curatorBatchSize,
              1,
              50,
              "invalid_batch_size",
            ),
            p_lease_minutes: integer(
              config.leaseMinutes,
              1,
              1440,
              "invalid_lease_duration",
            ),
            p_max_attempts: integer(
              config.maxAttempts,
              1,
              20,
              "invalid_max_attempts",
            ),
            p_enqueue_rate_limit_per_hour: integer(
              config.enqueueRateLimitPerHour,
              1,
              1000,
              "invalid_rate_limit",
            ),
            p_reason: requireReason(body.reason),
          },
        ),
      );
      return { configuration: updated };
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
