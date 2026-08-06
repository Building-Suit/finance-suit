import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';
import 'package:work_tracker/features/finance/domain/expense_account_options.dart';

/// The one eligibility rule shared by Add Expense and Edit Expense. It is
/// role-based, so credit cards and BNPL facilities are always treated alike
/// and neither can be forgotten by a hardcoded account-type check.
AccountBalance _asset(
  String id, {
  String name = 'Wallet',
  String currency = 'EGP',
  bool archived = false,
  bool isDefault = false,
  AccountType type = AccountType.cash,
}) => AccountBalance(
  accountId: id,
  name: name,
  accountType: type,
  currencyCode: currency,
  isDefault: isDefault,
  isArchived: archived,
  allowNegativeBalance: false,
  openingBalanceMinor: 0,
  balanceMinor: 100000,
  totalIncomingMinor: 100000,
  totalOutgoingMinor: 0,
);

CreditFacilitySummary _facility(
  String id, {
  required String name,
  AccountType type = AccountType.creditCard,
  String currency = 'EGP',
  bool archived = false,
  FacilityStatus status = FacilityStatus.active,
  int? statementDay = 5,
}) => CreditFacilitySummary(
  accountId: id,
  name: name,
  accountType: type,
  currencyCode: currency,
  isArchived: archived,
  openingOwedMinor: 0,
  creditLimitMinor: 500000,
  defaultDueDay: 10,
  reminderLeadDays: 3,
  outstandingMinor: 0,
  availableCreditMinor: 500000,
  utilizationBasisPoints: 0,
  dueNowMinor: 0,
  overdueMinor: 0,
  activePlanCount: 0,
  facilityStatus: status,
  statementDay: type == AccountType.creditCard ? statementDay : null,
);

void main() {
  final wallet = _asset('asset-1', name: 'Wallet', isDefault: true);
  final card = _facility('card-1', name: 'Visa');
  final bnpl = _facility(
    'bnpl-1',
    name: 'Valu',
    type: AccountType.bnpl,
    statementDay: null,
  );

  group('expenseSourceAccounts', () {
    test('includes active assets, credit cards, and BNPL facilities', () {
      final options = expenseSourceAccounts(
        accounts: [wallet],
        facilities: [card, bnpl],
        currencyCode: 'EGP',
      );

      expect(
        options.map((o) => o.accountId),
        containsAll(<String>['asset-1', 'card-1', 'bnpl-1']),
      );
      // Cash first, then credit, so the picker groups cleanly.
      expect(options.first.group, ExpenseAccountGroup.cash);
      expect(options.last.group, ExpenseAccountGroup.credit);
      expect(
        options.where((o) => o.isLiability).map((o) => o.accountType),
        containsAll(<AccountType>[AccountType.creditCard, AccountType.bnpl]),
      );
    });

    test('excludes archived, frozen, and closed liabilities', () {
      final options = expenseSourceAccounts(
        accounts: [wallet],
        facilities: [
          _facility('archived', name: 'Archived', archived: true),
          _facility('frozen', name: 'Frozen', status: FacilityStatus.frozen),
          _facility(
            'closed',
            name: 'Closed',
            type: AccountType.bnpl,
            status: FacilityStatus.closed,
            statementDay: null,
          ),
        ],
        currencyCode: 'EGP',
      );

      expect(options.map((o) => o.accountId), ['asset-1']);
    });

    test('excludes archived assets but keeps the current historical one', () {
      final archived = _asset('asset-2', name: 'Old', archived: true);

      expect(
        expenseSourceAccounts(
          accounts: [wallet, archived],
          facilities: const [],
          currencyCode: 'EGP',
        ).map((o) => o.accountId),
        ['asset-1'],
      );

      final editing = expenseSourceAccounts(
        accounts: [wallet, archived],
        facilities: const [],
        currencyCode: 'EGP',
        currentAccountId: 'asset-2',
      );
      expect(editing.map((o) => o.accountId), containsAll(['asset-2']));
      expect(
        editing.firstWhere((o) => o.accountId == 'asset-2').isCurrent,
        isTrue,
      );
    });

    test('keeps a closed facility visible while editing its own charge', () {
      final closed = _facility(
        'card-closed',
        name: 'Closed Visa',
        status: FacilityStatus.closed,
      );

      final options = expenseSourceAccounts(
        accounts: [wallet],
        facilities: [closed, card],
        currencyCode: 'EGP',
        currentAccountId: 'card-closed',
      );

      final current = options.firstWhere((o) => o.accountId == 'card-closed');
      expect(current.isCurrent, isTrue);
      // Still not offered to any other transaction.
      expect(
        expenseSourceAccounts(
          accounts: [wallet],
          facilities: [closed, card],
          currencyCode: 'EGP',
        ).map((o) => o.accountId),
        isNot(contains('card-closed')),
      );
    });

    test('filters both roles by currency', () {
      final options = expenseSourceAccounts(
        accounts: [
          wallet,
          _asset('usd', name: 'Dollar', currency: 'USD'),
        ],
        facilities: [
          card,
          _facility('usd-card', name: 'USD Visa', currency: 'USD'),
        ],
        currencyCode: 'EGP',
      );

      expect(options.map((o) => o.accountId), ['asset-1', 'card-1']);
    });

    test('lists an unconfigured card and says what it is missing', () {
      final options = expenseSourceAccounts(
        accounts: const [],
        facilities: [_facility('card-2', name: 'New Visa', statementDay: null)],
        currencyCode: 'EGP',
      );

      expect(options.single.block, ExpenseAccountBlock.cardNotConfigured);
    });

    test('a BNPL facility never needs a statement day', () {
      final options = expenseSourceAccounts(
        accounts: const [],
        facilities: [bnpl],
        currencyCode: 'EGP',
      );

      expect(options.single.block, isNull);
      expect(options.single.accountType, AccountType.bnpl);
    });
  });

  group('assetAccounts', () {
    test('income and cash-only pickers still exclude every liability', () {
      final rows = [
        wallet,
        _asset('card-row', name: 'Visa', type: AccountType.creditCard),
        _asset('bnpl-row', name: 'Valu', type: AccountType.bnpl),
      ];

      expect(rows.assetAccounts.map((a) => a.accountId), ['asset-1']);
    });
  });
}
