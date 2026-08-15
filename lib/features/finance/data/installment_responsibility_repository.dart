import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/result/result.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/finance/domain/installment_responsibility.dart';

/// Data access for installment responsibility links and reimbursements.
/// Everything goes through the narrow server RPCs: the client never mutates
/// link or reimbursement rows directly, and the shared installment data a
/// linked user sees is always the server-sanitized DTO.
class InstallmentResponsibilityRepository {
  InstallmentResponsibilityRepository(this._client);

  final SupabaseClient _client;

  SupabaseQuerySchema get _db => _client.schema(AppSchemas.finance);

  String? get _userId => _client.auth.currentUser?.id;

  /// Owner: link a plan to a private custom person. Active immediately.
  Future<Result<String>> linkToCustomPerson({
    required String planId,
    required String customName,
    String? sharedNote,
  }) {
    return guard(() async {
      return _db.rpc<String>(
        'link_installment_to_custom_person',
        params: {
          'p_plan_id': planId,
          'p_custom_name': customName,
          'p_shared_note': sharedNote,
        },
      );
    });
  }

  /// Owner: send a responsibility request to an accepted network contact.
  /// The installment stays untouched; the link waits for their consent.
  Future<Result<String>> requestResponsibility({
    required String planId,
    required String connectionId,
    String? sharedNote,
  }) {
    return guard(() async {
      return _db.rpc<String>(
        'request_installment_responsibility',
        params: {
          'p_plan_id': planId,
          'p_network_connection_id': connectionId,
          'p_shared_note': sharedNote,
        },
      );
    });
  }

  Future<Result<String>> acceptResponsibility(String linkId) {
    return guard(() async {
      return _db.rpc<String>(
        'accept_installment_responsibility',
        params: {'p_link_id': linkId},
      );
    });
  }

  Future<Result<void>> rejectResponsibility(String linkId) {
    return guard(() async {
      await _db.rpc<void>(
        'reject_installment_responsibility',
        params: {'p_link_id': linkId},
      );
    });
  }

  Future<Result<void>> removeResponsibility(String linkId) {
    return guard(() async {
      await _db.rpc<void>(
        'remove_installment_responsibility',
        params: {'p_link_id': linkId},
      );
    });
  }

  /// Both parties: the sanitized shared details, schedule, and
  /// reimbursement summary for one link.
  Future<Result<SharedInstallmentLinkDetails>> fetchSharedLinkDetails(
    String linkId,
  ) {
    return guard(() async {
      final json = await _db.rpc<Map<String, dynamic>>(
        'get_shared_installment_link_details',
        params: {'p_link_id': linkId},
      );
      return SharedInstallmentLinkDetails.fromJson(json);
    });
  }

  /// Responsible user: pending requests and accepted linked installments.
  Future<Result<List<LinkedInstallment>>> fetchMyLinkedInstallments() {
    return guard(() async {
      final rows = await _db.rpc<List<dynamic>>('list_my_linked_installments');
      return rows
          .map((row) => LinkedInstallment.fromJson(row as Map<String, dynamic>))
          .toList();
    });
  }

  /// Owner: link rows (live and history) for one plan.
  Future<Result<List<OwnerResponsibilityLink>>> fetchPlanLinks(String planId) {
    return guard(() async {
      final rows = await _db.rpc<List<dynamic>>(
        'list_installment_responsibility_links',
        params: {'p_plan_id': planId},
      );
      return rows
          .map(
            (row) =>
                OwnerResponsibilityLink.fromJson(row as Map<String, dynamic>),
          )
          .toList();
    });
  }

  /// Owner: live responsibility chips for all plans, one query.
  Future<Result<List<InstallmentResponsibilitySummary>>>
  fetchResponsibilitySummaries() {
    return guard(() async {
      final rows = await _db
          .from('installment_plan_responsibility_summaries')
          .select()
          .eq('user_id', _userId ?? '');
      return rows.map(InstallmentResponsibilitySummary.fromJson).toList();
    });
  }

  /// Owner: record a reimbursement received outside Finance Suit from a
  /// custom person. Books the protected one-sided inflow atomically.
  Future<Result<String>> recordCustomReimbursement({
    required String linkId,
    required String dueId,
    required int amountMinor,
    required PlainDate receivedOn,
    required String destinationAccountId,
    String? note,
    String? reimbursementId,
  }) {
    return guard(() async {
      return _db.rpc<String>(
        'record_custom_installment_reimbursement',
        params: {
          'p_link_id': linkId,
          'p_due_id': dueId,
          'p_amount_minor': amountMinor,
          'p_received_on': receivedOn.toIso(),
          'p_destination_account_id': destinationAccountId,
          'p_note': note,
          'p_reimbursement_id': reimbursementId,
        },
      );
    });
  }

  /// Responsible user: send a reimbursement for one linked due through the
  /// network transfer rail. Pending moves nothing until the owner accepts.
  Future<Result<String>> createNetworkReimbursement({
    required String linkId,
    required String dueId,
    required int amountMinor,
    required String sourceAccountId,
    String? note,
    String? reimbursementId,
  }) {
    return guard(() async {
      return _db.rpc<String>(
        'create_installment_network_reimbursement',
        params: {
          'p_link_id': linkId,
          'p_due_id': dueId,
          'p_amount_minor': amountMinor,
          'p_source_account_id': sourceAccountId,
          'p_note': note,
          'p_reimbursement_id': reimbursementId,
        },
      );
    });
  }
}

final installmentResponsibilityRepositoryProvider =
    Provider<InstallmentResponsibilityRepository>(
      (ref) => InstallmentResponsibilityRepository(
        ref.watch(supabaseClientProvider),
      ),
    );
