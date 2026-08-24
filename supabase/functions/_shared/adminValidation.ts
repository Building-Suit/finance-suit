export function requireReason(value: unknown): string {
  const reason = String(value ?? "").trim();
  if (reason.length < 6 || reason.length > 1000) {
    throw new Error("reason_required");
  }
  return reason;
}
export function uuid(value: unknown, code = "invalid_uuid"): string {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value)
  ) throw new Error(code);
  return value;
}
export function integer(
  value: unknown,
  minimum: number,
  maximum: number,
  code = "invalid_integer",
): number {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < minimum || parsed > maximum) {
    throw new Error(code);
  }
  return parsed;
}
export function enumValue<T extends string>(
  value: unknown,
  allowed: readonly T[],
  code = "invalid_enum",
): T {
  if (typeof value !== "string" || !allowed.includes(value as T)) {
    throw new Error(code);
  }
  return value as T;
}
export function boundedText(
  value: unknown,
  minimum: number,
  maximum: number,
  code = "invalid_text",
): string {
  const text = String(value ?? "").trim();
  if (text.length < minimum || text.length > maximum) throw new Error(code);
  return text;
}
export function optionalDate(
  value: unknown,
  code = "invalid_date",
): string | null {
  if (value == null || value === "") return null;
  const date = new Date(String(value));
  if (!Number.isFinite(date.getTime())) throw new Error(code);
  return date.toISOString();
}
export function pageOf(body: Record<string, unknown>, defaultSize = 25) {
  return {
    page: integer(body.page ?? 0, 0, 100000, "invalid_page"),
    pageSize: integer(
      body.pageSize ?? defaultSize,
      1,
      100,
      "invalid_page_size",
    ),
  };
}
export function redact(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(redact);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>).map((
        [key, item],
      ) => [
        key,
        /token|secret|credential|password|service.?account|authorization|provider_payload|payload$/i
            .test(key)
          ? "[REDACTED]"
          : redact(item),
      ]),
    );
  }
  return value;
}
export function validateAnnouncement(value: unknown) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("invalid_announcement");
  }
  const body = value as Record<string, unknown>;
  const startsAt = optionalDate(body.starts_at);
  const endsAt = optionalDate(body.ends_at);
  if (startsAt && endsAt && endsAt <= startsAt) {
    throw new Error("invalid_announcement_dates");
  }
  return {
    title: boundedText(body.title, 1, 140, "invalid_title"),
    body: boundedText(body.body, 1, 2000, "invalid_body"),
    active: body.active === true,
    severity: enumValue(
      body.severity ?? "info",
      ["info", "success", "warning", "critical"] as const,
      "invalid_severity",
    ),
    audience: enumValue(
      body.audience ?? "all",
      ["all", "free", "pro", "early_access"] as const,
      "invalid_audience",
    ),
    starts_at: startsAt,
    ends_at: endsAt,
    dismissible: body.dismissible !== false,
  };
}
