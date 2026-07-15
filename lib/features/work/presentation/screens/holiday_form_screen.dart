import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:work_tracker/features/work/data/work_repository.dart';
import 'package:work_tracker/features/work/presentation/providers/work_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Creates an official holiday from the global Add flow.
class HolidayFormScreen extends ConsumerStatefulWidget {
  const HolidayFormScreen({super.key});

  @override
  ConsumerState<HolidayFormScreen> createState() => _HolidayFormScreenState();
}

class _HolidayFormScreenState extends ConsumerState<HolidayFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();

  PlainDate _date = PlainDate.today();
  AppFailure? _failure;
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.toDateTime(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _date = PlainDate.fromDateTime(picked));
    }
  }

  Future<void> _save() async {
    setState(() => _failure = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final notes = _notesController.text.trim();
    final result = await ref
        .read(workRepositoryProvider)
        .createHoliday(
          date: _date,
          name: _nameController.text.trim(),
          notes: notes.isEmpty ? null : notes,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      ok: (_) {
        ref.invalidate(holidaysProvider);
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
    return Scaffold(
      appBar: AppBar(title: Text(l10n.workNewHoliday)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: true,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: l10n.workHolidayName),
                validator: (value) {
                  final error = Validators.requiredText(value, maxLength: 120);
                  return error == null
                      ? null
                      : validationMessage(context, error);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: !_busy,
                leading: const FinanceSuitIcon(FinanceSuitIcons.calendarToday),
                title: Text(l10n.commonDate),
                subtitle: Text(_date.toIso()),
                onTap: _pickDate,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _notesController,
                enabled: !_busy,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: '${l10n.commonNotes} (${l10n.commonOptional})',
                ),
                validator: (value) {
                  final error = Validators.optionalText(value);
                  return error == null
                      ? null
                      : validationMessage(context, error);
                },
              ),
              const SizedBox(height: 16),
              AuthErrorBanner(failure: _failure),
              AuthSubmitButton(
                label: l10n.commonSave,
                busy: _busy,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
