import 'package:flutter/foundation.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';

/// One row from `list_holds_against_me`: a held amount another Finance Suit
/// user recorded against the current user through a network connection.
///
/// This is the only cross-user view of a held amount, and it is read-only —
/// the counterparty can see the number but cannot settle, edit or dispute it,
/// and it never touches their own balances or held totals. The projection
/// deliberately carries no account, category, transaction id, title or private
/// notes; [sharedNote] is the single field the owner chose to share.
@immutable
class HeldAgainstMe {
  const HeldAgainstMe({
    required this.id,
    required this.ownerDirection,
    required this.counterpartyAlias,
    required this.amountMinor,
    required this.currencyCode,
    required this.heldOn,
    required this.connectionActive,
    required this.recordedAt,
    this.connectionId,
    this.settledOn,
    this.sharedNote,
  });

  factory HeldAgainstMe.fromJson(Map<String, dynamic> json) => HeldAgainstMe(
    id: json['held_id'] as String,
    ownerDirection: HeldAmountDirection.fromDb(
      json['owner_direction'] as String,
    ),
    counterpartyAlias: json['counterparty_alias'] as String? ?? '',
    amountMinor: (json['amount_minor'] as num).toInt(),
    currencyCode: json['currency_code'] as String,
    heldOn: PlainDate.parse(json['held_on'] as String),
    connectionActive: json['connection_active'] as bool? ?? false,
    recordedAt: DateTime.parse(json['recorded_at'] as String).toUtc(),
    connectionId: json['connection_id'] as String?,
    settledOn: switch (json['settled_on']) {
      final String value => PlainDate.parse(value),
      _ => null,
    },
    sharedNote: json['shared_note'] as String?,
  );

  final String id;

  /// The direction as the *owner* stored it, not as the viewer experiences it.
  /// See [theyOweMe] for the flip.
  final HeldAmountDirection ownerDirection;

  /// The viewer's own private alias for the person holding the amount.
  final String counterpartyAlias;
  final int amountMinor;
  final String currencyCode;
  final PlainDate heldOn;
  final bool connectionActive;
  final DateTime recordedAt;
  final String? connectionId;
  final PlainDate? settledOn;
  final String? sharedNote;

  Money get amount => Money(minor: amountMinor, currencyCode: currencyCode);

  bool get isSettled => settledOn != null;

  /// The owner recording "I owe" means they are holding the money *for* the
  /// viewer; "owed to me" means they are holding it *against* them.
  bool get theyOweMe => ownerDirection == HeldAmountDirection.iOwe;
}
