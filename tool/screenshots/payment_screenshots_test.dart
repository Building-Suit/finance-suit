// Screenshot generator for the selectable payment allocation flow.
//
// Not part of the normal test suite (it lives outside test/): run it
// explicitly with
//   flutter test tool/screenshots/payment_screenshots_test.dart
// PNGs are written to build/screenshots/. Real fonts are loaded from the
// Flutter SDK cache (Roboto); an optional Arabic font is picked up from
// SCREENSHOT_ARABIC_FONT if that environment variable points at a .ttf.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/card_fee_rule.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';
import 'package:work_tracker/features/finance/domain/facility_activity.dart';
import 'package:work_tracker/features/finance/domain/facility_payment_component.dart';
import 'package:work_tracker/features/finance/domain/held_amount.dart';
import 'package:work_tracker/features/finance/domain/recurring_rule.dart';
import 'package:work_tracker/features/finance/domain/transaction_query.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/screens/credit_facility_detail_screen.dart';
import 'package:work_tracker/features/finance/presentation/screens/facility_payment_screen.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

final _wallet = AccountBalance.fromJson(const {
  'account_id': 'wallet-1',
  'name': 'Main Wallet',
  'account_type': 'cash',
  'currency_code': 'EGP',
  'is_default': true,
  'is_archived': false,
  'allow_negative_balance': false,
  'opening_balance_minor': 1000000,
  'balance_minor': 745000,
  'total_incoming_minor': 0,
  'total_outgoing_minor': 255000,
});

final _visa = CreditFacilitySummary.fromJson(const {
  'account_id': 'facility-1',
  'name': 'Visa Card',
  'account_type': 'credit_card',
  'currency_code': 'EGP',
  'is_archived': false,
  'notes': null,
  'opening_owed_minor': 0,
  'credit_limit_minor': 2000000,
  'statement_day': 10,
  'default_due_day': 25,
  'last_four_digits': '1234',
  'reminder_lead_days': 3,
  'outstanding_minor': 421259,
  'available_credit_minor': 1578741,
  'utilization_basis_points': 2106,
  'due_now_minor': 275077,
  'overdue_minor': 104994,
  'next_due_on': '2026-08-25',
  'next_due_amount_minor': 104994,
  'active_plan_count': 2,
});

Map<String, dynamic> _component({
  required String type,
  required String id,
  required String title,
  required String kind,
  String? feeType,
  int? seq,
  int? count,
  required String on,
  required int amount,
  int paid = 0,
}) => {
  'component_type': type,
  'component_id': id,
  'title': title,
  'activity_kind': kind,
  'fee_type': feeType,
  'sequence_number': seq,
  'installment_count': count,
  'occurred_on': on,
  'amount_minor': amount,
  'paid_minor': paid,
  'remaining_minor': amount - paid,
  'payment_status': paid == 0
      ? 'unpaid'
      : paid >= amount
      ? 'paid'
      : 'partially_paid',
  'scope': 'current',
};

FacilityDueBreakdown _breakdown({required bool afterPayment}) {
  final components = [
    _component(
      type: 'installment_due',
      id: 'due-1',
      title: 'Al Araby installment',
      kind: 'installment_due',
      seq: 4,
      count: 12,
      on: '2026-08-25',
      amount: 104994,
      paid: afterPayment ? 50000 : 0,
    ),
    _component(
      type: 'installment_due',
      id: 'due-2',
      title: 'Samsung Monitor',
      kind: 'installment_due',
      seq: 2,
      count: 6,
      on: '2026-08-25',
      amount: 55187,
      paid: afterPayment ? 55187 : 0,
    ),
    _component(
      type: 'statement_item',
      id: 'item-1',
      title: 'Solidarity insurance',
      kind: 'fee_charge',
      feeType: 'insurance',
      on: '2026-08-01',
      amount: 2500,
      paid: afterPayment ? 2500 : 0,
    ),
    _component(
      type: 'statement_item',
      id: 'item-2',
      title: 'Stamp duty',
      kind: 'fee_charge',
      feeType: 'stamp_tax',
      on: '2026-08-01',
      amount: 1312,
    ),
    _component(
      type: 'statement_item',
      id: 'item-3',
      title: 'Monthly interest',
      kind: 'purchase_interest',
      feeType: 'purchase_interest',
      on: '2026-08-05',
      amount: 10996,
      paid: afterPayment ? 10996 : 0,
    ),
    _component(
      type: 'statement_item',
      id: 'item-4',
      title: 'OpenAI',
      kind: 'ordinary_expense',
      on: '2026-07-18',
      amount: 99999,
    ),
    _component(
      type: 'statement_item',
      id: 'item-5',
      title: 'Netflix',
      kind: 'ordinary_expense',
      on: '2026-07-21',
      amount: 24999,
      paid: afterPayment ? 24999 : 0,
    ),
  ];
  final total = components.fold<int>(
    0,
    (a, c) => a + (c['amount_minor']! as int),
  );
  final paid = components.fold<int>(0, (a, c) => a + (c['paid_minor']! as int));
  return FacilityDueBreakdown.fromJson({
    'account_id': 'facility-1',
    'account_type': 'credit_card',
    'currency_code': 'EGP',
    'as_of': '2026-08-15',
    'outstanding_minor': 421259,
    'total_due_minor': total,
    'paid_minor': paid,
    'remaining_minor': total - paid,
    'additional_balance_minor': 421259 - (total - paid),
    'minimum_due_minor': 21063,
    'minimum_remaining_minor': afterPayment ? 0 : 21063,
    'components': components,
  });
}

