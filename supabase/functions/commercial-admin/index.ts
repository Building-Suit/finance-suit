import {
  type AdminContext,
  adminError,
  auditMutation,
  authorizeSuperAdmin,
  corsHeaders,
  json,
} from "../_shared/admin.ts";
import {
  boundedText,
  enumValue,
  integer,
  optionalDate,
  pageOf,
  redact,
  requireReason,
  uuid,
  validateAnnouncement,
} from "../_shared/adminValidation.ts";
import { normalizeCatalogSummary } from "../_shared/adminPresentation.ts";

type Body = Record<string, unknown>;
function value<T>(result: { data: T; error: unknown }): T {
  if (result.error) throw result.error;
  return result.data;
}
const key = (input: unknown, code = "invalid_key") => {
  const result = String(input ?? "");
  if (!/^[a-z][a-z0-9_]*$/.test(result)) throw new Error(code);
  return result;
};

async function overview(context: AdminContext) {
  const { admin } = context;
  const now = new Date().toISOString();
  const recent = new Date(Date.now() - 86_400_000 * 7).toISOString();
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
    audit,
    catalog,
    pending,
    sending,
    failed,
    devices,
    announcements,
  ] = await Promise.all([
    admin.schema("app_core").from("profiles").select("id", {
      count: "exact",
      head: true,
    }),
    admin.schema("app_commercial").from("paid_subscriptions").select("id", {
      count: "exact",
      head: true,
    }).in("status", ["active", "in_grace_period", "canceled"]).gt(
      "expires_at",
      now,
    ),
    admin.schema("app_commercial").from("entitlement_grants").select("id", {
      count: "exact",
      head: true,
    }).in("source", ["early_access", "migration", "promotional_campaign"]).eq(
      "status",
      "active",
    ).gt("ends_at", now),
    admin.schema("app_commercial").from("entitlement_grants").select("id", {
      count: "exact",
      head: true,
    }).eq("source", "standard_trial").eq("status", "active").gt("ends_at", now),
    admin.schema("app_commercial").from("paid_subscriptions").select("id", {
      count: "exact",
      head: true,
    }).eq("status", "canceled"),
    admin.schema("app_commercial").from("paid_subscriptions").select("id", {
      count: "exact",
      head: true,
    }).eq("status", "verification_failed"),
    admin.schema("app_commercial").from("billing_events").select("id", {
      count: "exact",
      head: true,
    }).neq("processing_result", "processed"),
    admin.schema("app_commercial").from("promotional_campaigns").select("*")
      .order("created_at", { ascending: false }),
    admin.schema("app_commercial").from("plan_prices").select("*").eq(
      "status",
      "published",
    ),
    admin.schema("app_commercial").from("provider_configurations").select(
      "provider,package_name,status,last_synced_at,last_error,updated_at,metadata",
    ),
    admin.schema("app_commercial").from("app_config").select(
      "key,value,status,updated_at",
    ).eq("status", "published"),
    admin.schema("app_commercial").from("monetization_state").select("*").eq(
      "singleton",
      true,
    ).single(),
    admin.schema("app_commercial").from("audit_log").select(
      "id,actor_user_id,action,target_type,target_id,reason,created_at,correlation_id",
    ).order("created_at", { ascending: false }).limit(8),
    admin.schema("app_finance").rpc("catalog_status_summary"),
    admin.schema("app_core").from("notification_outbox").select("id", {
      count: "exact",
      head: true,
    }).in("status", ["pending", "retry"]),
    admin.schema("app_core").from("notification_outbox").select("id", {
      count: "exact",
      head: true,
    }).eq("status", "sending"),
    admin.schema("app_core").from("notification_outbox").select("id", {
      count: "exact",
      head: true,
    }).eq("status", "failed"),
    admin.schema("app_core").from("push_devices").select("id", {
      count: "exact",
      head: true,
    }).eq("is_enabled", true),
    admin.schema("app_commercial").from("announcements").select("id", {
      count: "exact",
      head: true,
    }).eq("active", true).or(`ends_at.is.null,ends_at.gt.${now}`).or(
      `starts_at.is.null,starts_at.lte.${now}`,
    ),
  ]);
  const maintenance = (config.data || []).find((item) =>
    item.key === "maintenance"
  )?.value as Record<string, unknown> | undefined;
  const versionPolicy = (config.data || []).find((item) =>
    item.key === "version_policy"
  );
  return {
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
    provider: (provider.data ?? []).map((item) => redact(item)),
    config: config.data ?? [],
    monetization: monetization.data,
    recentAudit: (audit.data ?? []).map((item) => redact(item)),
    catalog: normalizeCatalogSummary(
      (catalog.data ?? {}) as Record<string, unknown>,
    ),
    notifications: {
      pending: pending.count ?? 0,
      sending: sending.count ?? 0,
      failed: failed.count ?? 0,
      enabledDevices: devices.count ?? 0,
      since: recent,
    },
    operations: {
      maintenanceEnabled: maintenance?.enabled === true,
      activeAnnouncements: announcements.count ?? 0,
      versionPolicyStatus: versionPolicy ? "configured" : "missing",
    },
  };
}

