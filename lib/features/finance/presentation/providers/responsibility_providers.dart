import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/finance/data/installment_responsibility_repository.dart';
import 'package:work_tracker/features/finance/domain/installment_responsibility.dart';

/// Owner-side responsibility chips keyed by plan id, one query for all
/// plans so lists never fan out per card.
final responsibilitySummariesProvider =
    FutureProvider<Map<String, InstallmentResponsibilitySummary>>((ref) async {
      ref.watch(currentUserIdProvider);
      final result = await ref
          .watch(installmentResponsibilityRepositoryProvider)
          .fetchResponsibilitySummaries();
      return result.when(
        ok: (summaries) => {for (final s in summaries) s.planId: s},
        err: (f) => throw f,
      );
    });

/// Owner-side link rows (live and history) for one plan.
final planResponsibilityLinksProvider =
    FutureProvider.family<List<OwnerResponsibilityLink>, String>((
      ref,
      planId,
    ) async {
      ref.watch(currentUserIdProvider);
      final result = await ref
          .watch(installmentResponsibilityRepositoryProvider)
          .fetchPlanLinks(planId);
      return result.when(ok: (links) => links, err: (f) => throw f);
    });

/// Installments linked to the current user: pending requests to review
/// plus accepted responsibilities.
final myLinkedInstallmentsProvider = FutureProvider<List<LinkedInstallment>>((
  ref,
) async {
  ref.watch(currentUserIdProvider);
  final result = await ref
      .watch(installmentResponsibilityRepositoryProvider)
      .fetchMyLinkedInstallments();
  return result.when(ok: (links) => links, err: (f) => throw f);
});

/// Pending installment link requests awaiting the current user's consent —
/// the Home pending card and the Linked tab badge feed from this.
final pendingLinkedInstallmentRequestsProvider =
    FutureProvider<List<LinkedInstallment>>((ref) async {
      final links = await ref.watch(myLinkedInstallmentsProvider.future);
      return links.where((l) => l.isPending).toList();
    });

/// The sanitized shared details for one link, for either party.
final sharedLinkDetailsProvider =
    FutureProvider.family<SharedInstallmentLinkDetails, String>((
      ref,
      linkId,
    ) async {
      ref.watch(currentUserIdProvider);
      final result = await ref
          .watch(installmentResponsibilityRepositoryProvider)
          .fetchSharedLinkDetails(linkId);
      return result.when(ok: (details) => details, err: (f) => throw f);
    });

/// Invalidate after any responsibility or reimbursement mutation.
void invalidateResponsibilityData(WidgetRef ref) {
  ref.invalidate(responsibilitySummariesProvider);
  ref.invalidate(planResponsibilityLinksProvider);
  ref.invalidate(myLinkedInstallmentsProvider);
  ref.invalidate(sharedLinkDetailsProvider);
}
