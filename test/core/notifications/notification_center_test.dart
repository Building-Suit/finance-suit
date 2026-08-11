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
        createdAt: DateTime.utc(2026, 8, 11, 12),
        payload: const {},
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

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await opened;
    expect(find.byKey(const Key('notification-center-panel')), findsNothing);
  });
}
