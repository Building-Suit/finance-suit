import 'package:flutter/foundation.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';

/// What a due-breakdown component is: a card statement item or an
/// installment due. Mirrors `component_type` in
/// `app_finance.facility_due_breakdown`.
enum FacilityComponentType {
  statementItem('statement_item'),
  installmentDue('installment_due');

  const FacilityComponentType(this.dbValue);
  final String dbValue;

  static FacilityComponentType fromDb(String value) => values.firstWhere(
    (v) => v.dbValue == value,
    orElse: () => FacilityComponentType.statementItem,
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

  bool get isSelectable => remainingMinor > 0;
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
  final List<FacilityPaymentComponent> components;

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
/// interest, then ordinary charges, chronological within each group. This is
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

/// Next installment preset: the earliest unpaid installment due, matching
/// the audited `next_due_amount_minor` semantics (one due, never a batch of
/// future installments).
PresetAllocation nextInstallmentAllocation(
  List<FacilityPaymentComponent> components,
) {
  FacilityPaymentComponent? next;
  for (final c in components) {
    if (c.type != FacilityComponentType.installmentDue || !c.isSelectable) {
      continue;
    }
    if (next == null ||
        _dueOrder(c, next) < 0 ||
        (_dueOrder(c, next) == 0 &&
            (c.sequenceNumber ?? 0) < (next.sequenceNumber ?? 0))) {
      next = c;
    }
  }
  if (next == null) return PresetAllocation.empty;
  return PresetAllocation(componentAmounts: {next.key: next.remainingMinor});
}

int _dueOrder(FacilityPaymentComponent a, FacilityPaymentComponent b) {
  final aOn = a.occurredOn;
  final bOn = b.occurredOn;
  if (aOn == null || bOn == null) return 0;
  return aOn.compareTo(bOn);
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
