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
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Focused form for paying a credit card or BNPL facility from an asset
/// account. The payment books one transfer — never an expense — and the
/// server allocates it to the oldest unpaid dues first.
class FacilityPaymentScreen extends ConsumerStatefulWidget {
  const FacilityPaymentScreen({super.key, this.accountId});

  final String? accountId;

  @override
  ConsumerState<FacilityPaymentScreen> createState() =>
      _FacilityPaymentScreenState();
}

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

  @override
  void initState() {
    super.initState();
    _facilityId = widget.accountId;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidOn.toDateTime(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _paidOn = PlainDate.fromDateTime(picked));
  }

  void _setAmount(int minor) {
    _amountController.text = (minor / Money.minorUnitsPerMajor).toStringAsFixed(
      2,
    );
    setState(() {});
  }

  Future<void> _save(CreditFacilitySummary facility) async {
    setState(() => _failure = null);
    if (!_formKey.currentState!.validate()) return;
    if (_busy) return;
    final amount = Money.tryParse(
      _amountController.text,
      currencyCode: facility.currencyCode,
    )!;
    setState(() => _busy = true);
    final result = await ref
        .read(financeRepositoryProvider)
        .payCreditFacility(
          FacilityPaymentDraft(
            accountId: facility.accountId,
            sourceAccountId: _sourceAccountId!,
            amountMinor: amount.minor,
            paidOn: _paidOn,
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
      err: (failure) => setState(() => _failure = failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final facilitiesAsync = ref.watch(creditFacilitiesProvider);
    final title = l10n.paymentTitle;
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
            return _buildForm(context, l10n, payable, facility);
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
    final theme = Theme.of(context);
    final sources =
        (ref.watch(accountBalancesProvider).value ?? <AccountBalance>[])
            .assetAccounts
            .where((a) => a.currencyCode == currency)
            .toList();
    final dues =
        (ref.watch(installmentDuesProvider(facility.accountId)).value ??
                const <InstallmentDue>[])
            .where(
              (d) =>
                  d.planStatus == InstallmentPlanStatus.active &&
                  d.remainingMinor > 0,
            )
            .toList();
    final amountMinor = Money.tryParse(
      _amountController.text,
      currencyCode: currency,
    )?.minor;

    // Advisory preview of the server's oldest-first auto-allocation.
    final preview = <({InstallmentDue due, int amountMinor})>[];
    var left = amountMinor ?? 0;
    for (final due in dues) {
      if (left <= 0) break;
      final take = left < due.remainingMinor ? left : due.remainingMinor;
      preview.add((due: due, amountMinor: take));
      left -= take;
    }

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
              decoration: InputDecoration(
                labelText: l10n.commonAmount,
                suffixText: currency,
              ),
              onChanged: (_) => setState(() {}),
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
                if (facility.dueNowMinor > 0)
                  ActionChip(
                    key: const Key('payment-chip-due-now'),
                    label: Text(l10n.paymentDueNowChip),
                    onPressed: () => _setAmount(facility.dueNowMinor),
                  ),
                if (facility.nextDueAmountMinor != null &&
                    facility.nextDueAmountMinor! > 0)
                  ActionChip(
                    key: const Key('payment-chip-next'),
                    label: Text(l10n.paymentNextChip),
                    onPressed: () => _setAmount(facility.nextDueAmountMinor!),
                  ),
                ActionChip(
                  key: const Key('payment-chip-full'),
                  label: Text(l10n.paymentFullChip),
                  onPressed: () => _setAmount(facility.outstandingMinor),
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
            if (amountMinor != null && amountMinor > 0) ...[
              const SizedBox(height: 16),
              Card(
                key: const Key('payment-allocation-preview'),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.paymentAllocationPreview,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      for (final entry in preview.take(12))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${entry.due.planTitle} · '
                                  '${entry.due.dueOn.toIso()}',
                                  style: theme.textTheme.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              ProtectedMoneyText(
                                Money(
                                  minor: entry.amountMinor,
                                  currencyCode: currency,
                                ).format(),
                                style: theme.textTheme.bodyMedium,
                                interactive: false,
                              ),
                            ],
                          ),
                        ),
                      if (left > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: ProtectedMoneyText(
                            l10n.paymentUnallocatedNote(
                              Money(
                                minor: left,
                                currencyCode: currency,
                              ).format(),
                            ),
                            style: theme.textTheme.bodySmall,
                            interactive: false,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            AuthErrorBanner(failure: _failure),
            AuthSubmitButton(
              label: l10n.facilityMakePayment,
              busy: _busy,
              onPressed: () => _save(facility),
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
