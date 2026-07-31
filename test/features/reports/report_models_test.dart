import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/core/date_time/date_range.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/features/reports/domain/report_models.dart';

void main() {
  group('CashFlowSummary', () {
    test('parses integer minor-unit totals', () {
      final summary = CashFlowSummary.fromJson({
        'currency_code': 'EGP',
        'starting_balance_minor': 113000,
        'income_minor': 500000,
        'expenses_minor': 125000,
        'allowances_minor': 25000,
        'net_minor': 350000,
        'ending_balance_minor': 463000,
      });

      expect(summary.currencyCode, 'EGP');
      expect(summary.startingBalanceMinor, 113000);
      expect(summary.incomeMinor, 500000);
      expect(summary.netMinor, 350000);
      expect(summary.endingBalanceMinor, 463000);
      expect(summary.isZero, isFalse);
    });
  });

  group('ReportRangeSelection', () {
    test('currentMonth starts and ends on calendar month boundaries', () {
      final selection = ReportRangeSelection.currentMonth(
        const PlainDate(2026, 7, 10),
      );

      expect(selection.preset, DateRangePreset.currentMonth);
      expect(selection.range.start, const PlainDate(2026, 7, 1));
      expect(selection.range.end, const PlainDate(2026, 7, 31));
    });
  });

  group('SalaryComparisonPoint', () {
    test('parses estimate-versus-actual rows', () {
      final point = SalaryComparisonPoint.fromJson({
        'period_id': '00000000-0000-0000-0000-000000000001',
        'period_start': '2026-06-01',
        'period_end': '2026-06-30',
        'expected_payment_date': '2026-07-25',
        'status': 'paid',
        'estimated_minor': 1000000,
        'actual_amount_minor': 1050000,
        'difference_minor': 50000,
        'currency_code': 'EGP',
      });

      expect(point.actualAmountMinor, 1050000);
      expect(point.differenceMinor, 50000);
      expect(point.periodStart, const PlainDate(2026, 6, 1));
    });
  });
}
