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
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/widgets/category_selector.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

enum _FinancingMode { fees, total }

/// Focused form for financing a purchase through a credit card or BNPL
/// facility: recognizes the expense once and schedules the monthly dues.
class InstallmentPurchaseScreen extends ConsumerStatefulWidget {
  const InstallmentPurchaseScreen({super.key, this.accountId});

  final String? accountId;

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
  final _countController = TextEditingController(text: '1');
  final _notesController = TextEditingController();

  /// Client-generated so a save retry cannot create a second plan.
  final String _planId = newClientUuid();

  String? _facilityId;
  String? _categoryId;
  String? _downAccountId;
  bool _hasDownPayment = false;
  _FinancingMode _mode = _FinancingMode.fees;
  PlainDate _purchasedOn = PlainDate.today();
  PlainDate? _firstDueOn;
  AppFailure? _failure;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _facilityId = widget.accountId;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _downController.dispose();
    _feesController.dispose();
    _totalController.dispose();
    _countController.dispose();
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

  Future<void> _save(CreditFacilitySummary facility) async {
    setState(() => _failure = null);
    if (!_formKey.currentState!.validate()) return;
    if (_busy) return;
    final currency = facility.currencyCode;
    final price = _minor(_priceController, currency)!;
    final down = _hasDownPayment ? (_minor(_downController, currency) ?? 0) : 0;
    final count = int.parse(_countController.text.trim());
    setState(() => _busy = true);
    final result = await ref
        .read(financeRepositoryProvider)
        .createInstallmentPlan(
          InstallmentPlanDraft(
            accountId: facility.accountId,
            title: _titleController.text.trim(),
            categoryId: _categoryId!,
            purchasedOn: _purchasedOn,
            purchasePriceMinor: price,
            installmentCount: count,
            firstDueOn: _firstDueOn ?? _defaultFirstDue(facility),
            downPaymentMinor: down,
            downPaymentAccountId: down > 0 ? _downAccountId : null,
            financingFeesMinor: _mode == _FinancingMode.fees
                ? (_minor(_feesController, currency) ?? 0)
                : null,
            totalPayableMinor: _mode == _FinancingMode.total
                ? _minor(_totalController, currency)
                : null,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
            planId: _planId,
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
      err: (failure) => setState(() => _failure = failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final facilitiesAsync = ref.watch(creditFacilitiesProvider);
    final title = l10n.purchaseTitle;
    return Scaffold(
      appBar: FinanceSuitAppBar.focused(semanticTitle: title),
      body: FinanceSuitFocusedBody(
        title: title,
        child: AsyncView<List<CreditFacilitySummary>>(
          value: facilitiesAsync,
          onRetry: () => ref.invalidate(creditFacilitiesProvider),
          data: (facilities) {
            if (facilities.isEmpty) {
              return EmptyStateView(
                icon: FinanceSuitIcons.creditCard,
                message: l10n.facilityEmptyTitle,
                actionLabel: l10n.facilityEmptyAction,
                onAction: () => context.push('/money/accounts/new'),
              );
            }
            final facility =
                facilities
                    .where((f) => f.accountId == _facilityId)
                    .firstOrNull ??
                facilities.first;
            _facilityId = facility.accountId;
            return _buildForm(context, l10n, facilities, facility);
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
    int? fees;
    int? total;
    if (financed != null && financed > 0) {
      if (_mode == _FinancingMode.fees) {
        fees = _minor(_feesController, currency) ?? 0;
        total = financed + fees;
      } else {
        total = _minor(_totalController, currency);
        if (total != null && total >= financed) {
          fees = total - financed;
        }
      }
    }
    final exceedsCredit =
        total != null && total > facility.availableCreditMinor;

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
              onChanged: (v) => setState(() {
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
            const SizedBox(height: 8),
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
                decoration: InputDecoration(
                  labelText: l10n.purchaseDownPayment,
                  suffixText: currency,
                ),
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  final e = Validators.positiveAmount(
                    v,
                    currencyCode: currency,
                  );
                  if (e != null) return validationMessage(context, e);
                  final parsed = Money.tryParse(v!, currencyCode: currency)!;
                  final priceNow = _minor(_priceController, currency);
                  if (priceNow != null && parsed.minor >= priceNow) {
                    return l10n.valDownPaymentTooLarge;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              AppSelectionField<String>(
                key: ValueKey('purchase-down-account-$_downAccountId'),
                initialValue: assets.any((a) => a.accountId == _downAccountId)
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
                          '${account.name} (${account.balance.format()})',
                        ),
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _downAccountId = v),
                validator: (v) => _hasDownPayment && v == null
                    ? validationMessage(context, ValidationError.required)
                    : null,
              ),
              const SizedBox(height: 8),
            ],
            AppSelectionField<_FinancingMode>(
              key: ValueKey('purchase-mode-$_mode'),
              initialValue: _mode,
              decoration: InputDecoration(
                labelText: l10n.purchaseFinancingMode,
              ),
              items: [
                DropdownMenuItem(
                  value: _FinancingMode.fees,
                  child: Text(l10n.purchaseFinancingModeFees),
                ),
                DropdownMenuItem(
                  value: _FinancingMode.total,
                  child: Text(l10n.purchaseFinancingModeTotal),
                ),
              ],
              onChanged: (v) => setState(() {
                _mode = v ?? _FinancingMode.fees;
              }),
            ),
            const SizedBox(height: 16),
            if (_mode == _FinancingMode.fees)
              AppTextFormField(
                key: const Key('purchase-fees'),
                controller: _feesController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: l10n.purchaseFinancingFees,
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
              )
            else
              AppTextFormField(
                key: const Key('purchase-total'),
                controller: _totalController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: l10n.purchaseTotalPayable,
                  suffixText: currency,
                ),
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  final e = Validators.positiveAmount(
                    v,
                    currencyCode: currency,
                  );
                  if (e != null) return validationMessage(context, e);
                  final parsed = Money.tryParse(v!, currencyCode: currency)!;
                  if (financed != null && parsed.minor < financed) {
                    return l10n.valTotalBelowFinanced;
                  }
                  return null;
                },
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
              financed: financed,
              fees: fees,
              total: total,
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

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.facility,
    required this.price,
    required this.down,
    required this.financed,
    required this.fees,
    required this.total,
    required this.count,
    required this.firstDueOn,
    required this.exceedsCredit,
  });

  final CreditFacilitySummary facility;
  final int? price;
  final int down;
  final int? financed;
  final int? fees;
  final int? total;
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
    final schedule = total != null && total! > 0 && validCount
        ? previewInstallmentSchedule(
            totalPayableMinor: total!,
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
            if (financed != null && financed! > 0)
              _PreviewRow(
                label: l10n.purchaseFinancedPrincipal,
                money: money(financed!),
              ),
            if (fees != null)
              _PreviewRow(
                label: l10n.purchaseFinancingFees,
                money: money(fees!),
              ),
            if (total != null)
              _PreviewRow(
                label: l10n.purchaseTotalPayable,
                money: money(total!),
              ),
            if (schedule != null) ...[
              const Divider(height: 24),
              Text(l10n.purchaseMonthly, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              for (final entry in schedule.take(24))
                _PreviewRow(
                  label: '${entry.sequence} · ${entry.dueOn.toIso()}',
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
            if (total != null)
              _PreviewRow(
                label: l10n.purchaseAvailableAfter,
                money: money(
                  (facility.availableCreditMinor - total!).clamp(
                    -total!,
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
