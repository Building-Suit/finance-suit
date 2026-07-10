import 'package:meta/meta.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';

/// A row from `public.work_entries`.
@immutable
class WorkEntry {
  const WorkEntry({
    required this.id,
    required this.workDate,
    required this.entryType,
    required this.breakMinutes,
    this.startMinuteOfDay,
    this.endMinuteOfDay,
    this.durationMinutes,
    this.dayUnitsHundredths,
    this.multiplierPct,
    this.customRateMinor,
    this.computedAmountMinor,
    this.holidayId,
    this.notes,
  });

  factory WorkEntry.fromJson(Map<String, dynamic> json) => WorkEntry(
    id: json['id'] as String,
    workDate: PlainDate.parse(json['work_date'] as String),
    entryType: WorkEntryType.fromDb(json['entry_type'] as String),
    breakMinutes: (json['break_minutes'] as num).toInt(),
    startMinuteOfDay: _parseTime(json['start_time'] as String?),
    endMinuteOfDay: _parseTime(json['end_time'] as String?),
    durationMinutes: (json['duration_minutes'] as num?)?.toInt(),
    dayUnitsHundredths: (json['day_units_hundredths'] as num?)?.toInt(),
    multiplierPct: (json['multiplier_pct'] as num?)?.toInt(),
    customRateMinor: (json['custom_rate_minor'] as num?)?.toInt(),
    computedAmountMinor: (json['computed_amount_minor'] as num?)?.toInt(),
    holidayId: json['holiday_id'] as String?,
    notes: json['notes'] as String?,
  );

  /// Parses PostgreSQL `time` wire format `HH:MM:SS` into minute-of-day.
  static int? _parseTime(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  static String? formatTime(int? minuteOfDay) {
    if (minuteOfDay == null) return null;
    final h = (minuteOfDay ~/ 60).toString().padLeft(2, '0');
    final m = (minuteOfDay % 60).toString().padLeft(2, '0');
    return '$h:$m:00';
  }

  final String id;
  final PlainDate workDate;
  final WorkEntryType entryType;
  final int breakMinutes;
  final int? startMinuteOfDay;
  final int? endMinuteOfDay;
  final int? durationMinutes;
  final int? dayUnitsHundredths;
  final int? multiplierPct;
  final int? customRateMinor;
  final int? computedAmountMinor;
  final String? holidayId;
  final String? notes;

  Money? amount(String currencyCode) => computedAmountMinor == null
      ? null
      : Money(minor: computedAmountMinor!, currencyCode: currencyCode);
}

/// Insert/update payload for a work entry. The computed amount and its
/// calculation snapshot come from the pure salary calculator at save time.
@immutable
class WorkEntryDraft {
  const WorkEntryDraft({
    required this.workDate,
    required this.entryType,
    required this.breakMinutes,
    required this.computedAmountMinor,
    required this.calcSnapshot,
    this.startMinuteOfDay,
    this.endMinuteOfDay,
    this.durationMinutes,
    this.dayUnitsHundredths,
    this.multiplierPct,
    this.customRateMinor,
    this.holidayId,
    this.notes,
  });

  final PlainDate workDate;
  final WorkEntryType entryType;
  final int breakMinutes;
  final int computedAmountMinor;
  final Map<String, dynamic> calcSnapshot;
  final int? startMinuteOfDay;
  final int? endMinuteOfDay;
  final int? durationMinutes;
  final int? dayUnitsHundredths;
  final int? multiplierPct;
  final int? customRateMinor;
  final String? holidayId;
  final String? notes;

  Map<String, dynamic> toJson() => {
    'work_date': workDate.toIso(),
    'entry_type': entryType.dbValue,
    'break_minutes': breakMinutes,
    'start_time': WorkEntry.formatTime(startMinuteOfDay),
    'end_time': WorkEntry.formatTime(endMinuteOfDay),
    'duration_minutes': durationMinutes,
    'day_units_hundredths': dayUnitsHundredths,
    'multiplier_pct': multiplierPct,
    'custom_rate_minor': customRateMinor,
    'computed_amount_minor': computedAmountMinor,
    'calc_snapshot': calcSnapshot,
    'holiday_id': holidayId,
    'notes': notes,
  };
}
