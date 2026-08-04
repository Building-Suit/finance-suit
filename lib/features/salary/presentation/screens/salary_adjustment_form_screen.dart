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
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:work_tracker/features/salary/data/salary_repository.dart';
import 'package:work_tracker/features/salary/domain/salary_adjustment.dart';
import 'package:work_tracker/features/salary/domain/salary_period.dart';
import 'package:work_tracker/features/salary/presentation/providers/salary_providers.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class _OpenPeriod {
  const _OpenPeriod({
    required this.id,
    required this.start,
    required this.end,
    required this.isCurrent,
  });

  final String id;
  final PlainDate start;
  final PlainDate end;
  final bool isCurrent;
}

/// Creates a salary adjustment from the global Add flow. The period picker
/// retains the range context that used to come from a period-detail page.
class SalaryAdjustmentFormScreen extends ConsumerStatefulWidget {
  const SalaryAdjustmentFormScreen({super.key, this.preferredPeriodId});

  final String? preferredPeriodId;

  @override
  ConsumerState<SalaryAdjustmentFormScreen> createState() =>
      _SalaryAdjustmentFormScreenState();
}

class _SalaryAdjustmentFormScreenState
    extends ConsumerState<SalaryAdjustmentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();

  List<_OpenPeriod> _periods = const [];
  String? _periodKey;
  String _currencyCode = 'EGP';
  PlainDate _date = PlainDate.today();
  AdjustmentType _type = AdjustmentType.bonus;
  AppFailure? _failure;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadPeriods();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadPeriods() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _failure = null;
      });
    }
    try {
      final bounds = await ref.read(currentPeriodBoundsProvider.future);
      final fetchedPeriods = await ref.read(salaryPeriodsProvider.future);
      final settings = await ref.read(salarySettingsProvider.future);
      final periods = [...fetchedPeriods];

      // Adjustments are date-based rather than period-ID-based. Never create
      // a synthetic current period over an existing stored range, otherwise
      // one adjustment could be counted by two overlapping periods after a
      // salary start-day setting change.
      final hasCurrentStart = periods.any(
        (period) => period.periodStart == bounds.start,
      );
      final overlapsStoredPeriod = periods.any(
        (period) =>
            !period.periodEnd.isBefore(bounds.start) &&
            !period.periodStart.isAfter(bounds.end),
      );
      if (!hasCurrentStart && !overlapsStoredPeriod) {
        final ensured = await ref
            .read(salaryRepositoryProvider)
            .ensurePeriod(bounds);
        periods.add(
          ensured.when(ok: (period) => period, err: (failure) => throw failure),
        );
      }

      final openPeriods = periods.where((period) => period.isOpen).toList();
      final prioritized = <SalaryPeriod>[];
      final seenIds = <String>{};
      void addMatching(bool Function(SalaryPeriod period) predicate) {
        for (final period in openPeriods) {
          if (predicate(period) && seenIds.add(period.id)) {
            prioritized.add(period);
          }
        }
      }

      final today = PlainDate.today();
      addMatching((period) => period.id == widget.preferredPeriodId);
      addMatching(
        (period) =>
            period.periodStart == bounds.start &&
            period.periodEnd == bounds.end,
      );
      addMatching(
        (period) =>
            !today.isBefore(period.periodStart) &&
            !today.isAfter(period.periodEnd),
      );
      addMatching((_) => true);

      // Existing ranges can overlap after settings changes. Offer only one
      // authoritative option per date range so a new date-based adjustment
      // cannot be selected through two different periods.
      final options = <_OpenPeriod>[];
      for (final period in prioritized) {
        final overlapsAccepted = options.any(
          (accepted) =>
              !accepted.end.isBefore(period.periodStart) &&
              !accepted.start.isAfter(period.periodEnd),
        );
        if (overlapsAccepted) continue;
        options.add(
          _OpenPeriod(
            id: period.id,
            start: period.periodStart,
            end: period.periodEnd,
            isCurrent:
                period.periodStart == bounds.start &&
                period.periodEnd == bounds.end,
          ),
        );
      }

      if (!mounted) return;
      final selected = options.firstOrNull;
      setState(() {
        _periods = options;
        _periodKey = selected?.id;
        _currencyCode = settings.currencyCode;
        _date = selected == null
            ? PlainDate.today()
            : _clampToday(selected.start, selected.end);
        _loading = false;
      });
    } on AppFailure catch (failure) {
      if (mounted) {
        setState(() {
          _failure = failure;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _failure = const UnknownFailure();
          _loading = false;
        });
      }
    }
  }

  Future<void> _retryLoadPeriods() async {
    ref
      ..invalidate(salarySettingsProvider)
      ..invalidate(currentPeriodBoundsProvider)
      ..invalidate(salaryPeriodsProvider);
    await _loadPeriods();
  }

  _OpenPeriod? get _selectedPeriod {
    for (final period in _periods) {
      if (period.id == _periodKey) return period;
    }
    return null;
  }

  Future<void> _pickDate() async {
    final period = _selectedPeriod;
    if (period == null) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.toDateTime(),
      firstDate: period.start.toDateTime(),
      lastDate: period.end.toDateTime(),
    );
    if (picked != null) {
      setState(() => _date = PlainDate.fromDateTime(picked));
    }
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _failure = null);
    final selectedPeriod = _selectedPeriod;
    if (selectedPeriod == null || !_formKey.currentState!.validate()) return;
    final amount = Money.tryParse(
      _amountController.text,
      currencyCode: _currencyCode,
    )!;
    final title = _titleController.text.trim();
    final notes = _notesController.text.trim();
    setState(() => _busy = true);
    final repository = ref.read(salaryRepositoryProvider);
    final refreshedResult = await repository.fetchPeriod(selectedPeriod.id);
    if (!mounted) return;
    final refreshFailure = refreshedResult.failureOrNull;
    if (refreshFailure != null) {
      setState(() {
        _busy = false;
        _failure = refreshFailure;
      });
      return;
    }
    final refreshed = refreshedResult.valueOrNull!;
    if (!refreshed.isOpen ||
        _date.isBefore(refreshed.periodStart) ||
        _date.isAfter(refreshed.periodEnd)) {
      setState(() => _busy = false);
      AppToast.warning(context, l10n.salPeriodNoLongerOpen);
      await _retryLoadPeriods();
      return;
    }
    final result = await repository.createAdjustment(
      SalaryAdjustmentDraft(
        effectiveDate: _date,
        adjustmentType: _type,
        amountMinor: amount.minor,
        title: title.isEmpty ? null : title,
        notes: notes.isEmpty ? null : notes,
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      ok: (_) {
        invalidateSalaryData(ref);
        AppToast.success(context, AppLocalizations.of(context).setSaved);
        context.pop();
      },
      err: (failure) => setState(() => _failure = failure),
    );
  }

  static PlainDate _clampToday(PlainDate start, PlainDate end) {
    final today = PlainDate.today();
    if (today.isBefore(start)) return start;
    if (today.isAfter(end)) return end;
    return today;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: FinanceSuitAppBar.focused(semanticTitle: l10n.salNewAdjustment),
      body: FinanceSuitFocusedBody(
        title: l10n.salNewAdjustment,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _failure != null && _periods.isEmpty
            ? ErrorRetryView(failure: _failure!, onRetry: _retryLoadPeriods)
            : _periods.isEmpty
            ? EmptyStateView(
                icon: FinanceSuitIcons.eventBusy,
                message: l10n.salNoOpenPeriods,
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppSelectionField<String>(
                        initialValue: _periodKey,
                        decoration: InputDecoration(
                          labelText: l10n.salPeriodsTitle,
                        ),
                        items: [
                          for (final period in _periods)
                            DropdownMenuItem(
                              value: period.id,
                              child: Text(
                                period.isCurrent
                                    ? l10n.salCurrentPeriod
                                    : '${period.start.toIso()} → ${period.end.toIso()}',
                              ),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (key) {
                                if (key == null) return;
                                final period = _periods.firstWhere(
                                  (candidate) => candidate.id == key,
                                );
                                setState(() {
                                  _periodKey = key;
                                  _date = _clampToday(period.start, period.end);
                                });
                              },
                      ),
                      const SizedBox(height: 16),
                      SegmentedButton<AdjustmentType>(
                        segments: [
                          ButtonSegment(
                            value: AdjustmentType.bonus,
                            label: Text(l10n.salAdjBonus),
                          ),
                          ButtonSegment(
                            value: AdjustmentType.deduction,
                            label: Text(l10n.salAdjDeduction),
                          ),
                        ],
                        selected: {_type},
                        onSelectionChanged: _busy
                            ? null
                            : (selection) =>
                                  setState(() => _type = selection.first),
                      ),
                      const SizedBox(height: 16),
                      AppTextFormField(
                        controller: _amountController,
                        enabled: !_busy,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: moneyInputFormatters(),
                        decoration: InputDecoration(
                          labelText: l10n.commonAmount,
                          suffixText: _currencyCode,
                        ),
                        validator: (value) {
                          final error = Validators.positiveAmount(
                            value,
                            currencyCode: _currencyCode,
                          );
                          return error == null
                              ? null
                              : validationMessage(context, error);
                        },
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        enabled: !_busy,
                        leading: const FinanceSuitIcon(
                          FinanceSuitIcons.calendarToday,
                        ),
                        title: Text(l10n.salEffectiveDate),
                        subtitle: Text(_date.toIso()),
                        onTap: _pickDate,
                      ),
                      AppTextFormField(
                        controller: _titleController,
                        enabled: !_busy,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText:
                              '${l10n.txTitleField} (${l10n.commonOptional})',
                        ),
                        validator: (value) {
                          final error = Validators.optionalText(
                            value,
                            maxLength: 120,
                          );
                          return error == null
                              ? null
                              : validationMessage(context, error);
                        },
                      ),
                      const SizedBox(height: 8),
                      AppTextFormField(
                        controller: _notesController,
                        enabled: !_busy,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText:
                              '${l10n.commonNotes} (${l10n.commonOptional})',
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
      ),
    );
  }
}
