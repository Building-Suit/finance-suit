import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
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
import 'package:work_tracker/core/widgets/domain_labels.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/core/widgets/protected_money.dart';
import 'package:work_tracker/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';
import 'package:work_tracker/features/finance/domain/money_destination.dart';
import 'package:work_tracker/features/finance/domain/recurring_rule.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/widgets/category_selector.dart';
import 'package:work_tracker/features/finance/presentation/widgets/destination_selection_field.dart';
import 'package:work_tracker/features/network/domain/network_models.dart';
import 'package:work_tracker/features/network/presentation/providers/network_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Choices for how many days ahead a pending occurrence appears.
const _promptChoices = [0, 1, 2, 3, 5, 7];

/// Create or edit a recurring expense or transfer rule.
class RecurringRuleFormScreen extends ConsumerStatefulWidget {
  const RecurringRuleFormScreen({
    super.key,
    this.existing,
    this.showAppBar = true,
  });

  final RecurringRule? existing;
  final bool showAppBar;

  @override
  ConsumerState<RecurringRuleFormScreen> createState() =>
      _RecurringRuleFormScreenState();
}

class _RecurringRuleFormScreenState
    extends ConsumerState<RecurringRuleFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  late final TextEditingController _notesController;

  /// Client-generated so a save retry cannot create a second rule.
  late final String _ruleId = widget.existing?.id ?? newClientUuid();

  late RecurringRuleKind _kind;
  late RecurringFrequency _frequency;
  late int _paymentDay;
  late int _weekday;
  late PlainDate _startDate;
  late int _promptDays;
  late bool _isActive;
  late bool _isForeignCurrency;
  String? _sourceAccountId;
  MoneyDestination? _destination;
  String? _categoryId;
  AppFailure? _failure;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _amountController = TextEditingController(
      text: existing == null ? '' : formatMinorForInput(existing.amountMinor),
    );
    _notesController = TextEditingController(text: existing?.notes ?? '');
    _kind = existing?.kind ?? RecurringRuleKind.expense;
    _frequency = existing?.frequency ?? RecurringFrequency.monthly;
    final isWeekly = existing?.frequency == RecurringFrequency.weekly;
    _paymentDay = isWeekly ? 1 : (existing?.paymentDay ?? 1);
    _weekday = isWeekly ? existing!.paymentDay : 1;
    _startDate = existing?.startDate ?? PlainDate.today();
    _promptDays = existing?.promptDaysBefore ?? 3;
    _isActive = existing?.isActive ?? true;
    _isForeignCurrency = existing?.isForeignCurrency ?? false;
    _sourceAccountId = existing?.sourceAccountId;
    _destination = switch ((
      existing?.destinationAccountId,
      existing?.destinationNetworkConnectionId,
    )) {
      (final String accountId, _) => OwnAccountDestination(accountId),
      (_, final String connectionId) => NetworkContactDestination(connectionId),
      _ => null,
    };
    _categoryId = existing?.categoryId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _weekdayName(int isoWeekday) {
    // 2024-01-01 is a Monday; DateFormat handles the locale.
    final date = DateTime(2024, 1, isoWeekday);
    return DateFormat.EEEE(
      Localizations.localeOf(context).toString(),
    ).format(date);
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate.toDateTime(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _startDate = PlainDate.fromDateTime(picked));
  }

  Future<void> _save(String currency) async {
    setState(() => _failure = null);
    if (!_formKey.currentState!.validate()) return;
    if (_sourceAccountId == null) return;
    if (_kind == RecurringRuleKind.expense && _categoryId == null) return;
    final destination = _destination;
    if (_kind == RecurringRuleKind.transfer && destination == null) {
      return;
    }
    final amount = Money.tryParse(
      _amountController.text,
      currencyCode: currency,
    )!;
    final notes = _notesController.text.trim();
    setState(() => _busy = true);
    final result = await ref
        .read(financeRepositoryProvider)
        .saveRecurringRule(
          name: _nameController.text.trim(),
          kind: _kind,
          amountMinor: amount.minor,
          frequency: _frequency,
          paymentDay: _frequency == RecurringFrequency.weekly
              ? _weekday
              : _paymentDay,
          startDate: _startDate,
          promptDaysBefore: _promptDays,
          sourceAccountId: _sourceAccountId!,
          destinationAccountId:
              _kind == RecurringRuleKind.transfer &&
                  destination is OwnAccountDestination
              ? destination.accountId
              : null,
          destinationNetworkConnectionId:
              _kind == RecurringRuleKind.transfer &&
                  destination is NetworkContactDestination
              ? destination.connectionId
              : null,
          categoryId: _kind == RecurringRuleKind.expense ? _categoryId : null,
          notes: notes.isEmpty ? null : notes,
          ruleId: _ruleId,
          isActive: _isActive,
          isForeignCurrency: _isForeignCurrency,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      ok: (_) {
        invalidateRecurringAutomation(ref);
        AppToast.success(context, AppLocalizations.of(context).setSaved);
        context.pop();
      },
      err: (failure) => setState(() => _failure = failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = _isEdit ? l10n.recurringEditRule : l10n.recurringAddRule;
    final accounts =
        ref.watch(accountBalancesProvider).value ?? <AccountBalance>[];
    final facilities =
        ref.watch(creditFacilitiesProvider).value ?? <CreditFacilitySummary>[];
    final assets = accounts.assetAccounts;
    final categories =
        ref.watch(categoriesProvider(CategoryKind.expense)).value ?? const [];

    // Expenses can come from cash or an active credit card with a
    // statement day (charges need a cycle to land on); transfers move cash.
    final cards = facilities
        .where((f) => f.canFundPurchases && f.statementDay != null)
        .toList();
    final sourceIsCard = cards.any((c) => c.accountId == _sourceAccountId);
    final currency =
        assets
            .where((a) => a.accountId == _sourceAccountId)
            .map((a) => a.currencyCode)
            .firstOrNull ??
        cards
            .where((c) => c.accountId == _sourceAccountId)
            .map((c) => c.currencyCode)
            .firstOrNull ??
        widget.existing?.currencyCode ??
        assets.firstOrNull?.currencyCode ??
        'EGP';
    final destinations = assets
        .where(
          (a) => a.accountId != _sourceAccountId && a.currencyCode == currency,
        )
        .toList();
    // Connected people can receive recurring transfers; the pending network
    // transfer created on approval carries the source account's currency.
    final contacts = _kind == RecurringRuleKind.transfer
        ? (ref.watch(networkContactsProvider).value ?? const [])
        : const <NetworkContact>[];

    return Scaffold(
      appBar: widget.showAppBar
          ? FinanceSuitAppBar.focused(semanticTitle: title)
          : null,
      body: FinanceSuitFocusedBody(
        title: title,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSelectionField<RecurringRuleKind>(
                  key: ValueKey('recurring-kind-$_kind'),
                  initialValue: _kind,
                  decoration: InputDecoration(
                    labelText: l10n.recurringKindLabel,
                  ),
                  items: [
                    for (final kind in RecurringRuleKind.values)
                      DropdownMenuItem(
                        value: kind,
                        child: Text(recurringRuleKindLabel(l10n, kind)),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _kind = v ?? RecurringRuleKind.expense;
                    _sourceAccountId = null;
                    _destination = null;
                  }),
                ),
                const SizedBox(height: 16),
                AppTextFormField(
                  key: const Key('recurring-name'),
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: l10n.recurringNameLabel,
                  ),
                  validator: (v) {
                    final e = Validators.requiredText(v, maxLength: 80);
                    return e == null ? null : validationMessage(context, e);
                  },
                ),
                const SizedBox(height: 16),
                AppTextFormField(
                  key: const Key('recurring-amount'),
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: moneyInputFormatters(),
                  decoration: InputDecoration(
                    labelText: l10n.recurringAmountLabel,
                    suffixText: currency,
                  ),
                  validator: (v) {
                    final e = Validators.positiveAmount(
                      v,
                      currencyCode: currency,
                    );
                    return e == null ? null : validationMessage(context, e);
                  },
                ),
                const SizedBox(height: 16),
                AppSelectionField<String>(
                  key: ValueKey('recurring-source-$_sourceAccountId-$_kind'),
                  initialValue: _sourceAccountId,
                  decoration: InputDecoration(
                    labelText: _kind == RecurringRuleKind.expense
                        ? l10n.recurringPayFrom
                        : l10n.txFromAccount,
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
                    if (_kind == RecurringRuleKind.expense)
                      for (final card in cards)
                        DropdownMenuItem(
                          value: card.accountId,
                          child: ProtectedMoney(
                            interactive: false,
                            child: Text(
                              '${card.name} '
                              '(${card.availableCredit.format()})',
                            ),
                          ),
                        ),
                  ],
                  onChanged: (v) => setState(() {
                    _sourceAccountId = v;
                    _destination = null;
                  }),
                  validator: (v) => v == null
                      ? validationMessage(context, ValidationError.required)
                      : null,
                ),
                if (_kind == RecurringRuleKind.transfer) ...[
                  const SizedBox(height: 16),
                  DestinationSelectionField(
                    key: ValueKey('recurring-destination-$_destination'),
                    initialValue: switch (_destination) {
                      OwnAccountDestination(:final accountId)
                          when !destinations.any(
                            (a) => a.accountId == accountId,
                          ) =>
                        null,
                      NetworkContactDestination(:final connectionId)
                          when !contacts.any(
                            (c) => c.connectionId == connectionId,
                          ) =>
                        null,
                      final value => value,
                    },
                    decoration: InputDecoration(labelText: l10n.txToAccount),
                    accounts: destinations,
                    contacts: contacts,
                    onChanged: (v) => setState(() => _destination = v),
                    validator: (v) => v == null || v is DestinationPickerHeader
                        ? validationMessage(context, ValidationError.required)
                        : null,
                  ),
                  if (_destination is NetworkContactDestination)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        l10n.networkLedgerDisclaimer,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ] else ...[
                  const SizedBox(height: 8),
                  CategorySelector(
                    categories: categories,
                    selectedCategoryId: _categoryId,
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                  if (sourceIsCard)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        l10n.recurringCardSourceHint,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (sourceIsCard) ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      key: const Key('recurring-is-foreign-currency'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.txIsForeignCurrency),
                      subtitle: Text(l10n.txIsForeignCurrencyHelp),
                      value: _isForeignCurrency,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _isForeignCurrency = v),
                    ),
                  ],
                ],
                const SizedBox(height: 16),
                AppSelectionField<RecurringFrequency>(
                  key: ValueKey('recurring-frequency-$_frequency'),
                  initialValue: _frequency,
                  decoration: InputDecoration(
                    labelText: l10n.recurringFrequencyLabel,
                  ),
                  items: [
                    for (final frequency in RecurringFrequency.values)
                      DropdownMenuItem(
                        value: frequency,
                        child: Text(recurringFrequencyLabel(l10n, frequency)),
                      ),
                  ],
                  onChanged: (v) => setState(
                    () => _frequency = v ?? RecurringFrequency.monthly,
                  ),
                ),
                const SizedBox(height: 16),
                if (_frequency == RecurringFrequency.weekly)
                  AppSelectionField<int>(
                    key: ValueKey('recurring-weekday-$_weekday'),
                    initialValue: _weekday,
                    decoration: InputDecoration(
                      labelText: l10n.recurringWeekdayLabel,
                    ),
                    items: [
                      for (var day = 1; day <= 7; day++)
                        DropdownMenuItem(
                          value: day,
                          child: Text(_weekdayName(day)),
                        ),
                    ],
                    onChanged: (v) => setState(() => _weekday = v ?? 1),
                  )
                else
                  AppSelectionField<int>(
                    key: ValueKey('recurring-day-$_paymentDay'),
                    initialValue: _paymentDay,
                    decoration: InputDecoration(
                      labelText: l10n.recurringDayOfMonthLabel,
                      helperText: l10n.recurringDayOfMonthHelp,
                      helperMaxLines: 2,
                    ),
                    items: [
                      for (var day = 1; day <= 28; day++)
                        DropdownMenuItem(value: day, child: Text('$day')),
                    ],
                    onChanged: (v) => setState(() => _paymentDay = v ?? 1),
                  ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const FinanceSuitIcon(
                    FinanceSuitIcons.calendarToday,
                  ),
                  title: Text(l10n.incomeStartDate),
                  subtitle: Text(_startDate.toIso()),
                  trailing: const FinanceSuitIcon(FinanceSuitIcons.edit),
                  onTap: _busy ? null : _pickStartDate,
                ),
                const SizedBox(height: 8),
                AppSelectionField<int>(
                  key: ValueKey('recurring-prompt-$_promptDays'),
                  initialValue: _promptChoices.contains(_promptDays)
                      ? _promptDays
                      : 3,
                  decoration: InputDecoration(
                    labelText: l10n.incomePromptBefore,
                  ),
                  items: [
                    for (final days in _promptChoices)
                      DropdownMenuItem(
                        value: days,
                        child: Text(
                          days == 0
                              ? l10n.facilityReminderOnDueDay
                              : l10n.facilityReminderDaysBefore(days),
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _promptDays = v ?? 3),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  key: const Key('recurring-active'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.incomeAutomationEnabled),
                  value: _isActive,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _isActive = v),
                ),
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
                AuthErrorBanner(failure: _failure),
                AuthSubmitButton(
                  label: l10n.commonSave,
                  busy: _busy,
                  onPressed: () => _save(currency),
                ),
                if (_kind == RecurringRuleKind.expense && _categoryId == null)
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
        ),
      ),
    );
  }
}
