import 'package:meta/meta.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/money/money.dart';

/// A row from `app_finance.held_amounts`: money the user owes someone,
/// optionally linked to the transaction it originated from. Deleting that
/// transaction unlinks the hold but keeps the record.
@immutable
class HeldAmount {
  const HeldAmount({
    required this.id,
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
    required this.amountMinor,
    required this.currencyCode,
    required this.counterparty,
    required this.heldOn,
    this.transactionId,
    this.title,
    this.notes,
  });

  final int amountMinor;
  final String currencyCode;
  final String counterparty;
  final PlainDate heldOn;
  final String? transactionId;
  final String? title;
  final String? notes;

  Map<String, dynamic> toJson() => {
    'amount_minor': amountMinor,
    'currency_code': currencyCode,
    'counterparty': counterparty,
    'held_on': heldOn.toIso(),
    'transaction_id': transactionId,
    'title': title,
    'notes': notes,
  };
}
