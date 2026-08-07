import 'dart:math' as math;

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
import 'package:work_tracker/core/utils/client_uuid.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/app_selection_field.dart';
import 'package:work_tracker/core/widgets/app_text_form_field.dart';
import 'package:work_tracker/core/widgets/app_toast.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/core/widgets/domain_labels.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/core/widgets/protected_money.dart';
import 'package:work_tracker/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/widgets/category_selector.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Focused form for financing a purchase through a credit card or BNPL
/// facility, and for fully editing a plan that has no payments yet.
///
/// Financing supports four pricing methods (manual fees, quoted monthly
/// amount, quoted total payable, interest rate), optional upfront and
/// financed fees, a dedicated down-payment section, and importing a plan
/// that is already partially paid outside the app.
class InstallmentPurchaseScreen extends ConsumerStatefulWidget {
  const InstallmentPurchaseScreen({super.key, this.accountId, this.planId});

  final String? accountId;

  /// When set, the screen edits this existing (unpaid) plan in place.
  final String? planId;

  @override
  ConsumerState<InstallmentPurchaseScreen> createState() =>
      _InstallmentPurchaseScreenState();
}

class _InstallmentPurchaseScreenState
    extends ConsumerState<InstallmentPurchaseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _priceController = TextEditingController();
  final _downController = TextEditingController();
  final _feesController = TextEditingController(text: '0');
  final _totalController = TextEditingController();
  final _monthlyController = TextEditingController();
  final _rateController = TextEditingController(text: '0');
  final _financedFeesController = TextEditingController(text: '0');
  final _upfrontFeesController = TextEditingController(text: '0');
  final _countController = TextEditingController(text: '1');
  final _paidCountController = TextEditingController(text: '0');
  final _notesController = TextEditingController();

  /// Client-generated so a save retry cannot create a second plan.
  final String _newPlanId = newClientUuid();

  String? _facilityId;
  String? _categoryId;
  String? _downAccountId;
  bool _hasDownPayment = false;
  bool _importRunning = false;
  PlanPricingMethod _pricing = PlanPricingMethod.manualFees;
  InterestRatePeriod _ratePeriod = InterestRatePeriod.monthly;
  InterestMethod _rateMethod = InterestMethod.flat;
  PlainDate _purchasedOn = PlainDate.today();
  PlainDate? _firstDueOn;
  AppFailure? _failure;
  bool _busy = false;
  bool _editLoaded = false;

  bool get _isEdit => widget.planId != null;

  @override
  void initState() {
    super.initState();
    _facilityId = widget.accountId;
    if (_isEdit) {
      _loadExisting();
    } else {
      _editLoaded = true;
    }
  }

  Future<void> _loadExisting() async {
    final result = await ref
        .read(financeRepositoryProvider)
        .fetchInstallmentPlan(widget.planId!);
    if (!mounted) return;
    final plan = result.valueOrNull;
    if (plan == null) {
      setState(() {
        _failure = result.failureOrNull;
        _editLoaded = true;
      });
      return;
    }
    _facilityId = plan.accountId;
    _categoryId = plan.categoryId;
    _titleController.text = plan.title;
    _priceController.text = formatMinorForInput(plan.purchasePriceMinor);
    _countController.text = '${plan.installmentCount}';
    _notesController.text = plan.notes ?? '';
    _purchasedOn = plan.purchasedOn;
    _firstDueOn = plan.firstDueOn;
    _pricing = plan.pricingMethod;
    _ratePeriod = plan.interestRatePeriod;
    _rateMethod = plan.interestMethod;
    if (plan.downPaymentMinor > 0) {
      _hasDownPayment = true;
      _downController.text = formatMinorForInput(plan.downPaymentMinor);
    }
    switch (plan.pricingMethod) {
      case PlanPricingMethod.manualFees:
        _feesController.text = formatMinorForInput(
          plan.financingFeesMinor - plan.interestMinor,
        );
      case PlanPricingMethod.totalPayable:
        _totalController.text = formatMinorForInput(plan.totalPayableMinor);
      case PlanPricingMethod.monthlyAmount:
        _monthlyController.text = formatMinorForInput(
          plan.installmentCount == 0
              ? 0
              : plan.totalPayableMinor ~/ plan.installmentCount,
        );
      case PlanPricingMethod.interestRate:
      case PlanPricingMethod.cardTenorDefault:
        // Both snapshot their resolved rate the same way at creation; the
        // card's tenor table itself may have since changed, so show what
        // this plan actually locked in, not today's table value.
        _rateController.text = (plan.interestRateBasisPoints / 100)
            .toStringAsFixed(2);
    }
    if (plan.origin == PlanOrigin.historicalImport) {
      // Editing an imported plan must keep its presettled dues; count them
      // so the rebuilt schedule marks the same leading portion as paid.
      final dues = await ref
          .read(financeRepositoryProvider)
          .fetchInstallmentDues(planId: plan.id);
      if (!mounted) return;
      final presettled =
          dues.valueOrNull?.where((d) => d.isPresettled).length ?? 0;
      if (presettled > 0) {
        _importRunning = true;
        _paidCountController.text = '$presettled';
      }
    }
    setState(() => _editLoaded = true);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _downController.dispose();
    _feesController.dispose();
    _totalController.dispose();
    _monthlyController.dispose();
    _rateController.dispose();
    _financedFeesController.dispose();
    _upfrontFeesController.dispose();
    _countController.dispose();
    _paidCountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  PlainDate _defaultFirstDue(CreditFacilitySummary facility) {
    final day = facility.defaultDueDay;
    var candidate = _purchasedOn.withDay(
      math.min(
        day,
        PlainDate.daysInMonth(_purchasedOn.year, _purchasedOn.month),
      ),
    );
    if (candidate.isBefore(_purchasedOn)) {
      candidate = _purchasedOn.withDay(1).addMonths(1);
      candidate = candidate.withDay(
        math.min(day, PlainDate.daysInMonth(candidate.year, candidate.month)),
      );
    }
    return candidate;
  }

  int? _minor(TextEditingController controller, String currency) =>
      Money.tryParse(controller.text, currencyCode: currency)?.minor;

  /// The rate field takes a percentage like `2.5`; basis points are exact
  /// because the input allows at most two decimals.
  int get _rateBasisPoints {
    final money = Money.tryParse(_rateController.text, currencyCode: 'BP');
    return money?.minor ?? 0;
  }

  Future<void> _pickDate({required bool purchase}) async {
    final initial = purchase ? _purchasedOn : (_firstDueOn ?? _purchasedOn);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.toDateTime(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (purchase) {
        _purchasedOn = PlainDate.fromDateTime(picked);
      } else {
        _firstDueOn = PlainDate.fromDateTime(picked);
      }
    });
  }

  InstallmentPlanDraft _buildDraft(CreditFacilitySummary facility) {
    final currency = facility.currencyCode;
    final price = _minor(_priceController, currency)!;
    final down = _hasDownPayment ? (_minor(_downController, currency) ?? 0) : 0;
    final count = int.parse(_countController.text.trim());
    final financedFees = _minor(_financedFeesController, currency) ?? 0;
    final upfrontFees = _hasDownPayment
        ? (_minor(_upfrontFeesController, currency) ?? 0)
        : 0;
    final paid = _importRunning
        ? (int.tryParse(_paidCountController.text.trim()) ?? 0)
        : 0;
    return InstallmentPlanDraft(
      accountId: facility.accountId,
      title: _titleController.text.trim(),
      categoryId: _categoryId!,
      purchasedOn: _purchasedOn,
      purchasePriceMinor: price,
      installmentCount: count,
      firstDueOn: _firstDueOn ?? _defaultFirstDue(facility),
      downPaymentMinor: down,
      downPaymentAccountId: down > 0 || upfrontFees > 0 ? _downAccountId : null,
      financingFeesMinor: _pricing == PlanPricingMethod.manualFees
          ? (_minor(_feesController, currency) ?? 0)
          : null,
      totalPayableMinor: _pricing == PlanPricingMethod.totalPayable
          ? _minor(_totalController, currency)
          : null,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      planId: _isEdit ? widget.planId : _newPlanId,
      pricingMethod: _pricing,
      monthlyPaymentMinor: _pricing == PlanPricingMethod.monthlyAmount
          ? _minor(_monthlyController, currency)
          : null,
      interestRateBasisPoints: _pricing == PlanPricingMethod.interestRate
          ? _rateBasisPoints
          : 0,
      interestRatePeriod: _ratePeriod,
      interestMethod: _rateMethod,
      financedFeesMinor: financedFees,
      upfrontFeesMinor: upfrontFees,
      downPaidOn: down > 0 ? _purchasedOn : null,
      paidInstallments: paid,
    );
  }

  Future<void> _save(CreditFacilitySummary facility) async {
    setState(() => _failure = null);
    if (!_formKey.currentState!.validate()) return;
    if (_busy) return;
    setState(() => _busy = true);
    final repo = ref.read(financeRepositoryProvider);
    final draft = _buildDraft(facility);
    final result = _isEdit
        ? await repo.updateInstallmentPlan(widget.planId!, draft)
        : await repo.createInstallmentPlan(draft);
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      ok: (_) {
        invalidateFinanceData(ref);
        AppToast.success(context, AppLocalizations.of(context).setSaved);
        context.pushReplacement('/money/facilities/${facility.accountId}');
      },
      err: (failure) => setState(() => _failure = failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final facilitiesAsync = ref.watch(creditFacilitiesProvider);
    final title = _isEdit ? l10n.purchaseEditTitle : l10n.purchaseTitle;
    return Scaffold(
      appBar: FinanceSuitAppBar.focused(semanticTitle: title),
      body: FinanceSuitFocusedBody(
        title: title,
        child: !_editLoaded
            ? const Center(child: CircularProgressIndicator())
            : AsyncView<List<CreditFacilitySummary>>(
                value: facilitiesAsync,
                onRetry: () => ref.invalidate(creditFacilitiesProvider),
                data: (facilities) {
                  final usable = _isEdit
                      ? facilities
                      : facilities.where((f) => f.canFundPurchases).toList();
                  if (usable.isEmpty) {
                    return EmptyStateView(
                      icon: FinanceSuitIcons.creditCard,
                      message: l10n.facilityEmptyTitle,
                      actionLabel: l10n.facilityEmptyAction,
                      onAction: () => context.push('/money/accounts/new'),
                    );
                  }
                  final facility =
                      usable
                          .where((f) => f.accountId == _facilityId)
                          .firstOrNull ??
                      usable.first;
                  _facilityId = facility.accountId;
                  return _buildForm(context, l10n, usable, facility);
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
  ) {
    final currency = facility.currencyCode;
    final categories =
        ref.watch(categoriesProvider(CategoryKind.expense)).value ?? const [];
    final assets =
        (ref.watch(accountBalancesProvider).value ?? <AccountBalance>[])
            .assetAccounts
            .where((a) => a.currencyCode == currency)
            .toList();

    final price = _minor(_priceController, currency);
    final down = _hasDownPayment ? (_minor(_downController, currency) ?? 0) : 0;
    final financed = price == null ? null : price - down;
    final count = int.tryParse(_countController.text.trim());
    final financedFees = _minor(_financedFeesController, currency) ?? 0;
    final upfrontFees = _hasDownPayment
        ? (_minor(_upfrontFeesController, currency) ?? 0)
        : 0;
    final financing = financed == null || financed <= 0 || count == null
        ? null
        : previewPlanFinancing(
            pricingMethod: _pricing,
            principalMinor: financed,
            count: count,
            manualFeesMinor: _minor(_feesController, currency),
            totalPayableMinor: _minor(_totalController, currency),
            monthlyPaymentMinor: _minor(_monthlyController, currency),
            rateBasisPoints: _rateBasisPoints,
            ratePeriod: _ratePeriod,
            interestMethod: _rateMethod,
            financedFeesMinor: financedFees,
          );
    final paidCount = _importRunning
        ? (int.tryParse(_paidCountController.text.trim()) ?? 0)
        : 0;
    final chargeMinor = financing == null || count == null || count < 1
        ? null
        : financing.totalMinor -
              previewInstallmentSchedule(
                    totalPayableMinor: financing.totalMinor,
                    installmentCount: count,
                    firstDueOn: _firstDueOn ?? _defaultFirstDue(facility),
                  )
                  .take(paidCount.clamp(0, count).toInt())
                  .fold<int>(0, (sum, e) => sum + e.amountMinor);
    final exceedsCredit =
        !_isEdit &&
        chargeMinor != null &&
        chargeMinor > facility.availableCreditMinor;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSelectionField<String>(
              key: ValueKey('purchase-facility-$_facilityId'),
              initialValue: facility.accountId,
              decoration: InputDecoration(labelText: l10n.purchaseFacility),
              items: [
                for (final f in facilities)
                  DropdownMenuItem(
                    value: f.accountId,
                    child: ProtectedMoney(
                      interactive: false,
                      child: Text('${f.name} (${f.availableCredit.format()})'),
                    ),
                  ),
              ],
              onChanged: _isEdit
                  ? null
                  : (v) => setState(() {
                      _facilityId = v;
                      _downAccountId = null;
                      _firstDueOn = null;
                    }),
            ),
            const SizedBox(height: 16),
            AppTextFormField(
              key: const Key('purchase-merchant'),
              controller: _titleController,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: l10n.purchaseMerchant),
              validator: (v) {
                final e = Validators.requiredText(v);
                return e == null ? null : validationMessage(context, e);
              },
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const FinanceSuitIcon(FinanceSuitIcons.calendarToday),
              title: Text(l10n.purchaseDateLabel),
              subtitle: Text(_purchasedOn.toIso()),
              trailing: const FinanceSuitIcon(FinanceSuitIcons.edit),
              onTap: _busy ? null : () => _pickDate(purchase: true),
            ),
            const SizedBox(height: 8),
            CategorySelector(
              categories: categories,
              selectedCategoryId: _categoryId,
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 16),
            AppTextFormField(
              key: const Key('purchase-price'),
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: moneyInputFormatters(),
              decoration: InputDecoration(
                labelText: l10n.purchasePrice,
                suffixText: currency,
              ),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final e = Validators.positiveAmount(v, currencyCode: currency);
                return e == null ? null : validationMessage(context, e);
              },
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: l10n.purchaseDownPaymentSection,
              subtitle: l10n.purchaseDownPaymentSectionHelp,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    key: const Key('purchase-down-toggle'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.purchaseDownPayment),
                    value: _hasDownPayment,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _hasDownPayment = v),
                  ),
                  if (_hasDownPayment) ...[
                    AppTextFormField(
                      key: const Key('purchase-down-amount'),
                      controller: _downController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: moneyInputFormatters(),
                      decoration: InputDecoration(
                        labelText: l10n.purchaseDownPayment,
                        suffixText: currency,
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        if (!_hasDownPayment) return null;
                        final e = Validators.positiveAmount(
                          v,
                          currencyCode: currency,
                        );
                        if (e != null) return validationMessage(context, e);
                        final parsed = Money.tryParse(
                          v!,
                          currencyCode: currency,
                        )!;
                        final priceNow = _minor(_priceController, currency);
                        if (priceNow != null && parsed.minor >= priceNow) {
                          return l10n.valDownPaymentTooLarge;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    AppTextFormField(
                      key: const Key('purchase-upfront-fees'),
                      controller: _upfrontFeesController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: moneyInputFormatters(),
                      decoration: InputDecoration(
                        labelText:
                            '${l10n.purchaseUpfrontFees} '
                            '(${l10n.commonOptional})',
                        helperText: l10n.purchaseUpfrontFeesHelp,
                        helperMaxLines: 3,
                        suffixText: currency,
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        final e = Validators.nonNegativeAmount(
                          v,
                          currencyCode: currency,
                        );
                        return e == null ? null : validationMessage(context, e);
                      },
                    ),
                    const SizedBox(height: 16),
                    AppSelectionField<String>(
                      key: ValueKey('purchase-down-account-$_downAccountId'),
                      initialValue:
                          assets.any((a) => a.accountId == _downAccountId)
                          ? _downAccountId
                          : null,
                      decoration: InputDecoration(
                        labelText: l10n.purchaseDownPaymentAccount,
                      ),
                      items: [
                        for (final account in assets)
                          DropdownMenuItem(
                            value: account.accountId,
                            child: ProtectedMoney(
                              interactive: false,
                              child: Text(
                                '${account.name} '
                                '(${account.balance.format()})',
                              ),
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _downAccountId = v),
                      validator: (v) => _hasDownPayment && v == null
                          ? validationMessage(context, ValidationError.required)
                          : null,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: l10n.purchaseFinancingSection,
              subtitle: l10n.purchaseFinancingSectionHelp,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSelectionField<PlanPricingMethod>(
                    key: ValueKey('purchase-mode-$_pricing'),
                    initialValue: _pricing,
                    decoration: InputDecoration(
                      labelText: l10n.purchaseFinancingMode,
                    ),
                    items: [
                      for (final method in PlanPricingMethod.values)
                        DropdownMenuItem(
                          value: method,
                          child: Text(planPricingMethodLabel(l10n, method)),
                        ),
                    ],
                    onChanged: (v) => setState(() {
                      _pricing = v ?? PlanPricingMethod.manualFees;
                    }),
                  ),
                  const SizedBox(height: 16),
                  switch (_pricing) {
                    PlanPricingMethod.manualFees => AppTextFormField(
                      key: const Key('purchase-fees'),
                      controller: _feesController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: moneyInputFormatters(),
                      decoration: InputDecoration(
                        labelText: l10n.purchaseFinancingFees,
                        helperText: l10n.purchaseFinancingFeesHelp,
                        helperMaxLines: 3,
                        suffixText: currency,
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        if (_pricing != PlanPricingMethod.manualFees) {
                          return null;
                        }
                        final e = Validators.nonNegativeAmount(
                          v,
                          currencyCode: currency,
                        );
                        return e == null ? null : validationMessage(context, e);
                      },
                    ),
                    PlanPricingMethod.totalPayable => AppTextFormField(
                      key: const Key('purchase-total'),
                      controller: _totalController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: moneyInputFormatters(),
                      decoration: InputDecoration(
                        labelText: l10n.purchaseTotalPayable,
                        helperText: l10n.purchaseTotalPayableHelp,
                        helperMaxLines: 3,
                        suffixText: currency,
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        if (_pricing != PlanPricingMethod.totalPayable) {
                          return null;
                        }
                        final e = Validators.positiveAmount(
                          v,
                          currencyCode: currency,
                        );
                        if (e != null) return validationMessage(context, e);
                        final parsed = Money.tryParse(
                          v!,
                          currencyCode: currency,
                        )!;
                        if (financed != null && parsed.minor < financed) {
                          return l10n.valTotalBelowFinanced;
                        }
                        return null;
                      },
                    ),
                    PlanPricingMethod.monthlyAmount => AppTextFormField(
                      key: const Key('purchase-monthly'),
                      controller: _monthlyController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: moneyInputFormatters(),
                      decoration: InputDecoration(
                        labelText: l10n.purchaseMonthlyAmount,
                        helperText: l10n.purchaseMonthlyAmountHelp,
                        helperMaxLines: 3,
                        suffixText: currency,
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        if (_pricing != PlanPricingMethod.monthlyAmount) {
                          return null;
                        }
                        final e = Validators.positiveAmount(
                          v,
                          currencyCode: currency,
                        );
                        return e == null ? null : validationMessage(context, e);
                      },
                    ),
                    PlanPricingMethod.interestRate => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppTextFormField(
                          key: const Key('purchase-rate'),
                          controller: _rateController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: moneyInputFormatters(),
                          decoration: InputDecoration(
                            labelText: _ratePeriod == InterestRatePeriod.monthly
                                ? l10n.purchaseMonthlyRate
                                : l10n.purchaseAnnualRate,
                            helperText: l10n.purchaseRateHelp,
                            helperMaxLines: 3,
                            suffixText: '%',
                          ),
                          onChanged: (_) => setState(() {}),
                          validator: (v) {
                            if (_pricing != PlanPricingMethod.interestRate) {
                              return null;
                            }
                            final e = Validators.nonNegativeAmount(
                              v,
                              currencyCode: currency,
                            );
                            if (e != null) {
                              return validationMessage(context, e);
                            }
                            return _rateBasisPoints > 100000
                                ? l10n.valInterestRate
                                : null;
                          },
                        ),
                        const SizedBox(height: 16),
                        AppSelectionField<InterestRatePeriod>(
                          key: ValueKey('purchase-rate-period-$_ratePeriod'),
                          initialValue: _ratePeriod,
                          decoration: InputDecoration(
                            labelText: l10n.purchaseRatePeriod,
                          ),
                          items: [
                            DropdownMenuItem(
                              value: InterestRatePeriod.monthly,
                              child: Text(l10n.purchaseRatePerMonth),
                            ),
                            DropdownMenuItem(
                              value: InterestRatePeriod.annual,
                              child: Text(l10n.purchaseRatePerYear),
                            ),
                          ],
                          onChanged: (v) => setState(() {
                            _ratePeriod = v ?? InterestRatePeriod.monthly;
                          }),
                        ),
                        const SizedBox(height: 16),
                        AppSelectionField<InterestMethod>(
                          key: ValueKey('purchase-rate-method-$_rateMethod'),
                          initialValue: _rateMethod,
                          decoration: InputDecoration(
                            labelText: l10n.purchaseInterestMethod,
                            helperText: l10n.purchaseInterestMethodHelp,
                            helperMaxLines: 3,
                          ),
                          items: [
                            DropdownMenuItem(
                              value: InterestMethod.flat,
                              child: Text(l10n.purchaseInterestFlat),
                            ),
                            DropdownMenuItem(
                              value: InterestMethod.reducing,
                              child: Text(l10n.purchaseInterestReducing),
                            ),
                          ],
                          onChanged: (v) => setState(() {
                            _rateMethod = v ?? InterestMethod.flat;
                          }),
                        ),
                      ],
                    ),
                    PlanPricingMethod.cardTenorDefault => Text(
                      l10n.purchaseCardTenorDefaultHint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  },
                  const SizedBox(height: 16),
                  AppTextFormField(
                    key: const Key('purchase-financed-fees'),
                    controller: _financedFeesController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: moneyInputFormatters(),
                    decoration: InputDecoration(
                      labelText:
                          '${l10n.purchaseFinancedFees} '
                          '(${l10n.commonOptional})',
                      helperText: l10n.purchaseFinancedFeesHelp,
                      helperMaxLines: 3,
                      suffixText: currency,
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      final e = Validators.nonNegativeAmount(
                        v,
                        currencyCode: currency,
                      );
                      return e == null ? null : validationMessage(context, e);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppTextFormField(
              key: const Key('purchase-count'),
              controller: _countController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.purchaseInstallmentCount,
                helperText: l10n.purchaseSingleCycleHint,
                helperMaxLines: 3,
              ),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final value = int.tryParse(v?.trim() ?? '');
                return value == null || value < 1 || value > 120
                    ? l10n.valInstallmentCount
                    : null;
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const FinanceSuitIcon(FinanceSuitIcons.eventAvailable),
              title: Text(l10n.purchaseFirstDueDate),
              subtitle: Text(
                (_firstDueOn ?? _defaultFirstDue(facility)).toIso(),
              ),
              trailing: const FinanceSuitIcon(FinanceSuitIcons.edit),
              onTap: _busy ? null : () => _pickDate(purchase: false),
            ),
            const SizedBox(height: 8),
            _SectionCard(
              title: l10n.purchaseImportSection,
              subtitle: l10n.purchaseImportSectionHelp,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    key: const Key('purchase-import-toggle'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.purchaseImportToggle),
                    value: _importRunning,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _importRunning = v),
                  ),
                  if (_importRunning) ...[
                    AppTextFormField(
                      key: const Key('purchase-paid-count'),
                      controller: _paidCountController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.purchasePaidCount,
                        helperText: l10n.purchasePaidCountHelp,
                        helperMaxLines: 3,
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        if (!_importRunning) return null;
                        final paid = int.tryParse(v?.trim() ?? '');
                        final total = int.tryParse(
                          _countController.text.trim(),
                        );
                        if (paid == null || paid < 0) {
                          return l10n.valPaidInstallments;
                        }
                        if (total != null && paid >= total) {
                          return l10n.valPaidInstallments;
                        }
                        return null;
                      },
                    ),
                  ],
                ],
              ),
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
            _PreviewCard(
              facility: facility,
              price: price,
              down: down,
              upfrontFees: upfrontFees,
              financed: financed,
              financing: financing,
              chargeMinor: chargeMinor,
              paidCount: paidCount,
              count: count,
              firstDueOn: _firstDueOn ?? _defaultFirstDue(facility),
              exceedsCredit: exceedsCredit,
            ),
            const SizedBox(height: 16),
            AuthErrorBanner(failure: _failure),
            AuthSubmitButton(
              label: l10n.commonSave,
              busy: _busy,
              onPressed: exceedsCredit || _categoryId == null
                  ? null
                  : () => _save(facility),
            ),
            if (_categoryId == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.valCategoryRequired,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A visually separated form section with a title and explainer.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(subtitle, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.facility,
    required this.price,
    required this.down,
    required this.upfrontFees,
    required this.financed,
    required this.financing,
    required this.chargeMinor,
    required this.paidCount,
    required this.count,
    required this.firstDueOn,
    required this.exceedsCredit,
  });

  final CreditFacilitySummary facility;
  final int? price;
  final int down;
  final int upfrontFees;
  final int? financed;
  final ({int interestMinor, int feesMinor, int totalMinor})? financing;
  final int? chargeMinor;
  final int paidCount;
  final int? count;
  final PlainDate firstDueOn;
  final bool exceedsCredit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final currency = facility.currencyCode;
    Money money(int minor) => Money(minor: minor, currencyCode: currency);
    final validCount = count != null && count! >= 1 && count! <= 120;
    final schedule =
        financing != null && financing!.totalMinor > 0 && validCount
        ? previewInstallmentSchedule(
            totalPayableMinor: financing!.totalMinor,
            installmentCount: count!,
            firstDueOn: firstDueOn,
          )
        : null;
    return Card(
      key: const Key('purchase-preview'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.purchasePreviewTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (price != null)
              _PreviewRow(label: l10n.purchasePrice, money: money(price!)),
            if (down > 0)
              _PreviewRow(label: l10n.purchaseDownPayment, money: money(down)),
            if (upfrontFees > 0)
              _PreviewRow(
                label: l10n.purchaseUpfrontFees,
                money: money(upfrontFees),
              ),
            if (financed != null && financed! > 0)
              _PreviewRow(
                label: l10n.purchaseFinancedPrincipal,
                money: money(financed!),
              ),
            if (financing != null) ...[
              if (financing!.interestMinor > 0)
                _PreviewRow(
                  label: l10n.purchaseInterest,
                  money: money(financing!.interestMinor),
                ),
              _PreviewRow(
                label: l10n.purchaseFinancingFees,
                money: money(financing!.feesMinor),
              ),
              _PreviewRow(
                label: l10n.purchaseTotalPayable,
                money: money(financing!.totalMinor),
              ),
              if (paidCount > 0 && chargeMinor != null) ...[
                _PreviewRow(
                  label: l10n.purchaseAlreadyPaidPortion(paidCount),
                  money: money(financing!.totalMinor - chargeMinor!),
                ),
                _PreviewRow(
                  label: l10n.purchaseRemainingCharge,
                  money: money(chargeMinor!),
                ),
              ],
            ],
            if (schedule != null) ...[
              const Divider(height: 24),
              Text(l10n.purchaseMonthly, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              for (final entry in schedule.take(24))
                _PreviewRow(
                  label:
                      '${entry.sequence} · ${entry.dueOn.toIso()}'
                      '${entry.sequence <= paidCount ? ' ✓' : ''}',
                  money: money(entry.amountMinor),
                ),
              if (schedule.length > 24)
                Text(
                  '…',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
            ],
            const Divider(height: 24),
            _PreviewRow(
              label: l10n.purchaseAvailableBefore,
              money: facility.availableCredit,
            ),
            if (chargeMinor != null)
              _PreviewRow(
                label: l10n.purchaseAvailableAfter,
                money: money(
                  (facility.availableCreditMinor - chargeMinor!).clamp(
                    -chargeMinor!,
                    facility.availableCreditMinor,
                  ),
                ),
              ),
            if (exceedsCredit) ...[
              const SizedBox(height: 8),
              Text(
                l10n.purchaseExceedsCredit,
                key: const Key('purchase-over-limit'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.money});

  final String label;
  final Money money;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ProtectedMoneyText(
            money.format(),
            style: theme.textTheme.bodyMedium,
            interactive: false,
          ),
        ],
      ),
    );
  }
}
