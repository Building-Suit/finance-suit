import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  addDays,
  backoff,
  type ClaimedRow,
  compose,
  dayDiff,
  eventKeyFor,
  fcmData,
  localParts,
} from "./compose.ts";

function claim(overrides: Partial<ClaimedRow> = {}): ClaimedRow {
  return {
    id: "outbox-1",
    user_id: "user-1",
    device_id: "device-1",
    notification_id: "notification-1",
    event_key: "credit_card.statement_due_today",
    route: "/money/facilities/account-1",
    fcm_token: "a-very-secret-device-token-value",
    platform: "android",
    locale: "en",
    timezone: "Africa/Cairo",
    obligation_type: null,
    obligation_id: null,
    reminder_kind: null,
    scheduled_local_date: null,
    payload_snapshot: {},
    attempt_count: 1,
    ...overrides,
  };
}

Deno.test("legacy payload types map onto canonical event keys", () => {
  assertEquals(
    eventKeyFor("credit_card_statement_due", "overdue"),
    "credit_card.statement_overdue",
  );
  assertEquals(
    eventKeyFor("credit_card_statement_due", "due_today"),
    "credit_card.statement_due_today",
  );
  assertEquals(
    eventKeyFor("credit_card_statement_due", "due_soon"),
    "credit_card.statement_due_soon",
  );
  assertEquals(eventKeyFor("bnpl_due", "overdue"), "bnpl.overdue");
  assertEquals(
    eventKeyFor("network_transfer_pending", null),
    "network.transfer_received",
  );
  assertEquals(eventKeyFor("something_new", "due_today"), null);
});

Deno.test("lock-screen text never contains an amount by default", () => {
  const withoutAmount = compose("credit_card.statement_due_today", {
    account_name: "CIB Gold",
    due_on: "2026-08-17",
    // Present in the logical payload for the in-app center, absent from the
    // pre-rendered text because the user did not opt into amounts.
    amount_minor: 4753282,
    currency_code: "EGP",
    amount_text: null,
  }, "en");
  assert(!withoutAmount.body.includes("47"));
  assert(!withoutAmount.body.includes("4753282"));
  assert(withoutAmount.title.includes("due today"));
  assert(withoutAmount.body.includes("CIB Gold"));
});

Deno.test("amounts appear only when the user opted in", () => {
  const withAmount = compose("credit_card.statement_due_today", {
    account_name: "CIB Gold",
    due_on: "2026-08-17",
    amount_text: "EGP 47,532.82",
  }, "en");
  assert(withAmount.body.includes("EGP 47,532.82"));
});

Deno.test("Arabic composition is used for an Arabic locale", () => {
  const ar = compose("credit_card.statement_overdue", {
    account_name: "بطاقة",
    due_on: "2026-08-17",
  }, "ar-EG");
  assert(ar.title.includes("متأخرة"));
  assert(ar.body.includes("بطاقة"));

  const en = compose("credit_card.statement_overdue", {
    account_name: "Card",
  }, "en");
  assert(en.title.includes("overdue"));
});

Deno.test("rows written before the catalog still compose from payload.type", () => {
  const legacy = compose(null, {
    type: "network_transfer_pending",
    counterparty_name: "Sara",
    amount_text: null,
  }, "en");
  assertEquals(legacy.title, "New transfer request");
  assert(legacy.body.includes("Sara"));
});

Deno.test("every catalogued event composes non-empty title and body", () => {
  const keys = [
    "credit_card.statement_due_soon",
    "credit_card.statement_due_today",
    "credit_card.statement_overdue",
    "installment.due_soon",
    "installment.due_today",
    "installment.overdue",
    "bnpl.due_soon",
    "bnpl.due_today",
    "bnpl.overdue",
    "facility.payment_recorded",
    "network.add_request_received",
    "network.add_request_accepted",
    "network.transfer_received",
    "network.transfer_accepted",
    "network.transfer_declined",
    "network.transfer_cancelled",
    "network.transfer_amended",
    "held_amount.recorded_against_you",
    "held_amount.updated",
    "held_amount.settled",
    "held_amount.removed",
    "installment_link.request_received",
    "installment_link.accepted",
    "installment_link.declined",
    "system.developer_test",
  ];
  for (const locale of ["en", "ar"]) {
    for (const key of keys) {
      const { title, body } = compose(key, {}, locale);
      assert(title.length > 0, `${key}/${locale} has no title`);
      assert(body.length > 0, `${key}/${locale} has no body`);
      assert(!title.includes(key), `${key}/${locale} leaks the machine key`);
      assert(!body.includes(key), `${key}/${locale} leaks the machine key`);
    }
  }
});

Deno.test("the FCM data block carries routing keys and no money", () => {
  const data = fcmData(claim(), {
    type: "credit_card_statement_due",
    obligation_id: "statement-1",
    account_id: "account-1",
    amount_minor: 4753282,
    amount_text: "EGP 47,532.82",
  });
  assertEquals(data.event_key, "credit_card.statement_due_today");
  assertEquals(data.route, "/money/facilities/account-1");
  assertEquals(data.notification_id, "notification-1");
  assertEquals(data.entity_id, "statement-1");
  const serialized = JSON.stringify(data);
  assert(!serialized.includes("47,532.82"));
  assert(!serialized.includes("4753282"));
  // The device token is addressing, never payload.
  assert(!serialized.includes("a-very-secret-device-token-value"));
});

Deno.test("retry backoff is bounded and increasing", () => {
  const delays = [1, 2, 3, 4, 5, 9].map((attempt) =>
    Date.parse(backoff(attempt)) - Date.now()
  );
  for (let i = 1; i < 4; i++) {
    assert(delays[i] > delays[i - 1], "backoff should grow while bounded");
  }
  // Past the table it plateaus rather than growing without limit.
  assert(delays[5] <= 61 * 60_000);
  assert(delays[0] > 0);
});

Deno.test("day arithmetic crosses month and February boundaries", () => {
  assertEquals(addDays("2026-01-31", 1), "2026-02-01");
  assertEquals(addDays("2026-02-28", 1), "2026-03-01");
  // 2028 is a leap year.
  assertEquals(addDays("2028-02-28", 1), "2028-02-29");
  assertEquals(dayDiff("2026-02-26", "2026-03-01"), 3);
  assertEquals(dayDiff("2026-03-01", "2026-02-28"), -1);
  assertEquals(dayDiff("2026-08-17", "2026-08-17"), 0);
});

Deno.test("local date follows the given timezone, not the server", () => {
  // Kiritimati is UTC+14 and Baker Island style offsets are UTC-11, so the
  // same instant is a different calendar day in each.
  const ahead = localParts("Pacific/Kiritimati");
  const behind = localParts("Pacific/Midway");
  assert(ahead.date >= behind.date);
  assert(ahead.hour >= 0 && ahead.hour <= 23);
  assertEquals(localParts("UTC").date.length, 10);
});
