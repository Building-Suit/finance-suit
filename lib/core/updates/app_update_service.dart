import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';

/// A store update that is ready to install.
@immutable
class PendingAppUpdate {
  const PendingAppUpdate({this.availableVersionCode});

  final int? availableVersionCode;
}

/// Store update checks, abstracted so the shell can be tested with fakes.
abstract class AppUpdateService {
  /// Returns the available update, or null when up to date / not
  /// installed from a store / unsupported platform.
  Future<PendingAppUpdate?> checkForUpdate();

  /// Starts the platform update flow.
  Future<void> startUpdate();
}

/// Google Play in-app-update implementation. All failures (sideloaded
/// build, no Play services, emulator) resolve to "no update" silently.
class PlayAppUpdateService implements AppUpdateService {
  @override
  Future<PendingAppUpdate?> checkForUpdate() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        return PendingAppUpdate(
          availableVersionCode: info.availableVersionCode,
        );
      }
      return null;
    } on Exception {
      return null;
    }
  }

  @override
  Future<void> startUpdate() async {
    try {
      final result = await InAppUpdate.startFlexibleUpdate();
      if (result == AppUpdateResult.success) {
        await InAppUpdate.completeFlexibleUpdate();
      }
    } on Exception {
      try {
        await InAppUpdate.performImmediateUpdate();
      } on Exception {
        // The store screen is the user's fallback; never crash over it.
      }
    }
  }
}

final appUpdateServiceProvider = Provider<AppUpdateService>(
  (ref) => PlayAppUpdateService(),
);
