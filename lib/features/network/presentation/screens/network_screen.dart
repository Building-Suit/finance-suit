import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/widgets/app_toast.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/core/widgets/protected_money.dart';
import 'package:work_tracker/features/finance/presentation/providers/responsibility_providers.dart';
import 'package:work_tracker/features/finance/presentation/widgets/responsibility_widgets.dart';
import 'package:work_tracker/features/network/data/network_repository.dart';
import 'package:work_tracker/features/network/domain/network_models.dart';
import 'package:work_tracker/features/network/presentation/providers/network_providers.dart';
import 'package:work_tracker/features/network/presentation/widgets/network_widgets.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Finance Suit Network center: connections with private aliases, incoming
/// and sent add requests, and the shared network transfer history.
class NetworkScreen extends ConsumerStatefulWidget {
  const NetworkScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends ConsumerState<NetworkScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 4,
    vsync: this,
    initialIndex: widget.initialTab.clamp(0, 3),
  );

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: FinanceSuitAppBar.focused(semanticTitle: l10n.networkTitle),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('network-add-person'),
        onPressed: () => context.push('/money/network/search'),
        // The global FAB theme is a circle for the square add buttons;
        // an extended FAB needs a stadium or its label gets clipped.
        shape: const StadiumBorder(),
        icon: const FinanceSuitIcon(FinanceSuitIcons.personAdd),
        label: Text(l10n.networkAddPerson),
      ),
      body: FinanceSuitFocusedBody(
        title: l10n.networkTitle,
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              tabAlignment: TabAlignment.start,
              isScrollable: true,
              tabs: [
                Tab(text: l10n.networkTabConnections),
                Tab(text: l10n.networkTabRequests),
                Tab(text: l10n.networkTabTransfers),
                Tab(text: l10n.respLinkedInstallmentsTab),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _ConnectionsTab(
                    onViewTransfers: () => _tabController.animateTo(2),
                  ),
                  const _RequestsTab(),
                  const _TransfersTab(),
                  const _LinkedInstallmentsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Connections
// ---------------------------------------------------------------------------

class _ConnectionsTab extends ConsumerWidget {
  const _ConnectionsTab({required this.onViewTransfers});

  final VoidCallback onViewTransfers;

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    NetworkContact contact,
  ) async {
    final l10n = AppLocalizations.of(context);
    final alias = await showNetworkAliasSheet(
      context,
      title: l10n.networkAliasQuestionFor(contact.realDisplayName),
      initialValue: contact.localAlias,
    );
    if (alias == null || !context.mounted) return;
    final result = await ref
        .read(networkRepositoryProvider)
        .renameContact(connectionId: contact.connectionId, newAlias: alias);
    if (!context.mounted) return;
    result.when(
      ok: (_) {
        invalidateNetworkData(ref);
        AppToast.success(context, l10n.setSaved);
      },
      err: (failure) =>
          AppToast.error(context, failureMessage(context, failure)),
    );
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    NetworkContact contact,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final dialogL10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(dialogL10n.networkRemoveConfirmTitle),
          content: Text(
            dialogL10n.networkRemoveConfirmBody(contact.localAlias),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(dialogL10n.commonCancel),
            ),
            FilledButton(
              key: const Key('network-remove-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(dialogL10n.networkRemove),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;
    final result = await ref
        .read(networkRepositoryProvider)
        .removeConnection(contact.connectionId);
    if (!context.mounted) return;
    result.when(
      ok: (_) {
        invalidateNetworkData(ref);
        AppToast.success(context, l10n.networkRemovedToast);
      },
      err: (failure) =>
          AppToast.error(context, failureMessage(context, failure)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final contacts = ref.watch(networkContactsProvider);
    return AsyncView(
      value: contacts,
      onRetry: () => ref.invalidate(networkContactsProvider),
      data: (items) {
        if (items.isEmpty) {
          return EmptyStateView(
            icon: FinanceSuitIcons.people,
            message: l10n.networkNoConnections,
            actionLabel: l10n.networkAddPerson,
            onAction: () => context.push('/money/network/search'),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => invalidateNetworkData(ref),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final contact = items[index];
              return Card(
                key: Key('network-contact-${contact.connectionId}'),
                child: ListTile(
                  leading: const FinanceSuitIcon(FinanceSuitIcons.person),
                  title: Text(contact.localAlias),
                  subtitle: Text(
                    '${contact.realDisplayName}\n${contact.email}',
                  ),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    key: Key('network-contact-menu-${contact.connectionId}'),
                    onSelected: (action) => switch (action) {
                      'rename' => _rename(context, ref, contact),
                      'transfers' => onViewTransfers(),
                      'remove' => _remove(context, ref, contact),
                      _ => null,
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'rename',
                        child: Text(l10n.networkEditAlias),
                      ),
                      PopupMenuItem(
                        value: 'transfers',
                        child: Text(l10n.networkViewTransfers),
                      ),
                      PopupMenuItem(
                        value: 'remove',
                        child: Text(l10n.networkRemove),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Requests
// ---------------------------------------------------------------------------

class _RequestsTab extends ConsumerWidget {
  const _RequestsTab();

  Future<void> _accept(
    BuildContext context,
    WidgetRef ref,
    NetworkAddRequest request,
  ) async {
    final l10n = AppLocalizations.of(context);
    final alias = await showNetworkAliasSheet(
      context,
      title: l10n.networkAliasQuestionFor(request.otherDisplayName),
      subtitle: request.otherEmail,
    );
    if (alias == null || !context.mounted) return;
    final result = await ref
        .read(networkRepositoryProvider)
        .acceptAddRequest(requestId: request.id, localAlias: alias);
    if (!context.mounted) return;
    result.when(
      ok: (_) {
        invalidateNetworkData(ref);
        AppToast.success(context, l10n.networkConnectedToast);
      },
      err: (failure) =>
          AppToast.error(context, failureMessage(context, failure)),
    );
  }

  Future<void> _reject(
    BuildContext context,
    WidgetRef ref,
    NetworkAddRequest request,
  ) async {
    final l10n = AppLocalizations.of(context);
    final result = await ref
        .read(networkRepositoryProvider)
        .rejectAddRequest(request.id);
    if (!context.mounted) return;
    result.when(
      ok: (_) {
        invalidateNetworkData(ref);
        AppToast.success(context, l10n.networkRequestRejectedToast);
      },
      err: (failure) =>
          AppToast.error(context, failureMessage(context, failure)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final requests = ref.watch(networkAddRequestsProvider);
    return AsyncView(
      value: requests,
      onRetry: () => ref.invalidate(networkAddRequestsProvider),
      data: (items) {
        final incoming = items
            .where((r) => r.isIncoming && r.isPending)
            .toList();
        final sent = items.where((r) => !r.isIncoming).toList();
        if (incoming.isEmpty && sent.isEmpty) {
          return EmptyStateView(
            icon: FinanceSuitIcons.personAdd,
            message: l10n.networkNoRequests,
          );
        }
        final theme = Theme.of(context);
        return RefreshIndicator(
          onRefresh: () async => invalidateNetworkData(ref),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              if (incoming.isNotEmpty) ...[
                Text(l10n.networkIncoming, style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                for (final request in incoming)
                  Card(
                    key: Key('network-incoming-${request.id}'),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            request.otherDisplayName,
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            request.otherEmail,
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 4),
                          Text(l10n.networkWantsToAdd),
                          const SizedBox(height: 8),
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            children: [
                              TextButton(
                                key: Key('network-reject-${request.id}'),
                                onPressed: () => _reject(context, ref, request),
                                child: Text(l10n.networkReject),
                              ),
                              FilledButton(
                                key: Key('network-accept-${request.id}'),
                                onPressed: () => _accept(context, ref, request),
                                child: Text(l10n.networkAccept),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
              ],
              if (sent.isNotEmpty) ...[
                Text(l10n.networkSent, style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                for (final request in sent)
                  Card(
                    key: Key('network-sent-${request.id}'),
                    child: ListTile(
                      leading: const FinanceSuitIcon(FinanceSuitIcons.person),
                      title: Text(request.otherDisplayName),
                      subtitle: Text(
                        request.myAlias == null
                            ? request.otherEmail
                            : '${request.otherEmail}\n'
                                  '${l10n.networkAliasLabel}: '
                                  '${request.myAlias}',
                      ),
                      isThreeLine: request.myAlias != null,
                      trailing: Text(switch (request.status) {
                        NetworkAddRequestStatus.pending =>
                          l10n.networkStatusPending,
                        NetworkAddRequestStatus.accepted =>
                          l10n.networkStatusAccepted,
                        NetworkAddRequestStatus.rejected =>
                          l10n.networkStatusRejected,
                      }),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Transfers
// ---------------------------------------------------------------------------

class _TransfersTab extends ConsumerStatefulWidget {
  const _TransfersTab();

  @override
  ConsumerState<_TransfersTab> createState() => _TransfersTabState();
}

class _TransfersTabState extends ConsumerState<_TransfersTab> {
  NetworkTransferStatus? _filter = NetworkTransferStatus.pending;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final transfers = ref.watch(networkTransfersProvider);
    return AsyncView(
      value: transfers,
      onRetry: () => ref.invalidate(networkTransfersProvider),
      data: (items) {
        final visible = _filter == null
            ? items
            : items.where((t) => t.status == _filter).toList();
        return RefreshIndicator(
          onRefresh: () async => invalidateNetworkData(ref),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (final (label, value) in [
                    (l10n.networkStatusPending, NetworkTransferStatus.pending),
                    (
                      l10n.networkStatusAccepted,
                      NetworkTransferStatus.accepted,
                    ),
                    (
                      l10n.networkStatusRejected,
                      NetworkTransferStatus.rejected,
                    ),
                    (l10n.networkFilterAll, null),
                  ])
                    FilterChip(
                      key: Key('network-filter-${value?.dbValue ?? 'all'}'),
                      label: Text(label),
                      selected: _filter == value,
                      onSelected: (_) => setState(() => _filter = value),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (visible.isEmpty)
                EmptyStateView(
                  icon: FinanceSuitIcons.swapHoriz,
                  message: l10n.networkNoTransfers,
                )
              else
                for (final transfer in visible)
                  _NetworkTransferCard(transfer: transfer),
            ],
          ),
        );
      },
    );
  }
}

class _NetworkTransferCard extends ConsumerWidget {
  const _NetworkTransferCard({required this.transfer});

  final NetworkTransfer transfer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final title = transfer.isIncoming
        ? l10n.networkTransferFrom(transfer.counterpartyAlias)
        : l10n.networkTransferTo(transfer.counterpartyAlias);
    return Card(
      key: Key('network-transfer-${transfer.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                NetworkStatusChip(status: transfer.status),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: ProtectedMoneyText(
                    transfer.amount.format(),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                Text(
                  transfer.requestedOn.toIso(),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            if (transfer.sharedNote != null &&
                transfer.sharedNote!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(transfer.sharedNote!, style: theme.textTheme.bodySmall),
            ],
            if (transfer.isActionable) ...[
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    key: Key('network-transfer-reject-${transfer.id}'),
                    onPressed: () =>
                        rejectNetworkTransfer(context, ref, transfer),
                    child: Text(l10n.networkReject),
                  ),
                  FilledButton(
                    key: Key('network-transfer-accept-${transfer.id}'),
                    onPressed: () =>
                        acceptNetworkTransfer(context, ref, transfer),
                    child: Text(l10n.networkAccept),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Linked installments
// ---------------------------------------------------------------------------

/// Installments other people linked to this user: pending requests to
/// review first, then accepted responsibilities with their remaining state.
class _LinkedInstallmentsTab extends ConsumerWidget {
  const _LinkedInstallmentsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final linked = ref.watch(myLinkedInstallmentsProvider);
    return AsyncView(
      value: linked,
      onRetry: () => ref.invalidate(myLinkedInstallmentsProvider),
      data: (items) {
        if (items.isEmpty) {
          return EmptyStateView(
            icon: FinanceSuitIcons.creditCard,
            message: l10n.respNoLinkedInstallments,
          );
        }
        return RefreshIndicator(
          onRefresh: () async => invalidateResponsibilityData(ref),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final link = items[index];
              return Card(
                key: Key('linked-installment-${link.linkId}'),
                child: ListTile(
                  leading: const FinanceSuitIcon(FinanceSuitIcons.creditCard),
                  title: Text(
                    link.planTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.respOwnerLabel(link.ownerName)),
                      if (link.isPending)
                        Text(l10n.respReviewBeforeAccepting)
                      else ...[
                        ProtectedMoneyText(
                          l10n.respYourResponsibilityRemaining(
                            link.remainingTotal.format(),
                          ),
                          interactive: false,
                        ),
                        if (link.nextDueOn != null &&
                            link.nextDueAmount != null)
                          ProtectedMoneyText(
                            l10n.respNextInstallment(
                              link.nextDueAmount!.format(),
                              link.nextDueOn!.toIso(),
                            ),
                            interactive: false,
                          ),
                      ],
                    ],
                  ),
                  isThreeLine: true,
                  trailing: link.isPending
                      ? FilledButton(
                          key: Key('linked-review-${link.linkId}'),
                          onPressed: () =>
                              context.push('/money/linked/${link.linkId}'),
                          child: Text(l10n.respReviewAction),
                        )
                      : ResponsibilityStatusChip(status: link.status),
                  onTap: () => context.push('/money/linked/${link.linkId}'),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
