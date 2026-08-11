import 'package:flutter/material.dart';
import 'package:work_tracker/app/configuration/env.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

enum LegalDocument { privacyPolicy, terms, accountDeletion }

class LegalDocumentScreen extends StatefulWidget {
  const LegalDocumentScreen({super.key, required this.document});

  final LegalDocument document;

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends State<LegalDocumentScreen> {
  String? _loadedAssetPath;
  Future<String>? _documentFuture;

  String _title(AppLocalizations l10n) => switch (document) {
    LegalDocument.privacyPolicy => l10n.setPrivacyPolicy,
    LegalDocument.terms => l10n.setTerms,
    LegalDocument.accountDeletion => l10n.deleteAccountPolicy,
  };

  LegalDocument get document => widget.document;

  String _assetPath(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode == 'ar'
        ? 'ar'
        : 'en';
    final filename = switch (document) {
      LegalDocument.privacyPolicy => 'privacy_policy_$language.md',
      LegalDocument.terms => 'terms_$language.md',
      LegalDocument.accountDeletion => 'account_deletion_$language.md',
    };
    return 'assets/legal/$filename';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final assetPath = _assetPath(context);
    if (_loadedAssetPath == assetPath) return;
    _loadedAssetPath = assetPath;
    _documentFuture = DefaultAssetBundle.of(context).loadString(assetPath);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: FinanceSuitAppBar.focused(semanticTitle: _title(l10n)),
      body: FutureBuilder<String>(
        future: _documentFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(l10n.commonError));
          }
          final source = snapshot.data;
          if (source == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final resolved = source
              .replaceAll('{{DEVELOPER_NAME}}', Env.legalDeveloperName)
              .replaceAll('{{PRIVACY_EMAIL}}', Env.privacyContactEmail);
          return _LegalMarkdown(source: resolved);
        },
      ),
    );
  }
}

class _LegalMarkdown extends StatelessWidget {
  const _LegalMarkdown({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final widgets = <Widget>[];
    for (final rawLine in source.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        widgets.add(const SizedBox(height: 8));
      } else if (line.startsWith('# ')) {
        widgets.add(
          Text(line.substring(2), style: theme.textTheme.headlineSmall),
        );
      } else if (line.startsWith('## ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(line.substring(3), style: theme.textTheme.titleLarge),
          ),
        );
      } else if (line.startsWith('- ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 8, top: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  '),
                Expanded(child: Text(line.substring(2))),
              ],
            ),
          ),
        );
      } else {
        widgets.add(Text(line));
      }
    }

    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: widgets,
      ),
    );
  }
}
