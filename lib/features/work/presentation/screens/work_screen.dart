import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class WorkScreen extends ConsumerWidget {
  const WorkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabWork)),
      body: EmptyStateView(icon: Icons.work_outline, message: l10n.commonEmpty),
    );
  }
}
