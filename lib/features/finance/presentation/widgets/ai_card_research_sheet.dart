import 'package:flutter/material.dart';
import 'package:work_tracker/core/domain/countries.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/money/money_input.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/app_selection_field.dart';
import 'package:work_tracker/core/widgets/app_text_form_field.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/finance/domain/card_research.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Structured, non-chat identification data collected before AI research
/// starts (task spec section 3-8). Only product-identifying fields — never
/// PAN/CVV/PIN/OTP, and notes are sanitized server-side before use.
class AiCardResearchSheetInput {
  const AiCardResearchSheetInput({
    required this.issuerName,
    required this.countryCode,
    required this.productName,
    this.officialWebsite,
    this.tier,
    this.network,
    this.currencyCode,
    this.activationDate,
    this.knownCreditLimitMinor,
    this.knownStatementDay,
    this.knownDueDay,
    this.bnplTypicalTenorMonths,
    this.userNotes,
  });

  final String issuerName;
  final String countryCode;
  final String productName;
  final String? officialWebsite;
  final String? tier;
  final CardNetworkGuess? network;
  final String? currencyCode;
  final String? activationDate;
  final int? knownCreditLimitMinor;
  final int? knownStatementDay;
  final int? knownDueDay;
  final int? bnplTypicalTenorMonths;
  final String? userNotes;
}

/// Opens the "Let AI help do it" identification sheet. Returns null if the
/// user cancels without submitting.
Future<AiCardResearchSheetInput?> showAiCardResearchSheet(
  BuildContext context, {
  required AccountType accountType,
  required String currencyCode,
}) {
  return showModalBottomSheet<AiCardResearchSheetInput>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => _AiCardResearchSheet(
      accountType: accountType,
      formCurrencyCode: currencyCode,
    ),
  );
}

/// A plain (non-chat) disambiguation control (task spec section 45): shown
/// when research finds more than one concrete product match. Returns the
/// chosen candidate's id, or null if the user backs out.
Future<String?> showProductDisambiguationDialog(
  BuildContext context,
  List<ProductCandidate> candidates,
) {
  final l10n = AppLocalizations.of(context);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.aiResearchDisambiguationTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          key: const Key('ai-research-disambiguation-list'),
          shrinkWrap: true,
          itemCount: candidates.length,
          itemBuilder: (context, index) {
            final candidate = candidates[index];
            return ListTile(
              key: Key('ai-research-candidate-${candidate.id}'),
              title: Text(candidate.label),
              onTap: () => Navigator.of(dialogContext).pop(candidate.id),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.commonCancel),
        ),
      ],
    ),
  );
}

class _AiCardResearchSheet extends StatefulWidget {
  const _AiCardResearchSheet({
    required this.accountType,
    required this.formCurrencyCode,
  });

  final AccountType accountType;
  final String formCurrencyCode;

  @override
  State<_AiCardResearchSheet> createState() => _AiCardResearchSheetState();
}

class _AiCardResearchSheetState extends State<_AiCardResearchSheet> {
  final _formKey = GlobalKey<FormState>();
  final _issuerController = TextEditingController();
  final _websiteController = TextEditingController();
  final _productController = TextEditingController();
  final _tierController = TextEditingController();
  final _currencyController = TextEditingController();
  final _activationDateController = TextEditingController();
  final _creditLimitController = TextEditingController();
  final _statementDayController = TextEditingController();
  final _dueDayController = TextEditingController();
  final _tenorController = TextEditingController();
  final _notesController = TextEditingController();

  String? _countryCode;
  CardNetworkGuess? _network;

  bool get _isCreditCard => widget.accountType == AccountType.creditCard;

  @override
  void dispose() {
    _issuerController.dispose();
    _websiteController.dispose();
    _productController.dispose();
    _tierController.dispose();
    _currencyController.dispose();
    _activationDateController.dispose();
    _creditLimitController.dispose();
    _statementDayController.dispose();
    _dueDayController.dispose();
    _tenorController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String? _optionalDayError(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final e = Validators.dayOfMonth(int.tryParse(text));
    return e == null ? null : validationMessage(context, e);
  }

  String? _optionalIsoDateError(AppLocalizations l10n, String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)
        ? null
        : l10n.aiResearchInvalidDate;
  }

