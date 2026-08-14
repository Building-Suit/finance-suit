import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/widgets/app_toast.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/network/data/network_repository.dart';
import 'package:work_tracker/features/network/domain/network_models.dart';
import 'package:work_tracker/features/network/presentation/providers/network_providers.dart';
import 'package:work_tracker/features/network/presentation/widgets/network_widgets.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Find other Finance Suit users by name or email and send add requests.
/// Results carry identity and relationship state only — never balances.
class NetworkSearchScreen extends ConsumerStatefulWidget {
  const NetworkSearchScreen({super.key});

  @override
  ConsumerState<NetworkSearchScreen> createState() =>
      _NetworkSearchScreenState();
}

class _NetworkSearchScreenState extends ConsumerState<NetworkSearchScreen> {
  final _queryController = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  AppFailure? _failure;
  List<NetworkUserSearchResult>? _results;

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  bool _searchable(String query) {
    final trimmed = query.trim();
    return trimmed.contains('@') || trimmed.length >= 3;
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (!_searchable(query)) {
      setState(() {
        _results = null;
        _failure = null;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  Future<void> _search(String query) async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    final result = await ref
        .read(networkRepositoryProvider)
        .searchUsers(query.trim());
    if (!mounted) return;
    // Ignore responses for stale queries.
    if (_queryController.text.trim() != query.trim()) return;
    setState(() {
      _loading = false;
      result.when(
        ok: (rows) => _results = rows,
        err: (failure) {
          _failure = failure;
          _results = null;
        },
      );
    });
  }

  Future<void> _add(NetworkUserSearchResult user) async {
    final l10n = AppLocalizations.of(context);
    final alias = await showNetworkAliasSheet(
      context,
      title: l10n.networkAliasQuestion,
      subtitle: '${l10n.networkAliasAdding} ${user.displayName}\n${user.email}',
    );
    if (alias == null || !mounted) return;
    final result = await ref
        .read(networkRepositoryProvider)
        .sendAddRequest(targetUserId: user.userId, localAlias: alias);
    if (!mounted) return;
    result.when(
      ok: (_) {
        invalidateNetworkData(ref);
        AppToast.success(context, l10n.networkRequestSent);
        setState(() {
          _results = [
            for (final row in _results ?? <NetworkUserSearchResult>[])
              row.userId == user.userId
                  ? NetworkUserSearchResult(
                      userId: row.userId,
                      displayName: row.displayName,
                      email: row.email,
                      relationshipState:
                          NetworkRelationshipState.outgoingPending,
                    )
                  : row,
          ];
        });
      },
      err: (failure) =>
          AppToast.error(context, failureMessage(context, failure)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final results = _results;
    return Scaffold(
      appBar: FinanceSuitAppBar.focused(semanticTitle: l10n.networkAddPerson),
      body: FinanceSuitFocusedBody(
        title: l10n.networkAddPerson,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                key: const Key('network-search-field'),
                controller: _queryController,
                autofocus: true,
                onChanged: _onQueryChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: l10n.networkSearchHint,
                  helperText: l10n.networkSearchMinChars,
                  prefixIcon: const Padding(
                    padding: EdgeInsets.all(12),
                    child: FinanceSuitIcon(FinanceSuitIcons.search, size: 20),
                  ),
                ),
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_failure != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(failureMessage(context, _failure!)),
              ),
            Expanded(
              child: results == null
                  ? const SizedBox.shrink()
                  : results.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          l10n.networkSearchEmpty,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final user = results[index];
                        return Card(
                          key: Key('network-result-${user.userId}'),
                          child: ListTile(
                            leading: const FinanceSuitIcon(
                              FinanceSuitIcons.person,
                            ),
                            title: Text(user.displayName),
                            subtitle: Text(user.email),
                            trailing: switch (user.relationshipState) {
                              NetworkRelationshipState.none => FilledButton(
                                key: Key('network-add-${user.userId}'),
                                onPressed: () => _add(user),
                                child: Text(l10n.networkActionAdd),
                              ),
                              NetworkRelationshipState.outgoingPending => Text(
                                l10n.networkStateRequested,
                              ),
                              NetworkRelationshipState.incomingPending =>
                                OutlinedButton(
                                  key: Key('network-respond-${user.userId}'),
                                  onPressed: () => context.pushReplacement(
                                    '/money/network?tab=requests',
                                  ),
                                  child: Text(l10n.networkStateRespond),
                                ),
                              NetworkRelationshipState.connected => Text(
                                l10n.networkStateAdded,
                              ),
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
