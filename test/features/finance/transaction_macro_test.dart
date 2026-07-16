import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/features/finance/domain/transaction_macro.dart';

void main() {
  test('TransactionMacro.fromJson restores items by stored position', () {
    final macro = TransactionMacro.fromJson({
      'id': 'macro-1',
      'name': 'Morning routine',
      'transaction_macro_items': [
        {
          'position': 2,
          'transaction_kind': 'expense',
          'amount_minor': 300,
          'title': 'Third',
        },
        {
          'position': 0,
          'transaction_kind': 'expense',
          'amount_minor': 100,
          'title': 'First',
        },
        {
          'position': 1,
          'transaction_kind': 'expense',
          'amount_minor': 200,
          'title': 'Second',
        },
      ],
    });

    expect(
      macro.items.map((item) => item.title),
      orderedEquals(['First', 'Second', 'Third']),
    );
    expect(
      macro.items.map((item) => item.amountMinor),
      orderedEquals([100, 200, 300]),
    );
  });
}
