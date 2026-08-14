import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/card_research.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

Future<CatalogResearchMatch?> showCatalogProductPickerSheet(
  BuildContext context, {
  required AccountType accountType,
}) {
  return showModalBottomSheet<CatalogResearchMatch>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CatalogProductPicker(accountType: accountType),
  );
}

class _CatalogProductPicker extends ConsumerStatefulWidget {
  const _CatalogProductPicker({required this.accountType});

  final AccountType accountType;

  @override
  ConsumerState<_CatalogProductPicker> createState() =>
      _CatalogProductPickerState();
}

class _CatalogProductPickerState extends ConsumerState<_CatalogProductPicker> {
  final _searchController = TextEditingController();
  List<CatalogResearchMatch>? _matches;
  String? _selectedIssuer;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final result = await ref
        .read(financeRepositoryProvider)
        .browseCardCatalog(accountType: widget.accountType);
    if (!mounted) return;
    result.when(
      ok: (matches) => setState(() => _matches = matches),
      err: (failure) => setState(() => _error = failure),
    );
  }

  String get _query => _searchController.text.trim().toLowerCase();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final media = MediaQuery.of(context);
    return SizedBox(
      height: media.size.height * .78,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (_selectedIssuer != null)
                  IconButton(
                    onPressed: () => setState(() {
                      _selectedIssuer = null;
                      _searchController.clear();
                    }),
                    icon: const Icon(Icons.arrow_back),
                  ),
                Expanded(
                  child: Text(
                    _selectedIssuer ?? l10n.catalogPickerTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: _selectedIssuer == null
                    ? l10n.catalogSearchBankHint
                    : l10n.catalogSearchProductHint,
                prefixIcon: const Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildBody(l10n)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.catalogUnavailable, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _load, child: Text(l10n.commonRetry)),
          ],
        ),
      );
    }
    final matches = _matches;
    if (matches == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_selectedIssuer == null) {
      final issuers = <String, int>{};
      for (final match in matches) {
        final issuer = match.identity.issuerName;
        if (_query.isNotEmpty && !issuer.toLowerCase().contains(_query)) {
          continue;
        }
        issuers.update(issuer, (count) => count + 1, ifAbsent: () => 1);
      }
      final entries = issuers.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      if (entries.isEmpty) return Center(child: Text(l10n.catalogEmpty));
      return ListView.separated(
        itemCount: entries.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final issuer = entries[index];
          return ListTile(
            leading: const Icon(Icons.account_balance_outlined),
            title: Text(issuer.key),
            subtitle: Text(l10n.catalogProductCount(issuer.value)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() {
              _selectedIssuer = issuer.key;
              _searchController.clear();
            }),
          );
        },
      );
    }

    final products = matches.where((match) {
      if (match.identity.issuerName != _selectedIssuer) return false;
      if (_query.isEmpty) return true;
      return match.identity.productName.toLowerCase().contains(_query) ||
          (match.identity.tier?.toLowerCase().contains(_query) ?? false);
    }).toList();
    if (products.isEmpty) return Center(child: Text(l10n.catalogEmpty));
    return ListView.separated(
      itemCount: products.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final match = products[index];
        final details = [
          match.identity.tier,
          match.identity.network?.wireValue.toUpperCase(),
          match.identity.currencyCode,
        ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
        return ListTile(
          leading: const Icon(Icons.credit_card_outlined),
          title: Text(match.identity.productName),
          subtitle: details.isEmpty ? null : Text(details),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).pop(match),
        );
      },
    );
  }
}
