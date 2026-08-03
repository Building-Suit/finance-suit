import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/finance/domain/held_amount.dart';

HeldAmount heldAmount({
  required String id,
  required HeldAmountDirection direction,
  required int amountMinor,
  String currencyCode = 'EGP',
  PlainDate? settledOn,
}) {
  return HeldAmount(
    id: id,
    direction: direction,
    transactionKind: direction == HeldAmountDirection.iOwe
        ? TransactionKind.expense
        : TransactionKind.customIncome,
    amountMinor: amountMinor,
    currencyCode: currencyCode,
    counterparty: 'Counterparty',
    heldOn: const PlainDate(2026, 7, 16),
    settledOn: settledOn,
  );
}

void main() {
  group('HeldAmountDirection', () {
    test('uses the database wire values exactly', () {
      expect(HeldAmountDirection.iOwe.dbValue, 'i_owe');
      expect(HeldAmountDirection.owedToMe.dbValue, 'owed_to_me');
      expect(HeldAmountDirection.fromDb('i_owe'), HeldAmountDirection.iOwe);
      expect(
        HeldAmountDirection.fromDb('owed_to_me'),
        HeldAmountDirection.owedToMe,
      );
    });

    test('rejects unknown database values', () {
      expect(
        () => HeldAmountDirection.fromDb('unknown'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('HeldAmount', () {
    test('parses direction, kind, and category from a database row', () {
      final held = HeldAmount.fromJson({
        'id': 'held-1',
        'direction': 'owed_to_me',
        'transaction_kind': 'freelance_income',
        'category_id': 'category-1',
        'amount_minor': 12500,
        'currency_code': 'EGP',
        'counterparty': 'Mona',
        'held_on': '2026-07-16',
        'account_id': 'account-1',
        'manages_transaction': true,
      });

      expect(held.direction, HeldAmountDirection.owedToMe);
      expect(held.transactionKind, TransactionKind.freelanceIncome);
      expect(held.categoryId, 'category-1');
      expect(held.amountMinor, 12500);
      expect(held.isSettled, isFalse);
      expect(held.accountId, 'account-1');
      expect(held.managesTransaction, isTrue);
    });

    test('falls back to a direction-derived kind on rows without one', () {
      Map<String, dynamic> row(String direction) => {
        'id': 'held-$direction',
        'direction': direction,
        'amount_minor': 12500,
        'currency_code': 'EGP',
        'counterparty': 'Mona',
        'held_on': '2026-07-16',
      };

      final iOwe = HeldAmount.fromJson(row('i_owe'));
      final owedToMe = HeldAmount.fromJson(row('owed_to_me'));

      expect(iOwe.transactionKind, TransactionKind.expense);
      expect(owedToMe.transactionKind, TransactionKind.customIncome);
      expect(iOwe.categoryId, isNull);
    });

    test('draft serializes the kind and category, not a direction', () {
      const draft = HeldAmountDraft(
        transactionKind: TransactionKind.allowanceGiven,
        amountMinor: 2500,
        currencyCode: 'EGP',
        counterparty: 'Ahmed',
        heldOn: PlainDate(2026, 7, 16),
        categoryId: 'category-1',
      );

      final json = draft.toJson();
      expect(json['p_transaction_kind'], 'allowance_given');
      expect(json['p_category_id'], 'category-1');
      expect(json.containsKey('p_direction'), isFalse);
    });

    test('draft derives the direction from the kind', () {
      HeldAmountDraft draft(TransactionKind kind) => HeldAmountDraft(
        transactionKind: kind,
        amountMinor: 2500,
        currencyCode: 'EGP',
        counterparty: 'Ahmed',
        heldOn: const PlainDate(2026, 7, 16),
      );

      expect(
        draft(TransactionKind.expense).direction,
        HeldAmountDirection.iOwe,
      );
      expect(
        draft(TransactionKind.allowanceGiven).direction,
        HeldAmountDirection.iOwe,
      );
      expect(
        draft(TransactionKind.customIncome).direction,
        HeldAmountDirection.owedToMe,
      );
      expect(
        draft(TransactionKind.freelanceIncome).direction,
        HeldAmountDirection.owedToMe,
      );
    });

    test('draft serializes the account used by a managed transaction', () {
      const draft = HeldAmountDraft(
        transactionKind: TransactionKind.customIncome,
        amountMinor: 2500,
        currencyCode: 'EGP',
        counterparty: 'Ahmed',
        heldOn: PlainDate(2026, 7, 16),
        accountId: 'account-1',
      );

      expect(draft.toJson()['p_account_id'], 'account-1');
    });
  });

  group('ActiveHeldAmountTotals', () {
    test('separates directions and currencies and excludes settled rows', () {
      final totals = ActiveHeldAmountTotals.from([
        heldAmount(
          id: 'owe-egp',
          direction: HeldAmountDirection.iOwe,
          amountMinor: 1000,
        ),
        heldAmount(
          id: 'owe-usd',
          direction: HeldAmountDirection.iOwe,
          amountMinor: 2000,
          currencyCode: 'USD',
        ),
        heldAmount(
          id: 'owed-egp',
          direction: HeldAmountDirection.owedToMe,
          amountMinor: 3000,
        ),
        heldAmount(
          id: 'settled-owed-egp',
          direction: HeldAmountDirection.owedToMe,
          amountMinor: 4000,
          settledOn: const PlainDate(2026, 7, 16),
        ),
      ]);

      expect(totals.iOweByCurrency, {'EGP': 1000, 'USD': 2000});
      expect(totals.owedToMeByCurrency, {'EGP': 3000});
      expect(
        totals.forDirection(HeldAmountDirection.iOwe),
        totals.iOweByCurrency,
      );
      expect(
        totals.forDirection(HeldAmountDirection.owedToMe),
        totals.owedToMeByCurrency,
      );
    });

    test('adds multiple active amounts in the same bucket', () {
      final totals = ActiveHeldAmountTotals.from([
        heldAmount(
          id: 'first',
          direction: HeldAmountDirection.owedToMe,
          amountMinor: 1200,
        ),
        heldAmount(
          id: 'second',
          direction: HeldAmountDirection.owedToMe,
          amountMinor: 800,
        ),
      ]);

      expect(totals.owedToMeByCurrency, {'EGP': 2000});
      expect(totals.iOweByCurrency, isEmpty);
    });
  });
}