final _repayment = FacilityActivityItem.fromJson(const {
  'transaction_id': 'pay-1',
  'account_id': 'facility-1',
  'transaction_kind': 'transfer',
  'occurred_on': '2026-08-15',
  'amount_minor': 143682,
  'currency_code': 'EGP',
  'category_id': null,
  'title': null,
  'notes': null,
  'counterparty': null,
  'plan_id': null,
  'activity_kind': 'facility_repayment',
  'is_settled': false,
  'fee_type': null,
});

final _appliedTo = [
  for (final row in const [
    ('installment_due', 'due-2', 'Samsung Monitor', 2, '2026-08-25', 55187),
    (
      'statement_item',
      'item-1',
      'Solidarity insurance',
      null,
      '2026-08-01',
      2500,
    ),
    ('statement_item', 'item-3', 'Monthly interest', null, '2026-08-05', 10996),
    ('statement_item', 'item-5', 'Netflix', null, '2026-07-21', 24999),
    (
      'installment_due',
      'due-1',
      'Al Araby installment',
      4,
      '2026-08-25',
      50000,
    ),
  ])
    FacilityPaymentAllocationDetail.fromJson({
      'payment_transaction_id': 'pay-1',
      'component_type': row.$1,
      'component_id': row.$2,
      'title': row.$3,
      'sequence_number': row.$4,
      'detail_on': row.$5,
      'amount_minor': row.$6,
      'currency_code': 'EGP',
    }),
];

List<dynamic> _overrides({required bool afterPayment}) => [
  accountBalancesProvider.overrideWith((ref) async => [_wallet]),
  allAccountBalancesProvider.overrideWith((ref) async => [_wallet]),
  creditFacilitiesProvider.overrideWith((ref) async => [_visa]),
  allCreditFacilitiesProvider.overrideWith((ref) async => [_visa]),
  pendingRecurringProvider.overrideWith(
    (ref) async => const <PendingRecurring>[],
  ),
  installmentPlansProvider.overrideWith(
    (ref, accountId) async => const <InstallmentPlan>[],
  ),
  installmentDuesProvider.overrideWith(
    (ref, accountId) async => const <InstallmentDue>[],
  ),
  transactionsPageProvider.overrideWith(
    (ref, query) async => const TransactionPage(items: [], hasMore: false),
  ),
  heldAmountsProvider.overrideWith((ref) async => const <HeldAmount>[]),
  feeRulesProvider.overrideWith(
    (ref, accountId) async => const <CardFeeRule>[],
  ),
  statementSummariesProvider.overrideWith(
    (ref, accountId) async => const <CardStatementSummary>[],
  ),
  facilityActivityProvider.overrideWith((ref, accountId) async => [_repayment]),
  facilityDueBreakdownProvider.overrideWith(
    (ref, args) async => _breakdown(afterPayment: afterPayment),
  ),
  paymentAllocationsProvider.overrideWith(
    (ref, transactionId) async => _appliedTo,
  ),
];

