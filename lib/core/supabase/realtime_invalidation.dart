import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/history/presentation/providers/history_providers.dart';
import 'package:work_tracker/features/reports/presentation/providers/report_providers.dart';
import 'package:work_tracker/features/salary/presentation/providers/salary_providers.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/features/work/presentation/providers/work_providers.dart';

/// Subscribes to user-owned table changes while the authenticated app shell is
/// mounted. Aggregate providers are invalidated after a short debounce and
/// re-fetch from server-side views/RPCs.
final realtimeInvalidationProvider = Provider<void>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return;

  Timer? debounce;
  void scheduleInvalidation() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 450), () {
      ref
        ..invalidate(accountBalancesProvider)
        ..invalidate(allAccountBalancesProvider)
        ..invalidate(recentTransactionsProvider)
        ..invalidate(macrosProvider)
        ..invalidate(heldAmountsProvider)
        ..invalidate(creditFacilitiesProvider)
        ..invalidate(installmentPlansProvider)
        ..invalidate(installmentDuesProvider)
        ..invalidate(incomeSourcesProvider)
        ..invalidate(pendingIncomeProvider)
        ..invalidate(historyPageProvider)
        ..invalidate(cashFlowSummaryProvider)
        ..invalidate(debtSummaryProvider)
        ..invalidate(financeSeriesProvider)
        ..invalidate(expenseCategoryTotalsProvider)
        ..invalidate(allowanceCategoryTotalsProvider)
        ..invalidate(incomeCategoryTotalsProvider)
        ..invalidate(accountBalanceHistoryProvider)
        ..invalidate(workSummaryProvider)
        ..invalidate(workMinutesSeriesProvider)
        ..invalidate(salaryComparisonProvider)
        ..invalidate(salaryWorkPeriodsProvider)
        ..invalidate(workEntriesForMonthProvider)
        ..invalidate(holidaysProvider)
        ..invalidate(salaryPeriodsProvider)
        ..invalidate(salaryPeriodProvider)
        ..invalidate(adjustmentsForRangeProvider)
        ..invalidate(estimateForRangeProvider)
        ..invalidate(currentEstimateProvider)
        ..invalidate(salarySettingsProvider);
    });
  }

  final channel = client.channel('user-data-invalidation-$userId');
  const tables = [
    (schema: AppSchemas.finance, table: 'financial_transactions'),
    (schema: AppSchemas.finance, table: 'accounts'),
    (schema: AppSchemas.finance, table: 'transaction_categories'),
    (schema: AppSchemas.finance, table: 'transaction_macros'),
    (schema: AppSchemas.finance, table: 'transaction_macro_items'),
    (schema: AppSchemas.finance, table: 'held_amounts'),
    (schema: AppSchemas.finance, table: 'credit_facility_settings'),
    (schema: AppSchemas.finance, table: 'installment_plans'),
    (schema: AppSchemas.finance, table: 'installment_dues'),
    (schema: AppSchemas.finance, table: 'installment_payment_allocations'),
    (schema: AppSchemas.finance, table: 'installment_plan_revisions'),
    (schema: AppSchemas.finance, table: 'credit_card_statement_cycles'),
    (schema: AppSchemas.finance, table: 'credit_card_statement_items'),
    (schema: AppSchemas.finance, table: 'credit_card_statement_allocations'),
    (schema: AppSchemas.finance, table: 'credit_card_fee_rules'),
    (schema: AppSchemas.finance, table: 'credit_card_fee_charges'),
    (schema: AppSchemas.finance, table: 'income_sources'),
    (schema: AppSchemas.finance, table: 'income_source_allocations'),
    (schema: AppSchemas.finance, table: 'income_occurrences'),
    (schema: AppSchemas.work, table: 'work_entries'),
    (schema: AppSchemas.work, table: 'official_holidays'),
    (schema: AppSchemas.salary, table: 'salary_periods'),
    (schema: AppSchemas.salary, table: 'salary_adjustments'),
    (schema: AppSchemas.salary, table: 'salary_settings'),
  ];
  for (final tableSpec in tables) {
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: tableSpec.schema,
      table: tableSpec.table,
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: userId,
      ),
      callback: (_) => scheduleInvalidation(),
    );
  }
  channel.subscribe();

  ref.onDispose(() {
    debounce?.cancel();
    unawaited(client.removeChannel(channel));
  });
});
