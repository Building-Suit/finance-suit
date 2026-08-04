import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/money/money_input.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';

TextEditingValue _type(
  TextInputFormatter formatter,
  String oldText,
  String newText, {
  int? caret,
}) {
  return formatter.formatEditUpdate(
    TextEditingValue(
      text: oldText,
      selection: TextSelection.collapsed(offset: oldText.length),
    ),
    TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: caret ?? newText.length),
    ),
  );
}

void main() {
  group('ThousandsSeparatorInputFormatter', () {
    const formatter = ThousandsSeparatorInputFormatter();

    test('groups integer digits while typing', () {
      expect(_type(formatter, '123', '1234').text, '1,234');
      expect(_type(formatter, '1,234', '1,2345').text, '12,345');
      expect(_type(formatter, '999,999', '999,9999').text, '9,999,999');
    });

    test('keeps the caret with the typed digit', () {
      final value = _type(formatter, '123', '1234');
      expect(value.selection.baseOffset, value.text.length);
    });

    test('supports at most two decimal digits', () {
      expect(_type(formatter, '1,234', '1,234.').text, '1,234.');
      expect(_type(formatter, '1,234.5', '1,234.56').text, '1,234.56');
      expect(_type(formatter, '1,234.56', '1,234.567').text, '1,234.56');
    });

    test('regroups after deleting across a separator', () {
      expect(_type(formatter, '1,234', '1,24').text, '124');
      expect(_type(formatter, '12,345.67', '2,345.67').text, '2,345.67');
    });

    test('drops every non-numeric character', () {
      expect(_type(formatter, '', 'abc12x34').text, '1,234');
      expect(_type(formatter, '', '١٢٣').text, '');
    });

    test('integer mode never accepts a decimal point', () {
      const integers = ThousandsSeparatorInputFormatter(maxDecimalDigits: 0);
      expect(_type(integers, '1234', '1234.').text, '1,234');
      expect(_type(integers, '', '1000000').text, '1,000,000');
    });

    test('grouped text round-trips through Money.tryParse exactly', () {
      final grouped = _type(formatter, '', '1234567.89').text;
      expect(grouped, '1,234,567.89');
      final parsed = Money.tryParse(grouped, currencyCode: 'EGP');
      expect(parsed?.minor, 123456789);
    });
  });

  group('formatMinorForInput', () {
    test('formats minor units with grouping and two decimals', () {
      expect(formatMinorForInput(0), '0.00');
      expect(formatMinorForInput(5), '0.05');
      expect(formatMinorForInput(123456789), '1,234,567.89');
      expect(formatMinorForInput(-1050), '-10.50');
    });
  });

  group('previewPlanFinancing', () {
    test('flat monthly interest mirrors the SQL engine', () {
      final result = previewPlanFinancing(
        pricingMethod: PlanPricingMethod.interestRate,
        principalMinor: 100000,
        count: 10,
        rateBasisPoints: 200,
      );
      expect(result, isNotNull);
      expect(result!.interestMinor, 20000);
      expect(result.totalMinor, 120000);
    });

    test('annual rates divide by twelve', () {
      final result = previewPlanFinancing(
        pricingMethod: PlanPricingMethod.interestRate,
        principalMinor: 100000,
        count: 10,
        rateBasisPoints: 2400,
        ratePeriod: InterestRatePeriod.annual,
      );
      expect(result!.interestMinor, 20000);
    });

    test('reducing balance uses the annuity payment', () {
      final result = previewPlanFinancing(
        pricingMethod: PlanPricingMethod.interestRate,
        principalMinor: 120000,
        count: 12,
        rateBasisPoints: 200,
        interestMethod: InterestMethod.reducing,
      );
      // Matches resolve_plan_financing in SQL: round half-up to 16,166.
      expect(result!.interestMinor, 16166);
      expect(result.totalMinor, 136166);
    });

    test('monthly amount back-solves the financing cost', () {
      final result = previewPlanFinancing(
        pricingMethod: PlanPricingMethod.monthlyAmount,
        principalMinor: 100000,
        count: 10,
        monthlyPaymentMinor: 11000,
      );
      expect(result!.interestMinor, 10000);
      expect(result.totalMinor, 110000);
    });

    test('total payable splits interest from financed fees', () {
      final result = previewPlanFinancing(
        pricingMethod: PlanPricingMethod.totalPayable,
        principalMinor: 100000,
        count: 10,
        totalPayableMinor: 115000,
        financedFeesMinor: 5000,
      );
      expect(result!.interestMinor, 10000);
      expect(result.feesMinor, 15000);
      expect(result.totalMinor, 115000);
    });

    test('rejects impossible quotes', () {
      expect(
        previewPlanFinancing(
          pricingMethod: PlanPricingMethod.monthlyAmount,
          principalMinor: 100000,
          count: 10,
          monthlyPaymentMinor: 9000,
        ),
        isNull,
      );
      expect(
        previewPlanFinancing(
          pricingMethod: PlanPricingMethod.totalPayable,
          principalMinor: 100000,
          count: 10,
          totalPayableMinor: 90000,
        ),
        isNull,
      );
    });
  });
}
