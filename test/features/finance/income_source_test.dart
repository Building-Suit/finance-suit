import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';
import 'package:work_tracker/features/finance/domain/income_split_preview.dart';
import 'package:work_tracker/features/finance/domain/transaction_category.dart';

void main() {
  test('legacy category JSON remains a top-level category', () {
    final category = TransactionCategory.fromJson({
      'id': 'food',
      'name': 'Food',
      'category_kind': 'expense',
      'icon': 'category',
      'sort_order': 0,
      'is_archived': false,
    });

    expect(category.parentCategoryId, isNull);
    expect(category.isSubcategory, isFalse);
    expect(category.displayName([category]), 'Food');
  });

  test('subcategory display includes its parent without changing its id', () {
    const parent = TransactionCategory(
      id: 'home',
      name: 'Home',
      kind: CategoryKind.expense,
      icon: 'category',
      sortOrder: 0,
      isArchived: false,
    );
    const child = TransactionCategory(
      id: 'repairs',
      name: 'Repairs',
      kind: CategoryKind.expense,
      icon: 'category',
      sortOrder: 1,
      isArchived: false,
      parentCategoryId: 'home',
    );

    expect(child.displayName([parent, child]), 'Home › Repairs');
    expect(child.id, 'repairs');
  });

  test('income source keeps the unallocated percentage in primary account', () {
    final source = IncomeSource.fromJson({
      'id': 'source-1',
      'name': 'Allowance',
      'source_kind': 'allowance',
      'expected_amount_minor': 100000,
      'currency_code': 'EGP',
      'payment_day': 15,
      'start_date': '2026-07-01',
      'prompt_days_before': 7,
      'primary_account_id': 'current',
      'category_id': null,
      'is_active': true,
      'notes': null,
      'income_source_allocations': [
        {
          'id': 'allocation-1',
          'destination_account_id': 'savings',
          'allocation_method': 'percentage',
          'calculation_basis': 'original',
          'percentage_basis_points': 3000,
          'fixed_amount_minor': null,
          'sort_order': 0,
        },
      ],
    });

    expect(source.kind, IncomeSourceKind.allowance);
    expect(source.allocatedBasisPoints, 3000);
    expect(source.remainderBasisPoints, 7000);
    expect(source.expectedAmountMinor, 100000);
    expect(source.rolloverBalanceEnabled, isFalse);
    expect(source.rolloverDestinationAccountId, isNull);
  });

  test('ordered percentage rules can use original and remaining basis', () {
    final preview = IncomeSplitCalculator.preview(
      actualAmountMinor: 10000,
      kind: IncomeSourceKind.other,
      allocations: const [
        IncomeAllocation(
          destinationAccountId: 'savings',
          method: IncomeAllocationMethod.percentage,
          percentageBasisPoints: 5000,
        ),
        IncomeAllocation(
          destinationAccountId: 'bills',
          method: IncomeAllocationMethod.percentage,
          calculationBasis: IncomeAllocationCalculationBasis.remaining,
          percentageBasisPoints: 5000,
        ),
      ],
      includeExtraWorkInPercentage: true,
      extraWorkDestinationAccountId: null,
    );

    expect(preview.hasError, isFalse);
    expect(preview.rows.map((row) => row.amountMinor), [5000, 2500]);
    expect(preview.primaryAmountMinor, 2500);
  });

  test('salary extra work can be protected from split percentages', () {
    final preview = IncomeSplitCalculator.preview(
      actualAmountMinor: 12000,
      kind: IncomeSourceKind.salary,
      allocations: const [
        IncomeAllocation(
          destinationAccountId: 'savings',
          method: IncomeAllocationMethod.percentage,
          percentageBasisPoints: 5000,
        ),
      ],
      includeExtraWorkInPercentage: false,
      extraWorkDestinationAccountId: 'extra',
      extraWorkMinor: 2000,
    );

    expect(preview.hasError, isFalse);
    expect(preview.rows.single.amountMinor, 5000);
    expect(preview.extraWorkRoutedMinor, 2000);
    expect(preview.primaryAmountMinor, 5000);
  });

  test('fixed salary splits can still route protected extra work', () {
    final preview = IncomeSplitCalculator.preview(
      actualAmountMinor: 12000,
      kind: IncomeSourceKind.salary,
      allocations: const [
        IncomeAllocation(
          destinationAccountId: 'bills',
          method: IncomeAllocationMethod.fixed,
          fixedAmountMinor: 5000,
        ),
      ],
      includeExtraWorkInPercentage: false,
      extraWorkDestinationAccountId: 'extra',
      extraWorkMinor: 2000,
    );

    expect(preview.hasError, isFalse);
    expect(preview.rows.single.amountMinor, 5000);
    expect(preview.extraWorkRoutedMinor, 2000);
    expect(preview.primaryAmountMinor, 5000);
  });

  test('salary rollover settings are restored from persistence', () {
    final source = IncomeSource.fromJson({
      'id': 'salary-source',
      'name': 'Salary',
      'source_kind': 'salary',
      'expected_amount_minor': 100000,
      'currency_code': 'EGP',
      'payment_day': 25,
      'start_date': '2026-07-01',
      'prompt_days_before': 7,
      'primary_account_id': 'current',
      'category_id': null,
      'is_active': true,
      'include_extra_work_in_percentage': false,
      'extra_work_destination_account_id': 'extra',
      'rollover_balance_enabled': true,
      'rollover_destination_account_id': 'savings',
      'notes': null,
      'income_source_allocations': const <Map<String, dynamic>>[],
    });

    expect(source.rolloverBalanceEnabled, isTrue);
    expect(source.rolloverDestinationAccountId, 'savings');
  });

  test('fixed rules fail the preview when they exceed available income', () {
    final preview = IncomeSplitCalculator.preview(
      actualAmountMinor: 10000,
      kind: IncomeSourceKind.other,
      allocations: const [
        IncomeAllocation(
          destinationAccountId: 'savings',
          method: IncomeAllocationMethod.fixed,
          fixedAmountMinor: 11000,
        ),
      ],
      includeExtraWorkInPercentage: true,
      extraWorkDestinationAccountId: null,
    );

    expect(preview.hasError, isTrue);
    expect(preview.rows, isEmpty);
  });
}
