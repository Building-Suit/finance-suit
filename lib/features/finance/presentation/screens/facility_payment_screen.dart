import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/money/money_input.dart';
import 'package:work_tracker/core/utils/client_uuid.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/app_selection_field.dart';
import 'package:work_tracker/core/widgets/app_text_form_field.dart';
import 'package:work_tracker/core/widgets/app_toast.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/core/widgets/protected_money.dart';
import 'package:work_tracker/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';
import 'package:work_tracker/features/finance/domain/facility_payment_component.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/widgets/facility_due_breakdown_widgets.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Focused form for paying a credit card or BNPL facility from an asset
/// account. The payment books one transfer — never an expense — and the user
/// chooses exactly which currently payable components it satisfies. The
/// selection is sent as explicit typed allocations to the v2 RPC, which
/// persists them; the Amount always equals the selected allocation total.
class FacilityPaymentScreen extends ConsumerStatefulWidget {
  const FacilityPaymentScreen({super.key, this.accountId, this.monthStartIso});

  final String? accountId;

  /// When set, the screen pays exactly that calendar month: components come
  /// from the month-scoped breakdown and the payment goes through the
  /// month-aware RPC, which lets next month be prepaid while this month is
  /// still open. When null the screen keeps its original payable-now
  /// behavior for the top-level Make payment action.
  final String? monthStartIso;

  @override
  ConsumerState<FacilityPaymentScreen> createState() =>
      _FacilityPaymentScreenState();
}

/// The identity of the explicit facility-balance pseudo component.
const _kBalanceKey = 'facility_balance';

