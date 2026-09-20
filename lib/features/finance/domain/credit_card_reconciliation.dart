import 'package:flutter/foundation.dart';

@immutable
class BankStatementLine {
  const BankStatementLine({
    required this.id,
    required this.accountId,
    required this.lineDate,
    required this.postingDate,
    required this.amountMinor,
    required this.currencyCode,
    required this.description,
    this.referenceNumber,
    this.isPending = false,
    this.reconciliationStatus = 'unmatched',
    this.matchedTransactionId,
  });

  final String id;
  final String accountId;
  final DateTime lineDate;
  final DateTime postingDate;
  final int amountMinor;
  final String currencyCode;
  final String description;
  final String? referenceNumber;
  final bool isPending;
  final String reconciliationStatus;
  final String? matchedTransactionId;

  factory BankStatementLine.fromJson(Map<String, dynamic> json) {
    return BankStatementLine(
      id: json['id'] as String,
      accountId: json['account_id'] as String,
      lineDate: DateTime.parse(json['line_date'] as String),
      postingDate: DateTime.parse(json['posting_date'] as String),
      amountMinor: (json['amount_minor'] as num).toInt(),
      currencyCode: json['currency_code'] as String? ?? 'EGP',
      description: json['description'] as String? ?? '',
      referenceNumber: json['reference_number'] as String?,
      isPending: json['is_pending'] as bool? ?? false,
      reconciliationStatus:
          json['reconciliation_status'] as String? ?? 'unmatched',
      matchedTransactionId: json['matched_transaction_id'] as String?,
    );
  }
}

@immutable
class RepairManifest {
  const RepairManifest({
    required this.accountId,
    required this.status,
    required this.manifestHash,
    required this.reportedDiscrepancyMinor,
    required this.principalAnchorDiffMinor,
    required this.reassignments,
    required this.interestLinks,
    required this.unappliedCredits,
  });

  final String accountId;
  final String status;
  final String manifestHash;
  final int reportedDiscrepancyMinor;
  final int principalAnchorDiffMinor;
  final List<Map<String, dynamic>> reassignments;
  final List<Map<String, dynamic>> interestLinks;
  final List<Map<String, dynamic>> unappliedCredits;

  factory RepairManifest.fromJson(Map<String, dynamic> json) {
    return RepairManifest(
      accountId: json['account_id'] as String? ?? '',
      status: json['status'] as String? ?? 'preview_ready',
      manifestHash: json['manifest_hash'] as String? ?? '',
      reportedDiscrepancyMinor:
          (json['reported_discrepancy_minor'] as num?)?.toInt() ?? 0,
      principalAnchorDiffMinor:
          (json['principal_anchor_diff_minor'] as num?)?.toInt() ?? 0,
      reassignments:
          (json['reassignments'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
      interestLinks:
          (json['interest_links'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
      unappliedCredits:
          (json['unapplied_credits'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'account_id': accountId,
    'status': status,
    'manifest_hash': manifestHash,
    'reported_discrepancy_minor': reportedDiscrepancyMinor,
    'principal_anchor_diff_minor': principalAnchorDiffMinor,
    'reassignments': reassignments,
    'interest_links': interestLinks,
    'unapplied_credits': unappliedCredits,
  };
}
