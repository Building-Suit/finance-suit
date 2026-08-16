import 'package:flutter/foundation.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';

/// What a due-breakdown component is: a card statement item, an installment
/// due, or an ordinary BNPL purchase. Mirrors `component_type` in
/// `app_finance.facility_due_breakdown`.
enum FacilityComponentType {
  statementItem('statement_item'),
  installmentDue('installment_due'),
  bnplPurchase('bnpl_purchase'),

  /// A component type this build does not know. It is never misfiled as a
  /// real type and never selectable, so an older client facing a newer
  /// server shows the row honestly instead of allocating money to something
  /// it cannot describe.
  unknown('unknown');

  const FacilityComponentType(this.dbValue);
  final String dbValue;

  static FacilityComponentType fromDb(String value) => values.firstWhere(
    (v) => v.dbValue == value,
    orElse: () => FacilityComponentType.unknown,
  );
}

/// Server-derived paid state of one component.
enum ComponentPaymentStatus {
  unpaid('unpaid'),
  partiallyPaid('partially_paid'),
  paid('paid');

  const ComponentPaymentStatus(this.dbValue);
  final String dbValue;

  static ComponentPaymentStatus fromDb(String value) => values.firstWhere(
    (v) => v.dbValue == value,
    orElse: () => ComponentPaymentStatus.unpaid,
  );
}

/// Whether a component belongs to the current payable due or is only the
/// next upcoming installment group exposed when nothing is currently due.
enum FacilityComponentScope {
  current('current'),
  nextDue('next_due');

  const FacilityComponentScope(this.dbValue);
  final String dbValue;

  static FacilityComponentScope fromDb(String value) => values.firstWhere(
    (v) => v.dbValue == value,
    orElse: () => FacilityComponentScope.current,
  );
}

/// One currently payable component from `facility_due_breakdown`. All
/// amounts and paid states come from the server; the client never derives
/// them from raw allocation rows.
@immutable
class FacilityPaymentComponent {
  const FacilityPaymentComponent({
    required this.type,
    required this.id,
    required this.amountMinor,
    required this.paidMinor,
    required this.remainingMinor,
    required this.status,
    required this.scope,
    this.planId,
    this.cycleId,
    this.transactionId,
    this.title,
    this.activityKind,
    this.feeType,
    this.sequenceNumber,
    this.installmentCount,
    this.occurredOn,
    this.dueOn,
  });

  factory FacilityPaymentComponent.fromJson(Map<String, dynamic> json) {
    return FacilityPaymentComponent(
      type: FacilityComponentType.fromDb(json['component_type'] as String),
      id: json['component_id'] as String,
      planId: json['plan_id'] as String?,
      cycleId: json['cycle_id'] as String?,
      transactionId: json['transaction_id'] as String?,
      title: json['title'] as String?,
      activityKind: json['activity_kind'] as String?,
      feeType: json['fee_type'] as String?,
      sequenceNumber: (json['sequence_number'] as num?)?.toInt(),
      installmentCount: (json['installment_count'] as num?)?.toInt(),
      occurredOn: json['occurred_on'] == null
          ? null
          : PlainDate.parse(json['occurred_on'] as String),
      dueOn: json['due_on'] == null
          ? null
          : PlainDate.parse(json['due_on'] as String),
      amountMinor: (json['amount_minor'] as num).toInt(),
      paidMinor: (json['paid_minor'] as num).toInt(),
      remainingMinor: (json['remaining_minor'] as num).toInt(),
      status: ComponentPaymentStatus.fromDb(json['payment_status'] as String),
      scope: FacilityComponentScope.fromDb(
        json['scope'] as String? ?? 'current',
      ),
    );
  }

  final FacilityComponentType type;
  final String id;
  final String? planId;
  final String? cycleId;
  final String? transactionId;
  final String? title;
  final String? activityKind;
  final String? feeType;
  final int? sequenceNumber;
  final int? installmentCount;
  final PlainDate? occurredOn;

  /// When the component is contractually owed. Installment dues and BNPL
  /// obligations carry their own date; a statement item carries its cycle's
  /// payment due date. [occurredOn] stays the business date of the charge.
  final PlainDate? dueOn;
  final int amountMinor;
  final int paidMinor;
  final int remainingMinor;
  final ComponentPaymentStatus status;
  final FacilityComponentScope scope;

  /// Stable identity for selection maps.
  String get key => '${type.dbValue}:$id';

  bool get isFeeOrInterest =>
      type == FacilityComponentType.statementItem &&
      activityKind != 'ordinary_expense';

