import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';

/// Owner-side responsibility state for one installment plan, from the
/// `installment_plan_responsibility_summaries` view: who is linked, whether
/// they accepted, and how much has been reimbursed so far.
class InstallmentResponsibilitySummary {
  const InstallmentResponsibilitySummary({
    required this.planId,
    required this.linkId,
    required this.linkType,
    required this.status,
    required this.displayName,
    required this.fromSequence,
    required this.expectedTotalMinor,
    required this.receivedTotalMinor,
    required this.pendingTotalMinor,
    required this.expectedRemainingMinor,
  });

  factory InstallmentResponsibilitySummary.fromJson(
    Map<String, dynamic> json,
  ) => InstallmentResponsibilitySummary(
    planId: json['plan_id'] as String,
    linkId: json['link_id'] as String,
    linkType: ResponsibilityLinkType.fromDb(json['link_type'] as String),
    status: ResponsibilityLinkStatus.fromDb(json['status'] as String),
    displayName: json['display_name'] as String? ?? '',
    fromSequence: (json['responsibility_from_sequence'] as num).toInt(),
    expectedTotalMinor: (json['expected_total_minor'] as num?)?.toInt() ?? 0,
    receivedTotalMinor: (json['received_total_minor'] as num?)?.toInt() ?? 0,
    pendingTotalMinor: (json['pending_total_minor'] as num?)?.toInt() ?? 0,
    expectedRemainingMinor:
        (json['expected_remaining_minor'] as num?)?.toInt() ?? 0,
  );

  final String planId;
  final String linkId;
  final ResponsibilityLinkType linkType;
  final ResponsibilityLinkStatus status;
  final String displayName;
  final int fromSequence;
  final int expectedTotalMinor;
  final int receivedTotalMinor;
  final int pendingTotalMinor;
  final int expectedRemainingMinor;

  bool get isAccepted => status == ResponsibilityLinkStatus.accepted;
  bool get isPending => status == ResponsibilityLinkStatus.pending;
  bool get isRejected => status == ResponsibilityLinkStatus.rejected;
}

/// One row of `list_my_linked_installments`: an installment someone linked
/// to the current user, either waiting for their consent or accepted.
class LinkedInstallment {
  const LinkedInstallment({
    required this.linkId,
    required this.status,
    required this.ownerName,
    required this.planTitle,
    required this.currencyCode,
    required this.remainingCount,
    required this.remainingTotalMinor,
    required this.requestedAt,
    required this.termsChanged,
    this.nextDueOn,
    this.nextDueAmountMinor,
    this.acceptedAt,
  });

  factory LinkedInstallment.fromJson(Map<String, dynamic> json) =>
      LinkedInstallment(
        linkId: json['link_id'] as String,
        status: ResponsibilityLinkStatus.fromDb(json['status'] as String),
        ownerName: json['owner_name'] as String? ?? '',
        planTitle: json['plan_title'] as String? ?? '',
        currencyCode: json['currency_code'] as String? ?? 'EGP',
        remainingCount: (json['remaining_count'] as num?)?.toInt() ?? 0,
        remainingTotalMinor:
            (json['remaining_total_minor'] as num?)?.toInt() ?? 0,
        requestedAt: DateTime.parse(json['requested_at'] as String).toUtc(),
        termsChanged: json['terms_changed'] as bool? ?? false,
        nextDueOn: switch (json['next_due_on']) {
          final String value => PlainDate.parse(value),
          _ => null,
        },
        nextDueAmountMinor: (json['next_due_amount_minor'] as num?)?.toInt(),
        acceptedAt: switch (json['accepted_at']) {
          final String value => DateTime.parse(value).toUtc(),
          _ => null,
        },
      );

  final String linkId;
  final ResponsibilityLinkStatus status;
  final String ownerName;
  final String planTitle;
  final String currencyCode;
  final int remainingCount;
  final int remainingTotalMinor;
  final DateTime requestedAt;
  final bool termsChanged;
  final PlainDate? nextDueOn;
  final int? nextDueAmountMinor;
  final DateTime? acceptedAt;

  bool get isPending => status == ResponsibilityLinkStatus.pending;
  Money get remainingTotal =>
      Money(minor: remainingTotalMinor, currencyCode: currencyCode);
  Money? get nextDueAmount => nextDueAmountMinor == null
      ? null
      : Money(minor: nextDueAmountMinor!, currencyCode: currencyCode);
}

