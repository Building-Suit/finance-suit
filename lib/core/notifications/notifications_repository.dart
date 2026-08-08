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