Future<void> _loadFonts() async {
  final sdkFonts = Directory(
    '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}'
    '/bin/cache/artifacts/material_fonts',
  );
  final roboto = FontLoader('Roboto');
  for (final name in [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]) {
    final file = File('${sdkFonts.path}/$name');
    if (file.existsSync()) {
      roboto.addFont(
        Future.value(ByteData.view(file.readAsBytesSync().buffer)),
      );
    }
  }
  await roboto.load();
  final iconFont = File('${sdkFonts.path}/MaterialIcons-Regular.otf');
  if (iconFont.existsSync()) {
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.view(iconFont.readAsBytesSync().buffer)));
    await icons.load();
  }
  final arabicPath = Platform.environment['SCREENSHOT_ARABIC_FONT'];
  if (arabicPath != null && File(arabicPath).existsSync()) {
    final arabic = FontLoader('Roboto')
      ..addFont(
        Future.value(ByteData.view(File(arabicPath).readAsBytesSync().buffer)),
      );
    await arabic.load();
  }
}

final _shotKey = GlobalKey();

Widget _app(Widget home, {required bool afterPayment, Locale? locale}) {
  final theme = AppTheme.light();
  return ProviderScope(
    overrides: [..._overrides(afterPayment: afterPayment).cast()],
    child: RepaintBoundary(
      key: _shotKey,
      child: MaterialApp(
        theme: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
        ),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
}

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/screenshots/$name.png')
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
  });

  Future<void> pumpPhone(
    WidgetTester tester,
    Widget home, {
    bool afterPayment = false,
    Locale? locale,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(home, afterPayment: afterPayment, locale: locale),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('pay screen with three presets', (tester) async {
    await pumpPhone(
      tester,
      const FacilityPaymentScreen(accountId: 'facility-1'),
    );
    await _capture(tester, '01-pay-screen-presets');
  });

  testWidgets('minimum payment preset selected', (tester) async {
    await pumpPhone(
      tester,
      const FacilityPaymentScreen(accountId: 'facility-1'),
    );
    await tester.tap(find.byKey(const Key('payment-chip-minimum')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    await _capture(tester, '02-minimum-payment-selected');
  });

  testWidgets('custom checklist selection', (tester) async {
    await pumpPhone(
      tester,
      const FacilityPaymentScreen(accountId: 'facility-1'),
    );
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('payment-row-installment_due:due-2')),
    );
    await tester.tap(
      find.byKey(const ValueKey('payment-row-statement_item:item-1')),
    );
    await tester.tap(
      find.byKey(const ValueKey('payment-row-statement_item:item-3')),
    );
    await tester.pumpAndSettle();
    await _capture(tester, '03-custom-selection');
  });

  testWidgets('partial allocation on a row', (tester) async {
    await pumpPhone(
      tester,
      const FacilityPaymentScreen(accountId: 'facility-1'),
    );
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('payment-row-installment_due:due-1')),
    );
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('payment-row-installment_due:due-1'));
    await tester.tap(
      find.descendant(of: row, matching: find.byType(TextButton)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '500.00');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await _capture(tester, '04-partial-allocation');
  });

  testWidgets('due breakdown before payment', (tester) async {
    await pumpPhone(
      tester,
      const CreditFacilityDetailScreen(accountId: 'facility-1'),
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await _capture(tester, '05-due-breakdown-before');
  });

  testWidgets('due breakdown after payment with paid and partial rows', (
    tester,
  ) async {
    await pumpPhone(
      tester,
      const CreditFacilityDetailScreen(accountId: 'facility-1'),
      afterPayment: true,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await _capture(tester, '06-due-breakdown-after');
  });

  testWidgets('payment detail applied-to sheet', (tester) async {
    await pumpPhone(
      tester,
      const CreditFacilityDetailScreen(accountId: 'facility-1'),
      afterPayment: true,
    );
    await tester.dragUntilVisible(
      find.text('Facility payment'),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Facility payment'));
    await tester.pumpAndSettle();
    await _capture(tester, '07-payment-detail-applied-to');
  });

  testWidgets('arabic rtl pay screen', (tester) async {
    await pumpPhone(
      tester,
      const FacilityPaymentScreen(accountId: 'facility-1'),
      locale: const Locale('ar'),
    );
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    await _capture(tester, '08-arabic-rtl');
  });

  testWidgets('320x480 small viewport', (tester) async {
    await pumpPhone(
      tester,
      const FacilityPaymentScreen(accountId: 'facility-1'),
      size: const Size(320, 480),
    );
    await _capture(tester, '09-small-viewport-320x480');
  });
}