  String? _optionalCurrencyError(AppLocalizations l10n, String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    return RegExp(r'^[A-Za-z]{3}$').hasMatch(text)
        ? null
        : l10n.aiResearchInvalidCurrency;
  }

  String? _optionalUrlError(AppLocalizations l10n, String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    final valid =
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
    return valid ? null : l10n.aiResearchInvalidWebsite;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final creditLimit = _creditLimitController.text.trim().isEmpty
        ? null
        : Money.tryParse(
            _creditLimitController.text,
            currencyCode: widget.formCurrencyCode,
          )?.minor;
    Navigator.of(context).pop(
      AiCardResearchSheetInput(
        issuerName: _issuerController.text.trim(),
        countryCode: _countryCode!,
        productName: _productController.text.trim(),
        officialWebsite: _websiteController.text.trim().isEmpty
            ? null
            : _websiteController.text.trim(),
        tier: _tierController.text.trim().isEmpty
            ? null
            : _tierController.text.trim(),
        network: _isCreditCard ? _network : null,
        currencyCode: _currencyController.text.trim().isEmpty
            ? null
            : _currencyController.text.trim().toUpperCase(),
        activationDate:
            _isCreditCard && _activationDateController.text.trim().isNotEmpty
            ? _activationDateController.text.trim()
            : null,
        knownCreditLimitMinor: creditLimit,
        knownStatementDay: _isCreditCard
            ? int.tryParse(_statementDayController.text.trim())
            : null,
        knownDueDay: int.tryParse(_dueDayController.text.trim()),
        bnplTypicalTenorMonths: !_isCreditCard
            ? int.tryParse(_tenorController.text.trim())
            : null,
        userNotes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _isCreditCard
                        ? l10n.aiResearchSheetTitleCard
                        : l10n.aiResearchSheetTitleBnpl,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.aiAutofillHelperText,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  AppTextFormField(
                    key: const Key('ai-research-issuer'),
                    controller: _issuerController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: l10n.aiResearchIssuer,
                      hintText: l10n.aiResearchIssuerHint,
                    ),
                    validator: (v) {
                      final e = Validators.requiredText(v, maxLength: 120);
                      return e == null ? null : validationMessage(context, e);
                    },
                  ),
                  const SizedBox(height: 16),
                  AppSelectionField<String>(
                    key: const Key('ai-research-country'),
                    initialValue: _countryCode,
                    decoration: InputDecoration(
                      labelText: l10n.aiResearchCountry,
                    ),
                    sheetTitle: l10n.aiResearchCountry,
                    items: [
                      for (final country in kCountries)
                        DropdownMenuItem(
                          value: country.code,
                          child: Text('${country.name} (${country.code})'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _countryCode = v),
                    validator: (v) =>
                        v == null ? l10n.aiResearchCountryRequired : null,
                  ),
                  const SizedBox(height: 16),
                  AppTextFormField(
                    key: const Key('ai-research-website'),
                    controller: _websiteController,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText:
                          '${l10n.aiResearchWebsite} (${l10n.commonOptional})',
                    ),
                    validator: (v) => _optionalUrlError(l10n, v),
                  ),
                  const SizedBox(height: 16),
                  AppTextFormField(
                    key: const Key('ai-research-product'),
                    controller: _productController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: _isCreditCard
                          ? l10n.aiResearchProductCard
                          : l10n.aiResearchProductBnpl,
                    ),
                    validator: (v) {
                      final e = Validators.requiredText(v, maxLength: 120);
                      return e == null ? null : validationMessage(context, e);
                    },
                  ),
                  const SizedBox(height: 16),
                  AppTextFormField(
                    key: const Key('ai-research-tier'),
                    controller: _tierController,
                    decoration: InputDecoration(
                      labelText:
                          '${l10n.aiResearchTier} (${l10n.commonOptional})',
                    ),
                    validator: (v) {
                      final e = Validators.optionalText(v, maxLength: 80);
                      return e == null ? null : validationMessage(context, e);
                    },
                  ),
                  if (_isCreditCard) ...[
                    const SizedBox(height: 16),
                    AppSelectionField<CardNetworkGuess>(
                      key: const Key('ai-research-network'),
                      initialValue: _network,
                      decoration: InputDecoration(
                        labelText:
                            '${l10n.aiResearchNetwork} (${l10n.commonOptional})',
                      ),
                      sheetTitle: l10n.aiResearchNetwork,
                      items: [
                        DropdownMenuItem(
                          value: CardNetworkGuess.visa,
                          child: const Text('Visa'),
                        ),
                        DropdownMenuItem(
                          value: CardNetworkGuess.mastercard,
                          child: const Text('Mastercard'),
                        ),
                        DropdownMenuItem(
                          value: CardNetworkGuess.other,
                          child: Text(l10n.aiResearchNetworkOther),
                        ),
                        DropdownMenuItem(
                          value: CardNetworkGuess.unknown,
                          child: Text(l10n.aiResearchNetworkUnknown),
                        ),
                      ],
                      onChanged: (v) => setState(() => _network = v),
                    ),
                  ],
                  const SizedBox(height: 16),
                  AppTextFormField(
                    key: const Key('ai-research-currency'),
                    controller: _currencyController,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 3,
                    decoration: InputDecoration(
                      labelText:
                          '${l10n.aiResearchCurrency} (${l10n.commonOptional})',
                      hintText: widget.formCurrencyCode,
                      counterText: '',
                    ),
                    validator: (v) => _optionalCurrencyError(l10n, v),
                  ),
                  if (_isCreditCard) ...[
                    const SizedBox(height: 16),
                    AppTextFormField(
                      key: const Key('ai-research-activation-date'),
                      controller: _activationDateController,
                      decoration: InputDecoration(
                        labelText:
                            '${l10n.aiResearchActivationDate} (${l10n.commonOptional})',
                        hintText: 'YYYY-MM-DD',
                      ),
                      validator: (v) => _optionalIsoDateError(l10n, v),
                    ),
                  ],
                  const SizedBox(height: 16),
                  AppTextFormField(
                    key: const Key('ai-research-credit-limit'),
                    controller: _creditLimitController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: moneyInputFormatters(),
                    decoration: InputDecoration(
                      labelText:
                          '${_isCreditCard ? l10n.aiResearchCreditLimit : l10n.aiResearchFinanceLimit} (${l10n.commonOptional})',
                      suffixText: widget.formCurrencyCode,
                    ),
                  ),
                  if (_isCreditCard) ...[
                    const SizedBox(height: 16),
                    AppTextFormField(
                      key: const Key('ai-research-statement-day'),
                      controller: _statementDayController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText:
                            '${l10n.aiResearchStatementDay} (${l10n.commonOptional})',
                      ),
                      validator: _optionalDayError,
                    ),
                  ],
                  const SizedBox(height: 16),
                  AppTextFormField(
                    key: const Key('ai-research-due-day'),
                    controller: _dueDayController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText:
                          '${l10n.aiResearchDueDay} (${l10n.commonOptional})',
                    ),
                    validator: _optionalDayError,
                  ),
                  if (!_isCreditCard) ...[
                    const SizedBox(height: 16),
                    AppTextFormField(
                      key: const Key('ai-research-tenor'),
                      controller: _tenorController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText:
                            '${l10n.aiResearchTenor} (${l10n.commonOptional})',
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  AppTextFormField(
                    key: const Key('ai-research-notes'),
                    controller: _notesController,
                    maxLines: 4,
                    maxLength: 2000,
                    decoration: InputDecoration(
                      labelText: l10n.aiResearchNotes,
                      helperText: l10n.aiResearchNotesHelp,
                      helperMaxLines: 4,
                    ),
                    validator: (v) {
                      final e = Validators.optionalText(v, maxLength: 2000);
                      return e == null ? null : validationMessage(context, e);
                    },
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      l10n.aiResearchSensitiveWarning,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const Key('ai-research-submit'),
                    onPressed: _submit,
                    child: Text(
                      _isCreditCard
                          ? l10n.aiResearchSubmitCard
                          : l10n.aiResearchSubmitBnpl,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
