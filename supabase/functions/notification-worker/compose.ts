// Pure composition and scheduling helpers for the notification worker.
//
// Kept out of `index.ts` so the delivery-critical logic — event-key mapping,
// lock-screen text, retry backoff and the FCM data block — can be unit tested
// without a Supabase client or a network.

export interface ClaimedRow {
  id: string;
  user_id: string;
  device_id: string;
  notification_id: string | null;
  event_key: string | null;
  route: string | null;
  fcm_token: string;
  platform: string;
  locale: string | null;
  timezone: string | null;
  obligation_type: string | null;
  obligation_id: string | null;
  reminder_kind: string | null;
  scheduled_local_date: string | null;
  payload_snapshot: Record<string, unknown> | null;
  attempt_count: number;
}

/// Today's date and hour in the *user's* configured timezone. Reminders are
/// never scheduled from device-local or server-local time.
export function localParts(timezone: string): { date: string; hour: number } {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    hour12: false,
  }).formatToParts(new Date());
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? "";
  return {
    date: `${get("year")}-${get("month")}-${get("day")}`,
    hour: Number(get("hour")),
  };
}

export function addDays(iso: string, days: number): string {
  const base = Date.parse(`${iso}T00:00:00Z`);
  return new Date(base + days * 86_400_000).toISOString().slice(0, 10);
}

export function dayDiff(fromIso: string, toIso: string): number {
  const from = Date.parse(`${fromIso}T00:00:00Z`);
  const to = Date.parse(`${toIso}T00:00:00Z`);
  return Math.round((to - from) / 86_400_000);
}

export function isArabic(locale: string | null | undefined): boolean {
  return (locale ?? "").toLowerCase().startsWith("ar");
}

export function formatAmount(
  minor: number,
  currency: string,
  locale: string | null,
): string {
  return new Intl.NumberFormat(isArabic(locale) ? "ar-EG" : "en-EG", {
    style: "currency",
    currency,
    maximumFractionDigits: 2,
  }).format(minor / 100);
}

export function formatDate(iso: string, locale: string | null): string {
  const date = new Date(`${iso}T12:00:00Z`);
  return new Intl.DateTimeFormat(isArabic(locale) ? "ar-EG" : "en-GB", {
    day: "numeric",
    month: "short",
  }).format(date);
}
/// database owns the same mapping; this mirror keeps composition working for
/// outbox rows written before the catalog existed.
export function eventKeyFor(
  legacyType: string | null | undefined,
  reminderKind: string | null | undefined,
): string | null {
  const kind = reminderKind ?? "";
  switch (legacyType) {
    case "credit_card_statement_due":
      return kind === "overdue"
        ? "credit_card.statement_overdue"
        : kind === "due_today"
        ? "credit_card.statement_due_today"
        : "credit_card.statement_due_soon";
    case "installment_due":
      return kind === "overdue"
        ? "installment.overdue"
        : kind === "due_today"
        ? "installment.due_today"
        : "installment.due_soon";
    case "bnpl_due":
      return kind === "overdue"
        ? "bnpl.overdue"
        : kind === "due_today"
        ? "bnpl.due_today"
        : "bnpl.due_soon";
    case "facility_payment_confirmation":
      return "facility.payment_recorded";
    case "network_add_request":
      return "network.add_request_received";
    case "network_add_request_accepted":
      return "network.add_request_accepted";
    case "network_transfer_pending":
      return "network.transfer_received";
    case "network_transfer_accepted":
      return "network.transfer_accepted";
    case "network_transfer_rejected":
      return "network.transfer_declined";
    case "network_transfer_cancelled":
      return "network.transfer_cancelled";
    case "network_transfer_amended":
      return "network.transfer_amended";
    case "installment_link_request":
      return "installment_link.request_received";
    case "installment_link_accepted":
      return "installment_link.accepted";
    case "installment_link_rejected":
      return "installment_link.declined";
    case "developer_test":
      return "system.developer_test";
    default:
      return null;
  }
}

