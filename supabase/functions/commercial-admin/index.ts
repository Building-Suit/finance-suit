import { createClient } from "npm:@supabase/supabase-js@2.110.7";

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-max-age": "86400",
};

const jsonHeaders = {
  ...corsHeaders,
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

type AdminBody = {
  action?: string;
  reason?: string;
  userId?: string;
  grantId?: string;
  planKey?: "pro";
  days?: number;
  endsAt?: string;
  permanent?: boolean;
  enabled?: boolean;
  page?: number;
  pageSize?: number;
  campaignKey?: string;
  active?: boolean;
  durationDays?: number;
  configKey?: string;
  value?: Record<string, unknown>;
  announcement?: Record<string, unknown>;
};

function requireReason(body: AdminBody): string {
  const reason = String(body.reason ?? "").trim();
  if (reason.length < 6) throw new Error("reason_required");
  return reason;
}

function assertUuid(value: unknown, code: string): string {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value)
  ) {
    throw new Error(code);
  }
  return value;
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json(405, { code: "method_not_allowed" });
  }
  const authorization = request.headers.get("authorization");
  const accessToken = authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!accessToken) return json(401, { code: "missing_access_token" });

  let body: AdminBody;
  try {
    body = await request.json();
  } catch {
    return json(400, { code: "invalid_request" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    console.error("commercial-admin: Supabase service role unavailable");
    return json(500, { code: "server_misconfigured" });
  }
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
      detectSessionInUrl: false,
    },
  });
  const { data: { user }, error: userError } = await admin.auth.getUser(
    accessToken,
  );
  if (userError || !user) return json(401, { code: "invalid_access_token" });
  const actorUserId = user.id;

  const { data: adminRow } = await admin
    .schema("app_commercial")
    .from("platform_admins")
    .select("role,status")
    .eq("user_id", actorUserId)
    .eq("status", "active")
    .eq("role", "super_admin")
    .maybeSingle();
  if (!adminRow) return json(403, { code: "super_admin_required" });

  async function audit(
    action: string,
    targetType: string,
    targetId: string | null,
    beforeState: unknown,
    afterState: unknown,
    reason = "",
  ) {
    await admin.schema("app_commercial").from("audit_log").insert({
      actor_user_id: actorUserId,
      action,
      target_type: targetType,
      target_id: targetId,
      before_state: beforeState,
      after_state: afterState,
      reason,
      correlation_id: request.headers.get("x-request-id"),
    });
  }

  try {
    switch (body.action) {
      case "overview": {
        const now = new Date().toISOString();
        const [
          profiles,
          paid,
          early,
          trials,
          canceled,
          providerFailures,
          failedEvents,
          campaigns,
          prices,
          provider,
          config,
          monetization,
        ] = await Promise.all([
          admin.schema("app_core").from("profiles").select("id", {
            count: "exact",
            head: true,
          }),
          admin.schema("app_commercial").from("paid_subscriptions").select(
            "id",
            { count: "exact", head: true },
          ).in("status", ["active", "in_grace_period", "canceled"]).gt(
            "expires_at",
            now,
          ),
          admin.schema("app_commercial").from("entitlement_grants").select(
            "id",
            { count: "exact", head: true },
          ).in("source", ["early_access", "migration", "promotional_campaign"])
            .eq("status", "active").gt("ends_at", now),
          admin.schema("app_commercial").from("entitlement_grants").select(
            "id",
            { count: "exact", head: true },
          ).eq("source", "standard_trial").eq("status", "active").gt(
            "ends_at",
            now,
          ),
          admin.schema("app_commercial").from("paid_subscriptions").select(
            "id",
            { count: "exact", head: true },
          ).eq("status", "canceled"),
          admin.schema("app_commercial").from("paid_subscriptions").select(
            "id",
            { count: "exact", head: true },
          ).eq("status", "verification_failed"),
          admin.schema("app_commercial").from("billing_events").select("id", {
            count: "exact",
            head: true,
          }).neq("processing_result", "processed"),
          admin.schema("app_commercial").from("promotional_campaigns").select(
            "*",
          ).order("created_at", { ascending: false }),
          admin.schema("app_commercial").from("plan_prices").select("*").eq(
            "status",
            "published",
          ),
          admin.schema("app_commercial").from("provider_configurations").select(
            "*",
          ),
          admin.schema("app_commercial").from("app_config").select("*").eq(
            "status",
            "published",
          ),
          admin.schema("app_commercial").from("monetization_state").select("*")
            .eq("singleton", true).single(),
        ]);
        return json(200, {
          overview: {
            totalUsers: profiles.count ?? 0,
            paidProUsers: paid.count ?? 0,
            earlyAccessUsers: early.count ?? 0,
            standardTrialUsers: trials.count ?? 0,
            freeUsers: Math.max(
              (profiles.count ?? 0) - (paid.count ?? 0) - (early.count ?? 0) -
                (trials.count ?? 0),
              0,
            ),
            canceledSubscriptions: canceled.count ?? 0,
            providerVerificationFailures: providerFailures.count ?? 0,
            failedBillingEvents: failedEvents.count ?? 0,
          },
          campaigns: campaigns.data ?? [],
          prices: prices.data ?? [],
          provider: provider.data ?? [],
          config: config.data ?? [],
          monetization: monetization.data,
        });
      }
      case "users": {
        const query = String((body as Record<string, unknown>).query ?? "")
          .trim();
        const pageSize = Math.min(
          Math.max(Number(body.pageSize ?? 25), 1),
          100,
        );
        const page = Math.max(Number(body.page ?? 0), 0);
        let profiles = admin.schema("app_core").from("profiles").select(
          "id,display_name,created_at",
          { count: "exact" },
        ).order("created_at", { ascending: false }).range(
          page * pageSize,
          page * pageSize + pageSize - 1,
        );
        if (query) profiles = profiles.ilike("display_name", `%${query}%`);
        const { data, count, error } = await profiles;
        if (error) throw error;
        return json(200, {
          users: data ?? [],
          count: count ?? 0,
          page,
          pageSize,
        });
      }
      case "user_detail": {
        const targetUserId = assertUuid(body.userId, "invalid_user_id");
        const [
          profile,
          entitlement,
          grants,
          subscriptions,
          events,
          auditEvents,
          billingTester,
        ] = await Promise.all([
          admin.schema("app_core").from("profiles").select(
            "id,display_name,created_at",
          ).eq("id", targetUserId).maybeSingle(),
          admin.schema("app_commercial").rpc("resolve_effective_entitlement", {
            p_user_id: targetUserId,
          }),
          admin.schema("app_commercial").from("entitlement_grants").select("*")
            .eq("user_id", targetUserId).order("created_at", {
              ascending: false,
            }),
          admin.schema("app_commercial").from("paid_subscriptions").select(
            "id,provider,plan_key,status,expires_at,auto_renewing,last_verified_at,provider_product_id,provider_base_plan_id",
          ).eq("user_id", targetUserId).order("created_at", {
            ascending: false,
          }),
          admin.schema("app_commercial").from("billing_events").select(
            "id,provider,event_type,received_at,processed_at,processing_result",
          ).eq("user_id", targetUserId).order("received_at", {
            ascending: false,
          }).limit(50),
          admin.schema("app_commercial").from("audit_log").select(
            "id,action,reason,created_at,before_state,after_state",
          ).or(`target_id.eq.${targetUserId},actor_user_id.eq.${targetUserId}`)
            .order("created_at", { ascending: false }).limit(50),
          admin.schema("app_commercial").from("billing_testers").select(
            "enabled,reason,updated_at",
          ).eq("user_id", targetUserId).maybeSingle(),
        ]);
        return json(200, {
          profile: profile.data,
          entitlement: Array.isArray(entitlement.data)
            ? entitlement.data[0]
            : entitlement.data,
          grants: grants.data ?? [],
          subscriptions: subscriptions.data ?? [],
          billingEvents: events.data ?? [],
          auditEvents: auditEvents.data ?? [],
          billingTester: billingTester.data,
        });
      }
      case "grant_pro": {
        const targetUserId = assertUuid(body.userId, "invalid_user_id");
        const reason = requireReason(body);
        const startsAt = new Date();
        const endsAt = body.permanent
          ? null
          : body.endsAt
          ? new Date(body.endsAt)
          : new Date(Date.now() + (Number(body.days ?? 0) * 86_400_000));
        if (
          endsAt && (!Number.isFinite(endsAt.getTime()) || endsAt <= startsAt)
        ) {
          return json(400, { code: "invalid_expiration" });
        }
        const grant = {
          user_id: targetUserId,
          plan_key: "pro",
          source: "admin_grant",
          starts_at: startsAt.toISOString(),
          ends_at: endsAt?.toISOString() ?? null,
          granted_by: actorUserId,
          reason,
        };
        const { data, error } = await admin.schema("app_commercial").from(
          "entitlement_grants",
        ).insert(grant).select().single();
        if (error) throw error;
        await audit(
          "grant_pro",
          "entitlement_grant",
          data.id,
          null,
          data,
          reason,
        );
        return json(200, { grant: data });
      }
      case "end_grant": {
        const grantId = assertUuid(body.grantId, "invalid_grant_id");
        const reason = requireReason(body);
        const before = await admin.schema("app_commercial").from(
          "entitlement_grants",
        ).select("*").eq("id", grantId).single();
        if (before.data?.status !== "active") {
          return json(200, { grant: before.data, idempotent: true });
        }
        const { data, error } = await admin.schema("app_commercial").from(
          "entitlement_grants",
        ).update({
          status: "ended",
          ends_at: new Date().toISOString(),
        }).eq("id", grantId).select().single();
        if (error) throw error;
        await audit(
          "end_grant",
          "entitlement_grant",
          grantId,
          before.data,
          data,
          reason,
        );
        return json(200, { grant: data });
      }
      case "set_billing_test_access": {
        const targetUserId = assertUuid(body.userId, "invalid_user_id");
        const reason = requireReason(body);
        const enabled = body.enabled === true;
        const before = await admin.schema("app_commercial").from(
          "billing_testers",
        )
          .select("*").eq("user_id", targetUserId).maybeSingle();
        const billingTesters = admin.schema("app_commercial").from(
          "billing_testers",
        );
        const { data, error } = before.data
          ? await billingTesters.update({ enabled, reason })
            .eq("user_id", targetUserId).select().single()
          : await billingTesters.insert({
            user_id: targetUserId,
            enabled,
            created_by: actorUserId,
            reason,
          }).select().single();
        if (error) throw error;
        await audit(
          enabled
            ? "enable_billing_test_access"
            : "disable_billing_test_access",
          "billing_tester",
          targetUserId,
          before.data,
          data,
          reason,
        );
        return json(200, { billingTester: data });
      }
      case "start_monetization_cycle": {
        const reason = requireReason(body);
        const { data, error } = await admin.schema("app_commercial").rpc(
          "start_monetization_cycle",
          {
            p_actor_user_id: actorUserId,
            p_reason: reason,
          },
        );
        if (error) throw error;
        return json(200, { monetization: data });
      }
      case "audit_log": {
        const userId = typeof body.userId === "string" ? body.userId : null;
        let auditQuery = admin.schema("app_commercial").from("audit_log")
          .select(
            "id,actor_user_id,action,target_type,target_id,reason,before_state,after_state,created_at",
            { count: "exact" },
          )
          .order("created_at", { ascending: false }).limit(100);
        if (userId) {
          auditQuery = auditQuery.or(
            `actor_user_id.eq.${userId},target_id.eq.${userId}`,
          );
        }
        const { data, count, error } = await auditQuery;
        if (error) throw error;
        return json(200, { events: data ?? [], count: count ?? 0 });
      }
      case "update_campaign": {
        const campaignKey = String(body.campaignKey ?? "");
        const reason = requireReason(body);
        if (!/^[a-z][a-z0-9_]*$/.test(campaignKey)) {
          return json(400, { code: "invalid_campaign_key" });
        }
        const patch: Record<string, unknown> = {};
        if (typeof body.active === "boolean") patch.active = body.active;
        if (body.durationDays != null) {
          const days = Number(body.durationDays);
          if (!Number.isInteger(days) || days < 1 || days > 3650) {
            return json(400, { code: "invalid_duration" });
          }
          patch.duration_days = days;
        }
        const before = await admin.schema("app_commercial").from(
          "promotional_campaigns",
        ).select("*").eq("key", campaignKey).single();
        const { data, error } = await admin.schema("app_commercial").from(
          "promotional_campaigns",
        ).update(patch).eq("key", campaignKey).select().single();
        if (error) throw error;
        await audit(
          "update_campaign",
          "promotional_campaign",
          String(data.id),
          before.data,
          data,
          reason,
        );
        return json(200, { campaign: data });
      }
      case "update_config": {
        const configKey = String(body.configKey ?? "");
        const reason = requireReason(body);
        if (!/^[a-z][a-z0-9_]*$/.test(configKey) || !body.value) {
          return json(400, { code: "invalid_config" });
        }
        const before = await admin.schema("app_commercial").from("app_config")
          .select("*").eq("key", configKey).single();
        const { data, error } = await admin.schema("app_commercial").from(
          "app_config",
        ).update({ value: body.value }).eq("key", configKey).select().single();
        if (error) throw error;
        await audit(
          "update_config",
          "app_config",
          configKey,
          before.data,
          data,
          reason,
        );
        return json(200, { config: data });
      }
      default:
        return json(400, { code: "unknown_action" });
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : "unknown_error";
    if (message === "reason_required") {
      return json(400, { code: "reason_required" });
    }
    if (message.startsWith("invalid_")) return json(400, { code: message });
    console.error(`commercial-admin: ${message}`);
    return json(500, { code: "admin_operation_failed" });
  }
});
