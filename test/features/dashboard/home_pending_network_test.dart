import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/dashboard/presentation/screens/home_screen.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';
import 'package:work_tracker/features/finance/domain/recurring_rule.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/history/domain/history_models.dart';
import 'package:work_tracker/features/history/presentation/providers/history_providers.dart';
import 'package:work_tracker/features/network/domain/network_models.dart';
import 'package:work_tracker/features/network/presentation/providers/network_providers.dart';
import 'package:work_tracker/features/reports/domain/report_models.dart';
import 'package:work_tracker/features/reports/presentation/providers/report_providers.dart';
import 'package:work_tracker/features/salary/domain/salary_settings.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// An incoming pending network transfer surfaces on Home like the pending
/// income and recurring cards do. Only the receiver gets the card; the money
/// is not in any balance yet.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  final incoming = NetworkTransfer(
    id: 'transfer-1',
    direction: NetworkDirection.incoming,
    counterpartyAlias: 'Tarek',
    amountMinor: 50000,
    currencyCode: 'EGP',
    status: NetworkTransferStatus.pending,
    requestedOn: PlainDate.today(),
    requestedAt: DateTime.now().toUtc(),
    origin: NetworkTransferOrigin.manual,
    connectionActive: true,
    connectionId: 'connection-1',
  );
  final sent = NetworkTransfer(
    id: 'transfer-2',
    direction: NetworkDirection.outgoing,
    counterpartyAlias: 'Wife',
    amountMinor: 70000,
    currencyCode: 'EGP',
    status: NetworkTransferStatus.pending,
    requestedOn: PlainDate.today(),
    requestedAt: DateTime.now().toUtc(),
    origin: NetworkTransferOrigin.manual,
    connectionActive: true,
    connectionId: 'connection-1',
  );

  Future<void> pumpHome(
    WidgetTester tester,
    List<NetworkTransfer> transfers,
  ) async {
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
          pendingIncomeProvider.overrideWith(
            (ref) async => const <PendingIncome>[],
          ),
          pendingRecurringProvider.overrideWith(
            (ref) async => const <PendingRecurring>[],
          ),
          networkTransfersProvider.overrideWith((ref) async => transfers),
          cashFlowSummaryProvider.overrideWith(
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the receiver sees the pending network card', (tester) async {
    await pumpHome(tester, [incoming]);
    expect(
      find.byKey(const Key('home-pending-network-summary')),
      findsOneWidget,
    );
    expect(find.text('Network transfers to review'), findsOneWidget);
    expect(find.textContaining('Tarek sent you'), findsOneWidget);
    expect(find.text('Pending transfer'), findsOneWidget);
  });

  testWidgets('the sender gets no card for their own pending transfer', (
    tester,
  ) async {
    await pumpHome(tester, [sent]);
    expect(find.byKey(const Key('home-pending-network-summary')), findsNothing);
  });
}
