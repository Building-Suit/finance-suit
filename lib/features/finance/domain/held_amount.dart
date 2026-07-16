import 'package:meta/meta.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';

/// A row from `app_finance.held_amounts`: money owed in either direction,
/// optionally linked to the transaction it originated from. Deleting that
/// transaction unlinks the held amount but keeps the record.
@immutable
class HeldAmount {
  const HeldAmount({
    required this.id,
    required this.direction,
    required this.amountMinor,
    required this.currencyCode,
    required this.counterparty,
    required this.heldOn,
    this.settledOn,
    this.transactionId,
    this.title,
    this.notes,
  });

  factory HeldAmount.fromJson(Map<String, dynamic> json) => HeldAmount(
    id: json['id'] as String,
    direction: HeldAmountDirection.fromDb(json['direction'] as String),
    amountMinor: (json['amount_minor'] as num).toInt(),
    currencyCode: json['currency_code'] as String,
    counterparty: json['counterparty'] as String,
    heldOn: PlainDate.parse(json['held_on'] as String),
    settledOn: switch (json['settled_on'] as String?) {
      final String iso => PlainDate.parse(iso),
      null => null,
    },
    transactionId: json['transaction_id'] as String?,
    title: json['title'] as String?,
    notes: json['notes'] as String?,
  );

  final String id;
  final HeldAmountDirection direction;
  final int amountMinor;
  final String currencyCode;
  final String counterparty;
  final PlainDate heldOn;
  final PlainDate? settledOn;
  final String? transactionId;
  final String? title;
  final String? notes;

  Money get amount => Money(minor: amountMinor, currencyCode: currencyCode);
  bool get isSettled => settledOn != null;
  bool get isLinked => transactionId != null;
}

/// Payload for inserting or updating a held amount. Also used as the
/// prefill when creating a hold from an existing transaction.
@immutable
class HeldAmountDraft {
  const HeldAmountDraft({
    required this.direction,
    required this.amountMinor,
    required this.currencyCode,
    required this.counterparty,
    required this.heldOn,
    this.transactionId,
    this.title,
    this.notes,
  });

  final HeldAmountDirection direction;
  final int amountMinor;
  final String currencyCode;
  final String counterparty;
  final PlainDate heldOn;
  final String? transactionId;
  final String? title;
  final String? notes;

  Map<String, dynamic> toJson() => {
    'direction': direction.dbValue,
    'amount_minor': amountMinor,
    'currency_code': currencyCode,
    'counterparty': counterparty,
    'held_on': heldOn.toIso(),
    'transaction_id': transactionId,
    'title': title,
    'notes': notes,
  };
}

/// Active held amounts aggregated independently by direction and currency.
///
/// Stored amounts remain positive magnitudes; [HeldAmount.direction] carries
/// their financial meaning. Settled rows never contribute to active totals.
@immutable
class ActiveHeldAmountTotals {
  ActiveHeldAmountTotals._(
    Map<String, int> iOweByCurrency,
    Map<String, int> owedToMeByCurrency,
  ) : iOweByCurrency = Map.unmodifiable(iOweByCurrency),
      owedToMeByCurrency = Map.unmodifiable(owedToMeByCurrency);

  factory ActiveHeldAmountTotals.from(Iterable<HeldAmount> heldAmounts) {
    final iOweByCurrency = <String, int>{};
    final owedToMeByCurrency = <String, int>{};

    for (final held in heldAmounts) {
      if (held.isSettled) continue;
      final totals = switch (held.direction) {
        HeldAmountDirection.iOwe => iOweByCurrency,
        HeldAmountDirection.owedToMe => owedToMeByCurrency,
      };
      totals[held.currencyCode] =
          (totals[held.currencyCode] ?? 0) + held.amountMinor;
    }

    return ActiveHeldAmountTotals._(iOweByCurrency, owedToMeByCurrency);
  }

  final Map<String, int> iOweByCurrency;
  final Map<String, int> owedToMeByCurrency;

  Map<String, int> forDirection(HeldAmountDirection direction) {
    return switch (direction) {
      HeldAmountDirection.iOwe => iOweByCurrency,
      HeldAmountDirection.owedToMe => owedToMeByCurrency,
    };
  }
}
