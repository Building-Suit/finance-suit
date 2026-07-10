import 'package:meta/meta.dart';

@immutable
class UserProfile {
  const UserProfile({required this.id, required this.displayName});

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String,
    displayName: json['display_name'] as String,
  );

  final String id;
  final String displayName;
}

@immutable
class UserPreferences {
  const UserPreferences({
    required this.currencyCode,
    required this.timezone,
    required this.locale,
    required this.weekStartsOn,
    required this.weekendDays,
    required this.defaultHistoryDays,
    required this.onboardingCompleted,
  });

  factory UserPreferences.fromJson(Map<String, dynamic> json) =>
      UserPreferences(
        currencyCode: json['currency_code'] as String,
        timezone: json['timezone'] as String,
        locale: json['locale'] as String,
        weekStartsOn: json['week_starts_on'] as int,
        weekendDays: (json['weekend_days'] as List<dynamic>)
            .map((e) => e as int)
            .toList(),
        defaultHistoryDays: json['default_history_days'] as int,
        onboardingCompleted: json['onboarding_completed_at'] != null,
      );

  final String currencyCode;
  final String timezone;
  final String locale;

  /// ISO weekday 1 (Mon) .. 7 (Sun).
  final int weekStartsOn;
  final List<int> weekendDays;
  final int defaultHistoryDays;
  final bool onboardingCompleted;
}
