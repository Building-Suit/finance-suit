import 'package:meta/meta.dart';
import 'package:work_tracker/core/date_time/date_range.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/finance/domain/financial_transaction.dart';

/// The kinds a transaction list can be narrowed to. Income collapses the
/// three income kinds into the one grouping users think in.
enum TransactionFilterKind {
  all,
  expense,
  allowanceGiven,
  income,
  transfer;

  /// The database kinds this filter admits; empty means no restriction.
  List<TransactionKind> get kinds => switch (this) {
    TransactionFilterKind.all => const [],
    TransactionFilterKind.expense => const [TransactionKind.expense],
    TransactionFilterKind.allowanceGiven => const [
      TransactionKind.allowanceGiven,
    ],
    TransactionFilterKind.income => const [
      TransactionKind.customIncome,
      TransactionKind.freelanceIncome,
      TransactionKind.salaryIncome,
    ],
    TransactionFilterKind.transfer => const [TransactionKind.transfer],
  };
}

/// Keyset position in the newest-first transaction list. Paging on the
/// (date, sort_at, id) triple rather than an offset keeps the next page
/// correct even when rows are added or removed while the user scrolls.
@immutable
class TransactionCursor {
  const TransactionCursor({
    required this.occurredOn,
    required this.sortAt,
    required this.id,
  });

  /// The cursor that continues the list after [transaction], or null when
  /// the row predates the ordering key and cannot anchor a page.
  static TransactionCursor? after(FinancialTransaction transaction) {
    final sortAt = transaction.sortAt;
    if (sortAt == null) return null;
    return TransactionCursor(
      occurredOn: transaction.occurredOn,
      sortAt: sortAt,
      id: transaction.id,
    );
  }

  final PlainDate occurredOn;
  final DateTime sortAt;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is TransactionCursor &&
      other.occurredOn == occurredOn &&
      other.sortAt == sortAt &&
      other.id == id;

  @override
  int get hashCode => Object.hash(occurredOn, sortAt, id);
}

/// One filtered page request for the Money tab's transaction list.
@immutable
class TransactionQuery {
  const TransactionQuery({
    this.range,
    this.kind = TransactionFilterKind.all,
    this.accountId,
    this.categoryId,
    this.keyword,
    this.minAmountMinor,
    this.maxAmountMinor,
    this.cursor,
    this.limit = 30,
  });

  /// Null means every date: the list opens unfiltered, and a range is an
  /// explicit narrowing rather than a hidden default that hides rows.
  final DateRange? range;

  final TransactionFilterKind kind;

  /// Matches the transaction's own account on either side, so a transfer is
  /// found from both ends and a card charge from its facility.
  final String? accountId;

  final String? categoryId;

  /// Free text over title, notes, and counterparty.
  final String? keyword;

  final int? minAmountMinor;
  final int? maxAmountMinor;
  final TransactionCursor? cursor;
  final int limit;

  bool get hasActiveFilters =>
      range != null ||
      kind != TransactionFilterKind.all ||
      accountId != null ||
      categoryId != null ||
      (keyword?.trim().isNotEmpty ?? false) ||
      minAmountMinor != null ||
      maxAmountMinor != null;

  TransactionQuery copyWith({
    DateRange? Function()? range,
    TransactionFilterKind? kind,
    String? Function()? accountId,
    String? Function()? categoryId,
    String? Function()? keyword,
    int? Function()? minAmountMinor,
    int? Function()? maxAmountMinor,
    TransactionCursor? Function()? cursor,
    int? limit,
  }) => TransactionQuery(
    range: range == null ? this.range : range(),
    kind: kind ?? this.kind,
    accountId: accountId == null ? this.accountId : accountId(),
    categoryId: categoryId == null ? this.categoryId : categoryId(),
    keyword: keyword == null ? this.keyword : keyword(),
    minAmountMinor: minAmountMinor == null
        ? this.minAmountMinor
        : minAmountMinor(),
    maxAmountMinor: maxAmountMinor == null
        ? this.maxAmountMinor
        : maxAmountMinor(),
    cursor: cursor == null ? this.cursor : cursor(),
    limit: limit ?? this.limit,
  );

  // Value equality lets the query key a provider family, so two identical
  // filter sets share one request instead of refetching.
  @override
  bool operator ==(Object other) =>
      other is TransactionQuery &&
      other.range == range &&
      other.kind == kind &&
      other.accountId == accountId &&
      other.categoryId == categoryId &&
      other.keyword == keyword &&
      other.minAmountMinor == minAmountMinor &&
      other.maxAmountMinor == maxAmountMinor &&
      other.cursor == cursor &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(
    range,
    kind,
    accountId,
    categoryId,
    keyword,
    minAmountMinor,
    maxAmountMinor,
    cursor,
    limit,
  );
}

/// One page of transactions plus whether another page exists.
@immutable
class TransactionPage {
  const TransactionPage({required this.items, required this.hasMore});

  final List<FinancialTransaction> items;
  final bool hasMore;
}
