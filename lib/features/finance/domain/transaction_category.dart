import 'package:meta/meta.dart';
import 'package:work_tracker/core/domain/db_enums.dart';

/// A row from `app_finance.transaction_categories`.
@immutable
class TransactionCategory {
  const TransactionCategory({
    required this.id,
    required this.name,
    required this.kind,
    required this.icon,
    required this.sortOrder,
    required this.isArchived,
  });

  factory TransactionCategory.fromJson(Map<String, dynamic> json) =>
      TransactionCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: CategoryKind.fromDb(json['category_kind'] as String),
        icon: json['icon'] as String,
        sortOrder: (json['sort_order'] as num).toInt(),
        isArchived: json['is_archived'] as bool,
      );

  final String id;
  final String name;
  final CategoryKind kind;
  final String icon;
  final int sortOrder;
  final bool isArchived;
}
