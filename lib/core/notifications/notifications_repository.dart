import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/result/result.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';

/// A row from `app_core.notification_preferences`; every flag defaults to
/// the server-side default so a missing row behaves identically.
@immutable
class NotificationPreferences {
  const NotificationPreferences({
    this.dueRemindersEnabled = true,
    this.overdueRemindersEnabled = true,
    this.paymentConfirmationsEnabled = true,
    this.showAmounts = false,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      dueRemindersEnabled: json['due_reminders_enabled'] as bool? ?? true,
      overdueRemindersEnabled:
          json['overdue_reminders_enabled'] as bool? ?? true,
      paymentConfirmationsEnabled:
          json['payment_confirmations_enabled'] as bool? ?? true,
      showAmounts: json['show_amounts'] as bool? ?? false,
    );
  }

  final bool dueRemindersEnabled;
  final bool overdueRemindersEnabled;
  final bool paymentConfirmationsEnabled;

  /// Amounts stay out of push payloads unless the user opts in; lock-screen
  /// notifications must never leak balances by default.
  final bool showAmounts;

  NotificationPreferences copyWith({
    bool? dueRemindersEnabled,
    bool? overdueRemindersEnabled,
    bool? paymentConfirmationsEnabled,
    bool? showAmounts,
  }) => NotificationPreferences(
    dueRemindersEnabled: dueRemindersEnabled ?? this.dueRemindersEnabled,
    overdueRemindersEnabled:
        overdueRemindersEnabled ?? this.overdueRemindersEnabled,
    paymentConfirmationsEnabled:
        paymentConfirmationsEnabled ?? this.paymentConfirmationsEnabled,
    showAmounts: showAmounts ?? this.showAmounts,
  );
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

/// A delivered notification visible in the in-app Notification Center.
///
/// Delivery history already belongs to the authenticated user under RLS. The
/// app deliberately reads only sent rows, so pending/retry implementation
/// details and failed attempts are never presented as user notifications.
@immutable
class NotificationHistoryItem {
  const NotificationHistoryItem({
    required this.id,
    required this.obligationType,
    required this.reminderKind,
    required this.createdAt,
    required this.payload,
  });

  factory NotificationHistoryItem.fromJson(Map<String, dynamic> json) =>
      NotificationHistoryItem(
        id: json['id'] as String,
        obligationType: json['obligation_type'] as String? ?? 'general',
        reminderKind: json['reminder_kind'] as String? ?? 'due_today',
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        payload: Map<String, dynamic>.from(
          (json['payload_snapshot'] as Map?) ?? const <String, dynamic>{},
        ),
      );

  final String id;
  final String obligationType;
  final String reminderKind;
  final DateTime createdAt;
  final Map<String, dynamic> payload;
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

/// Push device registration and notification preferences in `app_core`.
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

  /// Fetches delivered notifications newest first with a stable
  /// `(created_at, id)` keyset cursor. RLS and the explicit owner filter keep
  /// the feed private even if a caller supplies a stale cursor.
  Future<Result<NotificationHistoryPage>> fetchHistory({
    NotificationHistoryCursor? after,
    int limit = 20,
  }) {
    return guard(() async {
      final pageSize = limit.clamp(1, 50).toInt();
      var query = _db
          .from('notification_outbox')
          .select(
            'id,obligation_type,reminder_kind,created_at,payload_snapshot',
          )
          .eq('user_id', _userId)
          .eq('status', 'sent');
      if (after != null) {
        final timestamp = after.createdAt.toUtc().toIso8601String();
        query = query.or(
          'created_at.lt.$timestamp,and(created_at.eq.$timestamp,id.lt.${after.id})',
        );
      }
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

  Future<Result<void>> savePreferences(NotificationPreferences preferences) {
    return guard(() async {
      await _db.from('notification_preferences').upsert({
        'user_id': _userId,
        'due_reminders_enabled': preferences.dueRemindersEnabled,
        'overdue_reminders_enabled': preferences.overdueRemindersEnabled,
        'payment_confirmations_enabled':
            preferences.paymentConfirmationsEnabled,
        'show_amounts': preferences.showAmounts,
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
