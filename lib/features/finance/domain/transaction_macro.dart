import 'package:meta/meta.dart';
import 'package:work_tracker/core/domain/db_enums.dart';

/// One saved action inside a macro. Mirrors the direction rules of
/// `financial_transactions`; currency is resolved from the accounts when the
/// macro is applied, so items never store a stale currency code.
@immutable
class TransactionMacroItem {
  const TransactionMacroItem({
    required this.kind,
    required this.amountMinor,
    this.id,
    this.sourceAccountId,
    this.destinationAccountId,
    this.categoryId,
    this.counterparty,
    this.title,
    this.notes,
    this.isReversible = false,
  });

  factory TransactionMacroItem.fromJson(Map<String, dynamic> json) =>
      TransactionMacroItem(
        id: json['id'] as String?,
        kind: TransactionKind.fromDb(json['transaction_kind'] as String),
        amountMinor: (json['amount_minor'] as num).toInt(),
        sourceAccountId: json['source_account_id'] as String?,
        destinationAccountId: json['destination_account_id'] as String?,
        categoryId: json['category_id'] as String?,
        counterparty: json['counterparty'] as String?,
        title: json['title'] as String?,
        notes: json['notes'] as String?,
        isReversible: json['is_reversible'] as bool? ?? false,
      );

  final String? id;
  final TransactionKind kind;
  final int amountMinor;
  final String? sourceAccountId;
  final String? destinationAccountId;
  final String? categoryId;
  final String? counterparty;
  final String? title;
  final String? notes;
  final bool isReversible;

  bool get isTransfer => kind == TransactionKind.transfer;

  /// Payload element for the `save_macro` RPC.
  Map<String, dynamic> toPayload(int position) => {
    'position': position,
    'transaction_kind': kind.dbValue,
    'amount_minor': amountMinor,
    'source_account_id': sourceAccountId,
    'destination_account_id': destinationAccountId,
    'category_id': categoryId,
    'counterparty': counterparty,
    'title': title,
    'notes': notes,
    'is_reversible': isReversible,
  };
}

/// A row from `app_finance.transaction_macros` with its items.
@immutable
class TransactionMacro {
  const TransactionMacro({
    required this.id,
    required this.name,
    required this.items,
  });

  factory TransactionMacro.fromJson(Map<String, dynamic> json) {
    final rawItems =
        (json['transaction_macro_items'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>()
            .toList()
          ..sort(
            (a, b) => (a['position'] as num).compareTo(b['position'] as num),
          );
    return TransactionMacro(
      id: json['id'] as String,
      name: json['name'] as String,
      items: rawItems.map(TransactionMacroItem.fromJson).toList(),
    );
  }

  final String id;
  final String name;
  final List<TransactionMacroItem> items;

  /// Reversible macros can also be run backwards ("From `<name>`"),
  /// applying only the items flagged as reversible.
  bool get isReversible => items.any((item) => item.isReversible);
}