/// One owner-side link row of `list_installment_responsibility_links`,
/// covering the live link and the plan's responsibility history.
class OwnerResponsibilityLink {
  const OwnerResponsibilityLink({
    required this.linkId,
    required this.linkType,
    required this.status,
    required this.displayName,
    required this.fromSequence,
    required this.requestedAt,
    required this.termsChanged,
    required this.expectedTotalMinor,
    required this.receivedTotalMinor,
    required this.pendingTotalMinor,
    this.sharedNote,
    this.acceptedAt,
    this.rejectedAt,
    this.removedAt,
  });

  factory OwnerResponsibilityLink.fromJson(
    Map<String, dynamic> json,
  ) => OwnerResponsibilityLink(
    linkId: json['link_id'] as String,
    linkType: ResponsibilityLinkType.fromDb(json['link_type'] as String),
    status: ResponsibilityLinkStatus.fromDb(json['status'] as String),
    displayName: json['display_name'] as String? ?? '',
    fromSequence: (json['responsibility_from_sequence'] as num).toInt(),
    requestedAt: DateTime.parse(json['requested_at'] as String).toUtc(),
    termsChanged: json['terms_changed'] as bool? ?? false,
    expectedTotalMinor: (json['expected_total_minor'] as num?)?.toInt() ?? 0,
    receivedTotalMinor: (json['received_total_minor'] as num?)?.toInt() ?? 0,
    pendingTotalMinor: (json['pending_total_minor'] as num?)?.toInt() ?? 0,
    sharedNote: json['shared_note'] as String?,
    acceptedAt: switch (json['accepted_at']) {
      final String value => DateTime.parse(value).toUtc(),
      _ => null,
    },
    rejectedAt: switch (json['rejected_at']) {
      final String value => DateTime.parse(value).toUtc(),
      _ => null,
    },
    removedAt: switch (json['removed_at']) {
      final String value => DateTime.parse(value).toUtc(),
      _ => null,
    },
  );

  final String linkId;
  final ResponsibilityLinkType linkType;
  final ResponsibilityLinkStatus status;
  final String displayName;
  final int fromSequence;
  final DateTime requestedAt;
  final bool termsChanged;
  final int expectedTotalMinor;
  final int receivedTotalMinor;
  final int pendingTotalMinor;
  final String? sharedNote;
  final DateTime? acceptedAt;
  final DateTime? rejectedAt;
  final DateTime? removedAt;

  bool get isLive =>
      removedAt == null && status != ResponsibilityLinkStatus.rejected;
}

/// The sanitized installment terms both sides review: the stored consent
/// snapshot and the freshly rebuilt current terms share this shape.
class ResponsibilityTerms {
  const ResponsibilityTerms({
    required this.title,
    required this.ownerDisplayName,
    required this.facilityName,
    required this.facilityType,
    required this.currencyCode,
    required this.purchasePriceMinor,
    required this.downPaymentMinor,
    required this.financedPrincipalMinor,
    required this.financingFeesMinor,
    required this.interestMinor,
    required this.totalPayableMinor,
    required this.pricingMethod,
    required this.interestRateBasisPoints,
    required this.interestRatePeriod,
    required this.interestMethod,
    required this.installmentCount,
    required this.paidInstallmentCount,
    required this.fromSequence,
    required this.remainingCount,
    required this.remainingTotalMinor,
    this.categoryName,
    this.purchasedOn,
    this.firstDueOn,
    this.nextDueOn,
    this.finalDueOn,
    this.typicalInstallmentMinor,
  });

