import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/finance/domain/installment_responsibility.dart';

Map<String, dynamic> _detailsJson({
  String status = 'pending',
  String viewerRole = 'responsible',
  bool termsChanged = false,
}) => {
  'link': {
    'id': 'link-1',
    'link_type': 'network',
    'status': status,
    'viewer_role': viewerRole,
    'counterparty_name': 'Tarek',
    'shared_note': 'TV for you',
    'responsibility_from_sequence': 3,
    'plan_revision_at_request': 1,
    'requested_at': '2026-08-14T09:00:00Z',
    'responded_at': null,
    'accepted_at': status == 'accepted' ? '2026-08-14T10:00:00Z' : null,
    'rejected_at': null,
    'removed_at': null,
    'connection_active': true,
  },
  'snapshot': {
    'title': 'Samsung TV',
    'currency_code': 'EGP',
    'remaining_count': 10,
    'remaining_total_minor': 1000000,
    'terms_fingerprint': 'abc',
  },
  'current': {
    'title': 'Samsung TV',
    'owner_display_name': 'Tarek Owner',
    'facility_name': 'CIB Gold',
    'facility_type': 'credit_card',
    'category_name': 'Electronics',
    'purchased_on': '2026-06-01',
    'first_due_on': '2026-06-25',
    'currency_code': 'EGP',
    'purchase_price_minor': 1300000,
    'down_payment_minor': 100000,
    'financed_principal_minor': 1200000,
    'financing_fees_minor': 55000,
    'interest_minor': 55000,
    'total_payable_minor': 1255000,
    'pricing_method': 'interest_rate',
    'interest_rate_basis_points': 250,
    'interest_rate_period': 'monthly',
    'interest_method': 'flat',
    'installment_count': 12,
    'paid_installment_count': 2,
    'responsibility_from_sequence': 3,
    'remaining_count': 10,
    'remaining_total_minor': 1000000,
    'next_due_on': '2026-08-25',
    'final_due_on': '2027-05-25',
    'typical_installment_minor': 100000,
    'plan_status': 'active',
    'terms_changed': termsChanged,
  },
  'schedule': [
    {
      'due_id': 'due-3',
      'sequence_number': 3,
      'due_on': '2026-08-25',
      'amount_minor': 100000,
      'received_minor': 60000,
      'pending_minor': 0,
      'remaining_minor': 40000,
      'reimbursement_status': 'partial',
    },
    {
      'due_id': 'due-4',
      'sequence_number': 4,
      'due_on': '2026-09-25',
      'amount_minor': 100000,
      'received_minor': 0,
      'pending_minor': 100000,
      'remaining_minor': 0,
      'reimbursement_status': 'pending',
    },
  ],
  'reimbursement_summary': {
    'expected_total_minor': 1000000,
    'received_total_minor': 60000,
    'pending_total_minor': 100000,
    'remaining_total_minor': 840000,
  },
};

void main() {
  test('responsibility summary parses the owner chip fields', () {
    final summary = InstallmentResponsibilitySummary.fromJson(const {
      'plan_id': 'plan-1',
      'user_id': 'user-1',
      'link_id': 'link-1',
      'link_type': 'custom',
      'status': 'accepted',
      'display_name': 'Dad',
      'responsibility_from_sequence': 1,
      'expected_total_minor': 1200000,
      'received_total_minor': 200000,
      'pending_total_minor': 0,
      'expected_remaining_minor': 1000000,
    });
    expect(summary.planId, 'plan-1');
    expect(summary.linkType, ResponsibilityLinkType.custom);
    expect(summary.isAccepted, isTrue);
    expect(summary.displayName, 'Dad');
    expect(summary.expectedRemainingMinor, 1000000);
  });

  test('linked installments parse both pending and accepted rows', () {
    final pending = LinkedInstallment.fromJson(const {
      'link_id': 'link-1',
      'status': 'pending',
      'owner_name': 'Tarek',
      'plan_title': 'Samsung TV',
      'currency_code': 'EGP',
      'remaining_count': 10,
      'remaining_total_minor': 1000000,
      'next_due_on': '2026-08-25',
      'next_due_amount_minor': 100000,
      'requested_at': '2026-08-14T09:00:00Z',
      'accepted_at': null,
      'terms_changed': false,
    });
    expect(pending.isPending, isTrue);
    expect(pending.remainingTotal.minor, 1000000);
    expect(pending.nextDueAmount!.minor, 100000);
    expect(pending.nextDueOn!.toIso(), '2026-08-25');
  });

  test('shared details parse the sanitized DTO end to end', () {
    final details = SharedInstallmentLinkDetails.fromJson(_detailsJson());
    expect(details.linkId, 'link-1');
    expect(details.viewerIsOwner, isFalse);
    expect(details.counterpartyName, 'Tarek');
    expect(details.fromSequence, 3);
    expect(details.current.facilityName, 'CIB Gold');
    expect(details.current.paidInstallmentCount, 2);
    expect(details.current.remainingTotalMinor, 1000000);
    expect(details.schedule, hasLength(2));
    expect(
      details.schedule.first.reimbursementStatus,
      DueReimbursementStatus.partial,
    );
    expect(details.schedule.first.remainingMinor, 40000);
    expect(details.schedule.last.canReimburse, isFalse);
    expect(details.remainingTotalMinor, 840000);
    expect(details.isPending, isTrue);
    expect(details.canRespond, isTrue);
  });

  test('reimbursement gating follows status, terms, and plan state', () {
    final accepted = SharedInstallmentLinkDetails.fromJson(
      _detailsJson(status: 'accepted'),
    );
    expect(accepted.canRespond, isFalse);
    expect(accepted.canSendReimbursement, isTrue);

    final stale = SharedInstallmentLinkDetails.fromJson(
      _detailsJson(status: 'accepted', termsChanged: true),
    );
    expect(stale.canSendReimbursement, isFalse);

    final ownerView = SharedInstallmentLinkDetails.fromJson(
      _detailsJson(status: 'accepted', viewerRole: 'owner'),
    );
    expect(ownerView.canSendReimbursement, isFalse);
    expect(ownerView.canRespond, isFalse);
  });

  test('owner link rows keep history flags', () {
    final removed = OwnerResponsibilityLink.fromJson(const {
      'link_id': 'link-1',
      'link_type': 'custom',
      'status': 'accepted',
      'display_name': 'Ahmed',
      'shared_note': null,
      'responsibility_from_sequence': 1,
      'requested_at': '2026-08-01T09:00:00Z',
      'accepted_at': '2026-08-01T09:00:00Z',
      'rejected_at': null,
      'removed_at': '2026-08-15T09:00:00Z',
      'terms_changed': false,
      'expected_total_minor': 1200000,
      'received_total_minor': 200000,
      'pending_total_minor': 0,
    });
    expect(removed.isLive, isFalse);
    expect(removed.receivedTotalMinor, 200000);
  });
}
