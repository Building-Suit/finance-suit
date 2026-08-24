import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  integer,
  redact,
  requireReason,
  uuid,
  validateAnnouncement,
} from "./adminValidation.ts";

Deno.test("admin validation rejects short reasons and malformed UUIDs", () => {
  assertThrows(() => requireReason("short"), Error, "reason_required");
  assertThrows(() => uuid("not-a-uuid"), Error, "invalid_uuid");
});
Deno.test("money and bounded integer inputs reject unsafe values", () => {
  assertEquals(integer(6000, 1, 10_000_000), 6000);
  assertThrows(() => integer(60.5, 1, 10_000_000), Error, "invalid_integer");
});
Deno.test("announcement dates and enums are validated", () => {
  assertThrows(
    () =>
      validateAnnouncement({
        title: "x",
        body: "y",
        severity: "party",
        audience: "all",
      }),
    Error,
    "invalid_severity",
  );
  assertThrows(
    () =>
      validateAnnouncement({
        title: "x",
        body: "y",
        severity: "info",
        audience: "all",
        starts_at: "2026-08-25",
        ends_at: "2026-08-24",
      }),
    Error,
    "invalid_announcement_dates",
  );
});
Deno.test("diagnostic objects redact secret-bearing fields recursively", () => {
  assertEquals(
    redact({
      purchaseToken: "raw",
      nested: { provider_payload: { secret: "x" } },
      safe: 1,
    }),
    {
      purchaseToken: "[REDACTED]",
      nested: { provider_payload: "[REDACTED]" },
      safe: 1,
    },
  );
});
