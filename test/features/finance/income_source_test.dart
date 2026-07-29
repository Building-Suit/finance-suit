import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';
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
          'percentage_basis_points': 3000,
          'sort_order': 0,
        },
      ],
    });

    expect(source.kind, IncomeSourceKind.allowance);
    expect(source.allocatedBasisPoints, 3000);
    expect(source.remainderBasisPoints, 7000);
    expect(source.expectedAmountMinor, 100000);
  });
}
