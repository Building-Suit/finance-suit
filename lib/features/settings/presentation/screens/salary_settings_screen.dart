import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/salary/domain/salary_settings.dart';
import 'package:work_tracker/features/salary/presentation/models/salary_configuration_draft.dart';
import 'package:work_tracker/features/salary/presentation/widgets/salary_configuration_fields.dart';
import 'package:work_tracker/features/settings/data/settings_repository.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class SalarySettingsScreen extends ConsumerWidget {
  const SalarySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(salarySettingsProvider);
    return Scaffold(
      appBar: FinanceSuitAppBar.focused(semanticTitle: l10n.setSalarySection),
      body: FinanceSuitFocusedBody(
        title: l10n.setSalarySection,
        child: AsyncView(
          value: settings,
          onRetry: () => ref.invalidate(salarySettingsProvider),
          data: (value) => _SalarySettingsForm(initial: value),
        ),
      ),
    );
  }
}

class _SalarySettingsForm extends ConsumerStatefulWidget {
  const _SalarySettingsForm({required this.initial});

  final SalarySettings initial;

  @override
  ConsumerState<_SalarySettingsForm> createState() =>
      _SalarySettingsFormState();
}

class _SalarySettingsFormState extends ConsumerState<_SalarySettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late bool _salaryEnabled = widget.initial.salaryEnabled;
  late final SalaryConfigurationDraft _draft =
      SalaryConfigurationDraft.fromSettings(widget.initial);
  bool _busy = false;
  AppFailure? _failure;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _failure = null);
    if (!_formKey.currentState!.validate()) return;
    final updated = _draft.toSettings(
      salaryEnabled: _salaryEnabled,
      currencyCode: widget.initial.currencyCode,
      fallback: widget.initial,
    );
    setState(() => _busy = true);
    final result = await ref
        .read(settingsRepositoryProvider)
        .updateSalarySettings(updated);
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      ok: (_) {
        ref
          ..invalidate(salarySettingsProvider)
          ..invalidate(incomeSourcesProvider)
          ..invalidate(pendingIncomeProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).setSaved)),
        );
        context.pop();
      },
      err: (failure) => setState(() => _failure = failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.incomeHasSalary),
              subtitle: Text(l10n.incomeHasSalaryHelp),
              value: _salaryEnabled,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _salaryEnabled = value),
            ),
            const SizedBox(height: 8),
            if (_salaryEnabled)
              SalaryConfigurationFields(
                draft: _draft,
                currencyCode: widget.initial.currencyCode,
                onChanged: () => setState(() {}),
              ),
            const SizedBox(height: 16),
            AuthErrorBanner(failure: _failure),
            AuthSubmitButton(
              label: l10n.commonSave,
              busy: _busy,
              onPressed: _save,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
