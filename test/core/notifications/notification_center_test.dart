import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/app/theme/finance_suit_semantic_colors.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/notifications/notification_center.dart';
import 'package:work_tracker/core/notifications/notification_events.dart';
import 'package:work_tracker/core/notifications/notification_feed.dart';
import 'package:work_tracker/core/notifications/notifications_repository.dart';
import 'package:work_tracker/core/result/result.dart';

import '../../app/routing/shell_test_harness.dart';

NotificationHistoryItem item({
  required String id,
  NotificationEvent event = NotificationEvent.creditCardStatementDueToday,
  DateTime? createdAt,
  DateTime? readAt,
  Map<String, dynamic> payload = const {},
  String? route,
}) => NotificationHistoryItem(
  id: id,
  event: event,
  createdAt: createdAt ?? DateTime.now(),
  readAt: readAt,
  payload: payload,
  route: route,
);

void main() {
  final firstPage = NotificationHistoryPage(
    items: [
      item(
        id: '00000000-0000-0000-0000-000000000001',
        payload: const {'account_name': 'CIB Gold'},
      ),
      item(
        id: '00000000-0000-0000-0000-000000000002',
        event: NotificationEvent.facilityPaymentRecorded,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        readAt: DateTime.now().subtract(const Duration(days: 1)),
        payload: const {'account_name': 'Saving'},
      ),
    ],
    next: null,
  );

  List<dynamic> overrides({NotificationHistoryPage? page}) => [
    notificationHistoryLoaderProvider.overrideWithValue(
      ({NotificationHistoryCursor? after, int limit = 20}) async =>
          Ok(page ?? firstPage),
    ),
    notificationReadMutationProvider.overrideWithValue(
      ({List<String>? ids}) async => const Ok(0),
    ),
  ];

  testWidgets('opens the notification center as a right-side drawer', (
    tester,
  ) async {
    await pumpShellApp(
      tester,
      buildShellTestRouter(),
      extraOverrides: overrides(),
    );
    final home = find.text('home-root');
    final restingHomeCenter = tester.getCenter(home);
    final context = tester.element(
      find.byKey(const Key('finance-suit-menu-button')),
    );
    final opened = NotificationCenter.open(context);
    await tester.pumpAndSettle();

    final screen = tester.getSize(find.byType(MaterialApp));
    final panel = tester.getRect(
      find.byKey(const Key('notification-center-panel')),
    );
    expect(panel.width, closeTo(screen.width * 0.675, 1));
    expect(panel.right, closeTo(screen.width, 1));
    expect(tester.getCenter(home).dx, lessThan(restingHomeCenter.dx));
    final panelMaterial = tester.widget<Material>(
      find.byKey(const Key('notification-center-panel')),
    );
    expect(panelMaterial.type, MaterialType.transparency);
    expect(panelMaterial.color, isNull);
    expect(panelMaterial.elevation, 0);
    expect(panelMaterial.borderRadius, isNull);
    expect(panelMaterial.clipBehavior, Clip.none);
    expect(
      find.descendant(
        of: find.byKey(const Key('notification-center-panel')),
        matching: find.byType(Divider),
      ),
      findsNothing,
    );
    expect(find.byKey(const Key('notification-center-list')), findsOneWidget);
    expect(
      find.byKey(const Key('notification-center-settings')),
      findsOneWidget,
    );
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(
      find.byKey(
        const Key('notification-unread-00000000-0000-0000-0000-000000000001'),
      ),
      findsOneWidget,
    );
    // A read notification carries no unread dot.
    expect(
      find.byKey(
        const Key('notification-unread-00000000-0000-0000-0000-000000000002'),
      ),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const Key('notification-center-mark-all-read')),
    );
    await tester.pump();
    expect(
      find.byKey(
        const Key('notification-unread-00000000-0000-0000-0000-000000000001'),
      ),
      findsNothing,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await opened;
    expect(find.byKey(const Key('notification-center-panel')), findsNothing);
  });

  testWidgets('renders localized event text, never the machine event key', (
    tester,
  ) async {
    await pumpShellApp(
      tester,
      buildShellTestRouter(),
      extraOverrides: overrides(),
    );
    final context = tester.element(
      find.byKey(const Key('finance-suit-menu-button')),
    );
    final opened = NotificationCenter.open(context);
    await tester.pumpAndSettle();

    expect(find.text('Credit card payment due today'), findsOneWidget);
    expect(find.text('Payment recorded'), findsOneWidget);
    expect(find.textContaining('CIB Gold'), findsOneWidget);
    expect(find.textContaining('credit_card.'), findsNothing);
    expect(find.textContaining('facility.payment_recorded'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await opened;
  });

  testWidgets('shows skeleton rows rather than an indefinite spinner', (
    tester,
  ) async {
    await pumpShellApp(
      tester,
      buildShellTestRouter(),
      extraOverrides: [
        notificationHistoryLoaderProvider.overrideWithValue(({
          NotificationHistoryCursor? after,
          int limit = 20,
        }) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return Ok(firstPage);
        }),
        notificationReadMutationProvider.overrideWithValue(
          ({List<String>? ids}) async => const Ok(0),
        ),
      ],
    );
    final context = tester.element(
      find.byKey(const Key('finance-suit-menu-button')),
    );
    final opened = NotificationCenter.open(context);
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const Key('notification-center-skeleton')),
      findsOneWidget,
    );

    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notification-center-skeleton')), findsNothing);
    expect(find.byKey(const Key('notification-center-list')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await opened;
  });

  testWidgets('a failed first load offers retry instead of an empty state', (
    tester,
  ) async {
    var attempts = 0;
    await pumpShellApp(
      tester,
      buildShellTestRouter(),
      extraOverrides: [
        notificationHistoryLoaderProvider.overrideWithValue(({
          NotificationHistoryCursor? after,
          int limit = 20,
        }) async {
          attempts++;
          if (attempts == 1) {
            return const Err<NotificationHistoryPage>(NetworkFailure());
          }
          return Ok(firstPage);
        }),
        notificationReadMutationProvider.overrideWithValue(
          ({List<String>? ids}) async => const Ok(0),
        ),
      ],
    );
    final context = tester.element(
      find.byKey(const Key('finance-suit-menu-button')),
    );
    final opened = NotificationCenter.open(context);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notification-center-error')), findsOneWidget);
    expect(find.text('No notifications yet.'), findsNothing);

    await tester.tap(find.byKey(const Key('notification-center-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notification-center-list')), findsOneWidget);
    expect(attempts, 2);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await opened;
  });

  testWidgets('the header bell shows the authoritative unread badge', (
    tester,
  ) async {
    await pumpShellApp(
      tester,
      buildShellTestRouter(),
      unreadCount: 7,
      extraOverrides: overrides(),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('finance-suit-notifications-badge')),
      findsWidgets,
    );
    expect(find.text('7'), findsWidgets);
  });

  testWidgets('a zero unread count leaves the bell unbadged', (tester) async {
    await pumpShellApp(
      tester,
      buildShellTestRouter(),
      extraOverrides: overrides(),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('finance-suit-notifications-badge')),
      findsNothing,
    );
  });

  testWidgets('opens the notification drawer from the logical end in RTL', (
    tester,
  ) async {
    await pumpShellApp(
      tester,
      buildShellTestRouter(),
      locale: const Locale('ar'),
      extraOverrides: overrides(),
    );
    final home = find.text('home-root');
    final restingHomeCenter = tester.getCenter(home);
    final context = tester.element(
      find.byKey(const Key('finance-suit-menu-button')),
    );
    final opened = NotificationCenter.open(context);
    await tester.pumpAndSettle();

    final panel = tester.getRect(
      find.byKey(const Key('notification-center-panel')),
    );
    expect(panel.left, closeTo(0, 1));
    expect(tester.getCenter(home).dx, greaterThan(restingHomeCenter.dx));
    // Arabic content, not an untranslated fallback.
    expect(find.text('دفعة بطاقة ائتمان مستحقة اليوم'), findsOneWidget);

    final panelMaterial = tester.widget<Material>(
      find.byKey(const Key('notification-center-panel')),
    );
    expect(panelMaterial.type, MaterialType.transparency);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await opened;
  });

  testWidgets(
    'uses transparent structure and dark semantic text in dark mode',
    (tester) async {
      await pumpShellApp(
        tester,
        buildShellTestRouter(),
        themeMode: ThemeMode.dark,
        extraOverrides: overrides(),
      );
      final context = tester.element(
        find.byKey(const Key('finance-suit-menu-button')),
      );
      final opened = NotificationCenter.open(context);
      await tester.pumpAndSettle();

      final panelMaterial = tester.widget<Material>(
        find.byKey(const Key('notification-center-panel')),
      );
      expect(panelMaterial.type, MaterialType.transparency);
      expect(panelMaterial.color, isNull);
      final foreground = context.suitColors.onBrandSurface;
      final mutedForeground = foreground.withValues(alpha: 0.76);
      expect(
        tester.widget<Text>(find.text('Notifications')).style?.color,
        foreground,
      );
      expect(
        tester.widget<Text>(find.text('Today')).style?.color,
        mutedForeground,
      );
      expect(
        tester
            .widget<Text>(find.text('Credit card payment due today'))
            .style
            ?.color,
        foreground,
      );
      final markAllRead = tester.widget<TextButton>(
        find.byKey(const Key('notification-center-mark-all-read')),
      );
      expect(
        markAllRead.style?.foregroundColor?.resolve(const <WidgetState>{}),
        context.suitColors.primary,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await opened;
    },
  );

  testWidgets('moves a pushed Settings route with the notification center', (
    tester,
  ) async {
    final router = buildShellTestRouter(initialLocation: '/settings');
    await pumpShellApp(tester, router, extraOverrides: overrides());
    final page = find.text('settings-root');
    final restingCenter = tester.getCenter(page);
    final context = tester.element(page);
    final opened = NotificationCenter.open(context);
    await tester.pumpAndSettle();

    expect(tester.getCenter(page).dx, lessThan(restingCenter.dx));
    expect(find.byKey(const Key('notification-center-panel')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await opened;
  });

  testWidgets('moves every primary tab with the notification center', (
    tester,
  ) async {
    await pumpShellApp(
      tester,
      buildShellTestRouter(),
      extraOverrides: overrides(),
    );

    for (final tab in [
      ('Home', 'home-root'),
      ('Work', 'work-root'),
      ('Money', 'money-root'),
      ('Reports', 'reports-root'),
    ]) {
      await tester.tap(find.text(tab.$1).last);
      await tester.pumpAndSettle();
      final page = find.text(tab.$2).first;
      final restingCenter = tester.getCenter(page);
      final opened = NotificationCenter.open(tester.element(page));
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(page).dx,
        lessThan(restingCenter.dx),
        reason: '${tab.$1} should move with the shared page plane',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await opened;
    }
  });
}