  /// The date the money is owed on, falling back to the business date for
  /// payloads from a server that predates `due_on`.
  PlainDate? get payableOn => dueOn ?? occurredOn;

  bool get isSelectable =>
      remainingMinor > 0 && type != FacilityComponentType.unknown;
}

/// The `facility_due_breakdown` DTO: authoritative totals plus every
/// current payable component with its exact paid state.
@immutable
class FacilityDueBreakdown {
  const FacilityDueBreakdown({
    required this.accountId,
    required this.accountType,
    required this.currencyCode,
    required this.asOf,
    required this.outstandingMinor,
    required this.totalDueMinor,
    required this.paidMinor,
    required this.remainingMinor,
    required this.additionalBalanceMinor,
    required this.components,
    this.minimumDueMinor,
    this.minimumRemainingMinor,
    this.monthStart,
    this.monthEnd,
  });

  factory FacilityDueBreakdown.fromJson(Map<String, dynamic> json) {
    return FacilityDueBreakdown(
      accountId: json['account_id'] as String,
      accountType: json['account_type'] as String,
      currencyCode: json['currency_code'] as String,
      asOf: PlainDate.parse(json['as_of'] as String),
      outstandingMinor: (json['outstanding_minor'] as num).toInt(),
      totalDueMinor: (json['total_due_minor'] as num).toInt(),
      paidMinor: (json['paid_minor'] as num).toInt(),
      remainingMinor: (json['remaining_minor'] as num).toInt(),
      additionalBalanceMinor:
          (json['additional_balance_minor'] as num?)?.toInt() ?? 0,
      minimumDueMinor: (json['minimum_due_minor'] as num?)?.toInt(),
      minimumRemainingMinor: (json['minimum_remaining_minor'] as num?)?.toInt(),
      monthStart: json['month_start'] == null
          ? null
          : PlainDate.parse(json['month_start'] as String),
      monthEnd: json['month_end'] == null
          ? null
          : PlainDate.parse(json['month_end'] as String),
      components: [
        for (final c in (json['components'] as List<dynamic>? ?? const []))
          FacilityPaymentComponent.fromJson(c as Map<String, dynamic>),
      ],
    );
  }

  final String accountId;
  final String accountType;
  final String currencyCode;
  final PlainDate asOf;
  final int outstandingMinor;
  final int totalDueMinor;
  final int paidMinor;
  final int remainingMinor;
  final int additionalBalanceMinor;

  /// Null when the facility has no minimum-payment concept (e.g. BNPL).
  final int? minimumDueMinor;
  final int? minimumRemainingMinor;

  /// Set only by the month-scoped breakdown: the calendar month this payload
  /// describes. Null for the payable-now breakdown, which spans periods.
  final PlainDate? monthStart;
  final PlainDate? monthEnd;
  final List<FacilityPaymentComponent> components;

  bool get isFullyPaid => remainingMinor == 0 && totalDueMinor > 0;
  bool get hasNoDues => totalDueMinor == 0;

  bool get supportsMinimumPayment =>
      minimumRemainingMinor != null && minimumRemainingMinor! > 0;
}

/// One typed allocation entry of the v2 payment payload.
@immutable
class FacilityAllocationEntry {
  const FacilityAllocationEntry({
    required this.type,
    required this.id,
    required this.amountMinor,
  });

  /// `installment_due`, `statement_item`, or `facility_balance`.
  final String type;
  final String id;
  final int amountMinor;

  Map<String, dynamic> toJson() => {
    'type': type,
    'id': id,
    'amount_minor': amountMinor,
  };
}

/// Payload for `app_finance.pay_credit_facility_v2`. The server rejects the
/// call unless the allocation amounts total exactly [amountMinor].
@immutable
class FacilityPaymentV2Draft {
  const FacilityPaymentV2Draft({
    required this.accountId,
    required this.sourceAccountId,
    required this.amountMinor,
    required this.paidOn,
    required this.allocations,
    this.notes,
    this.paymentId,
  });

  final String accountId;
  final String sourceAccountId;
  final int amountMinor;
  final PlainDate paidOn;
  final List<FacilityAllocationEntry> allocations;
  final String? notes;

  /// Client-generated id makes retries idempotent server-side.
  final String? paymentId;

  Map<String, dynamic> toJson() => {
    'p_account_id': accountId,
    'p_source_account_id': sourceAccountId,
    'p_amount_minor': amountMinor,
    'p_paid_on': paidOn.toIso(),
    'p_allocations': [for (final a in allocations) a.toJson()],
    'p_notes': notes,
    'p_payment_id': paymentId,
  };
}

