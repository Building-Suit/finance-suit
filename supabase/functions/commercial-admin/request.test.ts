import {
  assertUuid,
  billingTestAccessReason,
  requireReason,
} from "./request.ts";

Deno.test("billing test access supplies an auditable default reason", () => {
  if (
    billingTestAccessReason({}, true) !==
      "Enabled for Google Play Billing testing"
  ) {
    throw new Error("missing enable reason");
  }
  if (
    billingTestAccessReason({}, false) !==
      "Disabled Google Play Billing testing"
  ) {
    throw new Error("missing disable reason");
  }
});

Deno.test("billing test access preserves a valid supplied reason", () => {
  const reason = "  QA checkout verification  ";
  if (
    billingTestAccessReason({ reason }, true) !== "QA checkout verification"
  ) {
    throw new Error("reason was not normalized");
  }
});

Deno.test("admin request validation rejects malformed values", () => {
  let rejectedReason = false;
  try {
    requireReason({ reason: "short" });
  } catch (error) {
    rejectedReason = error instanceof Error &&
      error.message === "reason_required";
  }
  if (!rejectedReason) throw new Error("short reason was accepted");

  let rejectedUuid = false;
  try {
    assertUuid("not-a-uuid", "invalid_user_id");
  } catch (error) {
    rejectedUuid = error instanceof Error &&
      error.message === "invalid_user_id";
  }
  if (!rejectedUuid) throw new Error("invalid UUID was accepted");
});