async function handle(
  context: AdminContext,
  body: Body,
): Promise<Record<string, unknown>> {
  const { admin, actorUserId } = context;
  switch (body.action) {
    case "access_check":
      return { authorized: true, role: "super_admin", userId: actorUserId };
    case "overview":
      return await overview(context);
    case "users": {
      const { page, pageSize } = pageOf(body);
      const query = String(body.query ?? "").trim();
      const ascending = body.sort === "asc";
      let request = admin.schema("app_core").from("profiles").select(
        "id,display_name,created_at",
        { count: "exact" },
      ).order("created_at", { ascending }).range(
        page * pageSize,
        page * pageSize + pageSize - 1,
      );
      if (query) {
        request = /^[0-9a-f-]{36}$/i.test(query)
          ? request.eq("id", uuid(query, "invalid_user_id"))
          : request.ilike(
            "display_name",
            `%${query.replaceAll("%", "\\%").replaceAll("_", "\\_")}%`,
          );
      }
      const result = await request;
      if (result.error) throw result.error;
      return {
        users: result.data ?? [],
        count: result.count ?? 0,
        page,
        pageSize,
      };
    }
    case "user_detail": {
      const userId = uuid(body.userId, "invalid_user_id");
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
        ).eq("id", userId).maybeSingle(),
        admin.schema("app_commercial").rpc("resolve_effective_entitlement", {
          p_user_id: userId,
        }),
        admin.schema("app_commercial").from("entitlement_grants").select(
          "id,plan_key,source,campaign_id,starts_at,ends_at,status,reason,created_at",
        ).eq("user_id", userId).order("created_at", { ascending: false }),
        admin.schema("app_commercial").from("paid_subscriptions").select(
          "id,provider,plan_key,status,starts_at,expires_at,auto_renewing,last_verified_at,provider_product_id,provider_base_plan_id,created_at",
        ).eq("user_id", userId).order("created_at", { ascending: false }),
        admin.schema("app_commercial").from("billing_events").select(
          "id,provider,event_type,subscription_id,user_id,received_at,processed_at,processing_result",
        ).eq("user_id", userId).order("received_at", { ascending: false })
          .limit(50),
        admin.schema("app_commercial").from("audit_log").select(
          "id,action,target_type,target_id,reason,created_at,before_state,after_state,correlation_id",
        ).or(`target_id.eq.${userId},actor_user_id.eq.${userId}`).order(
          "created_at",
          { ascending: false },
        ).limit(50),
        admin.schema("app_commercial").from("billing_testers").select(
          "enabled,reason,updated_at",
        ).eq("user_id", userId).maybeSingle(),
      ]);
      if (!profile.data) throw new Error("user_not_found");
      return {
        profile: profile.data,
        entitlement: Array.isArray(entitlement.data)
          ? entitlement.data[0]
          : entitlement.data,
        grants: grants.data ?? [],
        subscriptions: subscriptions.data ?? [],
        billingEvents: events.data ?? [],
        auditEvents: (auditEvents.data ?? []).map(redact),
        billingTester: billingTester.data,
      };
    }
    case "grant_pro": {
      const userId = uuid(body.userId, "invalid_user_id");
      const reason = requireReason(body.reason);
      const startsAt = new Date();
      const endsAt = body.permanent === true
        ? null
        : optionalDate(body.endsAt, "invalid_expiration");
      if (endsAt && endsAt <= startsAt.toISOString()) {
        throw new Error("invalid_expiration");
      }
      const result = await admin.schema("app_commercial").from(
        "entitlement_grants",
      ).insert({
        user_id: userId,
        plan_key: "pro",
        source: "admin_grant",
        starts_at: startsAt.toISOString(),
        ends_at: endsAt,
        granted_by: actorUserId,
        reason,
      }).select().single();
      const grant = value(result);
      await auditMutation(
        context,
        "grant_pro",
        "entitlement_grant",
        grant.id,
        null,
        grant,
        reason,
      );
      return { grant };
    }
    case "end_grant": {
      const grantId = uuid(body.grantId, "invalid_grant_id");
      const reason = requireReason(body.reason);
      const before = value(
        await admin.schema("app_commercial").from("entitlement_grants").select(
          "*",
        ).eq("id", grantId).single(),
      );
      if (before.status !== "active") {
        return { grant: before, idempotent: true };
      }
      const grant = value(
        await admin.schema("app_commercial").from("entitlement_grants").update({
          status: "ended",
          ends_at: new Date().toISOString(),
        }).eq("id", grantId).select().single(),
      );
      await auditMutation(
        context,
        "end_grant",
        "entitlement_grant",
        grantId,
        before,
        grant,
        reason,
      );
      return { grant };
    }
    case "set_billing_test_access": {
      const userId = uuid(body.userId, "invalid_user_id");
      const enabled = body.enabled === true;
      const reason = requireReason(body.reason);
      const before = value(
        await admin.schema("app_commercial").from("billing_testers").select("*")
          .eq("user_id", userId).maybeSingle(),
      );
      if (before?.enabled === enabled) {
        return { billingTester: before, idempotent: true };
      }
      const table = admin.schema("app_commercial").from("billing_testers");
      const result = before
        ? await table.update({ enabled, reason }).eq("user_id", userId).select()
          .single()
        : await table.insert({
          user_id: userId,
          enabled,
          created_by: actorUserId,
          reason,
        }).select().single();
      const after = value(result);
      await auditMutation(
        context,
        enabled ? "enable_billing_test_access" : "disable_billing_test_access",
        "billing_tester",
        userId,
        before,
        after,
        reason,
      );
      return { billingTester: after };
    }
    case "commercial_catalog": {
      const [
        plans,
        features,
        entitlements,
        prices,
        campaigns,
        monetization,
        provider,
      ] = await Promise.all([
        admin.schema("app_commercial").from("plans").select("*").order(
          "sort_order",
        ),
        admin.schema("app_commercial").from("features").select("*").order(
          "key",
        ),
        admin.schema("app_commercial").from("plan_feature_entitlements").select(
          "*",
        ).order("plan_key").order("feature_key"),
        admin.schema("app_commercial").from("plan_prices").select("*").order(
          "created_at",
          { ascending: false },
        ),
        admin.schema("app_commercial").from("promotional_campaigns").select("*")
          .order("created_at", { ascending: false }),
        admin.schema("app_commercial").from("monetization_state").select("*")
          .eq("singleton", true).single(),
        admin.schema("app_commercial").from("provider_configurations").select(
          "provider,package_name,status,last_synced_at,last_error,updated_at,metadata",
        ),
      ]);
      return {
        plans: plans.data ?? [],
        features: features.data ?? [],
        entitlements: entitlements.data ?? [],
        prices: prices.data ?? [],
        campaigns: campaigns.data ?? [],
        monetization: monetization.data,
        provider: (provider.data ?? []).map(redact),
      };
    }
    case "update_entitlement": {
      const planKey = enumValue(
        body.planKey,
        ["free", "pro"] as const,
        "invalid_plan_key",
      );
      const featureKey = key(body.featureKey, "invalid_feature_key");
      const reason = requireReason(body.reason);
      const before = value(
        await admin.schema("app_commercial").from("plan_feature_entitlements")
          .select("*").eq("plan_key", planKey).eq("feature_key", featureKey)
          .single(),
      );
      const feature = value(
        await admin.schema("app_commercial").from("features").select(
          "value_type",
        ).eq("key", featureKey).single(),
      );
      if (!feature) throw new Error("feature_not_found");
      const limitValue =
        feature.value_type === "limit" && body.limitValue != null
          ? integer(body.limitValue, 0, 1_000_000, "invalid_limit")
          : null;
      const after = value(
        await admin.schema("app_commercial").from("plan_feature_entitlements")
          .update({
            enabled: body.enabled === true,
            limit_value: limitValue,
            config: body.config && typeof body.config === "object"
              ? body.config
              : {},
          }).eq("plan_key", planKey).eq("feature_key", featureKey).select()
          .single(),
      );
      await auditMutation(
        context,
        "update_entitlement",
        "plan_feature_entitlement",
        `${planKey}:${featureKey}`,
        before,
        after,
        reason,
      );
      return { entitlement: after };
    }
    case "save_price": {
      const reason = requireReason(body.reason);
      const priceId = body.priceId
        ? uuid(body.priceId, "invalid_price_id")
        : null;
      const planKey = enumValue(
        body.planKey,
        ["pro"] as const,
        "invalid_plan_key",
      );
      const interval = enumValue(
        body.interval,
        ["month", "year"] as const,
        "invalid_interval",
      );
      const provider = enumValue(
        body.provider ?? "google_play",
        ["google_play"] as const,
        "invalid_provider",
      );
      const patch: Record<string, unknown> = {
        plan_key: planKey,
        interval,
        provider,
        currency_code: enumValue(
          body.currencyCode ?? "EGP",
          ["EGP"] as const,
          "invalid_currency",
        ),
        amount_minor: integer(
          body.amountMinor,
          1,
          1_000_000_000,
          "invalid_amount_minor",
        ),
        provider_product_id: boundedText(
          body.providerProductId,
          1,
          160,
          "invalid_provider_product_id",
        ),
        provider_base_plan_id: boundedText(
          body.providerBasePlanId,
          1,
          160,
          "invalid_provider_base_plan_id",
        ),
        provider_sync_status: "pending_sync",
        status: "draft",
      };
      const effectiveFrom = optionalDate(body.effectiveFrom);
      if (effectiveFrom) patch.effective_from = effectiveFrom;
      let before = null;
      let result;
      if (priceId) {
        before = value(
          await admin.schema("app_commercial").from("plan_prices").select("*")
            .eq("id", priceId).single(),
        );
        if (before.status !== "draft") throw new Error("price_not_draft");
        result = await admin.schema("app_commercial").from("plan_prices")
          .update(patch).eq("id", priceId).select().single();
      } else {
        result = await admin.schema("app_commercial").from("plan_prices")
          .insert(patch).select().single();
      }
      const after = value(result);
      await auditMutation(
        context,
        priceId ? "update_price_draft" : "create_price_draft",
        "plan_price",
        after.id,
        before,
        after,
        reason,
      );
      return { price: after };
    }
    case "publish_price": {
      const reason = requireReason(body.reason);
      const result = await admin.schema("app_commercial").rpc(
        "publish_plan_price",
        {
          p_actor_user_id: actorUserId,
          p_price_id: uuid(body.priceId, "invalid_price_id"),
          p_reason: reason,
        },
      );
      return { price: value(result) };
    }
    case "archive_price": {
      const priceId = uuid(body.priceId, "invalid_price_id");
      const reason = requireReason(body.reason);
      const before = value(
        await admin.schema("app_commercial").from("plan_prices").select("*").eq(
          "id",
          priceId,
        ).single(),
      );
      if (before.status === "archived") {
        return { price: before, idempotent: true };
      }
      const after = value(
        await admin.schema("app_commercial").from("plan_prices").update({
          status: "archived",
          effective_until: new Date().toISOString(),
        }).eq("id", priceId).select().single(),
      );
      await auditMutation(
        context,
        "archive_price",
        "plan_price",
        priceId,
        before,
        after,
        reason,
      );
      return { price: after };
    }
    case "update_campaign": {
      const campaignKey = key(body.campaignKey, "invalid_campaign_key");
      const reason = requireReason(body.reason);
      const before = value(
        await admin.schema("app_commercial").from("promotional_campaigns")
          .select("*").eq("key", campaignKey).single(),
      );
      const patch: Record<string, unknown> = {};
      if (typeof body.active === "boolean") patch.active = body.active;
      if (body.durationDays != null) {
        patch.duration_days = integer(
          body.durationDays,
          1,
          3650,
          "invalid_duration",
        );
      }
      if (!Object.keys(patch).length) {
        throw new Error("invalid_campaign_update");
      }
      const after = value(
        await admin.schema("app_commercial").from("promotional_campaigns")
          .update(patch).eq("key", campaignKey).select().single(),
      );
      await auditMutation(
        context,
        "update_campaign",
        "promotional_campaign",
        String(after.id),
        before,
        after,
        reason,
      );
      return { campaign: after };
    }
    case "update_monetization_duration": {
      const result = await admin.schema("app_commercial").rpc(
        "update_monetization_duration",
        {
          p_actor_user_id: actorUserId,
          p_duration_days: integer(
            body.durationDays,
            1,
            3650,
            "invalid_duration",
          ),
          p_reason: requireReason(body.reason),
        },
      );
      return { monetization: value(result) };
    }
    case "start_monetization_cycle": {
      const result = await admin.schema("app_commercial").rpc(
        "start_monetization_cycle",
        { p_actor_user_id: actorUserId, p_reason: requireReason(body.reason) },
      );
      return { monetization: value(result) };
    }
    case "transition_paid_live": {
      const result = await admin.schema("app_commercial").rpc(
        "transition_paid_live",
        { p_actor_user_id: actorUserId, p_reason: requireReason(body.reason) },
      );
      return { monetization: value(result) };
    }
    case "billing_events": {
      const { page, pageSize } = pageOf(body);
      let request = admin.schema("app_commercial").from("billing_events")
        .select(
          "id,provider,event_type,subscription_id,user_id,received_at,processed_at,processing_result",
          { count: "exact" },
        ).order("received_at", { ascending: false }).range(
          page * pageSize,
          page * pageSize + pageSize - 1,
        );
      if (body.provider) {
        request = request.eq(
          "provider",
          enumValue(
            body.provider,
            ["google_play", "apple_app_store", "manual"] as const,
          ),
        );
      }
      if (body.processingResult) {
        request = request.eq(
          "processing_result",
          boundedText(body.processingResult, 1, 120),
        );
      }
      if (body.userId) request = request.eq("user_id", uuid(body.userId));
      const result = await request;
      if (result.error) throw result.error;
      return {
        events: result.data ?? [],
        count: result.count ?? 0,
        page,
        pageSize,
      };
    }
    case "operations": {
      const [config, announcements, admins] = await Promise.all([
        admin.schema("app_commercial").from("app_config").select(
          "key,value,status,validation,updated_at",
        ).order("key"),
        admin.schema("app_commercial").from("announcements").select("*").order(
          "created_at",
          { ascending: false },
        ),
        admin.schema("app_commercial").from("platform_admins").select(
          "user_id,role,status,created_by,created_at,updated_at",
        ).order("created_at"),
      ]);
      return {
        config: config.data ?? [],
        announcements: announcements.data ?? [],
        admins: admins.data ?? [],
      };
    }
    case "update_config": {
      const configKey = key(body.configKey, "invalid_config_key");
      const reason = requireReason(body.reason);
      if (
        !body.value || typeof body.value !== "object" ||
        Array.isArray(body.value)
      ) throw new Error("invalid_config");
      const config = body.value as Record<string, unknown>;
      if (configKey === "maintenance" && typeof config.enabled !== "boolean") {
        throw new Error("invalid_maintenance_config");
      }
      if (configKey === "general") {
        if (
          config.support_email &&
          !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(config.support_email))
        ) throw new Error("invalid_support_email");
        for (const name of ["support_url", "privacy_url", "terms_url"]) {
          if (config[name] && !/^https:\/\//i.test(String(config[name]))) {
            throw new Error("invalid_config_url");
          }
        }
      }
      if (configKey === "monetization" && "mode" in config) {
        throw new Error("monetization_mode_managed_by_state_machine");
      }
      const before = value(
        await admin.schema("app_commercial").from("app_config").select("*").eq(
          "key",
          configKey,
        ).single(),
      );
      const after = value(
        await admin.schema("app_commercial").from("app_config").update({
          value: config,
        }).eq("key", configKey).select().single(),
      );
      await auditMutation(
        context,
        "update_config",
        "app_config",
        configKey,
        before,
        after,
        reason,
      );
      return { config: after };
    }
    case "save_announcement": {
      const announcementId = body.announcementId
        ? uuid(body.announcementId, "invalid_announcement_id")
        : null;
      const reason = requireReason(body.reason);
      const patch = validateAnnouncement(body.announcement);
      let before = null;
      let result;
      if (announcementId) {
        before = value(
          await admin.schema("app_commercial").from("announcements").select("*")
            .eq("id", announcementId).single(),
        );
        result = await admin.schema("app_commercial").from("announcements")
          .update(patch).eq("id", announcementId).select().single();
      } else {
        result = await admin.schema("app_commercial").from(
          "announcements",
        ).insert({ ...patch, created_by: actorUserId }).select().single();
      }
      const after = value(result);
      await auditMutation(
        context,
        announcementId ? "update_announcement" : "create_announcement",
        "announcement",
        after.id,
        before,
        after,
        reason,
      );
      return { announcement: after };
    }
    case "platform_admins": {
      const result = await admin.schema("app_commercial").from(
        "platform_admins",
      ).select("user_id,role,status,created_by,created_at,updated_at").order(
        "created_at",
      );
      return { admins: value(result) ?? [] };
    }
    case "update_platform_admin": {
      const result = await admin.schema("app_commercial").rpc(
        "upsert_platform_admin",
        {
          p_actor_user_id: actorUserId,
          p_user_id: uuid(body.userId, "invalid_user_id"),
          p_role: enumValue(
            body.role,
            ["super_admin"] as const,
            "undefined_admin_role",
          ),
          p_status: enumValue(
            body.status,
            ["active", "suspended", "revoked"] as const,
            "invalid_admin_status",
          ),
          p_reason: requireReason(body.reason),
        },
      );
      return { admin: value(result) };
    }
    case "audit_log": {
      const { page, pageSize } = pageOf(body, 50);
      let request = admin.schema("app_commercial").from("audit_log").select(
        "id,actor_user_id,action,target_type,target_id,reason,before_state,after_state,correlation_id,created_at",
        { count: "exact" },
      ).order("created_at", { ascending: false }).range(
        page * pageSize,
        page * pageSize + pageSize - 1,
      );
      if (body.actorId) {
        request = request.eq(
          "actor_user_id",
          uuid(body.actorId, "invalid_actor_id"),
        );
      }
      if (body.targetId) {
        request = request.eq("target_id", boundedText(body.targetId, 1, 200));
      }
      if (body.action) {
        request = request.eq("action", boundedText(body.action, 1, 160));
      }
      if (body.targetType) {
        request = request.eq(
          "target_type",
          boundedText(body.targetType, 1, 120),
        );
      }
      if (body.reason) {
        request = request.ilike(
          "reason",
          `%${boundedText(body.reason, 1, 200).replaceAll("%", "\\%")}%`,
        );
      }
      if (body.from) {
        request = request.gte("created_at", optionalDate(body.from));
      }
      if (body.to) {
        request = request.lt(
          "created_at",
          new Date(new Date(String(body.to)).getTime() + 86_400_000)
            .toISOString(),
        );
      }
      const result = await request;
      if (result.error) throw result.error;
      return {
        events: (result.data ?? []).map(redact),
        count: result.count ?? 0,
        page,
        pageSize,
      };
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
    return adminError(error, {
      action: String(body.action ?? "unknown"),
      correlationId: context.correlationId,
    });
  }
});
