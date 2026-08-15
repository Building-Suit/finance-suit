// Play Store screenshot generator: renders every major screen with rich
// sample data at 1080x2160 (2:1 — Play-compliant for phone screenshots).
//
// Not part of the normal test suite (it lives outside test/): run with
//   flutter test tool/screenshots/play_store_screenshots_test.dart
// PNGs land in build/play-screenshots/. The app's bundled fonts (Manrope,
// IBM Plex Sans Arabic) are loaded from assets so text renders exactly as
// in production.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/result/result.dart';
import 'package:work_tracker/core/supabase/realtime_invalidation.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/auth/presentation/controllers/auth_controller.dart';
import 'package:work_tracker/features/commercial/domain/commercial_models.dart';
import 'package:work_tracker/features/commercial/presentation/providers/commercial_providers.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/card_fee_rule.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';
import 'package:work_tracker/features/finance/domain/facility_activity.dart';
import 'package:work_tracker/features/finance/domain/facility_payment_component.dart';
import 'package:work_tracker/features/finance/domain/financial_transaction.dart';
import 'package:work_tracker/features/finance/domain/held_amount.dart';
import 'package:work_tracker/features/finance/domain/home_due_obligation.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';
import 'package:work_tracker/features/finance/domain/installment_responsibility.dart';
import 'package:work_tracker/features/finance/domain/recurring_rule.dart';
import 'package:work_tracker/features/finance/domain/transaction_category.dart';
import 'package:work_tracker/features/finance/domain/transaction_macro.dart';
import 'package:work_tracker/features/finance/domain/transaction_query.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/providers/responsibility_providers.dart';
import 'package:work_tracker/features/history/data/history_repository.dart';
import 'package:work_tracker/features/history/domain/history_models.dart';
import 'package:work_tracker/features/history/presentation/providers/history_providers.dart';
import 'package:work_tracker/features/network/domain/network_models.dart';
import 'package:work_tracker/features/network/presentation/providers/network_providers.dart';
import 'package:work_tracker/features/onboarding/presentation/providers/onboarding_status_provider.dart';
import 'package:work_tracker/features/reports/domain/report_models.dart';
import 'package:work_tracker/features/reports/presentation/providers/report_providers.dart';
import 'package:work_tracker/features/salary/domain/salary_adjustment.dart';
import 'package:work_tracker/features/salary/domain/salary_estimate.dart';
import 'package:work_tracker/features/salary/domain/salary_period.dart';
import 'package:work_tracker/features/salary/domain/salary_settings.dart';
import 'package:work_tracker/features/salary/presentation/providers/salary_providers.dart';
import 'package:work_tracker/features/settings/domain/user_profile.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/features/work/domain/official_holiday.dart';
import 'package:work_tracker/features/work/domain/work_entry.dart';
import 'package:work_tracker/features/work/presentation/providers/work_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class _FakeAuthNotifier extends AuthStateNotifier {
  @override
  AuthStateData build() =>
      const AuthStateData(phase: AuthPhase.signedIn, userId: 'user-1');
}

class _FakeOnboardingNotifier extends OnboardingStatusNotifier {
  @override
  OnboardingStatus build() => OnboardingStatus.complete;
}

