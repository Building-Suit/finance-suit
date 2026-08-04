import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/core/notifications/notifications_repository.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';

/// Android channel for every Finance Suit reminder. The id must match the
/// `default_notification_channel_id` meta-data in the Android manifest so
/// background FCM messages land on the same channel.
const kRemindersChannelId = 'finance_suit_reminders';

/// Background messages are delivered by the OS from the notification
/// payload; nothing needs to run here, but FCM requires a registered
/// top-level entry point so data messages never crash the app.
@pragma('vm:entry-point')
Future<void> financeSuitMessagingBackgroundHandler(
  RemoteMessage message,
) async {}

/// Wires Firebase Cloud Messaging into the app.
///
/// Everything degrades gracefully: when Firebase is not configured for the
/// current build (no google-services.json) the service simply stays off and
/// the rest of the app is unaffected. Amount-free reminder content is
/// composed server-side; this class never puts balances into notifications.
class PushNotificationsService {
  PushNotificationsService(this._repository);

  final NotificationsRepository _repository;

  static bool _firebaseReady = false;
  String? _syncedKey;

  /// Attempts Firebase startup once per process, never throwing: builds
  /// without Firebase config run with push disabled.
  static Future<void> initializeFirebase() async {
    if (_firebaseReady) return;
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(
        financeSuitMessagingBackgroundHandler,
      );
      _firebaseReady = true;
    } on Object catch (error) {
      debugPrint('Push notifications unavailable: $error');
      _firebaseReady = false;
    }
  }

  static bool get isAvailable => _firebaseReady;

  /// Requests permission, registers the FCM token for [userId], creates the
  /// Android channel, and starts foreground/refresh listeners. Idempotent
  /// per (user, token); safe to call on every sign-in.
  Future<void> syncRegistration({
    required String userId,
    String? appVersion,
    String? locale,
  }) async {
    if (!_firebaseReady) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      await _ensureLocalNotificationChannel();

      final token = await messaging.getToken();
      if (token == null) return;
      final key = '$userId:$token';
      if (_syncedKey != key) {
        await _repository.upsertPushDevice(
          fcmToken: token,
          platform: Platform.isAndroid ? 'android' : 'ios',
          appVersion: appVersion,
          locale: locale,
        );
        _syncedKey = key;
      }

      messaging.onTokenRefresh.listen((refreshed) {
        _repository.upsertPushDevice(
          fcmToken: refreshed,
          platform: Platform.isAndroid ? 'android' : 'ios',
          appVersion: appVersion,
          locale: locale,
        );
        _syncedKey = '$userId:$refreshed';
      });

      // Foreground messages skip the system tray; mirror them onto the
      // reminders channel so a due date never passes silently.
      FirebaseMessaging.onMessage.listen(_showForegroundMessage);
    } on Object catch (error) {
      // Registration failures must never break sign-in.
      debugPrint('Push registration failed: $error');
    }
  }

  /// Marks this device disabled before a sign-out so the sender stops
  /// targeting it.
  Future<void> unregister() async {
    if (!_firebaseReady) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _repository.disablePushDevice(token);
      }
      _syncedKey = null;
    } on Object catch (error) {
      debugPrint('Push unregistration failed: $error');
    }
  }

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _localReady = false;

  Future<void> _ensureLocalNotificationChannel() async {
    if (_localReady) return;
    const channel = AndroidNotificationChannel(
      kRemindersChannelId,
      'Payment reminders',
      description: 'Installment and credit card due date reminders.',
      importance: Importance.high,
    );
    await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
    _localReady = true;
  }

  Future<void> _showForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await _localNotifications.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          kRemindersChannelId,
          'Payment reminders',
          channelDescription: 'Installment and credit card due date reminders.',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}

final pushNotificationsServiceProvider = Provider<PushNotificationsService>(
  (ref) => PushNotificationsService(ref.watch(notificationsRepositoryProvider)),
);

/// Registers the signed-in user's device for push reminders. Watched from
/// the app root; a no-op whenever Firebase is not configured.
final pushRegistrationProvider = Provider<void>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null || !PushNotificationsService.isAvailable) return;
  final locale = PlatformDispatcher.instance.locale.toLanguageTag();
  ref
      .read(pushNotificationsServiceProvider)
      .syncRegistration(userId: userId, locale: locale);
});
