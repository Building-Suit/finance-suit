import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/notifications/notification_events.dart';
import 'package:work_tracker/core/result/result.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';

/// A row from `app_core.notification_preferences`; every flag defaults to
/// the server-side default so a missing row behaves identically.
///
/// The category switches decide whether a notification exists at all; the
/// matching `*Push` switches only silence the lock screen, so a user can keep
/// their in-app history while turning phone alerts off.
@immutable
class NotificationPreferences {
  const NotificationPreferences({
    this.dueRemindersEnabled = true,
    this.overdueRemindersEnabled = true,
    this.paymentConfirmationsEnabled = true,
    this.networkEnabled = true,
    this.duePushEnabled = true,
    this.overduePushEnabled = true,
    this.paymentPushEnabled = true,
    this.networkPushEnabled = true,
    this.systemPushEnabled = true,
    this.showAmounts = false,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    bool flag(String key, {bool fallback = true}) =>
        json[key] as bool? ?? fallback;
    return NotificationPreferences(
      dueRemindersEnabled: flag('due_reminders_enabled'),
      overdueRemindersEnabled: flag('overdue_reminders_enabled'),
      paymentConfirmationsEnabled: flag('payment_confirmations_enabled'),
      networkEnabled: flag('network_enabled'),
      duePushEnabled: flag('due_push_enabled'),
      overduePushEnabled: flag('overdue_push_enabled'),
      paymentPushEnabled: flag('payment_push_enabled'),
      networkPushEnabled: flag('network_push_enabled'),
      systemPushEnabled: flag('system_push_enabled'),
      showAmounts: flag('show_amounts', fallback: false),
    );
  }

  final bool dueRemindersEnabled;
  final bool overdueRemindersEnabled;
  final bool paymentConfirmationsEnabled;
  final bool networkEnabled;

  final bool duePushEnabled;
  final bool overduePushEnabled;
  final bool paymentPushEnabled;
  final bool networkPushEnabled;
  final bool systemPushEnabled;

  /// Amounts stay out of push payloads unless the user opts in; lock-screen
  /// notifications must never leak balances by default.
  final bool showAmounts;

  NotificationPreferences copyWith({
    bool? dueRemindersEnabled,
    bool? overdueRemindersEnabled,
    bool? paymentConfirmationsEnabled,
    bool? networkEnabled,
    bool? duePushEnabled,
    bool? overduePushEnabled,
    bool? paymentPushEnabled,
    bool? networkPushEnabled,
    bool? systemPushEnabled,
    bool? showAmounts,
  }) => NotificationPreferences(
    dueRemindersEnabled: dueRemindersEnabled ?? this.dueRemindersEnabled,
    overdueRemindersEnabled:
        overdueRemindersEnabled ?? this.overdueRemindersEnabled,
    paymentConfirmationsEnabled:
        paymentConfirmationsEnabled ?? this.paymentConfirmationsEnabled,
    networkEnabled: networkEnabled ?? this.networkEnabled,
    duePushEnabled: duePushEnabled ?? this.duePushEnabled,
    overduePushEnabled: overduePushEnabled ?? this.overduePushEnabled,
    paymentPushEnabled: paymentPushEnabled ?? this.paymentPushEnabled,
    networkPushEnabled: networkPushEnabled ?? this.networkPushEnabled,
    systemPushEnabled: systemPushEnabled ?? this.systemPushEnabled,
    showAmounts: showAmounts ?? this.showAmounts,
  );

  Map<String, dynamic> toJson() => {
    'due_reminders_enabled': dueRemindersEnabled,
    'overdue_reminders_enabled': overdueRemindersEnabled,
    'payment_confirmations_enabled': paymentConfirmationsEnabled,
    'network_enabled': networkEnabled,
    'due_push_enabled': duePushEnabled,
    'overdue_push_enabled': overduePushEnabled,
    'payment_push_enabled': paymentPushEnabled,
    'network_push_enabled': networkPushEnabled,
    'system_push_enabled': systemPushEnabled,
    'show_amounts': showAmounts,
  };
}

@immutable
class NotificationTestDelivery {
  const NotificationTestDelivery({
    required this.outboxId,
    required this.sent,
    required this.failed,
    required this.suppressed,
  });

