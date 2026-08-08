import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/core/notifications/notifications_repository.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/firebase_options.dart';

/// Android channel for every Finance Suit reminder. The id must match the
/// `default_notification_channel_id` meta-data in the Android manifest so
/// background FCM messages land on the same channel.
const kRemindersChannelId = 'finance_due_reminders';
const _permissionPromptedKey = 'finance_suit_push_permission_prompted';

@immutable
class PushNotificationStatus {
  const PushNotificationStatus({
    required this.firebaseAvailable,
    this.permission,
    this.hasFcmToken = false,
    this.registered = false,
    this.maskedToken,
    this.lastError,
  });

  final bool firebaseAvailable;
  final AuthorizationStatus? permission;
  final bool hasFcmToken;
  final bool registered;
  final String? maskedToken;
  final String? lastError;
}

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
class PushNotificationsService with WidgetsBindingObserver {
  PushNotificationsService(this._repository);

  final NotificationsRepository _repository;

  static bool _firebaseReady = false;

  /// Attempts Firebase startup once per process, never throwing: builds
  /// without Firebase config run with push disabled.
  static Future<void> initializeFirebase() async {
    if (_firebaseReady) return;
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
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

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  Future<void>? _syncInFlight;
  void Function(String route)? _openRoute;
  String? _currentUserId;
  String? _currentToken;
  String? _syncedKey;
  String? _handledInitialMessageId;
  String? _lastError;
  bool _localReady = false;
  bool _lifecycleAttached = false;

  /// Requests permission, registers the FCM token for [userId], creates the
  /// Android channel, and starts foreground/refresh listeners. Idempotent
  /// per (user, token); safe to call on every sign-in.
  Future<void> syncRegistration({
    required String userId,
    required void Function(String route) openRoute,
    String? appVersion,
    String? locale,
    String timezone = 'Africa/Cairo',
    bool forcePermissionRequest = false,
  }) async {
    if (!_firebaseReady) return;
    _openRoute = openRoute;
    _currentUserId = userId;
    if (_syncInFlight != null) return _syncInFlight;
    _syncInFlight = _syncRegistration(
      userId: userId,
      appVersion: appVersion,
      locale: locale,
      timezone: timezone,
      forcePermissionRequest: forcePermissionRequest,
    ).whenComplete(() => _syncInFlight = null);
    return _syncInFlight;
  }

  Future<void> _syncRegistration({
    required String userId,
    String? appVersion,
    String? locale,
    required String timezone,
    required bool forcePermissionRequest,
  }) async {
    try {
      _lastError = null;
      final messaging = FirebaseMessaging.instance;
      final settings = await _syncPermission(
        messaging,
        forceRequest: forcePermissionRequest,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied ||
          settings.authorizationStatus == AuthorizationStatus.notDetermined) {
        _lastError = 'notification_permission_not_granted';
        return;
      }

      await _ensureLocalNotificationChannel();

      final token = await messaging.getToken();
      if (token == null) return;
      _currentToken = token;
      final key = '$userId:$token';
      if (_syncedKey != key) {
        final result = await _repository.registerPushDevice(
          fcmToken: token,
          platform: Platform.isAndroid ? 'android' : 'ios',
          appVersion: appVersion,
          locale: locale,
          timezone: timezone,
        );
        result.when(
          ok: (_) {
            _lastError = null;
            _syncedKey = key;
          },
          err: (failure) => _lastError = failure.toString(),
        );
      }

      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = messaging.onTokenRefresh.listen((refreshed) {
        _currentToken = refreshed;
        unawaited(
          _repository
              .registerPushDevice(
                fcmToken: refreshed,
                platform: Platform.isAndroid ? 'android' : 'ios',
                appVersion: appVersion,
                locale: locale,
                timezone: timezone,
              )
              .then(
                (result) => result.when(
                  ok: (_) {
                    _lastError = null;
                    _syncedKey = '$userId:$refreshed';
                  },
                  err: (failure) => _lastError = failure.toString(),
                ),
              ),
        );
      });

      await _foregroundSub?.cancel();
      _foregroundSub = FirebaseMessaging.onMessage.listen(
        _showForegroundMessage,
      );
      await _openedSub?.cancel();
      _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(
        _handleRemoteMessageOpen,
      );
      await _handleInitialMessage();
      _attachLifecycleObserver();
    } on Object catch (error) {
      // Registration failures must never break sign-in.
      _lastError = error.toString();
      debugPrint('Push registration failed: $error');
    }
  }

  Future<NotificationSettings> _syncPermission(
    FirebaseMessaging messaging, {
    bool forceRequest = false,
  }) async {
    var settings = await messaging.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
      final prompted = await _preferences.getBool(_permissionPromptedKey);
      if (forceRequest || prompted != true) {
        settings = await messaging.requestPermission();
        await _preferences.setBool(_permissionPromptedKey, true);
      }
    }
    return settings;
  }

