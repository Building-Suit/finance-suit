import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/features/finance/domain/credit_card_reconciliation.dart';

void main() {
  group('CreditCardReconciliation & Repair Domain Tests', () {
    test('BankStatementLine deserialization maps fields correctly', () {
      final json = {
        'id': 'line-123',
        'account_id': 'acc-456',
        'line_date': '2026-08-01',
        'posting_date': '2026-08-01',
        'amount_minor': 10996,
        'currency_code': 'EGP',
        'description': 'CIB Interest Charge',
        'reference_number': 'REF-001',
        'is_pending': false,
        'reconciliation_status': 'unmatched',
      };

      final line = BankStatementLine.fromJson(json);

      expect(line.id, 'line-123');
      expect(line.accountId, 'acc-456');
      expect(line.amountMinor, 10996);
      expect(line.currencyCode, 'EGP');
      expect(line.description, 'CIB Interest Charge');
      expect(line.referenceNumber, 'REF-001');
      expect(line.isPending, isFalse);
    });

    test('RepairManifest preview model serializes and parses correctly', () {
      final manifest = RepairManifest(
        accountId: 'a7a0709a-f11e-460f-920c-aad88c096e7b',
        status: 'preview_ready',
        manifestHash: 'hash123',
        reportedDiscrepancyMinor: 31636,
        principalAnchorDiffMinor: 19,
        reassignments: [
          {
            'item': 'Purchase 810 EGP',
            'original_cycle': 'September',
            'target_cycle': 'August',
          },
        ],
        interestLinks: [
          {
            'installment': 'Samsung Monitor (25 Aug)',
            'payment_date': '2026-08-15',
          },
        ],
        unappliedCredits: [
          {'payment_date': '2026-09-07', 'unapplied_credit': 265562},
        ],
      );

      final json = manifest.toJson();
      final parsed = RepairManifest.fromJson(json);

      expect(parsed.accountId, 'a7a0709a-f11e-460f-920c-aad88c096e7b');
      expect(parsed.reportedDiscrepancyMinor, 31636);
      expect(parsed.principalAnchorDiffMinor, 19);
      expect(parsed.reassignments.length, 1);
      expect(parsed.interestLinks.length, 1);
      expect(parsed.unappliedCredits.length, 1);
    });
  });
}