  factory ResponsibilityTerms.fromJson(
    Map<String, dynamic> json,
  ) => ResponsibilityTerms(
    title: json['title'] as String? ?? '',
    ownerDisplayName: json['owner_display_name'] as String? ?? '',
    facilityName: json['facility_name'] as String? ?? '',
    facilityType: json['facility_type'] as String? ?? '',
    currencyCode: json['currency_code'] as String? ?? 'EGP',
    purchasePriceMinor: (json['purchase_price_minor'] as num?)?.toInt() ?? 0,
    downPaymentMinor: (json['down_payment_minor'] as num?)?.toInt() ?? 0,
    financedPrincipalMinor:
        (json['financed_principal_minor'] as num?)?.toInt() ?? 0,
    financingFeesMinor: (json['financing_fees_minor'] as num?)?.toInt() ?? 0,
    interestMinor: (json['interest_minor'] as num?)?.toInt() ?? 0,
    totalPayableMinor: (json['total_payable_minor'] as num?)?.toInt() ?? 0,
    pricingMethod: json['pricing_method'] as String? ?? '',
    interestRateBasisPoints:
        (json['interest_rate_basis_points'] as num?)?.toInt() ?? 0,
    interestRatePeriod: json['interest_rate_period'] as String? ?? '',
    interestMethod: json['interest_method'] as String? ?? '',
    installmentCount: (json['installment_count'] as num?)?.toInt() ?? 0,
    paidInstallmentCount:
        (json['paid_installment_count'] as num?)?.toInt() ?? 0,
    fromSequence: (json['responsibility_from_sequence'] as num?)?.toInt() ?? 1,
    remainingCount: (json['remaining_count'] as num?)?.toInt() ?? 0,
    remainingTotalMinor: (json['remaining_total_minor'] as num?)?.toInt() ?? 0,
    categoryName: json['category_name'] as String?,
    purchasedOn: switch (json['purchased_on']) {
      final String value => PlainDate.parse(value),
      _ => null,
    },
    firstDueOn: switch (json['first_due_on']) {
      final String value => PlainDate.parse(value),
      _ => null,
    },
    nextDueOn: switch (json['next_due_on']) {
      final String value => PlainDate.parse(value),
      _ => null,
    },
    finalDueOn: switch (json['final_due_on']) {
      final String value => PlainDate.parse(value),
      _ => null,
    },
    typicalInstallmentMinor: (json['typical_installment_minor'] as num?)
        ?.toInt(),
  );

  final String title;
  final String ownerDisplayName;
  final String facilityName;
  final String facilityType;
  final String currencyCode;
  final int purchasePriceMinor;
  final int downPaymentMinor;
  final int financedPrincipalMinor;
  final int financingFeesMinor;
  final int interestMinor;
  final int totalPayableMinor;
  final String pricingMethod;
  final int interestRateBasisPoints;
  final String interestRatePeriod;
  final String interestMethod;
  final int installmentCount;
  final int paidInstallmentCount;
  final int fromSequence;
  final int remainingCount;
  final int remainingTotalMinor;
  final String? categoryName;
  final PlainDate? purchasedOn;
  final PlainDate? firstDueOn;
  final PlainDate? nextDueOn;
  final PlainDate? finalDueOn;
  final int? typicalInstallmentMinor;

  Money get remainingTotal =>
      Money(minor: remainingTotalMinor, currencyCode: currencyCode);
  Money get totalPayable =>
      Money(minor: totalPayableMinor, currencyCode: currencyCode);
  Money? get typicalInstallment => typicalInstallmentMinor == null
      ? null
      : Money(minor: typicalInstallmentMinor!, currencyCode: currencyCode);
}

/// One due of the linked schedule with its reimbursement position.
class ResponsibilityDueEntry {
  const ResponsibilityDueEntry({
    required this.dueId,
    required this.sequenceNumber,
    required this.dueOn,
    required this.amountMinor,
    required this.receivedMinor,
    required this.pendingMinor,
    required this.remainingMinor,
    required this.reimbursementStatus,
  });

  factory ResponsibilityDueEntry.fromJson(Map<String, dynamic> json) =>
      ResponsibilityDueEntry(
        dueId: json['due_id'] as String,
        sequenceNumber: (json['sequence_number'] as num).toInt(),
        dueOn: PlainDate.parse(json['due_on'] as String),
        amountMinor: (json['amount_minor'] as num).toInt(),
        receivedMinor: (json['received_minor'] as num?)?.toInt() ?? 0,
        pendingMinor: (json['pending_minor'] as num?)?.toInt() ?? 0,
        remainingMinor: (json['remaining_minor'] as num?)?.toInt() ?? 0,
        reimbursementStatus: DueReimbursementStatus.fromDb(
          json['reimbursement_status'] as String? ?? 'not_paid',
        ),
      );

  final String dueId;
  final int sequenceNumber;
  final PlainDate dueOn;
  final int amountMinor;
  final int receivedMinor;
  final int pendingMinor;
  final int remainingMinor;
  final DueReimbursementStatus reimbursementStatus;

  bool get canReimburse => remainingMinor > 0;
}

