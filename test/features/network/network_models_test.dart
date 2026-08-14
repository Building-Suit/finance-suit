import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/network/domain/network_models.dart';

void main() {
  test('search results parse identity and relationship state', () {
    final result = NetworkUserSearchResult.fromJson(const {
      'target_user_id': 'user-2',
      'display_name': 'Mona Ahmed',
      'email': 'mona@example.com',
      'relationship_state': 'incoming_pending',
      'request_direction': 'incoming',
      'request_id': 'request-1',
    });
    expect(result.userId, 'user-2');
    expect(result.displayName, 'Mona Ahmed');
    expect(result.email, 'mona@example.com');
    expect(result.relationshipState, NetworkRelationshipState.incomingPending);
    expect(result.requestId, 'request-1');
  });

  test('add requests keep the private alias only on the outgoing side', () {
    final incoming = NetworkAddRequest.fromJson(const {
      'request_id': 'request-1',
      'direction': 'incoming',
      'other_user_id': 'user-1',
      'other_display_name': 'Tarek Abdelwahab',
      'other_email': 'tarek@example.com',
      'my_alias': null,
      'status': 'pending',
      'requested_at': '2026-08-01T10:00:00Z',
      'responded_at': null,
    });
    expect(incoming.isIncoming, isTrue);
    expect(incoming.isPending, isTrue);
    expect(incoming.myAlias, isNull);
    expect(incoming.otherDisplayName, 'Tarek Abdelwahab');

    final outgoing = NetworkAddRequest.fromJson(const {
      'request_id': 'request-2',
      'direction': 'outgoing',
      'other_user_id': 'user-2',
      'other_display_name': 'Mona Ahmed',
      'other_email': 'mona@example.com',
      'my_alias': 'Wife',
      'status': 'accepted',
      'requested_at': '2026-08-01T10:00:00Z',
      'responded_at': '2026-08-01T11:00:00Z',
    });
    expect(outgoing.isIncoming, isFalse);
    expect(outgoing.myAlias, 'Wife');
    expect(outgoing.status, NetworkAddRequestStatus.accepted);
    expect(outgoing.respondedAt, isNotNull);
  });

  test('contacts resolve the caller-side alias', () {
    final contact = NetworkContact.fromJson(const {
      'connection_id': 'connection-1',
      'other_user_id': 'user-2',
      'local_alias': 'Wife',
      'real_display_name': 'Mona Ahmed',
      'email': 'mona@example.com',
      'connected_at': '2026-08-01T10:00:00Z',
    });
    expect(contact.localAlias, 'Wife');
    expect(contact.realDisplayName, 'Mona Ahmed');
  });

  test('transfers expose direction, money, and actionability', () {
    final received = NetworkTransfer.fromJson(const {
      'transfer_id': 'transfer-1',
      'connection_id': 'connection-1',
      'direction': 'received',
      'counterparty_alias': 'Tarek',
      'amount_minor': 50000,
      'currency_code': 'EGP',
      'status': 'pending',
      'requested_on': '2026-08-14',
      'requested_at': '2026-08-14T09:00:00Z',
      'responded_at': null,
      'shared_note': 'rent share',
      'origin_kind': 'manual',
      'my_account_id': null,
      'my_transaction_id': null,
      'connection_active': true,
    });
    expect(received.isIncoming, isTrue);
    expect(received.isPending, isTrue);
    expect(received.isActionable, isTrue);
    expect(received.amount.minor, 50000);
    expect(received.amount.currencyCode, 'EGP');
    expect(received.origin, NetworkTransferOrigin.manual);

    final sent = NetworkTransfer.fromJson(const {
      'transfer_id': 'transfer-2',
      'connection_id': 'connection-1',
      'direction': 'sent',
      'counterparty_alias': 'Wife',
      'amount_minor': 200000,
      'currency_code': 'EGP',
      'status': 'accepted',
      'requested_on': '2026-08-10',
      'requested_at': '2026-08-10T09:00:00Z',
      'responded_at': '2026-08-11T09:00:00Z',
      'shared_note': null,
      'origin_kind': 'recurring_rule',
      'my_account_id': 'account-1',
      'my_transaction_id': 'tx-1',
      'connection_active': true,
    });
    // The sender never gets accept/reject, whatever the status.
    expect(sent.isActionable, isFalse);
    expect(sent.origin, NetworkTransferOrigin.recurringRule);
    expect(sent.myAccountId, 'account-1');
  });

  test('a removed connection makes a pending incoming transfer inert', () {
    final transfer = NetworkTransfer.fromJson(const {
      'transfer_id': 'transfer-3',
      'connection_id': null,
      'direction': 'received',
      'counterparty_alias': '',
      'amount_minor': 700,
      'currency_code': 'EGP',
      'status': 'pending',
      'requested_on': '2026-08-14',
      'requested_at': '2026-08-14T09:00:00Z',
      'responded_at': null,
      'shared_note': null,
      'origin_kind': 'manual',
      'my_account_id': null,
      'my_transaction_id': null,
      'connection_active': false,
    });
    expect(transfer.isActionable, isFalse);
  });
}
