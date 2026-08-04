import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/money/money_input.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/app_selection_field.dart';
import 'package:work_tracker/core/widgets/app_text_form_field.dart';
import 'package:work_tracker/core/widgets/app_toast.dart';
import 'package:work_tracker/core/widgets/domain_labels.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/core/widgets/protected_money.dart';
import 'package:work_tracker/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:work_tracker/features/salary/domain/salary_calculator.dart';
import 'package:work_tracker/features/salary/domain/salary_settings.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/features/work/data/work_repository.dart';
import 'package:work_tracker/features/work/domain/official_holiday.dart';
import 'package:work_tracker/features/work/domain/work_entry.dart';
import 'package:work_tracker/features/work/presentation/providers/work_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Create or edit a work entry. Fields adapt to the entry type and a live
/// estimate shows the extra pay the pure salary calculator would produce.
class WorkEntryFormScreen extends ConsumerStatefulWidget {
  const WorkEntryFormScreen({
    super.key,
    this.initialDate,
    this.initialType,
    this.existing,
  });

  final PlainDate? initialDate;
  final WorkEntryType? initialType;
  final WorkEntry? existing;

  @override
  ConsumerState<WorkEntryFormScreen> createState() =>
      _WorkEntryFormScreenState();
}

class _WorkEntryFormScreenState extends ConsumerState<WorkEntryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _durationController = TextEditingController();
  final _breakController = TextEditingController(text: '0');
  final _unitsController = TextEditingController(text: '1');
  final _multiplierController = TextEditingController();
  final _customRateController = TextEditingController();
  final _notesController = TextEditingController();

  late WorkEntryType _type =
      widget.existing?.entryType ??
      widget.initialType ??
      WorkEntryType.overtime;
  late PlainDate _date =
      widget.existing?.workDate ?? widget.initialDate ?? PlainDate.today();
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _useDayUnits = true;
  String? _holidayId;
  AppFailure? _failure;
  bool _busy = false;
  bool _multiplierTouched = false;

  bool get _isEdit => widget.existing != null;

  bool get _needsDuration =>
      _type == WorkEntryType.regular ||
      _type == WorkEntryType.overtime ||
      (_type == WorkEntryType.holidayWorked && !_useDayUnits);

  bool get _needsUnits =>
      _type == WorkEntryType.extraDay ||
      (_type == WorkEntryType.holidayWorked && _useDayUnits);

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _breakController.text = '${existing.breakMinutes}';
      if (existing.startMinuteOfDay != null) {
        _startTime = TimeOfDay(
          hour: existing.startMinuteOfDay! ~/ 60,
          minute: existing.startMinuteOfDay! % 60,
        );
      }
      if (existing.endMinuteOfDay != null) {
        _endTime = TimeOfDay(
          hour: existing.endMinuteOfDay! ~/ 60,
          minute: existing.endMinuteOfDay! % 60,
        );
      }
      if (existing.durationMinutes != null && _startTime == null) {
        _durationController.text = '${existing.durationMinutes}';
      }
      if (existing.dayUnitsHundredths != null) {
        _unitsController.text = (existing.dayUnitsHundredths! / 100)
            .toStringAsFixed(2);
      }
      _useDayUnits =
          existing.entryType != WorkEntryType.holidayWorked ||
          existing.dayUnitsHundredths != null;
      if (existing.multiplierPct != null) {
        _multiplierController.text = '${existing.multiplierPct}';
        _multiplierTouched = true;
      }
      if (existing.customRateMinor != null) {
        _customRateController.text = formatMinorForInput(
          existing.customRateMinor!,
        );
      }
      _holidayId = existing.holidayId;
      _notesController.text = existing.notes ?? '';
    }
  }

  @override
  void dispose() {
    _durationController.dispose();
    _breakController.dispose();
    _unitsController.dispose();
    _multiplierController.dispose();
    _customRateController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  int _defaultMultiplier(SalarySettings s) => switch (_type) {
    WorkEntryType.regular => 100,
    WorkEntryType.overtime => s.overtimeMultiplierPct,
    WorkEntryType.extraDay => s.extraDayMultiplierPct,
    WorkEntryType.holidayWorked => s.officialHolidayMultiplierPct,
  };

  int? get _startMinute =>
      _startTime == null ? null : _startTime!.hour * 60 + _startTime!.minute;
  int? get _endMinute =>
      _endTime == null ? null : _endTime!.hour * 60 + _endTime!.minute;
  int get _breakMinutes => int.tryParse(_breakController.text.trim()) ?? 0;

  /// Effective worked minutes: from the time pair when both are set,
  /// otherwise from the manual duration field.
  int? get _durationMinutes {
    final start = _startMinute;
    final end = _endMinute;
    if (start != null && end != null) {
      return SalaryCalculator.sessionMinutes(
        startMinuteOfDay: start,
        endMinuteOfDay: end,
        breakMinutes: _breakMinutes,
      );
    }
    return int.tryParse(_durationController.text.trim());
  }

  int? get _dayUnitsHundredths {
    final value = double.tryParse(_unitsController.text.trim());
    if (value == null) return null;
    return (value * 100).round();
  }

  int? _multiplierPct(SalarySettings s) {
    if (!_multiplierTouched || _multiplierController.text.trim().isEmpty) {
      return null; // use settings default
    }
    return int.tryParse(_multiplierController.text.trim());
  }

  int? _customRateMinor(SalarySettings s) {
    final text = _customRateController.text.trim();
    if (text.isEmpty) return null;
    return Money.tryParse(text, currencyCode: s.currencyCode)?.minor;
  }

  EntryCalc? _estimate(SalarySettings s) {
    final duration = _needsDuration ? _durationMinutes : null;
    final units = _needsUnits ? _dayUnitsHundredths : null;
    if (_needsDuration && (duration == null || duration <= 0)) return null;
    if (_needsUnits && (units == null || units <= 0)) return null;
    return SalaryCalculator.entryAmount(
      s,
      entryType: _type,
      durationMinutes: duration,
      dayUnitsHundredths: units,
      multiplierPctOverride: _multiplierPct(s),
      customRateMinor: _customRateMinor(s),
    );
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

  Future<void> _pickTime({required bool start}) async {
    final current = start ? _startTime : _endTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: current ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) {
      setState(() => start ? _startTime = picked : _endTime = picked);
    }
  }

  Future<void> _save(SalarySettings settings) async {
    setState(() => _failure = null);
    if (!_formKey.currentState!.validate()) return;
    final calc = _estimate(settings);
    if (calc == null) return;
    final duration = _needsDuration ? _durationMinutes : null;
    final draft = WorkEntryDraft(
      workDate: _date,
      entryType: _type,
      breakMinutes: _needsDuration ? _breakMinutes : 0,
      computedAmountMinor: calc.amount.minor,
      calcSnapshot: calc.snapshot,
      startMinuteOfDay: _needsDuration ? _startMinute : null,
      endMinuteOfDay: _needsDuration ? _endMinute : null,
      durationMinutes: duration,
      dayUnitsHundredths: _needsUnits ? _dayUnitsHundredths : null,
      multiplierPct: _type == WorkEntryType.regular
          ? null
          : _multiplierPct(settings),
      customRateMinor: _type == WorkEntryType.regular
          ? null
          : _customRateMinor(settings),
      holidayId: _type == WorkEntryType.holidayWorked ? _holidayId : null,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );
    setState(() => _busy = true);
    final repo = ref.read(workRepositoryProvider);
    final result = _isEdit
        ? await repo.updateEntry(widget.existing!.id, draft)
        : await repo.createEntry(draft);
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      ok: (_) {
        ref.invalidate(workEntriesForMonthProvider);
        AppToast.success(context, AppLocalizations.of(context).setSaved);
        context.pop();
      },
      err: (failure) => setState(() => _failure = failure),
    );
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.workDeleteEntryTitle),
        content: Text(l10n.workDeleteEntryBody),
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
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final result = await ref
        .read(workRepositoryProvider)
        .deleteEntry(widget.existing!.id);
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      ok: (_) {
        ref.invalidate(workEntriesForMonthProvider);
        context.pop();
      },
      err: (failure) => setState(() => _failure = failure),
    );
  }

  String _formatTimeOfDay(TimeOfDay? time) => time == null
      ? '—'
      : MaterialLocalizations.of(context).formatTimeOfDay(time);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings =
        ref.watch(salarySettingsProvider).value ?? SalarySettings.defaults;
    final holidays = ref.watch(holidaysProvider).value ?? <OfficialHoliday>[];
    final estimate = _estimate(settings);

    return Scaffold(
      appBar: FinanceSuitAppBar.focused(
        semanticTitle: _isEdit ? l10n.workEditEntry : l10n.workAddEntry,
        actions: [
          if (_isEdit)
            IconButton(
              icon: const FinanceSuitIcon(FinanceSuitIcons.delete),
              tooltip: l10n.commonDelete,
              onPressed: _busy ? null : _delete,
            ),
        ],
      ),
      body: FinanceSuitFocusedBody(
        title: _isEdit ? l10n.workEditEntry : l10n.workAddEntry,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSelectionField<WorkEntryType>(
                  initialValue: _type,
                  decoration: InputDecoration(labelText: l10n.workEntryType),
                  items: [
                    for (final type in WorkEntryType.values)
                      DropdownMenuItem(
                        value: type,
                        child: Text(workEntryTypeLabel(l10n, type)),
                      ),
                  ],
                  onChanged: _isEdit
                      ? null // changing type on edit invites constraint clashes
                      : (v) => setState(() => _type = v!),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const FinanceSuitIcon(
                    FinanceSuitIcons.calendarToday,
                  ),
                  title: Text(l10n.commonDate),
                  subtitle: Text(_date.toIso()),
                  trailing: const FinanceSuitIcon(FinanceSuitIcons.edit),
                  onTap: _pickDate,
                ),
                if (_type == WorkEntryType.holidayWorked) ...[
                  AppSelectionField<String?>(
                    initialValue: _holidayId,
                    decoration: InputDecoration(
                      labelText: l10n.workLinkedHoliday,
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(l10n.commonNone),
                      ),
                      for (final holiday in holidays)
                        DropdownMenuItem<String?>(
                          value: holiday.id,
                          child: Text(
                            '${holiday.date.toIso()} · ${holiday.name}',
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _holidayId = v),
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: true,
                        label: Text(l10n.workDayUnits),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text(l10n.workDurationMinutes),
                      ),
                    ],
                    selected: {_useDayUnits},
                    onSelectionChanged: (selection) =>
                        setState(() => _useDayUnits = selection.first),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_needsUnits)
                  AppTextFormField(
                    controller: _unitsController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(labelText: l10n.workDayUnits),
                    onChanged: (_) => setState(() {}),
                    validator: (_) {
                      final e = Validators.dayUnitsHundredths(
                        _dayUnitsHundredths,
                      );
                      return e == null ? null : validationMessage(context, e);
                    },
                  ),
                if (_needsDuration) ...[
                  Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.workStartTime),
                          subtitle: Text(_formatTimeOfDay(_startTime)),
                          onTap: () => _pickTime(start: true),
                        ),
                      ),
                      Expanded(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.workEndTime),
                          subtitle: Text(_formatTimeOfDay(_endTime)),
                          onTap: () => _pickTime(start: false),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: AppTextFormField(
                          controller: _durationController,
                          enabled: _startTime == null || _endTime == null,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: l10n.workDurationMinutes,
                            helperText: _startTime != null && _endTime != null
                                ? '${_durationMinutes ?? 0}'
                                : null,
                          ),
                          onChanged: (_) => setState(() {}),
                          validator: (_) {
                            final duration = _durationMinutes;
                            final e =
                                Validators.durationMinutes(duration) ??
                                (_startMinute != null && _endMinute != null
                                    ? Validators.breakWithinDuration(
                                        _breakMinutes,
                                        duration! + _breakMinutes,
                                      )
                                    : null);
                            return e == null
                                ? null
                                : validationMessage(context, e);
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: AppTextFormField(
                          controller: _breakController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: l10n.workBreakMinutes,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_type != WorkEntryType.regular) ...[
                  const SizedBox(height: 16),
                  AppTextFormField(
                    controller: _multiplierController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.workMultiplier,
                      hintText: '${_defaultMultiplier(settings)}',
                    ),
                    onChanged: (_) => setState(() => _multiplierTouched = true),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final e = Validators.multiplierPct(
                        int.tryParse(v.trim()),
                      );
                      return e == null ? null : validationMessage(context, e);
                    },
                  ),
                  const SizedBox(height: 16),
                  AppTextFormField(
                    controller: _customRateController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: moneyInputFormatters(),
                    decoration: InputDecoration(
                      labelText:
                          '${l10n.workCustomRate} (${l10n.commonOptional})',
                      suffixText: settings.currencyCode,
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final e = Validators.positiveAmount(
                        v,
                        currencyCode: settings.currencyCode,
                      );
                      return e == null ? null : validationMessage(context, e);
                    },
                  ),
                ],
                const SizedBox(height: 16),
                AppTextFormField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: '${l10n.commonNotes} (${l10n.commonOptional})',
                  ),
                  validator: (v) {
                    final e = Validators.optionalText(v);
                    return e == null ? null : validationMessage(context, e);
                  },
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const FinanceSuitIcon(FinanceSuitIcons.calculate),
                    title: Text(l10n.workEstimatedPay),
                    trailing: ProtectedMoneyText(
                      estimate?.amount.format() ?? '—',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AuthErrorBanner(failure: _failure),
                AuthSubmitButton(
                  label: l10n.commonSave,
                  busy: _busy,
                  onPressed: () => _save(settings),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