/// The full shared payload of `get_shared_installment_link_details`.
class SharedInstallmentLinkDetails {
  const SharedInstallmentLinkDetails({
    required this.linkId,
    required this.linkType,
    required this.status,
    required this.viewerIsOwner,
    required this.counterpartyName,
    required this.fromSequence,
    required this.requestedAt,
    required this.connectionActive,
    required this.snapshot,
    required this.current,
    required this.planStatus,
    required this.termsChanged,
    required this.schedule,
    required this.expectedTotalMinor,
    required this.receivedTotalMinor,
    required this.pendingTotalMinor,
    required this.remainingTotalMinor,
    this.sharedNote,
    this.acceptedAt,
    this.rejectedAt,
    this.removedAt,
  });

  factory SharedInstallmentLinkDetails.fromJson(Map<String, dynamic> json) {
    final link = json['link'] as Map<String, dynamic>;
    final current = json['current'] as Map<String, dynamic>;
    final summary = json['reimbursement_summary'] as Map<String, dynamic>;
    return SharedInstallmentLinkDetails(
      linkId: link['id'] as String,
      linkType: ResponsibilityLinkType.fromDb(link['link_type'] as String),
      status: ResponsibilityLinkStatus.fromDb(link['status'] as String),
      viewerIsOwner: link['viewer_role'] == 'owner',
      counterpartyName: link['counterparty_name'] as String? ?? '',
      fromSequence:
          (link['responsibility_from_sequence'] as num?)?.toInt() ?? 1,
      requestedAt: DateTime.parse(link['requested_at'] as String).toUtc(),
      connectionActive: link['connection_active'] as bool? ?? false,
      snapshot: ResponsibilityTerms.fromJson(
        json['snapshot'] as Map<String, dynamic>? ?? const {},
      ),
      current: ResponsibilityTerms.fromJson(current),
      planStatus: current['plan_status'] as String? ?? 'active',
      termsChanged: current['terms_changed'] as bool? ?? false,
      schedule: (json['schedule'] as List<dynamic>? ?? const [])
          .map(
            (e) => ResponsibilityDueEntry.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      expectedTotalMinor:
          (summary['expected_total_minor'] as num?)?.toInt() ?? 0,
      receivedTotalMinor:
          (summary['received_total_minor'] as num?)?.toInt() ?? 0,
      pendingTotalMinor: (summary['pending_total_minor'] as num?)?.toInt() ?? 0,
      remainingTotalMinor:
          (summary['remaining_total_minor'] as num?)?.toInt() ?? 0,
      sharedNote: link['shared_note'] as String?,
      acceptedAt: switch (link['accepted_at']) {
        final String value => DateTime.parse(value).toUtc(),
        _ => null,
      },
      rejectedAt: switch (link['rejected_at']) {
        final String value => DateTime.parse(value).toUtc(),
        _ => null,
      },
      removedAt: switch (link['removed_at']) {
        final String value => DateTime.parse(value).toUtc(),
        _ => null,
      },
    );
  }

  final String linkId;
  final ResponsibilityLinkType linkType;
  final ResponsibilityLinkStatus status;
  final bool viewerIsOwner;
  final String counterpartyName;
  final int fromSequence;
  final DateTime requestedAt;
  final bool connectionActive;
  final ResponsibilityTerms snapshot;
  final ResponsibilityTerms current;
  final String planStatus;
  final bool termsChanged;
  final List<ResponsibilityDueEntry> schedule;
  final int expectedTotalMinor;
  final int receivedTotalMinor;
  final int pendingTotalMinor;
  final int remainingTotalMinor;
  final String? sharedNote;
  final DateTime? acceptedAt;
  final DateTime? rejectedAt;
  final DateTime? removedAt;

  bool get isPending =>
      status == ResponsibilityLinkStatus.pending && removedAt == null;
  bool get isAccepted =>
      status == ResponsibilityLinkStatus.accepted && removedAt == null;
  bool get canRespond => !viewerIsOwner && isPending && connectionActive;
  bool get canSendReimbursement =>
      !viewerIsOwner &&
      isAccepted &&
      connectionActive &&
      !termsChanged &&
      planStatus != 'cancelled' &&
      remainingTotalMinor > 0;
  Money get remainingTotal =>
      Money(minor: remainingTotalMinor, currencyCode: current.currencyCode);
  Money get receivedTotal =>
      Money(minor: receivedTotalMinor, currencyCode: current.currencyCode);
}
