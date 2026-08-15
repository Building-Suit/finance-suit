import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/dashboard/presentation/screens/home_screen.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';
import 'package:work_tracker/features/finance/domain/home_due_obligation.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';
import 'package:work_tracker/features/finance/domain/recurring_rule.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/history/domain/history_models.dart';
import 'package:work_tracker/features/history/presentation/providers/history_providers.dart';
import 'package:work_tracker/features/reports/domain/report_models.dart';
import 'package:work_tracker/features/reports/presentation/providers/report_providers.dart';
import 'package:work_tracker/features/salary/domain/salary_settings.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// The Home due-breakdown sheet mirrors the facility Due Breakdown: paid
/// components stay visible checked and struck through, partial components
/// show paid/remaining, and nothing is reconstructed client-side.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  final statementObligation = HomeDueObligation.fromJson({
    'obligation_id': 'statement-1',
    'obligation_kind': 'card_statement',
    'source_account_id': 'card-1',
    'source_name': 'Visa Gold',
    'due_on': PlainDate.today().addDays(6).toIso(),
    'currency_code': 'EGP',
    'remaining_minor': 167000,
    'paid_minor': 33000,
    'details': {
      'statement_due_minor': 200000,
      'total_paid_minor': 33000,
      'items': [
        {
          'id': 'item-1',
          'kind': 'purchase',
          'title': 'OpenAI',
          'occurred_on': '2026-03-05',
          'amount_minor': 70000,
          'paid_minor': 3000,
          'remaining_minor': 67000,
          'payment_status': 'partially_paid',
        },
        {
          'id': 'item-2',
          'kind': 'purchase',
          'title': 'Netflix',
          'occurred_on': '2026-03-06',
          'amount_minor': 30000,
          'paid_minor': 30000,
          'remaining_minor': 0,
          'payment_status': 'paid',
        },
        {
          'id': 'item-3',
          'kind': 'fee',
          'title': 'Solidarity insurance',
          'occurred_on': '2026-03-07',
          'amount_minor': 2500,
          'paid_minor': 0,
          'remaining_minor': 2500,
          'payment_status': 'unpaid',
        },
      ],
      'installments': [
        {
          'id': 'due-1',
          'title': 'Samsung Monitor',
          'sequence_number': 2,
          'installment_count': 6,
          'due_on': PlainDate.today().addDays(6).toIso(),
          'amount_minor': 100000,
          'paid_minor': 0,
          'remaining_minor': 100000,
          'payment_status': 'unpaid',
        },
      ],
    },
  });

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('user-1'),
          accountBalancesProvider.overrideWith(
            (ref) async => const <AccountBalance>[],
          ),
          allAccountBalancesProvider.overrideWith(
            (ref) async => const <AccountBalance>[],
          ),
          creditFacilitiesProvider.overrideWith(
            (ref) async => const <CreditFacilitySummary>[],
          ),
          homeUpcomingObligationsProvider.overrideWith(
            (ref) async => HomeDueSummary(
              today: PlainDate.today(),
              items: [statementObligation],
            ),
          ),
          pendingIncomeProvider.overrideWith(
            (ref) async => const <PendingIncome>[],
          ),
          pendingRecurringProvider.overrideWith(
            (ref) async => const <PendingRecurring>[],
          ),
          homeCashFlowSummaryProvider.overrideWith(
            (ref, range) async => const <CashFlowSummary>[],
          ),
          salarySettingsProvider.overrideWith(
            (ref) => Completer<SalarySettings>().future,
          ),
          historyPageProvider.overrideWith(
            (ref, query) async => const HistoryPage(items: [], hasMore: false),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HomeScreen(),
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  testWidgets('sheet shows paid, partial, and unpaid component states', (
    tester,
  ) async {
    await pumpHome(tester);

    await tester.dragUntilVisible(
      find.byKey(const Key('home-due-thisMonth')),
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('home-due-thisMonth')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    // Localized header, not the old hardcoded English strings.
    expect(find.text('Due breakdown'), findsOneWidget);

    // Expand the statement obligation group.
    await tester.tap(find.byKey(const ValueKey('due-obligation-statement-1')));
    await tester.pumpAndSettle();

    // Totals reflect server-side paid state.
    expect(find.text('Total due'), findsOneWidget);
    expect(find.text('Left to pay'), findsOneWidget);

    // Paid rows stay visible, muted and struck through.
    final netflix = tester.widget<Text>(find.text('Netflix'));
    expect(netflix.style?.decoration, TextDecoration.lineThrough);
    expect(find.text('Paid in full'), findsOneWidget);

    // Partial rows show paid/total and remaining, never struck through.
    final openai = tester.widget<Text>(find.text('OpenAI'));
    expect(openai.style?.decoration, isNot(TextDecoration.lineThrough));
    expect(find.textContaining('Paid 30.00'), findsOneWidget);
    expect(find.textContaining('670.00 EGP left'), findsOneWidget);

    // Unpaid rows render plainly inside their groups.
    expect(find.text('Solidarity insurance'), findsOneWidget);
    expect(find.text('Samsung Monitor'), findsOneWidget);
    expect(find.text('Installments'), findsOneWidget);
    expect(find.text('Fees & interest'), findsOneWidget);
    expect(find.text('Purchases'), findsOneWidget);
  });

  testWidgets('legacy payloads without paid state still render as unpaid', (
    tester,
  ) async {
    await pumpHome(tester);
    final legacy = HomeDueObligation.fromJson({
      'obligation_id': 'legacy-1',
      'obligation_kind': 'card_statement',
      'source_name': 'Old Card',
      'due_on': PlainDate.today().toIso(),
      'currency_code': 'EGP',
      'remaining_minor': 5000,
      'details': {
        'items': [
          {'id': 'x', 'title': 'Old charge', 'amount_minor': 5000},
        ],
      },
    });
    final components = legacy.components;
    expect(components.single.status.dbValue, 'unpaid');
    expect(components.single.remainingMinor, 5000);
    expect(legacy.paidMinor, 0);
  });
}
