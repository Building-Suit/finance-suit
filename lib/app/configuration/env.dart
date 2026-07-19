/// Typed compile-time configuration.
///
/// Values are provided with `--dart-define` or `--dart-define-from-file`.
/// See `config/development.example.json`.
class Env {
  const Env._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );
  static const String appEnvironment = String.fromEnvironment(
    'APP_ENVIRONMENT',
    defaultValue: 'development',
  );
  static const String authCallbackScheme = String.fromEnvironment(
    'AUTH_CALLBACK_SCHEME',
    defaultValue: 'worktracker',
  );
  static const String authCallbackHost = String.fromEnvironment(
    'AUTH_CALLBACK_HOST',
    defaultValue: 'auth-callback',
  );

  /// Human-readable build identifier shown in Settings. CI injects
  /// `<versionName>+<versionCode>` so installed builds are distinguishable.
  static const String appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: 'dev',
  );

  /// Public identity shown in the in-app legal documents. CI may override
  /// these values after the Play Console publisher details are finalized.
  static const String legalDeveloperName = String.fromEnvironment(
    'LEGAL_DEVELOPER_NAME',
    defaultValue: 'Building Suit',
  );
  static const String privacyContactEmail = String.fromEnvironment(
    'PRIVACY_CONTACT_EMAIL',
    defaultValue: '[privacy contact email pending]',
  );

  static bool get isProduction => appEnvironment == 'production';

  static Uri get authCallbackUri =>
      Uri(scheme: authCallbackScheme, host: authCallbackHost);

  static String get authCallbackUrl => authCallbackUri.toString();

  /// Fails fast with an actionable developer message when required
  /// configuration is missing.
  static void validate() {
    final missing = <String>[
      if (supabaseUrl.isEmpty) 'SUPABASE_URL',
      if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
    ];
    if (missing.isNotEmpty) {
      throw StateError(
        'Missing required configuration: ${missing.join(', ')}.\n'
        'Run the app with:\n'
        '  flutter run --dart-define-from-file=config/development.json\n'
        'Copy config/development.example.json to config/development.json '
        'and fill in the values from `supabase status` (local) or your '
        'Supabase project settings.',
      );
    }
  }
}
