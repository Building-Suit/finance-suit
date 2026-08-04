import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:work_tracker/app/app.dart';
import 'package:work_tracker/app/configuration/env.dart';
import 'package:work_tracker/core/notifications/push_notifications_service.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Fail fast with a clear developer message when configuration is missing.
  Env.validate();

  // Push reminders are optional: without Firebase config this quietly
  // leaves notifications off and the rest of the app untouched.
  await PushNotificationsService.initializeFirebase();

  await Supabase.initialize(
    url: Env.supabaseUrl,
    // The local Supabase stack still issues legacy anon JWT keys; the
    // deprecated parameter remains correct for that key format.
    // ignore: deprecated_member_use
    anonKey: Env.supabaseAnonKey,
    debug: kDebugMode,
  );

  runApp(const ProviderScope(child: FinanceSuitApp()));
}
