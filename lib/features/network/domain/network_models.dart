import 'package:flutter/foundation.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';

/// How another Finance Suit user relates to the current user, as resolved
/// server-side by `search_network_users`.
enum NetworkRelationshipState {
  none('none'),
  outgoingPending('outgoing_pending'),
  incomingPending('incoming_pending'),
  connected('connected');

  const NetworkRelationshipState(this.dbValue);
  final String dbValue;

  static NetworkRelationshipState fromDb(String value) =>
      values.firstWhere((e) => e.dbValue == value);
}

/// Which side of an add request or transfer the current user is on.
enum NetworkDirection {
  outgoing('outgoing'),
  incoming('incoming');

  const NetworkDirection(this.dbValue);
  final String dbValue;

  static NetworkDirection fromDb(String value) =>
      values.firstWhere((e) => e.dbValue == value);
}

/// One row from `search_network_users`: another user's public identity plus
/// the relationship state — never accounts, balances, or transactions.
@immutable
class NetworkUserSearchResult {
  const NetworkUserSearchResult({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.relationshipState,
    this.requestId,
  });

  factory NetworkUserSearchResult.fromJson(Map<String, dynamic> json) =>
      NetworkUserSearchResult(
        userId: json['target_user_id'] as String,
        displayName: json['display_name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        relationshipState: NetworkRelationshipState.fromDb(
          json['relationship_state'] as String,
        ),
        requestId: json['request_id'] as String?,
      );

  final String userId;
  final String displayName;
  final String email;
  final NetworkRelationshipState relationshipState;

  /// The pending add request between the two users, when one exists.
  final String? requestId;
}

/// One row from `list_network_add_requests`, direction already resolved.
/// [myAlias] is only present on outgoing requests: the private alias a
/// requester chose is never shown to the recipient.
@immutable
class NetworkAddRequest {
  const NetworkAddRequest({
    required this.id,
    required this.direction,
    required this.otherUserId,
    required this.otherDisplayName,
    required this.otherEmail,
    required this.status,
    required this.requestedAt,
    this.myAlias,
    this.respondedAt,
  });

  factory NetworkAddRequest.fromJson(Map<String, dynamic> json) =>
      NetworkAddRequest(
        id: json['request_id'] as String,
        direction: NetworkDirection.fromDb(json['direction'] as String),
        otherUserId: json['other_user_id'] as String,
        otherDisplayName: json['other_display_name'] as String? ?? '',
        otherEmail: json['other_email'] as String? ?? '',
        status: NetworkAddRequestStatus.fromDb(json['status'] as String),
        requestedAt: DateTime.parse(json['requested_at'] as String).toUtc(),
        myAlias: json['my_alias'] as String?,
        respondedAt: switch (json['responded_at']) {
          final String value => DateTime.parse(value).toUtc(),
          _ => null,
        },
      );

  final String id;
  final NetworkDirection direction;
  final String otherUserId;
  final String otherDisplayName;
  final String otherEmail;
  final NetworkAddRequestStatus status;
  final DateTime requestedAt;
  final String? myAlias;
  final DateTime? respondedAt;

  bool get isIncoming => direction == NetworkDirection.incoming;
  bool get isPending => status == NetworkAddRequestStatus.pending;
}

/// One row from `list_network_contacts`: the caller's private alias plus the
/// contact's real identity, with the alias direction resolved server-side.
@immutable
class NetworkContact {
  const NetworkContact({
    required this.connectionId,
    required this.otherUserId,
    required this.localAlias,
    required this.realDisplayName,
    required this.email,
    required this.connectedAt,
  });

  factory NetworkContact.fromJson(Map<String, dynamic> json) => NetworkContact(
    connectionId: json['connection_id'] as String,
    otherUserId: json['other_user_id'] as String,
    localAlias: json['local_alias'] as String,
    realDisplayName: json['real_display_name'] as String? ?? '',
    email: json['email'] as String? ?? '',
    connectedAt: DateTime.parse(json['connected_at'] as String).toUtc(),
  );

  final String connectionId;
  final String otherUserId;
  final String localAlias;
  final String realDisplayName;
  final String email;
  final DateTime connectedAt;
}

/// One row from `list_network_transfers`. Each party sees the shared facts
/// plus only their own side: [myAccountId] is the sender's source for sent
/// transfers and the receiver's chosen destination for received ones — the
/// other party's account never crosses the wire.
@immutable
class NetworkTransfer {
  const NetworkTransfer({
    required this.id,
    required this.direction,
    required this.counterpartyAlias,
    required this.amountMinor,
    required this.currencyCode,
    required this.status,
    required this.requestedOn,
    required this.requestedAt,
    required this.origin,
    required this.connectionActive,
    this.connectionId,
    this.respondedAt,
    this.sharedNote,
    this.myAccountId,
    this.myTransactionId,
  });

  factory NetworkTransfer.fromJson(Map<String, dynamic> json) =>
      NetworkTransfer(
        id: json['transfer_id'] as String,
        direction: (json['direction'] as String) == 'sent'
            ? NetworkDirection.outgoing
            : NetworkDirection.incoming,
        counterpartyAlias: json['counterparty_alias'] as String? ?? '',
        amountMinor: (json['amount_minor'] as num).toInt(),
        currencyCode: json['currency_code'] as String,
        status: NetworkTransferStatus.fromDb(json['status'] as String),
        requestedOn: PlainDate.parse(json['requested_on'] as String),
        requestedAt: DateTime.parse(json['requested_at'] as String).toUtc(),
        origin: NetworkTransferOrigin.fromDb(json['origin_kind'] as String),
        connectionActive: json['connection_active'] as bool? ?? false,
        connectionId: json['connection_id'] as String?,
        respondedAt: switch (json['responded_at']) {
          final String value => DateTime.parse(value).toUtc(),
          _ => null,
        },
        sharedNote: json['shared_note'] as String?,
        myAccountId: json['my_account_id'] as String?,
        myTransactionId: json['my_transaction_id'] as String?,
      );

  final String id;
  final NetworkDirection direction;
  final String counterpartyAlias;
  final int amountMinor;
  final String currencyCode;
  final NetworkTransferStatus status;
  final PlainDate requestedOn;
  final DateTime requestedAt;
  final NetworkTransferOrigin origin;
  final bool connectionActive;
  final String? connectionId;
  final DateTime? respondedAt;
  final String? sharedNote;
  final String? myAccountId;
  final String? myTransactionId;

  Money get amount => Money(minor: amountMinor, currencyCode: currencyCode);

  bool get isIncoming => direction == NetworkDirection.incoming;
  bool get isPending => status == NetworkTransferStatus.pending;

  /// An incoming pending transfer the receiver can still act on.
  bool get isActionable => isIncoming && isPending && connectionActive;
}