/// Payload for `app_finance.pay_credit_facility_v3`: the same allocation
/// contract as v2 plus the explicit calendar month being paid, so next
/// month's dues can be prepaid while this month is still open.
@immutable
class FacilityPaymentV3Draft {
  const FacilityPaymentV3Draft({
    required this.accountId,
    required this.sourceAccountId,
    required this.amountMinor,
    required this.paidOn,
    required this.monthStart,
    required this.allocations,
    this.notes,
    this.paymentId,
  });

  final String accountId;
  final String sourceAccountId;
  final int amountMinor;
  final PlainDate paidOn;

  /// First day of the calendar month whose dues this payment settles.
  final PlainDate monthStart;
  final List<FacilityAllocationEntry> allocations;
  final String? notes;

  /// Client-generated id makes retries idempotent server-side.
  final String? paymentId;

  Map<String, dynamic> toJson() => {
    'p_account_id': accountId,
    'p_source_account_id': sourceAccountId,
    'p_amount_minor': amountMinor,
    'p_paid_on': paidOn.toIso(),
    'p_month_start': monthStart.toIso(),
    'p_allocations': [for (final a in allocations) a.toJson()],
    'p_notes': notes,
    'p_payment_id': paymentId,
  };
}

/// Which of the two payable calendar months a due card represents.
enum FacilityDuePeriod { currentMonth, nextMonth }

/// The calendar month a due card and its payment are scoped to.
///
/// Month arithmetic is calendar based — never "today + 30 days" — so
/// December rolls into January of the next year and February keeps its own
/// length. The start day is normalized to the first of the month so two
/// logically identical requests always produce the same provider key.
@immutable
class FacilityDueMonth {
  const FacilityDueMonth({required this.period, required this.start});

  factory FacilityDueMonth.forPeriod(
    FacilityDuePeriod period, {
    PlainDate? today,
  }) {
    final anchor = today ?? PlainDate.today();
    final monthStart = PlainDate(anchor.year, anchor.month, 1);
    return FacilityDueMonth(
      period: period,
      start: period == FacilityDuePeriod.currentMonth
          ? monthStart
          : monthStart.addMonths(1),
    );
  }

  /// Both payable months, current first — the only periods the product
  /// exposes for payment.
  static List<FacilityDueMonth> payable({PlainDate? today}) => [
    for (final period in FacilityDuePeriod.values)
      FacilityDueMonth.forPeriod(period, today: today),
  ];

  final FacilityDuePeriod period;
  final PlainDate start;

  PlainDate get end => start.addMonths(1).addDays(-1);
  String get key => start.toIso();
  bool get isCurrentMonth => period == FacilityDuePeriod.currentMonth;
}

/// A row of `app_finance.facility_payment_allocations`: what one recorded
/// payment was applied to, exactly as persisted.
@immutable
class FacilityPaymentAllocationDetail {
  const FacilityPaymentAllocationDetail({
    required this.paymentTransactionId,
    required this.componentType,
    required this.componentId,
    required this.amountMinor,
    required this.currencyCode,
    this.title,
    this.feeType,
    this.activityKind,
    this.sequenceNumber,
    this.detailOn,
  });

  factory FacilityPaymentAllocationDetail.fromJson(Map<String, dynamic> json) {
    return FacilityPaymentAllocationDetail(
      paymentTransactionId: json['payment_transaction_id'] as String,
      componentType: json['component_type'] as String,
      componentId: json['component_id'] as String,
      title: json['title'] as String?,
      feeType: json['fee_type'] as String?,
      activityKind: json['activity_kind'] as String?,
      sequenceNumber: (json['sequence_number'] as num?)?.toInt(),
      detailOn: json['detail_on'] == null
          ? null
          : PlainDate.parse(json['detail_on'] as String),
      amountMinor: (json['amount_minor'] as num).toInt(),
      currencyCode: json['currency_code'] as String,
    );
  }

  final String paymentTransactionId;
  final String componentType;
  final String componentId;
  final String? title;
  final String? feeType;
  final String? activityKind;
  final int? sequenceNumber;
  final PlainDate? detailOn;
  final int amountMinor;
  final String currencyCode;
}

/// A preset's explicit allocation intent: per-component amounts plus an
/// optional facility-balance remainder for non-current-due outstanding.
@immutable
class PresetAllocation {
  const PresetAllocation({
    required this.componentAmounts,
    this.facilityBalanceMinor = 0,
  });

