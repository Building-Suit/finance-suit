import 'package:meta/meta.dart';
import 'package:work_tracker/core/date_time/date_range.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';

enum HistoryItemGroup {
  transaction('transaction'),
  work('work'),
  salaryAdjustment('salary_adjustment');

  const HistoryItemGroup(this.dbValue);
  final String dbValue;

  static HistoryItemGroup fromDb(String value) =>
      values.firstWhere((e) => e.dbValue == value);
}

enum HistoryFilterType {
  all,
  work,
  regularWork,
  overtime,
  extraDay,
  holidayWorked,
  expense,
  allowanceGiven,
  income,
  freelanceIncome,
  salaryIncome,
  transfer,
  salaryAdjustment,
}

enum HistorySort {
  recordDateDesc,
  recordDateAsc,
  amountDesc,
  amountAsc,
  createdAtDesc,
}

@immutable
class HistoryCursor {
  const HistoryCursor({
    required this.recordDate,
    required this.createdAt,
    required this.id,
  });

  final PlainDate recordDate;
  final DateTime createdAt;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is HistoryCursor &&
      other.recordDate == recordDate &&
      other.createdAt == createdAt &&
      other.id == id;

  @override
  int get hashCode => Object.hash(recordDate, createdAt, id);
}

@immutable
class HistoryQuery {
  const HistoryQuery({
    required this.range,
    this.type = HistoryFilterType.all,
    this.sort = HistorySort.recordDateDesc,
    this.accountId,
    this.categoryId,
    this.counterparty,
    this.minAmountMinor,
    this.maxAmountMinor,
    this.keyword,
    this.salaryPeriodId,
    this.cursor,
    this.limit = 30,
  });

  factory HistoryQuery.last30Days(PlainDate today) =>
      HistoryQuery(range: rangeForPreset(DateRangePreset.last30Days, today));

  final DateRange range;
  final HistoryFilterType type;
  final HistorySort sort;
  final String? accountId;
  final String? categoryId;
  final String? counterparty;
  final int? minAmountMinor;
  final int? maxAmountMinor;
  final String? keyword;
  final String? salaryPeriodId;
  final HistoryCursor? cursor;
  final int limit;

  bool get usesDefaultKeyset =>
      sort == HistorySort.recordDateDesc && cursor != null;

  HistoryQuery copyWith({
    DateRange? range,
    HistoryFilterType? type,
    HistorySort? sort,
    String? Function()? accountId,
    String? Function()? categoryId,
    String? Function()? counterparty,
    int? Function()? minAmountMinor,
    int? Function()? maxAmountMinor,
    String? Function()? keyword,
    String? Function()? salaryPeriodId,
    HistoryCursor? Function()? cursor,
    int? limit,
  }) {
    return HistoryQuery(
      range: range ?? this.range,
      type: type ?? this.type,
      sort: sort ?? this.sort,
      accountId: accountId == null ? this.accountId : accountId(),
      categoryId: categoryId == null ? this.categoryId : categoryId(),
      counterparty: counterparty == null ? this.counterparty : counterparty(),
      minAmountMinor: minAmountMinor == null
          ? this.minAmountMinor
          : minAmountMinor(),
      maxAmountMinor: maxAmountMinor == null
          ? this.maxAmountMinor
          : maxAmountMinor(),
      keyword: keyword == null ? this.keyword : keyword(),
      salaryPeriodId: salaryPeriodId == null
          ? this.salaryPeriodId
          : salaryPeriodId(),
      cursor: cursor == null ? this.cursor : cursor(),
      limit: limit ?? this.limit,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HistoryQuery &&
      other.range == range &&
      other.type == type &&
      other.sort == sort &&
      other.accountId == accountId &&
      other.categoryId == categoryId &&
      other.counterparty == counterparty &&
      other.minAmountMinor == minAmountMinor &&
      other.maxAmountMinor == maxAmountMinor &&
      other.keyword == keyword &&
      other.salaryPeriodId == salaryPeriodId &&
      other.cursor == cursor &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(
    range,
    type,
    sort,
    accountId,
    categoryId,
    counterparty,
    minAmountMinor,
    maxAmountMinor,
    keyword,
    salaryPeriodId,
    cursor,
    limit,
  );
}

@immutable
class HistoryItem {
  const HistoryItem({
    required this.id,
    required this.group,
    required this.recordType,
    required this.recordDate,
    required this.createdAt,
    this.amountMinor,
    this.currencyCode,
    this.sourceAccountId,
    this.destinationAccountId,
    this.categoryId,
    this.counterparty,
    this.salaryPeriodId,
    this.title,
    this.notes,
  });

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
    id: json['id'] as String,
    group: HistoryItemGroup.fromDb(json['record_group'] as String),
    recordType: json['record_type'] as String,
    recordDate: PlainDate.parse(json['record_date'] as String),
    createdAt: DateTime.parse(json['created_at'] as String),
    amountMinor: (json['amount_minor'] as num?)?.toInt(),
    currencyCode: json['currency_code'] as String?,
    sourceAccountId: json['source_account_id'] as String?,
    destinationAccountId: json['destination_account_id'] as String?,
    categoryId: json['category_id'] as String?,
    counterparty: json['counterparty'] as String?,
    salaryPeriodId: json['salary_period_id'] as String?,
    title: json['title'] as String?,
    notes: json['notes'] as String?,
  );

  final String id;
  final HistoryItemGroup group;
  final String recordType;
  final PlainDate recordDate;
  final DateTime createdAt;
  final int? amountMinor;
  final String? currencyCode;
  final String? sourceAccountId;
  final String? destinationAccountId;
  final String? categoryId;
  final String? counterparty;
  final String? salaryPeriodId;
  final String? title;
  final String? notes;

  HistoryCursor get cursor =>
      HistoryCursor(recordDate: recordDate, createdAt: createdAt, id: id);

  Money? get amount => amountMinor == null
      ? null
      : Money(minor: amountMinor!, currencyCode: currencyCode ?? 'EGP');

  TransactionKind? get transactionKind {
    if (group != HistoryItemGroup.transaction) return null;
    return TransactionKind.fromDb(recordType);
  }

  WorkEntryType? get workEntryType {
    if (group != HistoryItemGroup.work) return null;
    return WorkEntryType.fromDb(recordType);
  }

  bool get isIncome =>
      recordType == TransactionKind.customIncome.dbValue ||
      recordType == TransactionKind.freelanceIncome.dbValue ||
      recordType == TransactionKind.salaryIncome.dbValue;

  bool get isOutgoing =>
      recordType == TransactionKind.expense.dbValue ||
      recordType == TransactionKind.allowanceGiven.dbValue ||
      amountMinor != null && amountMinor! < 0;
}

@immutable
class HistoryPage {
  const HistoryPage({required this.items, required this.hasMore});

  final List<HistoryItem> items;
  final bool hasMore;

  HistoryCursor? get nextCursor => items.isEmpty ? null : items.last.cursor;
}
