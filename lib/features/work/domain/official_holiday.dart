import 'package:meta/meta.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';

/// A row from `public.official_holidays`.
@immutable
class OfficialHoliday {
  const OfficialHoliday({
    required this.id,
    required this.date,
    required this.name,
    this.notes,
  });

  factory OfficialHoliday.fromJson(Map<String, dynamic> json) =>
      OfficialHoliday(
        id: json['id'] as String,
        date: PlainDate.parse(json['holiday_date'] as String),
        name: json['name'] as String,
        notes: json['notes'] as String?,
      );

  final String id;
  final PlainDate date;
  final String name;
  final String? notes;
}
