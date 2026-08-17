import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/core/notifications/notification_events.dart';
import 'package:work_tracker/core/notifications/push_notifications_service.dart';

void main() {
  group('route validation', () {
    test('accepts the destinations the server actually produces', () {
      const facility = '/money/facilities/11111111-1111-4111-8111-111111111111';
      expect(NotificationRoutes.resolve(facility), facility);
      expect(NotificationRoutes.resolve('/money/network'), '/money/network');
      expect(
        NotificationRoutes.resolve(
          '/money/linked/22222222-2222-4222-8222-222222222222',
        ),
        '/money/linked/22222222-2222-4222-8222-222222222222',
      );
      expect(NotificationRoutes.resolve('/money'), '/money');
      expect(NotificationRoutes.resolve('/home'), '/home');
    });

    test('a malformed identifier resolves to nothing instead of crashing', () {
      expect(
        NotificationRoutes.resolve('/money/facilities/not-a-uuid'),
        isNull,
      );
      expect(NotificationRoutes.resolve('/money/facilities/'), isNull);
      expect(NotificationRoutes.resolve('/money/facilities'), isNull);
    });

    test('refuses anything that could escape the app router', () {
      expect(NotificationRoutes.resolve('https://evil.example/money'), isNull);
      expect(NotificationRoutes.resolve('//evil.example/money'), isNull);
      expect(NotificationRoutes.resolve('/money/../admin'), isNull);
      expect(NotificationRoutes.resolve('/money?next=/admin'), isNull);
      expect(NotificationRoutes.resolve('/money#/admin'), isNull);
      expect(NotificationRoutes.resolve('money'), isNull);
      expect(NotificationRoutes.resolve('/settings/subscription'), isNull);
      expect(NotificationRoutes.resolve(''), isNull);
      expect(NotificationRoutes.resolve(null), isNull);
      expect(NotificationRoutes.resolve('/money${'a' * 600}'), isNull);
    });
  });

  group('push payload routing', () {
    test('prefers the structured route the server sent', () {
      expect(
        PushNotificationsService.routeForMessage({
          'route': '/money/facilities/11111111-1111-4111-8111-111111111111',
          'event_key': 'credit_card.statement_due_today',
          'account_id': '99999999-9999-4999-8999-999999999999',
        }),
        '/money/facilities/11111111-1111-4111-8111-111111111111',
      );
    });

    test('falls back to the event key when no route is present', () {
      expect(
        PushNotificationsService.routeForMessage({
          'event_key': 'installment.due_today',
          'account_id': '11111111-1111-4111-8111-111111111111',
        }),
        '/money/facilities/11111111-1111-4111-8111-111111111111',
      );
      expect(
        PushNotificationsService.routeForMessage({
          'event_key': 'network.transfer_received',
        }),
        '/money/network',
      );
      expect(
        PushNotificationsService.routeForMessage({
          'event_key': 'system.developer_test',
        }),
        '/home',
      );
    });

    test('messages sent before the catalog still route by legacy type', () {
      expect(
        PushNotificationsService.routeForMessage({
          'type': 'bnpl_due',
          'account_id': '11111111-1111-4111-8111-111111111111',
        }),
        '/money/facilities/11111111-1111-4111-8111-111111111111',
      );
      expect(
        PushNotificationsService.routeForMessage({
          'type': 'credit_card_statement_due',
        }),
        '/money',
      );
    });

    test('never routes on human-readable notification text', () {
      // A title or body cannot influence the destination.
      expect(
        PushNotificationsService.routeForMessage({
          'title': 'Credit card payment due today',
          'body': 'Open /money/facilities now',
        }),
        isNull,
      );
    });

    test('a hostile route in the payload is refused', () {
      expect(
        PushNotificationsService.routeForMessage({
          'route': 'https://evil.example/steal',
          'event_key': 'system.developer_test',
        }),
        // Falls back to the event's own safe destination rather than the
        // attacker-supplied one.
        '/home',
      );
      expect(
        PushNotificationsService.routeForMessage({'route': '/money/../admin'}),
        isNull,
      );
    });

    test('an unknown event with no usable hint routes nowhere', () {
      expect(
        PushNotificationsService.routeForMessage({
          'event_key': 'something.invented_later',
        }),
        isNull,
      );
      expect(PushNotificationsService.routeForMessage(const {}), isNull);
    });
  });

  group('event catalog', () {
    test('every key round-trips and unknown keys degrade safely', () {
      for (final event in NotificationEvent.values) {
        if (event == NotificationEvent.unknown) continue;
        expect(NotificationEvent.fromKey(event.key), event);
      }
      expect(
        NotificationEvent.fromKey('not.a_real_event'),
        NotificationEvent.unknown,
      );
      expect(NotificationEvent.fromKey(null), NotificationEvent.unknown);
      expect(NotificationEvent.fromKey(''), NotificationEvent.unknown);
    });

    test('due and overdue events are classified as due work', () {
      expect(NotificationEvent.creditCardStatementOverdue.isDue, isTrue);
      expect(NotificationEvent.bnplDueSoon.isDue, isTrue);
      expect(NotificationEvent.networkTransferReceived.isDue, isFalse);
      expect(NotificationEvent.facilityPaymentRecorded.isDue, isFalse);
    });
  });
}