class _FacilityPaymentScreenState extends ConsumerState<FacilityPaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  /// Client-generated so a save retry cannot duplicate the transfer.
  final String _paymentId = newClientUuid();

  String? _facilityId;
  String? _sourceAccountId;
  PlainDate _paidOn = PlainDate.today();
  AppFailure? _failure;
  bool _busy = false;

  /// Component key -> allocated minor amount. The single source of truth the
  /// Amount field is derived from.
  Map<String, int> _allocations = {};
  int _balanceMinor = 0;
  String? _activePreset;

  FacilityDueMonth? _month;

  @override
  void initState() {
    super.initState();
    _facilityId = widget.accountId;
    final monthIso = widget.monthStartIso;
    if (monthIso != null) {
      final start = PlainDate.parse(monthIso);
      final months = FacilityDueMonth.payable();
      _month = months.firstWhere(
        (m) => m.start == start,
        orElse: () => FacilityDueMonth(
          period: FacilityDuePeriod.currentMonth,
          start: start,
        ),
      );
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  int get _allocationTotal =>
      _allocations.values.fold(0, (a, b) => a + b) + _balanceMinor;

  void _resetSelection() {
    _allocations = {};
    _balanceMinor = 0;
    _activePreset = null;
    _amountController.clear();
  }

  void _syncAmountFromAllocations() {
    final total = _allocationTotal;
    _amountController.text = total <= 0 ? '' : formatMinorForInput(total);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidOn.toDateTime(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _paidOn = PlainDate.fromDateTime(picked);
      // A new payment date can change which components are payable, so the
      // breakdown refetches and the old selection no longer applies.
      _resetSelection();
    });
  }

  void _applyPreset(String preset, FacilityDueBreakdown breakdown) {
    final allocation = switch (preset) {
      'next' => nextDueAllocation(breakdown.components),
      'minimum' => minimumPaymentAllocation(
        breakdown.minimumRemainingMinor ?? 0,
        breakdown.components,
      ),
      _ => fullOutstandingAllocation(breakdown),
    };
    setState(() {
      _allocations = Map.of(allocation.componentAmounts);
      _balanceMinor = allocation.facilityBalanceMinor;
      _activePreset = preset;
      _syncAmountFromAllocations();
    });
  }

  void _toggleComponent(FacilityPaymentComponent component, bool selected) {
    setState(() {
      if (selected) {
        _allocations[component.key] = component.remainingMinor;
      } else {
        _allocations.remove(component.key);
      }
      _activePreset = null;
      _syncAmountFromAllocations();
    });
  }

  void _toggleBalance(bool selected, int maxMinor) {
    setState(() {
      _balanceMinor = selected ? maxMinor : 0;
      _activePreset = null;
      _syncAmountFromAllocations();
    });
  }

  Future<void> _editAllocationAmount({
    required String title,
    required String currencyCode,
    required int currentMinor,
    required int maxMinor,
    required void Function(int minor) onChanged,
  }) async {
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => _AllocationAmountDialog(
        title: title,
        currencyCode: currencyCode,
        currentMinor: currentMinor,
        maxMinor: maxMinor,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      onChanged(result);
      _activePreset = null;
      _syncAmountFromAllocations();
    });
  }

  /// A manual Amount edit stays explicit: the typed total is redistributed
  /// over the already selected rows in the deterministic priority order and
  /// any remainder lands on the visible facility-balance row. Nothing is
  /// allocated silently to unselected components.
  void _applyManualAmount(String text, FacilityDueBreakdown breakdown) {
    final parsed = Money.tryParse(text, currencyCode: breakdown.currencyCode);
    setState(() {
      _activePreset = null;
      if (parsed == null) return;
      var left = parsed.minor;
      final selectedKeys = _allocations.keys.toSet();
      final next = <String, int>{};
      for (final component in paymentPriorityOrder(breakdown.components)) {
        if (!selectedKeys.contains(component.key)) continue;
        if (left <= 0) break;
        final take = left < component.remainingMinor
            ? left
            : component.remainingMinor;
        next[component.key] = take;
        left -= take;
      }
      _allocations = next;
      _balanceMinor = _balanceMinor > 0 || left > 0
          ? left.clamp(0, breakdown.additionalBalanceMinor)
          : 0;
    });
  }

  Future<void> _save(
    CreditFacilitySummary facility,
    FacilityDueBreakdown breakdown,
  ) async {
    setState(() => _failure = null);
    if (!_formKey.currentState!.validate()) return;
    if (_busy) return;
    final amount = Money.tryParse(
      _amountController.text,
      currencyCode: facility.currencyCode,
    )!;
    if (_allocations.isEmpty && _balanceMinor <= 0) {
      setState(
        () =>
            _failure = const ValidationFailure('allocation_selection_required'),
      );
      return;
    }
    if (_allocationTotal != amount.minor) {
      setState(
        () => _failure = const ValidationFailure('allocation_total_mismatch'),
      );
      return;
    }
    final allocations = [
      for (final entry in _allocations.entries)
        FacilityAllocationEntry(
          type: entry.key.substring(0, entry.key.indexOf(':')),
          id: entry.key.substring(entry.key.indexOf(':') + 1),
          amountMinor: entry.value,
        ),
      if (_balanceMinor > 0)
        FacilityAllocationEntry(
          type: _kBalanceKey,
          id: facility.accountId,
          amountMinor: _balanceMinor,
        ),
    ];
    setState(() => _busy = true);
    final month = _month;
    final repository = ref.read(financeRepositoryProvider);
    final result = month == null
        ? await repository.payCreditFacilityV2(
            FacilityPaymentV2Draft(
              accountId: facility.accountId,
              sourceAccountId: _sourceAccountId!,
              amountMinor: amount.minor,
              paidOn: _paidOn,
              allocations: allocations,
              notes: _notesController.text.trim().isEmpty
                  ? null
                  : _notesController.text.trim(),
              paymentId: _paymentId,
            ),
          )
        : await repository.payCreditFacilityV3(
            FacilityPaymentV3Draft(
              accountId: facility.accountId,
              sourceAccountId: _sourceAccountId!,
              amountMinor: amount.minor,
              paidOn: _paidOn,
              monthStart: month.start,
              allocations: allocations,
              notes: _notesController.text.trim().isEmpty
                  ? null
                  : _notesController.text.trim(),
              paymentId: _paymentId,
            ),
          );
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      ok: (_) {
        invalidateFinanceData(ref);
        AppToast.success(context, AppLocalizations.of(context).setSaved);
        context.pushReplacement('/money/facilities/${facility.accountId}');
      },
      err: (failure) {
        setState(() {
          _failure = failure;
          // Never trust a stale snapshot after the server rejects an
          // allocation: refetch components and start the selection over.
          _resetSelection();
        });
        ref
          ..invalidate(facilityDueBreakdownProvider)
          ..invalidate(facilityMonthDueBreakdownProvider);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final facilitiesAsync = ref.watch(creditFacilitiesProvider);
    final month = _month;
    final title = month == null
        ? l10n.paymentTitle
        : l10n.dueMonthPayTitle(
            DateFormat.MMMM(
              Localizations.localeOf(context).toLanguageTag(),
            ).format(month.start.toDateTime()),
          );
    return Scaffold(
      appBar: FinanceSuitAppBar.focused(semanticTitle: title),
      body: FinanceSuitFocusedBody(
        title: title,
        child: AsyncView<List<CreditFacilitySummary>>(
          value: facilitiesAsync,
          onRetry: () => ref.invalidate(creditFacilitiesProvider),
          data: (facilities) {
            final payable = facilities
                .where((f) => f.outstandingMinor > 0)
                .toList();
            if (payable.isEmpty) {
              return EmptyStateView(
                icon: FinanceSuitIcons.creditCard,
                message: facilities.isEmpty
                    ? l10n.facilityEmptyTitle
                    : l10n.paymentNothingOwed,
                actionLabel: facilities.isEmpty
                    ? l10n.facilityEmptyAction
                    : null,
                onAction: facilities.isEmpty
                    ? () => context.push('/money/accounts/new')
                    : null,
              );
            }
            final facility =
                payable.where((f) => f.accountId == _facilityId).firstOrNull ??
                payable.first;
            _facilityId = facility.accountId;
            final month = _month;
            final breakdownAsync = month == null
                ? ref.watch(
                    facilityDueBreakdownProvider((
                      accountId: facility.accountId,
                      asOfIso: _paidOn.toIso(),
                    )),
                  )
                : ref.watch(
                    facilityMonthDueBreakdownProvider((
                      accountId: facility.accountId,
                      monthStartIso: month.key,
                    )),
                  );
            return AsyncView<FacilityDueBreakdown>(
              value: breakdownAsync,
              onRetry: () => ref
                ..invalidate(facilityDueBreakdownProvider)
                ..invalidate(facilityMonthDueBreakdownProvider),
              data: (breakdown) =>
                  _buildForm(context, l10n, payable, facility, breakdown),
            );
          },
        ),
      ),
    );
  }

  Widget _buildForm(
    BuildContext context,
    AppLocalizations l10n,
    List<CreditFacilitySummary> facilities,
    CreditFacilitySummary facility,
    FacilityDueBreakdown breakdown,
  ) {
    final currency = facility.currencyCode;
    final theme = Theme.of(context);
    final sources =
        (ref.watch(accountBalancesProvider).value ?? <AccountBalance>[])
            .assetAccounts
            .where((a) => a.currencyCode == currency)
            .toList();
    final amountMinor = Money.tryParse(
      _amountController.text,
      currencyCode: currency,
    )?.minor;
    final mismatch =
        amountMinor != null &&
        amountMinor > 0 &&
        amountMinor != _allocationTotal;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSelectionField<String>(
              key: ValueKey('payment-facility-$_facilityId'),
              initialValue: facility.accountId,
              decoration: InputDecoration(labelText: l10n.purchaseFacility),
              items: [
                for (final f in facilities)
                  DropdownMenuItem(
                    value: f.accountId,
                    child: ProtectedMoney(
                      interactive: false,
                      child: Text('${f.name} (${f.outstanding.format()})'),
                    ),
                  ),
              ],
              onChanged: (v) => setState(() {
                _facilityId = v;
                _sourceAccountId = null;
                _resetSelection();
              }),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: _PaymentMetric(
                        label: l10n.facilityDueNow,
                        money: facility.dueNow,
                      ),
                    ),
                    Expanded(
                      child: _PaymentMetric(
                        label: l10n.facilityOverdueBadge,
                        money: facility.overdue,
                      ),
                    ),
                    Expanded(
                      child: _PaymentMetric(
                        label: l10n.facilityOwed,
                        money: facility.outstanding,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            AppSelectionField<String>(
              key: ValueKey('payment-source-$_sourceAccountId'),
              initialValue: sources.any((a) => a.accountId == _sourceAccountId)
                  ? _sourceAccountId
                  : null,
              decoration: InputDecoration(labelText: l10n.paymentSource),
              items: [
                for (final account in sources)
                  DropdownMenuItem(
                    value: account.accountId,
                    child: ProtectedMoney(
                      interactive: false,
                      child: Text(
                        '${account.name} (${account.balance.format()})',
                      ),
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _sourceAccountId = v),
              validator: (v) => v == null
                  ? validationMessage(context, ValidationError.required)
                  : null,
            ),
            const SizedBox(height: 16),
            AppTextFormField(
              key: const Key('payment-amount'),
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: moneyInputFormatters(),
              decoration: InputDecoration(
                labelText: l10n.commonAmount,
                suffixText: currency,
                helperText: _activePreset == null && _allocations.isNotEmpty
                    ? l10n.paymentCustomSelection
                    : null,
              ),
              onChanged: (text) => _applyManualAmount(text, breakdown),
              validator: (v) {
                final e = Validators.positiveAmount(v, currencyCode: currency);
                if (e != null) return validationMessage(context, e);
                final parsed = Money.tryParse(v!, currencyCode: currency)!;
                if (parsed.minor > facility.outstandingMinor) {
                  return l10n.valPaymentAboveOutstanding;
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  key: const Key('payment-chip-next'),
                  label: Text(l10n.paymentNextDueChip),
                  onPressed: () => _applyPreset('next', breakdown),
                ),
                if (breakdown.supportsMinimumPayment)
                  ActionChip(
                    key: const Key('payment-chip-minimum'),
                    label: Text(l10n.paymentMinimumChip),
                    onPressed: () => _applyPreset('minimum', breakdown),
                  ),
                ActionChip(
                  key: const Key('payment-chip-full'),
                  label: Text(l10n.paymentFullChip),
                  onPressed: () => _applyPreset('full', breakdown),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const FinanceSuitIcon(FinanceSuitIcons.calendarToday),
              title: Text(l10n.paymentDate),
              subtitle: Text(_paidOn.toIso()),
              trailing: const FinanceSuitIcon(FinanceSuitIcons.edit),
              onTap: _busy ? null : _pickDate,
            ),
            const SizedBox(height: 8),
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
            _buildChecklist(context, l10n, theme, breakdown),
            if (mismatch)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.valAllocationTotalMismatch,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            AuthErrorBanner(failure: _failure),
            AuthSubmitButton(
              label: l10n.facilityMakePayment,
              busy: _busy,
              onPressed: () => _save(facility, breakdown),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChecklist(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    FacilityDueBreakdown breakdown,
  ) {
    final groups = groupDueComponents(breakdown.components);
    final currency = breakdown.currencyCode;
    return Card(
      key: const Key('payment-checklist'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.paymentChooseWhatToPay,
              style: theme.textTheme.titleSmall,
            ),
            if (breakdown.components.isEmpty &&
                breakdown.additionalBalanceMinor <= 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.dueBreakdownEmpty,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            for (final group in DueComponentGroup.values)
              if (groups[group] case final components?) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Text(
                    dueComponentGroupLabel(l10n, group),
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                for (final component in components)
                  if (component.isSelectable)
                    _ChecklistRow(
                      key: ValueKey('payment-row-${component.key}'),
                      component: component,
                      currencyCode: currency,
                      allocatedMinor: _allocations[component.key],
                      busy: _busy,
                      onToggle: (selected) =>
                          _toggleComponent(component, selected),
                      onEditAmount: () => _editAllocationAmount(
                        title: dueComponentTitle(l10n, component),
                        currencyCode: currency,
                        currentMinor:
                            _allocations[component.key] ??
                            component.remainingMinor,
                        maxMinor: component.remainingMinor,
                        onChanged: (minor) =>
                            _allocations[component.key] = minor,
                      ),
                    )
                  else
                    DueBreakdownRow(
                      component: component,
                      currencyCode: currency,
                    ),
              ],
            if (breakdown.additionalBalanceMinor > 0) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(
                  l10n.paymentAdditionalBalance,
                  style: theme.textTheme.labelLarge,
                ),
              ),
              _BalanceRow(
                key: const ValueKey('payment-row-facility-balance'),
                currencyCode: currency,
                maxMinor: breakdown.additionalBalanceMinor,
                allocatedMinor: _balanceMinor > 0 ? _balanceMinor : null,
                busy: _busy,
                onToggle: (selected) =>
                    _toggleBalance(selected, breakdown.additionalBalanceMinor),
                onEditAmount: () => _editAllocationAmount(
                  title: l10n.paymentAdditionalBalance,
                  currencyCode: currency,
                  currentMinor: _balanceMinor > 0
                      ? _balanceMinor
                      : breakdown.additionalBalanceMinor,
                  maxMinor: breakdown.additionalBalanceMinor,
                  onChanged: (minor) => _balanceMinor = minor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Per-row payment amount editor: makes a partial allocation explicit as
/// "Pay X / Y" instead of silently splitting a bigger amount.
class _AllocationAmountDialog extends StatefulWidget {
  const _AllocationAmountDialog({
    required this.title,
    required this.currencyCode,
    required this.currentMinor,
    required this.maxMinor,
  });

  final String title;
  final String currencyCode;
  final int currentMinor;
  final int maxMinor;

  @override
  State<_AllocationAmountDialog> createState() =>
      _AllocationAmountDialogState();
}

class _AllocationAmountDialogState extends State<_AllocationAmountDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: formatMinorForInput(widget.currentMinor),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.paymentEditRowAmount(widget.title)),
      content: TextField(
        key: const Key('payment-row-amount-input'),
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: moneyInputFormatters(),
        decoration: InputDecoration(
          labelText: l10n.paymentRowPayAmount,
          suffixText: widget.currencyCode,
          helperText: Money(
            minor: widget.maxMinor,
            currencyCode: widget.currencyCode,
          ).format(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () {
            final parsed = Money.tryParse(
              _controller.text,
              currencyCode: widget.currencyCode,
            );
            if (parsed == null ||
                parsed.minor <= 0 ||
                parsed.minor > widget.maxMinor) {
              return;
            }
            Navigator.of(context).pop(parsed.minor);
          },
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({
    super.key,
    required this.component,
    required this.currencyCode,
    required this.allocatedMinor,
    required this.busy,
    required this.onToggle,
    required this.onEditAmount,
  });

  final FacilityPaymentComponent component;
  final String currencyCode;
  final int? allocatedMinor;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEditAmount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final selected = allocatedMinor != null;
    final partialTarget =
        selected && allocatedMinor! < component.remainingMinor;
    String money(int minor) =>
        Money(minor: minor, currencyCode: currencyCode).format();
    final subtitleParts = [
      ?dueComponentSubtitle(l10n, component),
      if (component.status == ComponentPaymentStatus.partiallyPaid)
        l10n.paymentRowRemaining(money(component.remainingMinor)),
      if (partialTarget)
        l10n.paymentRowPayPartial(
          money(allocatedMinor!),
          money(component.remainingMinor),
        ),
    ];

    return MergeSemantics(
      child: InkWell(
        onTap: busy ? null : () => onToggle(!selected),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: busy ? null : (v) => onToggle(v ?? false),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dueComponentTitle(l10n, component),
                      style: theme.textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitleParts.isNotEmpty)
                      Text(
                        subtitleParts.join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              TextButton(
                onPressed: busy || !selected ? null : onEditAmount,
                child: ProtectedMoneyText(
                  money(selected ? allocatedMinor! : component.remainingMinor),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                  ),
                  interactive: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({
    super.key,
    required this.currencyCode,
    required this.maxMinor,
    required this.allocatedMinor,
    required this.busy,
    required this.onToggle,
    required this.onEditAmount,
  });

  final String currencyCode;
  final int maxMinor;
  final int? allocatedMinor;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEditAmount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final selected = allocatedMinor != null;
    String money(int minor) =>
        Money(minor: minor, currencyCode: currencyCode).format();
    return MergeSemantics(
      child: InkWell(
        onTap: busy ? null : () => onToggle(!selected),
        child: Row(
          children: [
            Checkbox(
              value: selected,
              onChanged: busy ? null : (v) => onToggle(v ?? false),
            ),
            Expanded(
              child: Text(
                l10n.paymentAdditionalBalance,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            TextButton(
              onPressed: busy || !selected ? null : onEditAmount,
              child: ProtectedMoneyText(
                money(selected ? allocatedMinor! : maxMinor),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
                interactive: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentMetric extends StatelessWidget {
  const _PaymentMetric({required this.label, required this.money});

  final String label;
  final Money money;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        ProtectedMoneyText(
          money.format(),
          style: theme.textTheme.titleSmall,
          interactive: false,
        ),
      ],
    );
  }
}
