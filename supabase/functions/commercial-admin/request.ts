export type AdminBody = {
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

export function requireReason(body: AdminBody): string {
  const reason = String(body.reason ?? "").trim();
  if (reason.length < 6 || reason.length > 1000) {
    throw new Error("reason_required");
  }
  return reason;
}

export function billingTestAccessReason(
  body: AdminBody,
  enabled: boolean,
): string {
  const reason = String(body.reason ?? "").trim();
  if (reason.length === 0) {
    return enabled
      ? "Enabled for Google Play Billing testing"
      : "Disabled Google Play Billing testing";
  }
  return requireReason(body);
}

export function assertUuid(value: unknown, code: string): string {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value)
  ) {
    throw new Error(code);
  }
  return value;
}