  final String outboxId;
  final int sent;
  final int failed;
  final int suppressed;
}

/// One logical notification from `app_core.notifications`.
///
/// This is deliberately *not* a delivery record: a user with two phones has
/// one of these, and a user with no registered device still has one. Push
/// deliveries hang off it in `app_core.notification_outbox`.
@immutable
class NotificationHistoryItem {
  const NotificationHistoryItem({
    required this.id,
    required this.event,
    required this.createdAt,
    required this.payload,
    this.entityType,
    this.entityId,
    this.route,
    this.readAt,
  });

  factory NotificationHistoryItem.fromJson(Map<String, dynamic> json) =>
      NotificationHistoryItem(
        id: json['id'] as String,
        event: NotificationEvent.fromKey(json['event_key'] as String?),
        entityType: json['entity_type'] as String?,
        entityId: json['entity_id'] as String?,
        route: json['route'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        readAt: switch (json['read_at']) {
          final String value => DateTime.parse(value).toLocal(),
          _ => null,
        },
        payload: Map<String, dynamic>.from(
          (json['payload'] as Map?) ?? const <String, dynamic>{},
        ),
      );

  final String id;
  final NotificationEvent event;
  final String? entityType;
  final String? entityId;
  final String? route;
  final DateTime createdAt;
  final Map<String, dynamic> payload;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  String? get accountName => _text('account_name');
  String? get counterpartyName => _text('counterparty_name');
  String? get planTitle => _text('plan_title');
  String? get dueOn => _text('due_on');

  /// Integer minor units straight from the payload. The Notification Center
  /// renders this through the app's existing money-privacy control rather
  /// than showing the server's pre-rendered push text.
  Money? get amount {
    final minor = payload['amount_minor'];
    final currency = payload['currency_code'];
    if (minor is! num || currency is! String || currency.length != 3) {
      return null;
    }
    return Money(minor: minor.toInt(), currencyCode: currency);
  }

  /// The validated in-app destination, or null when there is nothing safe to
  /// open.
  String? get destination => NotificationRoutes.resolve(route);

  String? _text(String key) {
    final value = payload[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  NotificationHistoryItem copyWith({DateTime? readAt}) =>
      NotificationHistoryItem(
        id: id,
        event: event,
        entityType: entityType,
        entityId: entityId,
        route: route,
        createdAt: createdAt,
        payload: payload,
        readAt: readAt ?? this.readAt,
      );
}

@immutable
class NotificationHistoryCursor {
  const NotificationHistoryCursor({required this.createdAt, required this.id});

  final DateTime createdAt;
  final String id;
}

@immutable
class NotificationHistoryPage {
  const NotificationHistoryPage({required this.items, required this.next});

  final List<NotificationHistoryItem> items;
  final NotificationHistoryCursor? next;
}

/// Notification history, read state, push device registration and preferences
/// in `app_core`.
class NotificationsRepository {
  NotificationsRepository(this._client);

  final SupabaseClient _client;

  SupabaseQuerySchema get _db => _client.schema(AppSchemas.core);

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const AuthFailure(AuthFailureKind.sessionMissing);
    }
    return id;
  }

  /// Registers (or refreshes) this device's FCM token. Idempotent per
  /// token through the security-definer RPC, which atomically transfers a
  /// physical FCM token to the current authenticated user.
  Future<Result<String>> registerPushDevice({
    required String fcmToken,
    required String platform,
    String? appVersion,
    String? locale,
    String timezone = 'Africa/Cairo',
  }) {
    return guard(() async {
      final deviceId = await _db.rpc<String>(
        'register_push_device',
        params: {
          'p_fcm_token': fcmToken,
          'p_platform': platform,
          'p_app_version': appVersion,
          'p_locale': locale,
          'p_timezone': timezone,
        },
      );
      return deviceId;
    });
  }

  /// Stops deliveries to this device without losing the registration row.
  Future<Result<void>> disablePushDevice(String fcmToken) {
    return guard(() async {
      await _db.rpc<void>(
        'disable_push_device',
        params: {'fcm_token': fcmToken},
      );
    });
  }

  Future<Result<bool>> hasEnabledPushDevice(String fcmToken) {
    return guard(() async {
      final row = await _db
          .from('push_devices')
          .select('id')
          .eq('user_id', _userId)
          .eq('fcm_token', fcmToken)
          .eq('is_enabled', true)
          .maybeSingle();
      return row != null;
    });
  }

  /// Sends one real push through the production outbox + Edge Function path.
  /// This is intentionally a delivery diagnostic and does not create finance
  /// obligations or transactions.
  Future<Result<NotificationTestDelivery>> sendDeveloperTestNotification() {
    return guard(() async {
      final outboxId = await _db.rpc<String>(
        'enqueue_developer_test_notification',
      );
      final response = await _client.functions.invoke(
        'notification-worker',
        body: {'developer_test_outbox_id': outboxId},
      );
      final data = response.data as Map<String, dynamic>;
      return NotificationTestDelivery(
        outboxId: outboxId,
        sent: data['sent'] as int? ?? 0,
        failed: data['failed'] as int? ?? 0,
        suppressed: data['suppressed'] as int? ?? 0,
      );
    });
  }

  Future<Result<NotificationPreferences>> fetchPreferences() {
    return guard(() async {
      final row = await _db
          .from('notification_preferences')
          .select()
          .eq('user_id', _userId)
          .maybeSingle();
      return row == null
          ? const NotificationPreferences()
          : NotificationPreferences.fromJson(row);
    });
  }

  /// Fetches notifications newest first with a stable `(created_at, id)`
  /// keyset cursor. RLS and the explicit owner filter keep the feed private
  /// even if a caller supplies a stale cursor.
  Future<Result<NotificationHistoryPage>> fetchHistory({
    NotificationHistoryCursor? after,
    int limit = 20,
  }) {
    return guard(() async {
      final pageSize = limit.clamp(1, 50).toInt();
      var query = _db
          .from('notifications')
          .select(
            'id,event_key,category,entity_type,entity_id,route,payload,'
            'created_at,read_at',
          )
          .eq('user_id', _userId);
      if (after != null) {
        final timestamp = after.createdAt.toUtc().toIso8601String();
        query = query.or(
          'created_at.lt.$timestamp,'
          'and(created_at.eq.$timestamp,id.lt.${after.id})',
        );
      }
      // One extra row decides `hasMore` without a second count query.
      final rows = await query
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .limit(pageSize + 1);
      final parsed = rows
          .map((row) => NotificationHistoryItem.fromJson(row))
          .toList(growable: false);
      final items = parsed.take(pageSize).toList(growable: false);
      final last = items.isEmpty ? null : items.last;
      return NotificationHistoryPage(
        items: items,
        next: parsed.length > pageSize && last != null
            ? NotificationHistoryCursor(createdAt: last.createdAt, id: last.id)
            : null,
      );
    });
  }

  /// Authoritative unread count. Deliberately independent of which history
  /// pages the Notification Center happens to have loaded.
  Future<Result<int>> unreadCount() {
    return guard(() async {
      final value = await _db.rpc<dynamic>('unread_notification_count');
      return _count(value);
    });
  }

  /// PostgREST returns a scalar RPC result as JSON, which decodes to `num`
  /// rather than `int` on some platforms. A badge is never negative.
  static int _count(Object? value) {
    final parsed = switch (value) {
      final num number => number.toInt(),
      final String text => int.tryParse(text) ?? 0,
      _ => 0,
    };
    return parsed < 0 ? 0 : parsed;
  }

  /// Marks [ids] read, or every unread notification when [ids] is null.
  /// Returns the reconciled unread count so the badge settles in the same
  /// round trip instead of guessing.
  Future<Result<int>> markRead({List<String>? ids}) {
    return guard(() async {
      final value = await _db.rpc<dynamic>(
        'mark_notifications_read',
        params: {'p_ids': ids},
      );
      return _count(value);
    });
  }

  Future<Result<void>> savePreferences(NotificationPreferences preferences) {
    return guard(() async {
      await _db.from('notification_preferences').upsert({
        'user_id': _userId,
        ...preferences.toJson(),
      });
    });
  }
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(supabaseClientProvider)),
);

final notificationPreferencesProvider = FutureProvider<NotificationPreferences>(
  (ref) async {
    ref.watch(currentUserIdProvider);
    final result = await ref
        .watch(notificationsRepositoryProvider)
        .fetchPreferences();
    return result.when(ok: (p) => p, err: (failure) => throw failure);
  },
);