/// Lock-screen text. `amount_text` is present only when the recipient opted
/// into amounts in notifications, so balances never leak by default.
export function compose(
  eventKey: string | null,
  payload: Record<string, unknown>,
  locale: string | null,
): { title: string; body: string } {
  const ar = isArabic(locale);
  const key = eventKey ??
    eventKeyFor(payload.type as string, payload.reminder_kind as string);
  const accountName = String(
    payload.account_name ?? (ar ? "الحساب" : "Account"),
  );
  const counterparty = String(
    payload.counterparty_name ?? (ar ? "شخص ما" : "Someone"),
  );
  const planTitle = payload.plan_title ? String(payload.plan_title) : null;
  const dueOn = String(payload.due_on ?? "");
  const amount = payload.amount_text ? String(payload.amount_text) : null;

  switch (key) {
    case "system.developer_test":
      return ar
        ? {
          title: "اختبار إشعارات Finance Suit",
          body: "إذا ظهر هذا التنبيه، فإشعارات هذا الهاتف تعمل.",
        }
        : {
          title: "Finance Suit notification test",
          body: "If you see this, alerts are working on this phone.",
        };
    case "network.add_request_received":
      return ar
        ? {
          title: "طلب إضافة جديد",
          body: `${counterparty} يريد إضافتك إلى شبكته في Finance Suit.`,
        }
        : {
          title: "New add request",
          body:
            `${counterparty} wants to add you to their Finance Suit network.`,
        };
    case "network.add_request_accepted":
      return ar
        ? { title: "تم قبول الطلب", body: `${counterparty} الآن في شبكتك.` }
        : {
          title: "Request accepted",
          body: `${counterparty} is now in your network.`,
        };
    case "network.transfer_received":
      return ar
        ? {
          title: "طلب تحويل جديد",
          body: amount
            ? `${counterparty} أرسل لك ${amount}.`
            : `${counterparty} أرسل لك طلب تحويل.`,
        }
        : {
          title: "New transfer request",
          body: amount
            ? `${counterparty} sent you ${amount}.`
            : `${counterparty} sent you a transfer request.`,
        };
    case "network.transfer_accepted":
      return ar
        ? {
          title: "تم قبول التحويل",
          body: amount
            ? `${counterparty} قبل تحويلك بمبلغ ${amount}.`
            : `${counterparty} قبل تحويلك.`,
        }
        : {
          title: "Transfer accepted",
          body: amount
            ? `${counterparty} accepted your ${amount} transfer.`
            : `${counterparty} accepted your transfer.`,
        };
    case "network.transfer_declined":
      return ar
        ? { title: "تم رفض التحويل", body: `${counterparty} رفض تحويلك.` }
        : {
          title: "Transfer declined",
          body: `${counterparty} declined your transfer.`,
        };
    case "network.transfer_cancelled":
      return ar
        ? {
          title: "تم سحب التحويل",
          body: `${counterparty} سحب طلب التحويل.`,
        }
        : {
          title: "Transfer withdrawn",
          body: `${counterparty} withdrew their transfer request.`,
        };
    case "network.transfer_amended":
      return ar
        ? {
          title: "تم تعديل التحويل",
          body: amount
            ? `${counterparty} غيّر طلب التحويل إلى ${amount}.`
            : `${counterparty} غيّر طلب التحويل.`,
        }
        : {
          title: "Transfer changed",
          body: amount
            ? `${counterparty} changed their transfer request to ${amount}.`
            : `${counterparty} changed their transfer request.`,
        };
    case "held_amount.recorded_against_you":
      return ar
        ? {
          title: "مبلغ محجوز",
          body: amount
            ? `${counterparty} سجّل مبلغ ${amount} بينكما.`
            : `${counterparty} سجّل مبلغًا بينكما.`,
        }
        : {
          title: "Amount on hold",
          body: amount
            ? `${counterparty} recorded ${amount} held between you.`
            : `${counterparty} recorded an amount held between you.`,
        };
    case "held_amount.updated":
      return ar
        ? {
          title: "تم تعديل المبلغ المحجوز",
          body: amount
            ? `${counterparty} عدّل المبلغ المحجوز إلى ${amount}.`
            : `${counterparty} عدّل المبلغ المحجوز بينكما.`,
        }
        : {
          title: "Held amount changed",
          body: amount
            ? `${counterparty} changed the held amount to ${amount}.`
            : `${counterparty} changed the amount held between you.`,
        };
    case "held_amount.settled":
      return ar
        ? {
          title: "تمت تسوية المبلغ",
          body: amount
            ? `${counterparty} سوّى مبلغ ${amount}.`
            : `${counterparty} سوّى المبلغ المحجوز بينكما.`,
        }
        : {
          title: "Held amount settled",
          body: amount
            ? `${counterparty} settled ${amount}.`
            : `${counterparty} settled the amount held between you.`,
        };
    case "held_amount.removed":
      return ar
        ? {
          title: "تم حذف المبلغ المحجوز",
          body: `${counterparty} حذف المبلغ المحجوز بينكما.`,
        }
        : {
          title: "Held amount removed",
          body: `${counterparty} removed the amount held between you.`,
        };
    case "installment_link.request_received":
      return ar
        ? {
          title: "طلب ربط قسط",
          body: `${counterparty} يريد ربط قسط بك. راجع التفاصيل قبل القبول.`,
        }
        : {
          title: "Installment link request",
          body:
            `${counterparty} wants to link an installment to you. Review the details before accepting.`,
        };
    case "installment_link.accepted":
      return ar
        ? {
          title: "تم قبول ربط القسط",
          body: planTitle
            ? `${counterparty} قبل ربط قسط ${planTitle}.`
            : `${counterparty} قبل ربط القسط.`,
        }
        : {
          title: "Installment link accepted",
          body: planTitle
            ? `${counterparty} accepted the ${planTitle} installment link.`
            : `${counterparty} accepted the installment link.`,
        };
    case "installment_link.declined":
      return ar
        ? {
          title: "تم رفض ربط القسط",
          body: planTitle
            ? `${counterparty} رفض ربط قسط ${planTitle}.`
            : `${counterparty} رفض ربط القسط.`,
        }
        : {
          title: "Installment link declined",
          body: planTitle
            ? `${counterparty} declined the ${planTitle} installment link.`
            : `${counterparty} declined the installment link.`,
        };
    case "facility.payment_recorded":
      return ar
        ? {
          title: "تم تسجيل دفعة",
          body: amount
            ? `تم تسجيل دفعة ${amount} على ${accountName}.`
            : `تم تسجيل دفعة على ${accountName}.`,
        }
        : {
          title: "Payment recorded",
          body: amount
            ? `${amount} was recorded for ${accountName}.`
            : `A payment was recorded for ${accountName}.`,
        };
  }

  const label = key?.startsWith("bnpl.")
    ? (ar ? "دفعة اشتر الآن وادفع لاحقا" : "BNPL payment")
    : key?.startsWith("installment.")
    ? (ar ? "قسط" : "Installment")
    : (ar ? "دفعة بطاقة ائتمان" : "Credit Card payment");
  // `credit_card.statement_overdue` does not end in ".overdue", so match the
  // suffix rather than a dotted segment.
  const overdue = key?.endsWith("overdue") ??
    payload.reminder_kind === "overdue";
  const dueToday = key?.endsWith("due_today") ??
    payload.reminder_kind === "due_today";
  const dateText = dueOn ? formatDate(dueOn, locale) : "";

  if (ar) {
    const title = overdue
      ? `${label} متأخرة`
      : dueToday
      ? `${label} مستحقة اليوم`
      : `${label} مستحقة قريبا`;
    const body = amount
      ? `${amount} مستحقة على ${accountName}${
        dateText ? ` يوم ${dateText}` : ""
      }.`
      : `${accountName}${
        dateText ? ` مستحق يوم ${dateText}` : " عليه دفعة مستحقة"
      }.`;
    return { title, body };
  }
  const title = overdue
    ? `${label} overdue`
    : dueToday
    ? `${label} due today`
    : `${label} due soon`;
  const body = amount
    ? `${amount} is due for ${accountName}${dateText ? ` on ${dateText}` : ""}.`
    : `${accountName}${
      dateText ? ` is due on ${dateText}` : " has a payment due"
    }.`;
  return { title, body };
}

export function backoff(attempt: number): string {
  const minutes = [1, 5, 15, 60][Math.min(Math.max(attempt - 1, 0), 3)];
  return new Date(Date.now() + minutes * 60_000).toISOString();
}

/// Structured routing keys only. Nothing here may carry a balance: the data
/// block is readable by the OS and by any notification listener.
export function fcmData(
  row: ClaimedRow,
  payload: Record<string, unknown>,
): Record<string, string> {
  return {
    type: String(payload.type ?? ""),
    event_key: String(row.event_key ?? payload.event_key ?? ""),
    notification_id: String(row.notification_id ?? ""),
    route: String(row.route ?? payload.route ?? ""),
    entity_id: String(payload.obligation_id ?? row.obligation_id ?? ""),
    account_id: String(payload.account_id ?? ""),
  };
}
