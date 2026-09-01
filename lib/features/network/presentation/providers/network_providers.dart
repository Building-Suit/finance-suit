import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/network/data/network_repository.dart';
import 'package:work_tracker/features/network/domain/held_against_me.dart';
import 'package:work_tracker/features/network/domain/network_models.dart';

final networkContactsProvider = FutureProvider<List<NetworkContact>>((
  ref,
) async {
  ref.watch(currentUserIdProvider);
  final result = await ref.watch(networkRepositoryProvider).fetchContacts();
  return result.when(ok: (contacts) => contacts, err: (f) => throw f);
});

final networkAddRequestsProvider = FutureProvider<List<NetworkAddRequest>>((
  ref,
) async {
  ref.watch(currentUserIdProvider);
  final result = await ref.watch(networkRepositoryProvider).fetchAddRequests();
  return result.when(ok: (requests) => requests, err: (f) => throw f);
});

final networkTransfersProvider = FutureProvider<List<NetworkTransfer>>((
  ref,
) async {
  ref.watch(currentUserIdProvider);
  final result = await ref.watch(networkRepositoryProvider).fetchTransfers();
  return result.when(ok: (transfers) => transfers, err: (f) => throw f);
});

/// Incoming pending transfers the receiver can still act on — the Home
/// pending card and the Transfers tab badge feed from this.
final pendingIncomingNetworkTransfersProvider =
    FutureProvider<List<NetworkTransfer>>((ref) async {
      final transfers = await ref.watch(networkTransfersProvider.future);
      return transfers.where((t) => t.isActionable).toList();
    });

/// Incoming pending add requests, for the Requests tab badge.
final pendingIncomingNetworkRequestsProvider =
    FutureProvider<List<NetworkAddRequest>>((ref) async {
      final requests = await ref.watch(networkAddRequestsProvider.future);
      return requests.where((r) => r.isIncoming && r.isPending).toList();
    });

/// Held amounts other people recorded against the current user. Read-only:
/// these never affect the viewer's own balances or held totals.
final holdsAgainstMeProvider = FutureProvider<List<HeldAgainstMe>>((ref) async {
  ref.watch(currentUserIdProvider);
  final result = await ref
      .watch(networkRepositoryProvider)
      .fetchHoldsAgainstMe();
  return result.when(ok: (holds) => holds, err: (f) => throw f);
});

/// Unsettled holds against the viewer, for the tab badge.
final pendingHoldsAgainstMeProvider = FutureProvider<List<HeldAgainstMe>>((
  ref,
) async {
  final holds = await ref.watch(holdsAgainstMeProvider.future);
  return holds.where((h) => !h.isSettled).toList();
});

void invalidateNetworkData(WidgetRef ref) {
  ref
    ..invalidate(networkContactsProvider)
    ..invalidate(networkAddRequestsProvider)
    ..invalidate(networkTransfersProvider)
    ..invalidate(holdsAgainstMeProvider);
}