class _FakeHistoryRepository implements HistoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #fetchHistory) {
      return Future<Result<HistoryPage>>.value(
        Ok(HistoryPage(items: _historyItems, hasMore: false)),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

// ---------------------------------------------------------------------------
// One consistent sample story (EGP, family & friends network, Aug dues)
// ---------------------------------------------------------------------------

final _today = PlainDate.today();

AccountBalance _account(
  String id,
  String name,
  String type,
  int balance, {
  String currency = 'EGP',
  bool isDefault = false,
}) => AccountBalance.fromJson({
  'account_id': id,
  'name': name,
  'account_type': type,
  'currency_code': currency,
  'is_default': isDefault,
  'is_archived': false,
  'allow_negative_balance': false,
  'opening_balance_minor': 0,
  'balance_minor': balance,
  'total_incoming_minor': balance,
  'total_outgoing_minor': 0,
});

final _accounts = [
  _account('wallet-1', 'Main Wallet', 'cash', 1245000, isDefault: true),
  _account('bank-1', 'CIB Current', 'current', 4830025),
  _account('savings-1', 'Savings', 'savings', 12500000),
  _account('usd-1', 'USD Wallet', 'wallet', 32000, currency: 'USD'),
];

final _visa = CreditFacilitySummary.fromJson({
  'account_id': 'facility-1',
  'name': 'Visa Gold',
  'account_type': 'credit_card',
  'currency_code': 'EGP',
  'is_archived': false,
  'notes': null,
  'opening_owed_minor': 0,
  'credit_limit_minor': 2000000,
  'statement_day': 10,
  'default_due_day': 25,
  'last_four_digits': '4242',
  'reminder_lead_days': 3,
  'outstanding_minor': 421259,
  'available_credit_minor': 1578741,
  'utilization_basis_points': 2106,
  'due_now_minor': 261078,
  'overdue_minor': 0,
  'next_due_on': _today.addDays(6).toIso(),
  'next_due_amount_minor': 261078,
  'active_plan_count': 2,
  'color_hex': '#B45309',
});

final _valu = CreditFacilitySummary.fromJson({
  'account_id': 'facility-2',
  'name': 'ValU',
  'account_type': 'bnpl',
  'currency_code': 'EGP',
  'is_archived': false,
  'notes': null,
  'opening_owed_minor': 0,
  'credit_limit_minor': 1000000,
  'statement_day': null,
  'default_due_day': 1,
  'last_four_digits': null,
  'reminder_lead_days': 3,
  'outstanding_minor': 180000,
  'available_credit_minor': 820000,
  'utilization_basis_points': 1800,
  'due_now_minor': 45000,
  'overdue_minor': 0,
  'next_due_on': _today.addDays(12).toIso(),
  'next_due_amount_minor': 45000,
  'active_plan_count': 1,
  'color_hex': '#0F766E',
});

final _dues = HomeDueSummary(
  today: _today,
  items: [
    HomeDueObligation(
      id: 'statement-1',
      kind: 'card_statement',
      sourceAccountId: 'facility-1',
      sourceName: 'Visa Gold',
      dueOn: _today.addDays(6),
      currencyCode: 'EGP',
      remainingMinor: 261078,
      details: {
        'items': [
          {
            'title': 'OpenAI',
            'occurred_on': _today.addDays(-20).toIso(),
            'remaining_minor': 99999,
          },
          {
            'title': 'Solidarity insurance',
            'occurred_on': _today.addDays(-12).toIso(),
            'remaining_minor': 2500,
          },
          {
            'title': 'Monthly interest',
            'occurred_on': _today.addDays(-9).toIso(),
            'remaining_minor': 10996,
          },
        ],
        'installments': [
          {
            'title': 'Al Araby installment',
            'sequence_number': 4,
            'installment_count': 12,
            'due_on': _today.addDays(6).toIso(),
            'remaining_minor': 104994,
          },
          {
            'title': 'Samsung Monitor',
            'sequence_number': 2,
            'installment_count': 6,
            'due_on': _today.addDays(6).toIso(),
            'remaining_minor': 42589,
          },
        ],
      },
    ),
    HomeDueObligation(
      id: 'due-valu',
      kind: 'installment_due',
      sourceAccountId: 'facility-2',
      sourceName: 'ValU',
      dueOn: _today.addDays(12),
      currencyCode: 'EGP',
      remainingMinor: 45000,
    ),
    HomeDueObligation(
      id: 'recurring-internet',
      kind: 'recurring_expense',
      sourceName: 'Internet',
      dueOn: _today.addDays(9),
      currencyCode: 'EGP',
      remainingMinor: 60000,
    ),
    HomeDueObligation(
      id: 'due-next-month',
      kind: 'installment_due',
      sourceAccountId: 'facility-1',
      sourceName: 'Visa Gold',
      dueOn: PlainDate(
        _today.month == 12 ? _today.year + 1 : _today.year,
        _today.month == 12 ? 1 : _today.month + 1,
        25,
      ),
      currencyCode: 'EGP',
      remainingMinor: 104994,
    ),
  ],
);

final _cashflow = [
  const CashFlowSummary(
    currencyCode: 'EGP',
    startingBalanceMinor: 15200000,
    incomeMinor: 4520000,
    expensesMinor: 2315000,
    allowancesMinor: 180000,
    netMinor: 2025000,
    endingBalanceMinor: 17225000,
  ),
];

final _estimate = SalaryEstimate(
  periodStart: PlainDate(_today.year, _today.month, 1),
  periodEnd: _today.addDays(20),
  expectedPaymentDate: _today.addDays(22),
  currencyCode: 'EGP',
  baseSalaryMinor: 3200000,
  dayRateMinor: 106667,
  hourRateMinor: 13333,
  extraDayUnitsHundredths: 100,
  extraDayAmountMinor: 106667,
  holidayCount: 1,
  holidayAmountMinor: 106667,
  overtimeMinutes: 180,
  overtimeAmountMinor: 60000,
  bonusesMinor: 50000,
  deductionsMinor: 0,
  warnings: const [],
);

List<SalaryPeriod> get _periods {
  SalaryPeriod period(int monthsBack, String status, {int? actual}) {
    final start = PlainDate(
      _today.year,
      _today.month,
      1,
    ).addMonths(-monthsBack);
    final end = start.addMonths(1).addDays(-1);
    return SalaryPeriod.fromJson({
      'id': 'period-$monthsBack',
      'period_start': start.toIso(),
      'period_end': end.toIso(),
      'expected_payment_date': end.addDays(3).toIso(),
      'status': status,
      'actual_amount_minor': actual,
      'received_date': actual == null ? null : end.addDays(3).toIso(),
    });
  }

  return [
    period(0, 'open'),
    period(1, 'paid', actual: 3466667),
    period(2, 'paid', actual: 3200000),
  ];
}

final _historyItems = [
  for (final (i, row) in const [
    ('Salary — August', 'income', 3466667),
    ('Groceries', 'expense', 84500),
    ('Uber', 'expense', 12750),
    ('Transfer to Savings', 'transfer', 500000),
    ('Netflix', 'expense', 24999),
  ].indexed)
    HistoryItem(
      id: 'history-$i',
      group: HistoryItemGroup.transaction,
      recordType: row.$2,
      recordDate: _today.addDays(-i - 1),
      createdAt: DateTime.now().subtract(Duration(days: i + 1)),
      sortAt: DateTime.now().subtract(Duration(days: i + 1)),
      amountMinor: row.$3,
      currencyCode: 'EGP',
      sourceAccountId: 'bank-1',
      title: row.$1,
    ),
];

final _transactions = [
  for (final (i, row) in const [
    ('Groceries — Carrefour', 'expense', 84500),
    ('Uber to work', 'expense', 12750),
    ('Salary — August', 'custom_income', 3466667),
    ('Netflix', 'expense', 24999),
    ('Transfer to Savings', 'transfer', 500000),
    ('Pharmacy', 'expense', 31200),
    ('OpenAI', 'expense', 99999),
    ('Pocket money', 'allowance_given', 20000),
  ].indexed)
    FinancialTransaction(
      id: 'tx-$i',
      kind: TransactionKind.values.firstWhere((k) => k.dbValue == row.$2),
      occurredOn: _today.addDays(-i),
      amountMinor: row.$3,
      currencyCode: 'EGP',
      sourceAccountId: row.$2 == 'custom_income' ? null : 'bank-1',
      destinationAccountId: row.$2 == 'expense' ? null : 'savings-1',
      categoryId: 'cat-1',
      title: row.$1,
      sortAt: DateTime.utc(2026, 8, 1, 12, 0, i),
    ),
];

final _categories = [
  for (final (i, row) in const [
    ('Groceries', 'expense'),
    ('Transport', 'expense'),
    ('Subscriptions', 'expense'),
    ('Salary', 'income'),
  ].indexed)
    TransactionCategory(
      id: 'cat-${i + 1}',
      name: row.$1,
      kind: row.$2 == 'expense' ? CategoryKind.expense : CategoryKind.income,
      icon: 'category',
      sortOrder: i,
      isArchived: false,
    ),
];

final _contacts = [
  NetworkContact(
    connectionId: 'connection-1',
    otherUserId: 'user-2',
    localAlias: 'Sara',
    realDisplayName: 'Sara Hassan',
    email: 'sara@example.com',
    connectedAt: DateTime.utc(2026, 6, 1),
  ),
  NetworkContact(
    connectionId: 'connection-2',
    otherUserId: 'user-3',
    localAlias: 'Dad',
    realDisplayName: 'Hassan Mahmoud',
    email: 'hassan@example.com',
    connectedAt: DateTime.utc(2026, 5, 10),
  ),
];

final _transfers = [
  NetworkTransfer(
    id: 'transfer-1',
    direction: NetworkDirection.incoming,
    counterpartyAlias: 'Sara',
    amountMinor: 75000,
    currencyCode: 'EGP',
    status: NetworkTransferStatus.pending,
    requestedOn: _today,
    requestedAt: DateTime.now(),
    origin: NetworkTransferOrigin.manual,
    connectionActive: true,
    connectionId: 'connection-1',
    sharedNote: 'Dinner split',
  ),
  NetworkTransfer(
    id: 'transfer-2',
    direction: NetworkDirection.outgoing,
    counterpartyAlias: 'Dad',
    amountMinor: 120000,
    currencyCode: 'EGP',
    status: NetworkTransferStatus.accepted,
    requestedOn: _today.addDays(-3),
    requestedAt: DateTime.now().subtract(const Duration(days: 3)),
    respondedAt: DateTime.now().subtract(const Duration(days: 3)),
    origin: NetworkTransferOrigin.manual,
    connectionActive: true,
    connectionId: 'connection-2',
  ),
];

final _workEntries = [
  for (var day = 1; day <= 12; day++)
    if (PlainDate(_today.year, _today.month, day).toDateTime().weekday <= 4)
      WorkEntry(
        id: 'work-$day',
        workDate: PlainDate(_today.year, _today.month, day),
        entryType: WorkEntryType.regular,
        breakMinutes: 60,
        startMinuteOfDay: 9 * 60,
        endMinuteOfDay: 17 * 60,
        durationMinutes: 420,
      ),
  WorkEntry(
    id: 'work-ot',
    workDate: PlainDate(_today.year, _today.month, 5),
    entryType: WorkEntryType.overtime,
    breakMinutes: 0,
    durationMinutes: 120,
    multiplierPct: 150,
    computedAmountMinor: 40000,
  ),
  WorkEntry(
    id: 'work-extra',
    workDate: PlainDate(_today.year, _today.month, 6),
    entryType: WorkEntryType.extraDay,
    breakMinutes: 0,
    dayUnitsHundredths: 100,
    computedAmountMinor: 106667,
  ),
];

final _breakdown = FacilityDueBreakdown.fromJson({
  'account_id': 'facility-1',
  'account_type': 'credit_card',
  'currency_code': 'EGP',
  'as_of': _today.toIso(),
  'outstanding_minor': 421259,
  'total_due_minor': 299981,
  'paid_minor': 38903,
  'remaining_minor': 261078,
  'additional_balance_minor': 160181,
  'minimum_due_minor': 21063,
  'minimum_remaining_minor': 21063,
  'components': [
    {
      'component_type': 'installment_due',
      'component_id': 'due-1',
      'title': 'Al Araby installment',
      'activity_kind': 'installment_due',
      'sequence_number': 4,
      'installment_count': 12,
      'occurred_on': _today.addDays(6).toIso(),
      'amount_minor': 104994,
      'paid_minor': 0,
      'remaining_minor': 104994,
      'payment_status': 'unpaid',
      'scope': 'current',
    },
    {
      'component_type': 'installment_due',
      'component_id': 'due-2',
      'title': 'Samsung Monitor',
      'activity_kind': 'installment_due',
      'sequence_number': 2,
      'installment_count': 6,
      'occurred_on': _today.addDays(6).toIso(),
      'amount_minor': 55187,
      'paid_minor': 12598,
      'remaining_minor': 42589,
      'payment_status': 'partially_paid',
      'scope': 'current',
    },
    {
      'component_type': 'statement_item',
      'component_id': 'item-1',
      'title': 'Solidarity insurance',
      'activity_kind': 'fee_charge',
      'fee_type': 'insurance',
      'occurred_on': _today.addDays(-12).toIso(),
      'amount_minor': 2500,
      'paid_minor': 0,
      'remaining_minor': 2500,
      'payment_status': 'unpaid',
      'scope': 'current',
    },
    {
      'component_type': 'statement_item',
      'component_id': 'item-2',
      'title': 'Monthly interest',
      'activity_kind': 'purchase_interest',
      'fee_type': 'purchase_interest',
      'occurred_on': _today.addDays(-9).toIso(),
      'amount_minor': 10996,
      'paid_minor': 0,
      'remaining_minor': 10996,
      'payment_status': 'unpaid',
      'scope': 'current',
    },
    {
      'component_type': 'statement_item',
      'component_id': 'item-3',
      'title': 'OpenAI',
      'activity_kind': 'ordinary_expense',
      'occurred_on': _today.addDays(-20).toIso(),
      'amount_minor': 99999,
      'paid_minor': 0,
      'remaining_minor': 99999,
      'payment_status': 'unpaid',
      'scope': 'current',
    },
    {
      'component_type': 'statement_item',
      'component_id': 'item-4',
      'title': 'Netflix',
      'activity_kind': 'ordinary_expense',
      'occurred_on': _today.addDays(-24).toIso(),
      'amount_minor': 24999,
      'paid_minor': 24999,
      'remaining_minor': 0,
      'payment_status': 'paid',
      'scope': 'current',
    },
  ],
});

final _statement = CardStatementSummary.fromJson({
  'id': 'cycle-1',
  'account_id': 'facility-1',
  'currency_code': 'EGP',
  'cycle_start': _today.addDays(-40).toIso(),
  'cycle_close': _today.addDays(-9).toIso(),
  'due_on': _today.addDays(6).toIso(),
  'charges_minor': 152493,
  'paid_minor': 38903,
  'remaining_minor': 127594,
  'minimum_due_minor': 21063,
  'cycle_status': 'upcoming',
  'ordinary_statement_charges_minor': 124998,
  'fee_charges_minor': 13496,
  'installment_due_minor': 160181,
  'total_statement_due_minor': 299981,
  'total_paid_minor': 38903,
  'total_remaining_minor': 261078,
  'obligation_status': 'upcoming',
});

final _plans = [
  InstallmentPlan.fromJson({
    'id': 'plan-1',
    'account_id': 'facility-1',
    'title': 'Al Araby Fridge',
    'category_id': 'cat-1',
    'purchased_on': _today.addMonths(-4).toIso(),
    'first_due_on': _today.addMonths(-3).toIso(),
    'installment_count': 12,
    'purchase_price_minor': 1259928,
    'down_payment_minor': 0,
    'financed_principal_minor': 1259928,
    'financing_fees_minor': 0,
    'total_payable_minor': 1259928,
    'currency_code': 'EGP',
    'status': 'active',
    'paid_minor': 314982,
    'remaining_minor': 944946,
    'next_due_on': _today.addDays(6).toIso(),
    'next_due_amount_minor': 104994,
    'notes': null,
  }),
  InstallmentPlan.fromJson({
    'id': 'plan-2',
    'account_id': 'facility-1',
    'title': 'Samsung Monitor',
    'category_id': 'cat-1',
    'purchased_on': _today.addMonths(-2).toIso(),
    'first_due_on': _today.addMonths(-1).toIso(),
    'installment_count': 6,
    'purchase_price_minor': 331122,
    'down_payment_minor': 0,
    'financed_principal_minor': 331122,
    'financing_fees_minor': 0,
    'total_payable_minor': 331122,
    'currency_code': 'EGP',
    'status': 'active',
    'paid_minor': 67785,
    'remaining_minor': 263337,
    'next_due_on': _today.addDays(6).toIso(),
    'next_due_amount_minor': 42589,
    'notes': null,
  }),
];

final _linkDetails = SharedInstallmentLinkDetails.fromJson({
  'link': {
    'id': 'link-1',
    'link_type': 'network',
    'status': 'accepted',
    'viewer_role': 'owner',
    'counterparty_name': 'Dad',
    'shared_note': 'Fridge for the family home',
    'responsibility_from_sequence': 1,
    'plan_revision_at_request': 1,
    'requested_at': '2026-06-14T09:00:00Z',
    'accepted_at': '2026-06-14T10:00:00Z',
    'rejected_at': null,
    'removed_at': null,
    'connection_active': true,
  },
  'snapshot': {'title': 'Al Araby Fridge', 'currency_code': 'EGP'},
  'current': {
    'title': 'Al Araby Fridge',
    'owner_display_name': 'Omar',
    'facility_name': 'Visa Gold',
    'facility_type': 'credit_card',
    'category_name': 'Home',
    'purchased_on': _today.addMonths(-4).toIso(),
    'first_due_on': _today.addMonths(-3).toIso(),
    'currency_code': 'EGP',
    'purchase_price_minor': 1259928,
    'down_payment_minor': 0,
    'financed_principal_minor': 1259928,
    'financing_fees_minor': 0,
    'interest_minor': 0,
    'total_payable_minor': 1259928,
    'pricing_method': 'manual_fees',
    'interest_rate_basis_points': null,
    'interest_rate_period': null,
    'interest_method': 'flat',
    'installment_count': 12,
    'paid_installment_count': 3,
    'responsibility_from_sequence': 1,
    'remaining_count': 9,
    'remaining_total_minor': 944946,
    'next_due_on': _today.addDays(6).toIso(),
    'final_due_on': _today.addMonths(8).toIso(),
    'typical_installment_minor': 104994,
    'plan_status': 'active',
    'terms_changed': false,
  },
  'schedule': [
    for (var i = 1; i <= 4; i++)
      {
        'due_id': 'due-$i',
        'sequence_number': i,
        'due_on': _today.addMonths(i - 3).toIso(),
        'amount_minor': 104994,
        'received_minor': i <= 2 ? 104994 : 0,
        'pending_minor': 0,
        'remaining_minor': i <= 2 ? 0 : 104994,
        'reimbursement_status': i <= 2 ? 'received' : 'not_paid',
      },
  ],
  'reimbursement_summary': {
    'expected_total_minor': 1259928,
    'received_total_minor': 209988,
    'pending_total_minor': 0,
    'remaining_total_minor': 1049940,
  },
});

final _recurringRules = [
  RecurringRule.fromJson({
    'id': 'rule-1',
    'name': 'Internet',
    'rule_kind': 'expense',
    'amount_minor': 60000,
    'currency_code': 'EGP',
    'frequency': 'monthly',
    'payment_day': 20,
    'start_date': '2026-01-01',
    'prompt_days_before': 2,
    'source_account_id': 'bank-1',
    'is_active': true,
    'destination_account_id': null,
    'category_id': 'cat-3',
    'notes': null,
  }),
  RecurringRule.fromJson({
    'id': 'rule-2',
    'name': 'To Savings',
    'rule_kind': 'transfer',
    'amount_minor': 500000,
    'currency_code': 'EGP',
    'frequency': 'monthly',
    'payment_day': 1,
    'start_date': '2026-01-01',
    'prompt_days_before': 0,
    'source_account_id': 'bank-1',
    'is_active': true,
    'destination_account_id': 'savings-1',
    'category_id': null,
    'notes': null,
  }),
];

final _pendingRecurring = [
  PendingRecurring(
    rule: _recurringRules.first,
    occurrence: RecurringOccurrence.fromJson({
      'id': 'occ-1',
      'rule_id': 'rule-1',
      'scheduled_on': _today.toIso(),
      'expected_amount_minor': 60000,
      'status': 'pending',
      'actual_amount_minor': null,
      'paid_on': null,
      'transaction_id': null,
      'snoozed_until': null,
      'notes': null,
    }),
  ),
];

final _salarySource = IncomeSource(
  id: 'salary-source',
  name: 'Monthly salary',
  kind: IncomeSourceKind.salary,
  expectedAmountMinor: 3200000,
  currencyCode: 'EGP',
  paymentDay: 5,
  startDate: const PlainDate(2026, 1, 1),
  promptDaysBefore: 2,
  primaryAccountId: 'bank-1',
  isActive: true,
  allocations: const [
    IncomeAllocation(
      id: 'alloc-1',
      method: IncomeAllocationMethod.percentage,
      destinationAccountId: 'savings-1',
      percentageBasisPoints: 2000,
    ),
  ],
);

final _pendingIncome = [
  PendingIncome(
    source: _salarySource,
    occurrence: IncomeOccurrence(
      id: 'salary-occurrence',
      incomeSourceId: 'salary-source',
      scheduledOn: _today.addDays(2),
      expectedAmountMinor: 3466667,
      status: IncomeOccurrenceStatus.pending,
    ),
  ),
];

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

List<dynamic> _overrides() {
  final bounds = SalaryPeriods.boundsFor(SalarySettings.defaults, _today);
  return [
    realtimeInvalidationProvider.overrideWith((ref) {}),
    currentUserIdProvider.overrideWithValue('user-1'),
    authStateProvider.overrideWith(_FakeAuthNotifier.new),
    onboardingStatusProvider.overrideWith(_FakeOnboardingNotifier.new),
    effectiveEntitlementProvider.overrideWith(
      (ref) async => EffectiveEntitlement.free(),
    ),
    // Finance.
    accountBalancesProvider.overrideWith((ref) async => _accounts),
    allAccountBalancesProvider.overrideWith((ref) async => _accounts),
    transactionsPageProvider.overrideWith(
      (ref, query) async =>
          TransactionPage(items: _transactions, hasMore: false),
    ),
    heldAmountsProvider.overrideWith((ref) async => const <HeldAmount>[]),
    creditFacilitiesProvider.overrideWith((ref) async => [_visa, _valu]),
    allCreditFacilitiesProvider.overrideWith((ref) async => [_visa, _valu]),
    installmentPlansProvider.overrideWith((ref, accountId) async => _plans),
    installmentDuesProvider.overrideWith(
      (ref, accountId) async => const <InstallmentDue>[],
    ),
    statementSummariesProvider.overrideWith(
      (ref, accountId) async => [_statement],
    ),
    facilityActivityProvider.overrideWith(
      (ref, accountId) async => const <FacilityActivityItem>[],
    ),
    feeRulesProvider.overrideWith(
      (ref, accountId) async => const <CardFeeRule>[],
    ),
    facilityDueBreakdownProvider.overrideWith((ref, args) async => _breakdown),
    paymentAllocationsProvider.overrideWith(
      (ref, id) async => const <FacilityPaymentAllocationDetail>[],
    ),
    homeUpcomingObligationsProvider.overrideWith((ref) async => _dues),
    homeCashFlowSummaryProvider.overrideWith((ref, range) async => _cashflow),
    macrosProvider.overrideWith((ref) async => const <TransactionMacro>[]),
    pendingIncomeProvider.overrideWith((ref) async => _pendingIncome),
    pendingSalaryEstimateProvider.overrideWith((ref, key) async => _estimate),
    incomeSourcesProvider.overrideWith((ref) async => [_salarySource]),
    allCategoriesProvider.overrideWith((ref) async => _categories),
    categoriesProvider.overrideWith(
      (ref, kind) async => _categories.where((c) => c.kind == kind).toList(),
    ),
    recurringRulesProvider.overrideWith((ref) async => _recurringRules),
    pendingRecurringProvider.overrideWith((ref) async => _pendingRecurring),
    // Network + responsibility.
    networkContactsProvider.overrideWith((ref) async => _contacts),
    networkAddRequestsProvider.overrideWith(
      (ref) async => const <NetworkAddRequest>[],
    ),
    networkTransfersProvider.overrideWith((ref) async => _transfers),
    responsibilitySummariesProvider.overrideWith(
      (ref) async => const <String, InstallmentResponsibilitySummary>{},
    ),
    planResponsibilityLinksProvider.overrideWith(
      (ref, planId) async => const <OwnerResponsibilityLink>[],
    ),
    myLinkedInstallmentsProvider.overrideWith(
      (ref) async => const <LinkedInstallment>[],
    ),
    sharedLinkDetailsProvider.overrideWith((ref, linkId) async => _linkDetails),
    // Reports.
    cashFlowSummaryProvider.overrideWith((ref, range) async => _cashflow),
    financeSeriesProvider.overrideWith(
      (ref, key) async => [
        for (var i = 5; i >= 0; i--)
          FinanceSeriesPoint(
            bucketStart: PlainDate(_today.year, _today.month, 1).addMonths(-i),
            incomeMinor: 4200000 + i * 66667,
            expensesMinor: 2100000 + i * 120000,
            allowancesMinor: 150000,
            netMinor: 1950000 - i * 53333,
          ),
      ],
    ),
    expenseCategoryTotalsProvider.overrideWith(
      (ref, range) async => const [
        CategoryTotal(
          categoryName: 'Groceries',
          totalMinor: 845000,
          transactionCount: 14,
        ),
        CategoryTotal(
          categoryName: 'Transport',
          totalMinor: 384000,
          transactionCount: 22,
        ),
        CategoryTotal(
          categoryName: 'Subscriptions',
          totalMinor: 214000,
          transactionCount: 5,
        ),
        CategoryTotal(
          categoryName: 'Dining',
          totalMinor: 512000,
          transactionCount: 9,
        ),
      ],
    ),
    allowanceCategoryTotalsProvider.overrideWith(
      (ref, range) async => const [
        CategoryTotal(
          categoryName: 'Family',
          totalMinor: 180000,
          transactionCount: 4,
        ),
      ],
    ),
    incomeCategoryTotalsProvider.overrideWith(
      (ref, range) async => const [
        CategoryTotal(
          categoryName: 'Salary',
          totalMinor: 3466667,
          transactionCount: 1,
        ),
        CategoryTotal(
          categoryName: 'Freelance',
          totalMinor: 780000,
          transactionCount: 3,
        ),
      ],
    ),
    debtSummaryProvider.overrideWith(
      (ref, range) async => const [
        DebtSummary(
          currencyCode: 'EGP',
          repaymentsMinor: 320000,
          upcomingDuesMinor: 306078,
          overdueMinor: 0,
          outstandingMinor: 601259,
        ),
      ],
    ),
    accountBalanceHistoryProvider.overrideWith(
      (ref, key) async => [
        for (var i = 11; i >= 0; i--)
          AccountBalancePoint(
            day: _today.addDays(-i * 3),
            balanceMinor: 4400000 + (11 - i) * 39000,
          ),
      ],
    ),
    workSummaryProvider.overrideWith(
      (ref, range) async => const <WorkSummaryRow>[],
    ),
    workMinutesSeriesProvider.overrideWith(
      (ref, key) async => [
        for (var i = 5; i >= 0; i--)
          WorkMinutesPoint(
            bucketStart: PlainDate(_today.year, _today.month, 1).addMonths(-i),
            totalMinutes: 9600 + i * 240,
          ),
      ],
    ),
    salaryComparisonProvider.overrideWith(
      (ref, range) async => [
        for (var i = 2; i >= 1; i--)
          SalaryComparisonPoint(
            periodId: 'period-$i',
            periodStart: PlainDate(_today.year, _today.month, 1).addMonths(-i),
            periodEnd: PlainDate(
              _today.year,
              _today.month,
              1,
            ).addMonths(-i + 1).addDays(-1),
            expectedPaymentDate: PlainDate(
              _today.year,
              _today.month,
              1,
            ).addMonths(-i + 1).addDays(2),
            status: SalaryPeriodStatus.paid,
            estimatedMinor: 3200000 + i * 100000,
            actualAmountMinor: 3466667,
            differenceMinor: 166667 - i * 100000,
            currencyCode: 'EGP',
          ),
      ],
    ),
    salaryWorkPeriodsProvider.overrideWith(
      (ref, range) async => const <SalaryWorkPeriodPoint>[],
    ),
    // Salary / work.
    salarySettingsProvider.overrideWith(
      (ref) async => SalarySettings.defaults.copyWith(
        salaryEnabled: true,
        baseSalaryMinor: 3200000,
      ),
    ),
    currentPeriodBoundsProvider.overrideWith((ref) async => bounds),
    currentEstimateProvider.overrideWith((ref) async => _estimate),
    estimateForRangeProvider.overrideWith((ref, range) async => _estimate),
    salaryPeriodsProvider.overrideWith((ref) async => _periods),
    adjustmentsForRangeProvider.overrideWith(
      (ref, range) async => const <SalaryAdjustment>[],
    ),
    workEntriesForMonthProvider.overrideWith(
      (ref, month) async => _workEntries,
    ),
    holidaysProvider.overrideWith((ref) async => const <OfficialHoliday>[]),
    // History / settings.
    historyPageProvider.overrideWith(
      (ref, query) async => HistoryPage(items: _historyItems, hasMore: false),
    ),
    historyRepositoryProvider.overrideWithValue(_FakeHistoryRepository()),
    profileProvider.overrideWith(
      (ref) async => const UserProfile(id: 'user-1', displayName: 'Omar'),
    ),
    preferencesProvider.overrideWith(
      (ref) async => const UserPreferences(
        currencyCode: 'EGP',
        timezone: 'Africa/Cairo',
        locale: 'en',
        weekStartsOn: 6,
        weekendDays: [5, 6],
        defaultHistoryDays: 30,
        onboardingCompleted: true,
      ),
    ),
  ];
}

final _shotKey = GlobalKey();

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> assets) async {
    final loader = FontLoader(family);
    for (final asset in assets) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }

  await load('Manrope', ['assets/fonts/Manrope-VariableFont_wght.ttf']);
  await load('IBM Plex Sans Arabic', [
    'assets/fonts/IBMPlexSansArabic-Regular.ttf',
    'assets/fonts/IBMPlexSansArabic-Medium.ttf',
    'assets/fonts/IBMPlexSansArabic-SemiBold.ttf',
    'assets/fonts/IBMPlexSansArabic-Bold.ttf',
  ]);
  final iconFont = File(
    '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}'
    '/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (iconFont.existsSync()) {
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.view(iconFont.readAsBytesSync().buffer)));
    await icons.load();
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/play-screenshots/$name.png')
      ..createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(const {});
  });

  late GoRouter router;

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );

  Future<void> pumpApp(
    WidgetTester tester, {
    Locale? locale,
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [..._overrides().cast()]);
    addTearDown(container.dispose);
    router = container.read(appRouterProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
          key: _shotKey,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(locale: locale),
            darkTheme: AppTheme.dark(locale: locale),
            themeMode: themeMode,
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> scrollBy(WidgetTester tester, double dy) async {
    await tester.drag(find.byType(Scrollable).first, Offset(0, -dy));
    await settle(tester);
  }

  testWidgets('home, dues sheet, and tabs', (tester) async {
    await pumpApp(tester);
    await _capture(tester, '01-home-overview');

    await tester.dragUntilVisible(
      find.byKey(const Key('home-due-thisMonth')),
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    await settle(tester);
    await tester.tap(
      find.byKey(const Key('home-due-thisMonth')),
      warnIfMissed: false,
    );
    await settle(tester);
    if (find.byType(DraggableScrollableSheet).evaluate().isNotEmpty) {
      await _capture(tester, '02-home-due-breakdown');
      router.pop();
      await settle(tester);
    }
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 800));
    await settle(tester);

    await scrollBy(tester, 700);
    await _capture(tester, '03-home-cards-cashflow');

    router.go('/money');
    await settle(tester);
    await _capture(tester, '04-money-accounts');

    await tester.tap(find.text('Transactions'));
    await settle(tester);
    await _capture(tester, '05-money-transactions');

    router.go('/work');
    await settle(tester);
    await _capture(tester, '06-work-calendar');

    router.go('/reports');
    await settle(tester);
    await _capture(tester, '07-reports-overview');
    await scrollBy(tester, 900);
    await _capture(tester, '08-reports-charts');
  });

  testWidgets('network transfers', (tester) async {
    await pumpApp(tester);
    router.push('/money/network').ignore();
    await settle(tester);
    await _capture(tester, '09-network-contacts');
    await tester.tap(find.text('Transfers'));
    await settle(tester);
    await _capture(tester, '10-network-transfer-accept');
  });

  testWidgets('credit facility, pay, linked installment', (tester) async {
    await pumpApp(tester);
    router.push('/money/facilities/facility-1').ignore();
    await settle(tester);
    await scrollBy(tester, 250);
    await _capture(tester, '11-card-due-breakdown');

    router.push('/money/facilities/pay?accountId=facility-1').ignore();
    await settle(tester);
    await scrollBy(tester, 500);
    await _capture(tester, '12-pay-choose-what-to-pay');
    router.pop();
    await settle(tester);

    router.push('/money/linked/link-1').ignore();
    await settle(tester);
    await _capture(tester, '13-shared-installment');
  });

  testWidgets('salary, recurring, automation', (tester) async {
    await pumpApp(tester);
    router.push('/work/periods').ignore();
    await settle(tester);
    await _capture(tester, '14-salary-periods');

    router.push('/settings/recurring').ignore();
    await settle(tester);
    await _capture(tester, '15-recurring-payments');
    router.pop();
    await settle(tester);

    router.push('/settings/income-sources').ignore();
    await settle(tester);
    await _capture(tester, '16-income-automation');
  });

  testWidgets('arabic and dark home', (tester) async {
    await pumpApp(tester, locale: const Locale('ar'));
    await _capture(tester, '17-home-arabic-rtl');
  });

  testWidgets('dark mode home', (tester) async {
    await pumpApp(tester, themeMode: ThemeMode.dark);
    await _capture(tester, '18-home-dark');
  });
}
