import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/widgets/app_selection_field.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/screens/income_source_form_screen.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

void main() {
  const accounts = [
    AccountBalance(
      accountId: 'default',
      name: 'Default',
      accountType: AccountType.current,
      currencyCode: 'EGP',
      isDefault: true,
      isArchived: false,
      allowNegativeBalance: false,
      openingBalanceMinor: 0,
      balanceMinor: 125000,
      totalIncomingMinor: 125000,
      totalOutgoingMinor: 0,
    ),
    AccountBalance(
      accountId: 'savings',
      name: 'Savings',
      accountType: AccountType.savings,
      currencyCode: 'EGP',
      isDefault: false,
      isArchived: false,
      allowNegativeBalance: false,
      openingBalanceMinor: 0,
      balanceMinor: 0,
      totalIncomingMinor: 0,
      totalOutgoingMinor: 0,
    ),
    AccountBalance(
      accountId: 'extra-savings',
      name: 'Extra Savings',
      accountType: AccountType.savings,
      currencyCode: 'EGP',
      isDefault: false,
      isArchived: false,
      allowNegativeBalance: false,
      openingBalanceMinor: 0,
      balanceMinor: 0,
      totalIncomingMinor: 0,
      totalOutgoingMinor: 0,
    ),
    AccountBalance(
      accountId: 'bills',
      name: 'Bills',
      accountType: AccountType.bank,
      currencyCode: 'EGP',
      isDefault: false,
      isArchived: false,
      allowNegativeBalance: false,
      openingBalanceMinor: 0,
      balanceMinor: 0,
      totalIncomingMinor: 0,
      totalOutgoingMinor: 0,
    ),
  ];

  const salary = IncomeSource(
    id: 'salary',
    name: 'Salary',
    kind: IncomeSourceKind.salary,
    expectedAmountMinor: 4000000,
    currencyCode: 'EGP',
    paymentDay: 5,
    startDate: PlainDate(2026, 1, 1),
    promptDaysBefore: 2,
    primaryAccountId: 'default',
    isActive: true,
    includeExtraWorkInPercentage: false,
    extraWorkDestinationAccountId: 'extra-savings',
    rolloverBalanceEnabled: true,
    rolloverDestinationAccountId: 'savings',
    allocations: [
      IncomeAllocation(
        destinationAccountId: 'bills',
        method: IncomeAllocationMethod.percentage,
        percentageBasisPoints: 2500,
      ),
    ],
  );

  testWidgets(
    'fixed salary split keeps protected routing and explains every destination',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountBalancesProvider.overrideWith((ref) async => accounts),
            categoriesProvider.overrideWith((ref, kind) async => const []),
            incomeSourcesProvider.overrideWith((ref) async => const [salary]),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const IncomeSourceFormScreen(existing: salary),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final includeExtra = find.text(
        'Include extra hours and days in percentage calculations',
      );
      final protectedRouting = find.text(
        'Route all protected extra-work earnings to another account',
      );
      expect(includeExtra, findsOneWidget);
      expect(protectedRouting, findsOneWidget);

      final splitMethod = find.byType(
        AppSelectionField<IncomeAllocationMethod>,
      );
      expect(splitMethod, findsOneWidget);
      await tester.ensureVisible(splitMethod);
      await tester.tap(splitMethod);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fixed amount').last);
      await tester.pumpAndSettle();

      expect(includeExtra, findsNothing);
      expect(protectedRouting, findsOneWidget);
      expect(find.text('Move the previous balance to savings'), findsOneWidget);
      expect(find.text('Previous-balance destination'), findsOneWidget);

      final summary = find.text('Summary preview');
      await tester.ensureVisible(summary);
      await tester.pumpAndSettle();

      expect(summary, findsOneWidget);
      expect(find.textContaining('enters Default first'), findsOneWidget);
      expect(find.textContaining('fixed'), findsOneWidget);
      expect(
        find.text('Protected extra-work earnings go to Extra Savings.'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'any positive existing balance in Default moves to Savings',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