  static const empty = PresetAllocation(componentAmounts: {});

  /// component key -> allocated minor amount (only positive entries).
  final Map<String, int> componentAmounts;
  final int facilityBalanceMinor;

  int get totalMinor =>
      componentAmounts.values.fold(0, (a, b) => a + b) + facilityBalanceMinor;
}

/// Sorts components in the deterministic Finance Suit payment priority:
/// current before next-due, installment dues (oldest first) before fees and
/// interest, then ordinary charges and BNPL purchases, by due date and then
/// business date within each group. This is
/// an internal ordering, not a bank's statutory allocation order.
List<FacilityPaymentComponent> paymentPriorityOrder(
  List<FacilityPaymentComponent> components,
) {
  int groupOf(FacilityPaymentComponent c) {
    if (c.type == FacilityComponentType.installmentDue) return 0;
    if (c.isFeeOrInterest) return 1;
    return 2;
  }

  final sorted = [...components];
  sorted.sort((a, b) {
    final scope = a.scope.index.compareTo(b.scope.index);
    if (scope != 0) return scope;
    final group = groupOf(a).compareTo(groupOf(b));
    if (group != 0) return group;
    final aDue = a.payableOn;
    final bDue = b.payableOn;
    if (aDue != null && bDue != null) {
      final due = aDue.compareTo(bDue);
      if (due != 0) return due;
    }
    final aOn = a.occurredOn;
    final bOn = b.occurredOn;
    if (aOn != null && bOn != null) {
      final on = aOn.compareTo(bOn);
      if (on != 0) return on;
    }
    return a.id.compareTo(b.id);
  });
  return sorted;
}

/// Pay-next-due preset: every unpaid component owed on the earliest payable
/// date — an ordinary BNPL purchase, several purchases sharing a due day, a
/// purchase plus an installment, or a card statement plus the installment
/// falling on the same date. It matches `next_due_amount_minor`, which is the
/// total owed on that date rather than whichever single row sorted first.
///
/// Currently payable components always win over merely upcoming ones, so the
/// preset can never jump past overdue debt to a future bill.
PresetAllocation nextDueAllocation(List<FacilityPaymentComponent> components) {
  final selectable = components.where((c) => c.isSelectable).toList();
  if (selectable.isEmpty) return PresetAllocation.empty;
  final scope = selectable.any((c) => c.scope == FacilityComponentScope.current)
      ? FacilityComponentScope.current
      : FacilityComponentScope.nextDue;
  final inScope = selectable.where((c) => c.scope == scope);

  PlainDate? earliest;
  for (final c in inScope) {
    final on = c.payableOn;
    if (on == null) continue;
    if (earliest == null || on.compareTo(earliest) < 0) earliest = on;
  }
  final amounts = <String, int>{};
  for (final c in inScope) {
    // A dated component only belongs to the preset when it shares the
    // earliest date; undated ones are grouped only when nothing is dated,
    // so money is never allocated to a bill that cannot be identified.
    if (c.payableOn != earliest) continue;
    amounts[c.key] = c.remainingMinor;
  }
  return PresetAllocation(componentAmounts: amounts);
}

/// Minimum payment preset: covers exactly the server-computed remaining
/// minimum using the deterministic priority order. Never reaches into
/// next-due components.
PresetAllocation minimumPaymentAllocation(
  int minimumRemainingMinor,
  List<FacilityPaymentComponent> components,
) {
  var left = minimumRemainingMinor;
  final amounts = <String, int>{};
  for (final c in paymentPriorityOrder(components)) {
    if (left <= 0) break;
    if (!c.isSelectable || c.scope != FacilityComponentScope.current) continue;
    final take = left < c.remainingMinor ? left : c.remainingMinor;
    amounts[c.key] = take;
    left -= take;
  }
  return PresetAllocation(componentAmounts: amounts);
}

/// Full outstanding preset: every payable component in full plus an explicit
/// facility-balance remainder for outstanding money that is not part of the
/// current due (unbilled charges, future principal). Future installments are
/// never faked as due components.
PresetAllocation fullOutstandingAllocation(FacilityDueBreakdown breakdown) {
  final amounts = <String, int>{};
  for (final c in breakdown.components) {
    if (!c.isSelectable) continue;
    amounts[c.key] = c.remainingMinor;
  }
  return PresetAllocation(
    componentAmounts: amounts,
    facilityBalanceMinor: breakdown.additionalBalanceMinor,
  );
}