  /// Marks this device disabled before a sign-out so the sender stops
  /// targeting it.
  Future<void> unregister() async {
    if (!_firebaseReady) return;
    try {
      final token =
          _currentToken ?? await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _repository.disablePushDevice(token);
      }
      await disposeSession();
    } on Object catch (error) {
      debugPrint('Push unregistration failed: $error');
    }
  }

  Future<void> disposeSession() async {
    await _tokenRefreshSub?.cancel();
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
    _tokenRefreshSub = null;
    _foregroundSub = null;
    _openedSub = null;
    _currentUserId = null;
    _currentToken = null;
    _syncedKey = null;
    _openRoute = null;
    if (_lifecycleAttached) {
      WidgetsBinding.instance.removeObserver(this);
      _lifecycleAttached = false;
    }
  }

  Future<AuthorizationStatus?> permissionStatus() async {
    if (!_firebaseReady) return null;
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return settings.authorizationStatus;
  }

  Future<PushNotificationStatus> status() async {
    if (!_firebaseReady) {
      return PushNotificationStatus(
        firebaseAvailable: false,
        lastError: _lastError,
      );
    }
    try {
      final messaging = FirebaseMessaging.instance;
      final permission = await messaging.getNotificationSettings();
      final token = _currentToken ?? await messaging.getToken();
      _currentToken = token;
      var registered = false;
      if (token != null) {
        final result = await _repository.hasEnabledPushDevice(token);
        registered = result.when(ok: (value) => value, err: (_) => false);
      }
      return PushNotificationStatus(
        firebaseAvailable: true,
        permission: permission.authorizationStatus,
        hasFcmToken: token != null,
        registered: registered,
        maskedToken: token == null ? null : _maskToken(token),
        lastError: _lastError,
      );
    } on Object catch (error) {
      return PushNotificationStatus(
        firebaseAvailable: true,
        lastError: error.toString(),
      );
    }
  }

  String _maskToken(String token) {
    if (token.length <= 14) return '${token.substring(0, 4)}...';
    return '${token.substring(0, 8)}...${token.substring(token.length - 6)}';
  }

  void _attachLifecycleObserver() {
    if (_lifecycleAttached) return;
    WidgetsBinding.instance.addObserver(this);
    _lifecycleAttached = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final userId = _currentUserId;
    if (userId == null) return;
    unawaited(
      syncRegistration(
        userId: userId,
        openRoute: _openRoute ?? (_) {},
        locale: PlatformDispatcher.instance.locale.toLanguageTag(),
      ),
    );
  }

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
      onDidReceiveNotificationResponse: _handleLocalNotificationResponse,
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
      id: message.messageId?.hashCode ?? notification.hashCode,
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
      payload: jsonEncode(message.data),
    );
  }

  Future<void> _handleInitialMessage() async {
    final message = await FirebaseMessaging.instance.getInitialMessage();
    if (message == null) return;
    if (_handledInitialMessageId == message.messageId) return;
    _handledInitialMessageId = message.messageId;
    _handleRemoteMessageOpen(message);
  }

  void _handleRemoteMessageOpen(RemoteMessage message) {
    _openNotificationData(message.data);
  }

  void _handleLocalNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload);
      if (data is Map<String, dynamic>) _openNotificationData(data);
    } on FormatException {
      return;
    }
  }

  void _openNotificationData(Map<String, dynamic> data) {
    if (_currentUserId == null) return;
    final type = data['type'] as String?;
    final accountId = data['account_id'] as String?;
    final route = switch (type) {
      'credit_card_statement_due' ||
      'installment_due' ||
      'bnpl_due' ||
      'facility_payment_confirmation' =>
        accountId == null || accountId.isEmpty
            ? AppRoutes.money
            : '${AppRoutes.money}/facilities/$accountId',
      'developer_test' => AppRoutes.home,
      _ => null,
    };
    if (route != null) _openRoute?.call(route);
  }
}

final pushNotificationsServiceProvider = Provider<PushNotificationsService>((
  ref,
) {
  final service = PushNotificationsService(
    ref.watch(notificationsRepositoryProvider),
  );
  ref.onDispose(service.disposeSession);
  return service;
});

/// Registers the signed-in user's device for push reminders. Watched from
/// the app root; a no-op whenever Firebase is not configured.
final pushRegistrationProvider = Provider<void>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  final service = ref.read(pushNotificationsServiceProvider);
  if (userId == null || !PushNotificationsService.isAvailable) {
    unawaited(service.disposeSession());
    return;
  }
  final router = ref.watch(appRouterProvider);
  final locale = PlatformDispatcher.instance.locale.toLanguageTag();
  unawaited(
    service.syncRegistration(
      userId: userId,
      locale: locale,
      openRoute: router.go,
    ),
  );
});

final pushNotificationPermissionProvider = FutureProvider<AuthorizationStatus?>(
  (ref) {
    ref.watch(pushRegistrationProvider);
    return ref.watch(pushNotificationsServiceProvider).permissionStatus();
  },
);

final pushNotificationStatusProvider = FutureProvider<PushNotificationStatus>((
  ref,
) {
  ref.watch(currentUserIdProvider);
  ref.watch(pushRegistrationProvider);
  return ref.watch(pushNotificationsServiceProvider).status();
});
