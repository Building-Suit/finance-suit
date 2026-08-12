import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('keeps the notification drawer on the physical right in RTL', (
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
    final context = tester.element(
      find.byKey(const Key('finance-suit-menu-button')),
    );
    final opened = NotificationCenter.open(context);
    await tester.pumpAndSettle();

    final screen = tester.getSize(find.byType(MaterialApp));
    final panel = tester.getRect(
      find.byKey(const Key('notification-center-panel')),
    );
    expect(panel.right, closeTo(screen.width, 1));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await opened;
  });
}
