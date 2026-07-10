import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/result/result.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';

/// Payload for the atomic `complete_onboarding` RPC.
class OnboardingSubmission {
  const OnboardingSubmission({
    required this.displayName,
    required this.currencyCode,
    required this.timezone,
    required this.locale,
    required this.weekStartsOn,
    required this.weekendDays,
    required this.baseSalaryMinor,
    required this.salaryPeriodStartDay,
    required this.paymentDay,
    required this.paymentMonthOffset,
    required this.standardPaidDays,
    required this.standardMinutesPerDay,
    required this.dayRateMode,
    required this.manualDayRateMinor,
    required this.hourRateMode,
    required this.manualHourRateMinor,
    required this.extraDayMultiplierPct,
    required this.officialHolidayMultiplierPct,
    required this.overtimeMultiplierPct,
    required this.holidaySemantics,
    required this.accountName,
    required this.accountType,
    required this.openingBalanceMinor,
    required this.allowNegativeBalance,
  });

  final String displayName;
  final String currencyCode;
  final String timezone;
  final String locale;
  final int weekStartsOn;
  final List<int> weekendDays;
  final int baseSalaryMinor;
  final int salaryPeriodStartDay;
  final int paymentDay;
  final int paymentMonthOffset;
  final int standardPaidDays;
  final int standardMinutesPerDay;
  final RateMode dayRateMode;
  final int? manualDayRateMinor;
  final RateMode hourRateMode;
  final int? manualHourRateMinor;
  final int extraDayMultiplierPct;
  final int officialHolidayMultiplierPct;
  final int overtimeMultiplierPct;
  final HolidayMultiplierSemantics holidaySemantics;
  final String accountName;
  final AccountType accountType;
  final int openingBalanceMinor;
  final bool allowNegativeBalance;
}

class OnboardingRepository {
  OnboardingRepository(this._client);

  final SupabaseClient _client;

  /// Returns the id of the created first account.
  Future<Result<String>> completeOnboarding(OnboardingSubmission s) {
    return guard(() async {
      final result = await _client.rpc<String>(
        'complete_onboarding',
        params: {
          'p_display_name': s.displayName,
          'p_currency_code': s.currencyCode,
          'p_timezone': s.timezone,
          'p_locale': s.locale,
          'p_week_starts_on': s.weekStartsOn,
          'p_weekend_days': s.weekendDays,
          'p_base_salary_minor': s.baseSalaryMinor,
          'p_salary_period_start_day': s.salaryPeriodStartDay,
          'p_payment_day': s.paymentDay,
          'p_payment_month_offset': s.paymentMonthOffset,
          'p_standard_paid_days': s.standardPaidDays,
          'p_standard_minutes_per_day': s.standardMinutesPerDay,
          'p_day_rate_mode': s.dayRateMode.dbValue,
          'p_manual_day_rate_minor': s.manualDayRateMinor,
          'p_hour_rate_mode': s.hourRateMode.dbValue,
          'p_manual_hour_rate_minor': s.manualHourRateMinor,
          'p_extra_day_multiplier_pct': s.extraDayMultiplierPct,
          'p_official_holiday_multiplier_pct': s.officialHolidayMultiplierPct,
          'p_overtime_multiplier_pct': s.overtimeMultiplierPct,
          'p_holiday_semantics': s.holidaySemantics.dbValue,
          'p_account_name': s.accountName,
          'p_account_type': s.accountType.dbValue,
          'p_opening_balance_minor': s.openingBalanceMinor,
          'p_allow_negative_balance': s.allowNegativeBalance,
        },
      );
      return result;
    });
  }
}

final onboardingRepositoryProvider = Provider<OnboardingRepository>(
  (ref) => OnboardingRepository(ref.watch(supabaseClientProvider)),
);
