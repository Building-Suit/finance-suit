import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/result/result.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/network/domain/held_against_me.dart';
import 'package:work_tracker/features/network/domain/network_models.dart';

/// Data access for the Finance Suit Network: user discovery, add requests,
/// connections with private directional aliases, and pending network
/// transfers. Everything goes through the narrow server RPCs — the client
/// never reads profile tables directly and never mutates network rows.
class NetworkRepository {
  NetworkRepository(this._client);

  final SupabaseClient _client;

  SupabaseQuerySchema get _db => _client.schema(AppSchemas.finance);

  Future<Result<List<NetworkUserSearchResult>>> searchUsers(String query) {
    return guard(() async {
      final rows = await _db.rpc<List<dynamic>>(
        'search_network_users',
        params: {'p_query': query},
      );
      return rows
          .map(
            (row) =>
                NetworkUserSearchResult.fromJson(row as Map<String, dynamic>),
          )
          .toList();
    });
  }

  Future<Result<String>> sendAddRequest({
    required String targetUserId,
    required String localAlias,
  }) {
    return guard(() async {
      return _db.rpc<String>(
        'send_network_add_request',
        params: {'p_target_user_id': targetUserId, 'p_local_alias': localAlias},
      );
    });
  }

  Future<Result<String>> acceptAddRequest({
    required String requestId,
    required String localAlias,
  }) {
    return guard(() async {
      return _db.rpc<String>(
        'accept_network_add_request',
        params: {'p_request_id': requestId, 'p_local_alias': localAlias},
      );
    });
  }

  Future<Result<void>> rejectAddRequest(String requestId) {
    return guard(() async {
      await _db.rpc<void>(
        'reject_network_add_request',
        params: {'p_request_id': requestId},
      );
    });
  }

  Future<Result<List<NetworkAddRequest>>> fetchAddRequests() {
    return guard(() async {
      final rows = await _db.rpc<List<dynamic>>('list_network_add_requests');
      return rows
          .map((row) => NetworkAddRequest.fromJson(row as Map<String, dynamic>))
          .toList();
    });
  }

  Future<Result<List<NetworkContact>>> fetchContacts() {
    return guard(() async {
      final rows = await _db.rpc<List<dynamic>>('list_network_contacts');
      return rows
          .map((row) => NetworkContact.fromJson(row as Map<String, dynamic>))
          .toList();
    });
  }

  Future<Result<void>> renameContact({
    required String connectionId,
    required String newAlias,
  }) {
    return guard(() async {
      await _db.rpc<void>(
        'rename_network_contact',
        params: {'p_connection_id': connectionId, 'p_new_alias': newAlias},
      );
    });
  }

  Future<Result<void>> removeConnection(String connectionId) {
    return guard(() async {
      await _db.rpc<void>(
        'remove_network_connection',
        params: {'p_connection_id': connectionId},
      );
    });
  }

  Future<Result<String>> createTransferRequest({
    required String connectionId,
    required String sourceAccountId,
    required int amountMinor,
    required PlainDate requestedOn,
    String? sharedNote,
    String? idempotencyKey,
  }) {
    return guard(() async {
      return _db.rpc<String>(
        'create_network_transfer_request',
        params: {
          'p_connection_id': connectionId,
          'p_source_account_id': sourceAccountId,
          'p_amount_minor': amountMinor,
          'p_requested_on': requestedOn.toIso(),
          'p_shared_note': sharedNote,
          'p_idempotency_key': idempotencyKey,
        },
      );
    });
  }

  /// [expectedAmountMinor] is the amount the receiver was actually looking at.
  /// The server rejects the acceptance if the sender amended the request in the
  /// meantime, so a change can never be booked without being seen.
  Future<Result<String>> acceptTransfer({
    required String transferId,
    required String destinationAccountId,
    int? expectedAmountMinor,
  }) {
    return guard(() async {
      return _db.rpc<String>(
        'accept_network_transfer',
        params: {
          'p_transfer_id': transferId,
          'p_destination_account_id': destinationAccountId,
          'p_expected_amount_minor': expectedAmountMinor,
        },
      );
    });
  }

  Future<Result<void>> cancelTransfer(String transferId) {
    return guard(() async {
      await _db.rpc<void>(
        'cancel_network_transfer',
        params: {'p_transfer_id': transferId},
      );
    });
  }

  /// Changes a still-pending request. A null field is left untouched, which is
  /// why erasing the note needs its own flag.
  Future<Result<String>> amendTransfer({
    required String transferId,
    int? amountMinor,
    String? sourceAccountId,
    PlainDate? requestedOn,
    String? sharedNote,
    bool clearSharedNote = false,
  }) {
    return guard(() async {
      return _db.rpc<String>(
        'amend_network_transfer',
        params: {
          'p_transfer_id': transferId,
          'p_amount_minor': amountMinor,
          'p_source_account_id': sourceAccountId,
          'p_requested_on': requestedOn?.toIso(),
          'p_shared_note': sharedNote,
          'p_clear_shared_note': clearSharedNote,
        },
      );
    });
  }

  Future<Result<void>> rejectTransfer(String transferId) {
    return guard(() async {
      await _db.rpc<void>(
        'reject_network_transfer',
        params: {'p_transfer_id': transferId},
      );
    });
  }

  /// Held amounts other users recorded against the caller. Read-only: the
  /// counterparty sees the number, and that is the whole of the exposure.
  Future<Result<List<HeldAgainstMe>>> fetchHoldsAgainstMe() {
    return guard(() async {
      final rows = await _db.rpc<List<dynamic>>('list_holds_against_me');
      return rows
          .map((row) => HeldAgainstMe.fromJson(row as Map<String, dynamic>))
          .toList();
    });
  }

  Future<Result<List<NetworkTransfer>>> fetchTransfers() {
    return guard(() async {
      final rows = await _db.rpc<List<dynamic>>('list_network_transfers');
      return rows
          .map((row) => NetworkTransfer.fromJson(row as Map<String, dynamic>))
          .toList();
    });
  }
}

final networkRepositoryProvider = Provider<NetworkRepository>(
  (ref) => NetworkRepository(ref.watch(supabaseClientProvider)),
);
