import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/app_text_form_field.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/work/data/work_repository.dart';
import 'package:work_tracker/features/work/domain/official_holiday.dart';
import 'package:work_tracker/features/work/presentation/providers/work_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Manage the user's official holidays used by holiday-worked entries.
class HolidaysScreen extends ConsumerWidget {
  const HolidaysScreen({super.key});

  void _showFailure(BuildContext context, AppFailure failure) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(failureMessage(context, failure))));
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    OfficialHoliday existing,
  ) async {
    final l10n = AppLocalizations.of(context);
    final nameController = TextEditingController(text: existing.name);
    final notesController = TextEditingController(text: existing.notes ?? '');
    var date = existing.date;
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(l10n.workEditHoliday),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextFormField(
                  controller: nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: l10n.workHolidayName),
                  validator: (value) {
                    final error = Validators.requiredText(
                      value,
                      maxLength: 120,
                    );
                    return error == null
                        ? null
                        : validationMessage(dialogContext, error);
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const FinanceSuitIcon(
                    FinanceSuitIcons.calendarToday,
                  ),
                  title: Text(l10n.commonDate),
                  subtitle: Text(date.toIso()),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: date.toDateTime(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setDialogState(
                        () => date = PlainDate.fromDateTime(picked),
                      );
                    }
                  },
                ),
                AppTextFormField(
                  controller: notesController,
                  decoration: InputDecoration(
                    labelText: '${l10n.commonNotes} (${l10n.commonOptional})',
                  ),
                  validator: (value) {
                    final error = Validators.optionalText(value);
                    return error == null
                        ? null
                        : validationMessage(dialogContext, error);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(dialogContext).pop(true);
                }
              },
              child: Text(l10n.commonSave),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final name = nameController.text.trim();
    final notes = notesController.text.trim();
    final result = await ref
        .read(workRepositoryProvider)
        .updateHoliday(
          id: existing.id,
          date: date,
          name: name,
          notes: notes.isEmpty ? null : notes,
        );
    result.when(
      ok: (_) => ref.invalidate(holidaysProvider),
      err: (failure) {
        if (context.mounted) _showFailure(context, failure);
      },
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    OfficialHoliday holiday,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.workDeleteHolidayTitle),
        content: Text(l10n.workDeleteHolidayBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await ref
        .read(workRepositoryProvider)
        .deleteHoliday(holiday.id);
    result.when(
      ok: (_) {
        ref
          ..invalidate(holidaysProvider)
          ..invalidate(workEntriesForMonthProvider);
      },
      err: (failure) {
        if (context.mounted) _showFailure(context, failure);
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final holidaysAsync = ref.watch(holidaysProvider);
    return Scaffold(
      appBar: FinanceSuitAppBar.focused(semanticTitle: l10n.workHolidays),
      body: FinanceSuitFocusedBody(
        title: l10n.workHolidays,
        child: AsyncView(
          value: holidaysAsync,
          onRetry: () => ref.invalidate(holidaysProvider),
          data: (holidays) {
            if (holidays.isEmpty) {
              return EmptyStateView(
                icon: FinanceSuitIcons.event,
                message: l10n.workNoHolidays,
              );
            }
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(holidaysProvider),
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: holidays.length,
                itemBuilder: (context, index) {
                  final holiday = holidays[index];
                  return ListTile(
                    leading: const FinanceSuitIcon(
                      FinanceSuitIcons.celebration,
                    ),
                    title: Text(holiday.name),
                    subtitle: Text(
                      [
                        holiday.date.toIso(),
                        if (holiday.notes != null) holiday.notes!,
                      ].join(' · '),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) => action == 'edit'
                          ? _edit(context, ref, holiday)
                          : _delete(context, ref, holiday),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text(l10n.commonEdit),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(l10n.commonDelete),
                        ),
                      ],
                    ),
                    onTap: () => _edit(context, ref, holiday),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
