import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/app/theme/finance_suit_semantic_colors.dart';
import 'package:work_tracker/core/notifications/notification_center.dart';
import 'package:work_tracker/core/notifications/notifications_repository.dart';
import 'package:work_tracker/core/result/result.dart';

import '../../app/routing/shell_test_harness.dart';

void main() {
  final firstPage = NotificationHistoryPage(
    items: [
      NotificationHistoryItem(
        id: '00000000-0000-0000-0000-000000000001',
        obligationType: 'general',
        reminderKind: 'due_today',
        createdAt: DateTime.now(),
        payload: const {},
      ),
      NotificationHistoryItem(
        id: '00000000-0000-0000-0000-000000000002',
        obligationType: 'facility_payment',
        reminderKind: 'payment_confirmation',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        payload: const {'account_name': 'Saving'},
      ),
    ],
    next: null,
  );

  testWidgets('opens the notification center as a right-side drawer', (
    tester,
  ) async {
    await pumpShellApp(
      tester,
      buildShellTestRouter(),
      extraOverrides: [
        notificationHistoryLoaderProvider.overrideWithValue(
          ({NotificationHistoryCursor? after, int limit = 20}) async =>
              Ok(firstPage),
        ),
        notificationReadMutationProvider.overrideWithValue(
          (id) async => const Ok(null),
        ),
        notificationReadAllMutationProvider.overrideWithValue(
          () async => const Ok(null),
        ),
      ],
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

  testWidgets('opens the notification drawer from the logical end in RTL', (
    tester,
  ) async {
    await pumpShellApp(
      tester,
      buildShellTestRouter(),
      locale: const Locale('ar'),
      extraOverrides: [
        notificationHistoryLoaderProvider.overrideWithValue(
          ({NotificationHistoryCursor? after, int limit = 20}) async =>
              Ok(firstPage),
        ),
      ],
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
        extraOverrides: [
          notificationHistoryLoaderProvider.overrideWithValue(
            ({NotificationHistoryCursor? after, int limit = 20}) async =>
                Ok(firstPage),
          ),
        ],
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
      final foreground = context.suitColors.textPrimary;
      final mutedForeground = context.suitColors.textMuted;
      expect(
        tester.widget<Text>(find.text('Notifications')).style?.color,
        foreground,
      );
      expect(
        tester.widget<Text>(find.text('Today')).style?.color,
        mutedForeground,
      );
      expect(
        tester.widget<Text>(find.text('Due today')).style?.color,
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
    await pumpShellApp(
      tester,
      router,
      extraOverrides: [
        notificationHistoryLoaderProvider.overrideWithValue(
          ({NotificationHistoryCursor? after, int limit = 20}) async =>
              Ok(firstPage),
        ),
      ],
    );
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
      extraOverrides: [
        notificationHistoryLoaderProvider.overrideWithValue(
          ({NotificationHistoryCursor? after, int limit = 20}) async =>
              Ok(firstPage),
        ),
      ],
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
