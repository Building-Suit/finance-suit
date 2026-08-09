import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/app/theme/facility_palette.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/money/money_input.dart';
import 'package:work_tracker/core/result/result.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/app_selection_field.dart';
import 'package:work_tracker/core/widgets/app_text_form_field.dart';
import 'package:work_tracker/core/widgets/app_toast.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/core/widgets/domain_labels.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:work_tracker/features/commercial/data/commercial_repository.dart';
import 'package:work_tracker/features/commercial/presentation/widgets/pro_feature_gate.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/card_fee_rule.dart';
import 'package:work_tracker/features/finance/domain/card_research.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/widgets/ai_card_research_sheet.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Create (accountId == null) or edit an account.
///
/// Asset accounts keep the original fields. Selecting a Credit Card or
/// BNPL type swaps in the facility fields (credit limit, due day,
/// reminders, lifecycle) and saves through the atomic facility RPC. New
/// facilities always start at zero debt — there is no opening-owed input.
class AccountFormScreen extends ConsumerStatefulWidget {
  const AccountFormScreen({super.key, this.accountId});

  final String? accountId;

  @override
  ConsumerState<AccountFormScreen> createState() => _AccountFormScreenState();
}

/// Choices for how many days before a due date the reminder fires.
const _reminderLeadChoices = [0, 1, 2, 3, 5, 7, 10, 14];

class _AccountFormScreenState extends ConsumerState<AccountFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _balanceController = TextEditingController(text: '0');
  final _notesController = TextEditingController();
  final _creditLimitController = TextEditingController();
  final _dueDayController = TextEditingController(text: '1');
  final _statementDayController = TextEditingController();
  final _installmentDueDayController = TextEditingController();
  final _gracePeriodController = TextEditingController(text: '0');
  final _lastFourController = TextEditingController();
  final _minFixedController = TextEditingController();
  final _minPercentController = TextEditingController();
  final _fxMarkupController = TextEditingController();
  final _interestRateController = TextEditingController();

  AccountType _accountType = AccountType.current;
  bool _allowNegative = false;
  bool _hideFromHome = false;
  int _reminderLeadDays = 3;
  FacilityStatus _facilityStatus = FacilityStatus.active;
  MinPaymentMethod _minPaymentMethod = MinPaymentMethod.full;
  MinPaymentPercentageBasis _minPaymentPercentageBasis =
      MinPaymentPercentageBasis.statementTotal;
  bool _statementEndOfMonth = true;
  bool _minPaymentIncludeInstallments = false;
  bool _minPaymentIncludeBankFees = true;
  bool _minPaymentIncludeOverdue = false;
  CardRuleState _interestState = CardRuleState.unknown;
  CardInterestRatePeriod _interestRatePeriod = CardInterestRatePeriod.monthly;
  CardInterestAccrualMethod _interestAccrualMethod =
      CardInterestAccrualMethod.bankPostedManual;
  CardInterestStart _interestStarts = CardInterestStart.graceExpiry;
  PlainDate _interestEffectiveFrom = PlainDate.today();
  String? _interestCategoryId;
  String? _interestRuleId;
  bool _interestGraceApplies = true;
  bool _interestDirty = true;
  String? _colorHex;
  AppFailure? _failure;
  bool _busy = false;
  bool _loaded = false;
  Account? _existing;
  CreditFacilitySummary? _existingFacility;

  // --- AI autofill state (task: AI research -> autofill -> auto-create) ---
  AiAutofillPhase _aiPhase = AiAutofillPhase.idle;
  String? _aiRequestId;
  AccountType? _aiRequestAccountType;
  int _aiRequestCounter = 0;
  bool _autofillBatchInProgress = false;
  DateTime? _catalogVerifiedAt;
  final Map<String, FieldOrigin> _fieldOrigin = {};

  bool get _isEdit => widget.accountId != null;
  bool get _isLiability => _accountType.isLiability;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _loadExisting();
    } else {
      _loaded = true;
    }
  }

  Future<void> _loadExisting() async {
    final repo = ref.read(financeRepositoryProvider);
    final result = await repo.fetchAccount(widget.accountId!);
    if (!mounted) return;
    final account = result.valueOrNull;
    if (account == null) {
      setState(() {
        _failure = result.failureOrNull;
        _loaded = true;
      });
      return;
    }
    CreditFacilitySummary? facility;
    if (account.accountType.isLiability) {
      final facilities = await repo.fetchCreditFacilities(
        includeArchived: true,
      );
      if (!mounted) return;
      facility = facilities.valueOrNull
          ?.where((f) => f.accountId == account.id)
          .firstOrNull;
    }
    _existing = account;
    _existingFacility = facility;
    _nameController.text = account.name;
    _balanceController.text = formatMinorForInput(account.openingBalanceMinor);
    _notesController.text = account.notes ?? '';
    if (facility != null) {
      _creditLimitController.text = formatMinorForInput(
        facility.creditLimitMinor,
      );
      _dueDayController.text = '${facility.defaultDueDay}';
      _statementEndOfMonth = facility.statementDay == 31;
      _statementDayController.text =
          facility.statementDay == null || _statementEndOfMonth
          ? ''
          : '${facility.statementDay}';
      _installmentDueDayController.text = facility.installmentDueDay == null
          ? ''
          : '${facility.installmentDueDay}';
      _gracePeriodController.text = '${facility.gracePeriodDays}';
      _lastFourController.text = facility.lastFourDigits ?? '';
      _reminderLeadDays = facility.reminderLeadDays;
      _facilityStatus = facility.facilityStatus;
      _minPaymentMethod = facility.minPaymentMethod;
      _minPaymentPercentageBasis = facility.minPaymentPercentageBasis;
      _minPaymentIncludeInstallments =
          facility.minPaymentIncludeInstallmentDues;
      _minPaymentIncludeBankFees = facility.minPaymentIncludeBankFees;
      _minPaymentIncludeOverdue = facility.minPaymentIncludeOverdue;
      _colorHex = facility.colorHex;
      if (facility.minPaymentFixedMinor != null) {
        _minFixedController.text = formatMinorForInput(
          facility.minPaymentFixedMinor!,
        );
      }
      if (facility.minPaymentBasisPoints != null) {
        _minPercentController.text = (facility.minPaymentBasisPoints! / 100)
            .toStringAsFixed(2);
      }
      if (facility.fxMarkupBasisPoints != null) {
        _fxMarkupController.text = facility.fxMarkupPercent!.toStringAsFixed(2);
      }
      final rules = await repo.fetchFeeRules(facility.accountId);
      if (!mounted) return;
      final interestRule = rules.valueOrNull
          ?.where((rule) => rule.feeType == CardFeeType.purchaseInterest)
          .firstOrNull;
      if (interestRule != null) {
        _interestRuleId = interestRule.id;
        _interestCategoryId = interestRule.categoryId;
        _interestState = interestRule.state;
        _interestEffectiveFrom = interestRule.startsOn;
        if (interestRule.percentBasisPoints != null) {
          _interestRateController.text =
              (interestRule.percentBasisPoints! / 100).toStringAsFixed(2);
        }
      }
      _interestDirty = false;
    }
    setState(() {
      _accountType = account.accountType;
      _allowNegative = account.allowNegativeBalance;
      _hideFromHome = account.hideFromHome;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    _notesController.dispose();
    _creditLimitController.dispose();
    _dueDayController.dispose();
    _statementDayController.dispose();
    _installmentDueDayController.dispose();
    _gracePeriodController.dispose();
    _lastFourController.dispose();
    _minFixedController.dispose();
    _minPercentController.dispose();
    _fxMarkupController.dispose();
    _interestRateController.dispose();
    super.dispose();
  }

  bool get _minPaymentUsesFixed =>
      _minPaymentMethod == MinPaymentMethod.fixed ||
      _minPaymentMethod == MinPaymentMethod.greaterOf;

  bool get _minPaymentUsesPercent =>
      _minPaymentMethod == MinPaymentMethod.percent ||
      _minPaymentMethod == MinPaymentMethod.greaterOf;

  int? get _minPaymentBasisPoints {
    final value = double.tryParse(_minPercentController.text.trim());
    if (value == null) return null;
    final basisPoints = (value * 100).round();
    return basisPoints < 1 || basisPoints > 10000 ? null : basisPoints;
  }

  /// Optional: blank means no flat FX markup is configured. Unlike minimum
  /// payment, an invalid non-blank value is a validation error rather than
  /// a silent null, since the field being wrong should never save as "off".
  int? get _fxMarkupBasisPoints {
    final text = _fxMarkupController.text.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null) return null;
    final basisPoints = (value * 100).round();
    return basisPoints < 1 || basisPoints > 10000 ? null : basisPoints;
  }

  int? get _interestRateBasisPoints {
    final value = double.tryParse(_interestRateController.text.trim());
    if (value == null) return null;
    final basisPoints = (value * 100).round();
    return basisPoints < 1 || basisPoints > 10000 ? null : basisPoints;
  }

  String get _currencyCode {
    return _existing?.currencyCode ??
        ref.read(preferencesProvider).value?.currencyCode ??
        'EGP';
  }

  String? _optionalDayError(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final e = Validators.dayOfMonth(int.tryParse(text));
    return e == null ? null : validationMessage(context, e);
  }

  Future<void> _pickInterestEffectiveDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _interestEffectiveFrom.toDateTime(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _interestEffectiveFrom = PlainDate.fromDateTime(picked);
      _interestDirty = true;
    });
  }

  Future<void> _save() async {
    setState(() => _failure = null);
    if (!_formKey.currentState!.validate()) return;
    final notes = _notesController.text.trim();
    setState(() => _busy = true);
    final repo = ref.read(financeRepositoryProvider);
    final Result<void> result;
    if (_isLiability) {
      final limit = Money.tryParse(
        _creditLimitController.text,
        currencyCode: _currencyCode,
      )!;
      final statementDay = _statementDayController.text.trim();
      final lastFour = _lastFourController.text.trim();
      final facilityResult = await repo.saveCreditFacility(
        CreditFacilityDraft(
          name: _nameController.text.trim(),
          accountType: _accountType,
          currencyCode: _currencyCode,
          creditLimitMinor: limit.minor,
          defaultDueDay: int.parse(_dueDayController.text.trim()),
          statementDay: _accountType == AccountType.creditCard
              ? (_statementEndOfMonth
                    ? 31
                    : statementDay.isNotEmpty
                    ? int.parse(statementDay)
                    : null)
              : null,
          lastFourDigits:
              _accountType == AccountType.creditCard && lastFour.isNotEmpty
              ? lastFour
              : null,
          reminderLeadDays: _reminderLeadDays,
          notes: notes.isEmpty ? null : notes,
          accountId: widget.accountId,
          facilityStatus: _facilityStatus,
          minPaymentMethod: _accountType == AccountType.creditCard
              ? _minPaymentMethod
              : MinPaymentMethod.full,
          minPaymentFixedMinor:
              _accountType == AccountType.creditCard && _minPaymentUsesFixed
              ? Money.tryParse(
                  _minFixedController.text,
                  currencyCode: _currencyCode,
                )?.minor
              : null,
          minPaymentBasisPoints:
              _accountType == AccountType.creditCard && _minPaymentUsesPercent
              ? _minPaymentBasisPoints
              : null,
          colorHex: _colorHex,
          installmentDueDay:
              _accountType == AccountType.creditCard &&
                  _installmentDueDayController.text.trim().isNotEmpty
              ? int.parse(_installmentDueDayController.text.trim())
              : null,
          gracePeriodDays: _accountType == AccountType.creditCard
              ? int.parse(_gracePeriodController.text.trim())
              : 0,
          minPaymentPercentageBasis: _minPaymentPercentageBasis,
          minPaymentIncludeInstallmentDues:
              _accountType == AccountType.creditCard &&
              _minPaymentIncludeInstallments,
          minPaymentIncludeBankFees:
              _accountType != AccountType.creditCard ||
              _minPaymentIncludeBankFees,
          minPaymentIncludeOverdue:
              _accountType == AccountType.creditCard &&
              _minPaymentIncludeOverdue,
          fxMarkupBasisPoints: _accountType == AccountType.creditCard
              ? _fxMarkupBasisPoints
              : null,
        ),
      );
      // Home visibility rides along after the facility RPC, which owns
      // every other facility field.
      final accountId = facilityResult.valueOrNull;
      if (accountId == null) {
        result = Err(facilityResult.failureOrNull!);
      } else {
        var liabilityResult = await repo.setHideFromHome(
          accountId,
          hidden: _hideFromHome,
        );
        if (liabilityResult.isOk &&
            _accountType == AccountType.creditCard &&
            _interestDirty) {
          final categories =
              ref.read(categoriesProvider(CategoryKind.expense)).value ??
              const [];
          final categoryId = _interestCategoryId ?? categories.firstOrNull?.id;
          if (categoryId != null) {
            final interestResult = await repo.configurePurchaseInterest(
              PurchaseInterestRuleDraft(
                accountId: accountId,
                categoryId: categoryId,
                state: _interestState,
                effectiveFrom: _interestEffectiveFrom,
                rateBasisPoints: _interestState == CardRuleState.configured
                    ? _interestRateBasisPoints
                    : null,
                ratePeriod: _interestRatePeriod,
                accrualMethod: _interestAccrualMethod,
                interestStarts: _interestStarts,
                gracePeriodDays: int.parse(_gracePeriodController.text.trim()),
                graceApplies: _interestGraceApplies,
                notes: notes.isEmpty ? null : notes,
                ruleId: _interestRuleId,
              ),
            );
            liabilityResult = interestResult.when(
              ok: (_) => const Ok<void>(null),
              err: Err<void>.new,
            );
          }
        }
        result = liabilityResult;
      }
    } else {
      final opening = Money.tryParse(
        _balanceController.text,
        currencyCode: _currencyCode,
      )!;
      result = _isEdit
          ? await repo.updateAccount(
              id: widget.accountId!,
              name: _nameController.text.trim(),
              accountType: _accountType,
              openingBalanceMinor: opening.minor,
              allowNegativeBalance: _allowNegative,
              hideFromHome: _hideFromHome,
              notes: notes.isEmpty ? null : notes,
            )
          : await repo.createAccount(
              name: _nameController.text.trim(),
              accountType: _accountType,
              currencyCode: _currencyCode,
              openingBalanceMinor: opening.minor,
              allowNegativeBalance: _allowNegative,
              hideFromHome: _hideFromHome,
              notes: notes.isEmpty ? null : notes,
            );
    }
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      ok: (_) {
        invalidateFinanceData(ref);
        AppToast.success(context, AppLocalizations.of(context).setSaved);
        context.pop();
      },
      err: (failure) => setState(() => _failure = failure),
    );
  }

  // ---------------------------------------------------------------------
  // AI autofill: research -> map onto these same fields -> reuse _save().
  //
  // Event flow: researching -> (needsDisambiguation)? -> applyingAutofill
  // -> autofillApplied -> validating -> readyToAutoSubmit -> submitting.
  // readyToAutoSubmit is consumed exactly once per successful research
  // result; later manual edits never re-arm it (task spec section 54).
  // ---------------------------------------------------------------------

  String _nextAiRequestId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_aiRequestCounter++}';

  /// Marks a field as user-edited so a later AI run never silently
  /// overwrites it. No-ops while an autofill batch is writing the same
  /// controllers, since `TextEditingController` listeners fire for
  /// programmatic changes too.
  void _markFieldManual(String field) {
    if (_autofillBatchInProgress) return;
    _fieldOrigin[field] = FieldOrigin.manual;
  }

  Future<void> _openAiResearch() async {
    if (_aiPhase == AiAutofillPhase.researching) return;
    final input = await showAiCardResearchSheet(
      context,
      accountType: _accountType,
      currencyCode: _currencyCode,
    );
    if (input == null || !mounted) return;
    await _runAiResearch(input);
  }

  Future<void> _runAiResearch(
    AiCardResearchSheetInput input, {
    String? selectedProductId,
    List<CatalogResearchMatch> catalogMatches = const [],
    bool skipCatalog = false,
  }) async {
    final requestId = _nextAiRequestId();
    final requestAccountType = _accountType;
    setState(() {
      _aiRequestId = requestId;
      _aiRequestAccountType = requestAccountType;
      _aiPhase = AiAutofillPhase.researching;
      _catalogVerifiedAt = null;
    });

    final repo = ref.read(financeRepositoryProvider);
    final result = await repo.researchCardProduct(
      CardResearchRequest(
        requestId: requestId,
        accountType: requestAccountType,
        issuerName: input.issuerName,
        countryCode: input.countryCode,
        productName: input.productName,
        officialWebsite: input.officialWebsite,
        tier: input.tier,
        network: input.network,
        currencyCode: input.currencyCode,
        activationDate: input.activationDate,
        knownCreditLimitMinor: input.knownCreditLimitMinor,
        knownStatementDay: input.knownStatementDay,
        knownDueDay: input.knownDueDay,
        bnplTypicalTenorMonths: input.bnplTypicalTenorMonths,
        userNotes: input.userNotes,
        selectedProductId: selectedProductId,
        catalogMatches: catalogMatches,
        skipCatalog: skipCatalog,
      ),
    );

    // Stale-response guard: the form may have closed, started a new
    // request, or switched account type while this one was in flight.
    if (!mounted ||
        _aiRequestId != requestId ||
        _aiRequestAccountType != _accountType) {
      return;
    }

    final l10n = AppLocalizations.of(context);
    final research = result.valueOrNull;
    if (research == null) {
      setState(() => _aiPhase = AiAutofillPhase.failed);
      AppToast.error(context, l10n.aiResearchUnableToFind);
      return;
    }

    switch (research.status) {
      case ResearchStatus.resolved:
        setState(() => _catalogVerifiedAt = research.catalogVerifiedAt);
        _applyAutofill(research);
      case ResearchStatus.ambiguous:
        setState(() => _aiPhase = AiAutofillPhase.needsDisambiguation);
        final chosenId = await showProductDisambiguationDialog(
          context,
          research.candidates,
        );
        if (!mounted || _aiRequestId != requestId) return;
        if (chosenId == null) {
          setState(() => _aiPhase = AiAutofillPhase.idle);
          return;
        }
        await _runAiResearch(
          input,
          selectedProductId: chosenId,
          catalogMatches: research.catalogMatches,
          skipCatalog: research.origin != CardResearchOrigin.catalog,
        );
      case ResearchStatus.insufficientInformation:
      case ResearchStatus.error:
        setState(() => _aiPhase = AiAutofillPhase.failed);
        AppToast.error(context, l10n.aiResearchUnableToFind);
    }
  }

  /// Applies eligible researched fields onto the real form controllers as
  /// one batch (task spec section 25-26): manually-edited fields are never
  /// overwritten, and only verified/user-provided values are eligible —
  /// probable/conflicting/unknown values are left exactly as they were.
  void _applyAutofill(CardResearchResult result) {
    setState(() {
      _autofillBatchInProgress = true;
      _aiPhase = AiAutofillPhase.applyingAutofill;

      if (_fieldOrigin['name'] != FieldOrigin.manual &&
          _nameController.text.trim().isEmpty &&
          result.suggestedName.isAutofillEligible) {
        _nameController.text = result.suggestedName.value!;
        _fieldOrigin['name'] = FieldOrigin.ai;
      }
      if (_fieldOrigin['creditLimit'] != FieldOrigin.manual &&
          result.creditLimitMinor.isAutofillEligible) {
        _creditLimitController.text = formatMinorForInput(
          result.creditLimitMinor.value!,
        );
        _fieldOrigin['creditLimit'] = FieldOrigin.ai;
      }
      if (_fieldOrigin['dueDay'] != FieldOrigin.manual &&
          result.defaultDueDay.isAutofillEligible) {
        _dueDayController.text = '${result.defaultDueDay.value}';
        _fieldOrigin['dueDay'] = FieldOrigin.ai;
      }
      if (_accountType == AccountType.creditCard) {
        if (_fieldOrigin['statementDay'] != FieldOrigin.manual &&
            result.statementDay.isAutofillEligible) {
          _statementEndOfMonth = result.statementDay.value == 31;
          _statementDayController.text = _statementEndOfMonth
              ? ''
              : '${result.statementDay.value}';
          _fieldOrigin['statementDay'] = FieldOrigin.ai;
        }
        if (_fieldOrigin['minPaymentMethod'] != FieldOrigin.manual &&
            result.minPaymentMethod.isAutofillEligible) {
          _minPaymentMethod = result.minPaymentMethod.value!;
          _fieldOrigin['minPaymentMethod'] = FieldOrigin.ai;
        }
        if (_fieldOrigin['minPaymentFixed'] != FieldOrigin.manual &&
            _minPaymentUsesFixed &&
            result.minPaymentFixedMinor.isAutofillEligible) {
          _minFixedController.text = formatMinorForInput(
            result.minPaymentFixedMinor.value!,
          );
          _fieldOrigin['minPaymentFixed'] = FieldOrigin.ai;
        }
        if (_fieldOrigin['minPaymentPercent'] != FieldOrigin.manual &&
            _minPaymentUsesPercent &&
            result.minPaymentBasisPoints.isAutofillEligible) {
          _minPercentController.text =
              (result.minPaymentBasisPoints.value! / 100).toStringAsFixed(2);
          _fieldOrigin['minPaymentPercent'] = FieldOrigin.ai;
        }
      }

      _autofillBatchInProgress = false;
      _aiPhase = AiAutofillPhase.autofillApplied;
    });

    _afterAutofillApplied();
  }

  /// Runs the exact existing form validation after the batch settles, then
  /// either arms the one-shot auto-submit or leaves the user on the
  /// (partially filled) form with the normal validation errors visible.
  void _afterAutofillApplied() {
    setState(() => _aiPhase = AiAutofillPhase.validating);
    final requestId = _aiRequestId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _aiRequestId != requestId) return;
      final valid = _formKey.currentState?.validate() ?? false;
      if (!valid) {
        setState(() => _aiPhase = AiAutofillPhase.incomplete);
        AppToast.warning(
          context,
          AppLocalizations.of(context).aiResearchIncompleteMessage,
        );
        return;
      }
      setState(() => _aiPhase = AiAutofillPhase.readyToAutoSubmit);
      _autoSubmitOnce();
    });
  }

  /// Invokes the exact same `_save()` the manual Create button uses — no
  /// duplicated submit logic and no simulated tap (task spec section 27-28).
  Future<void> _autoSubmitOnce() async {
    if (_aiPhase != AiAutofillPhase.readyToAutoSubmit || _busy) return;
    setState(() => _aiPhase = AiAutofillPhase.submitting);
    await _save();
    if (!mounted) return;
    if (_failure != null) {
      setState(() => _aiPhase = AiAutofillPhase.failed);
    }
  }

  Future<void> _setArchived(bool archived) async {
    setState(() {
      _failure = null;
      _busy = true;
    });
    final result = await ref
        .read(financeRepositoryProvider)
        .setArchived(widget.accountId!, archived: archived);
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      ok: (_) {
        invalidateFinanceData(ref);
        AppToast.success(context, AppLocalizations.of(context).setSaved);
        context.pop();
      },
      err: (failure) => setState(() => _failure = failure),
    );
  }

  Future<void> _deleteFacility() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.facilityDeleteConfirmTitle),
        content: Text(l10n.facilityDeleteConfirmBody),
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
    setState(() {
      _failure = null;
      _busy = true;
    });
    final result = await ref
        .read(financeRepositoryProvider)
        .deleteCreditFacility(widget.accountId!);
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      ok: (_) {
        invalidateFinanceData(ref);
        AppToast.success(context, AppLocalizations.of(context).setSaved);
        context.pop();
      },
      err: (failure) => setState(() => _failure = failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final expenseCategories =
        ref.watch(categoriesProvider(CategoryKind.expense)).value ?? const [];
    final selectedInterestCategoryId =
        expenseCategories.any((category) => category.id == _interestCategoryId)
        ? _interestCategoryId
        : expenseCategories.firstOrNull?.id;
    return Scaffold(
      appBar: FinanceSuitAppBar.focused(
        semanticTitle: _isEdit ? l10n.moneyEditAccount : l10n.moneyNewAccount,
      ),
      body: FinanceSuitFocusedBody(
        title: _isEdit ? l10n.moneyEditAccount : l10n.moneyNewAccount,
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : _existing == null && _isEdit
            ? ErrorRetryView(
                failure: _failure ?? const NotFoundFailure(),
                onRetry: _loadExisting,
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppTextFormField(
                        key: const Key('account-name'),
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(labelText: l10n.accName),
                        onChanged: (_) => _markFieldManual('name'),
                        validator: (v) {
                          final e = Validators.requiredText(v, maxLength: 80);
                          return e == null
                              ? null
                              : validationMessage(context, e);
                        },
                      ),
                      const SizedBox(height: 16),
                      AppSelectionField<AccountType>(
                        key: ValueKey('account-type-$_accountType'),
                        initialValue: _accountType,
                        decoration: InputDecoration(labelText: l10n.accType),
                        items: [
                          for (final type in AccountType.values)
                            DropdownMenuItem(
                              value: type,
                              child: Text(accountTypeLabel(l10n, type)),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _accountType = v);
                        },
                      ),
                      if (!_isLiability) ...[
                        const SizedBox(height: 16),
                        AppTextFormField(
                          controller: _balanceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: moneyInputFormatters(),
                          decoration: InputDecoration(
                            labelText: l10n.accOpeningBalance,
                            suffixText: _currencyCode,
                          ),
                          validator: (v) {
                            final e = Validators.nonNegativeAmount(
                              v,
                              currencyCode: _currencyCode,
                            );
                            return e == null
                                ? null
                                : validationMessage(context, e);
                          },
                        ),
                      ],
                      if (_isLiability) ...[
                        if (!_isEdit) ...[
                          const SizedBox(height: 16),
                          _AiAutofillEntryPoint(
                            phase: _aiPhase,
                            catalogVerifiedAt: _catalogVerifiedAt,
                            onPressed: _openAiResearch,
                          ),
                        ],
                        const SizedBox(height: 16),
                        AppTextFormField(
                          key: const Key('facility-credit-limit'),
                          controller: _creditLimitController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: moneyInputFormatters(),
                          decoration: InputDecoration(
                            labelText: l10n.facilityCreditLimit,
                            suffixText: _currencyCode,
                          ),
                          onChanged: (_) => _markFieldManual('creditLimit'),
                          validator: (v) {
                            final e = Validators.positiveAmount(
                              v,
                              currencyCode: _currencyCode,
                            );
                            return e == null
                                ? null
                                : validationMessage(context, e);
                          },
                        ),
                        const SizedBox(height: 16),
                        AppTextFormField(
                          key: const Key('facility-due-day'),
                          controller: _dueDayController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: _accountType == AccountType.creditCard
                                ? l10n.cardPaymentDueDay
                                : l10n.facilityDefaultDueDay,
                          ),
                          onChanged: (_) => _markFieldManual('dueDay'),
                          validator: (v) {
                            final e = Validators.dayOfMonth(
                              int.tryParse(v?.trim() ?? ''),
                            );
                            return e == null
                                ? null
                                : validationMessage(context, e);
                          },
                        ),
                        const SizedBox(height: 16),
                        _ColorPicker(
                          selected: _colorHex,
                          onChanged: (value) =>
                              setState(() => _colorHex = value),
                        ),
                        if (_accountType == AccountType.creditCard) ...[
                          const SizedBox(height: 16),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              l10n.cardStatementCloses,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SegmentedButton<bool>(
                            key: const Key('facility-statement-close-mode'),
                            segments: [
                              ButtonSegment(
                                value: false,
                                label: Text(l10n.cardStatementExactDay),
                              ),
                              ButtonSegment(
                                value: true,
                                label: Text(l10n.cardStatementEndOfMonth),
                              ),
                            ],
                            selected: {_statementEndOfMonth},
                            onSelectionChanged: (selection) => setState(() {
                              _statementEndOfMonth = selection.single;
                              _markFieldManual('statementDay');
                            }),
                          ),
                          if (!_statementEndOfMonth) ...[
                            const SizedBox(height: 12),
                            AppTextFormField(
                              key: const Key('facility-statement-day'),
                              controller: _statementDayController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: l10n.facilityStatementDay,
                              ),
                              onChanged: (_) =>
                                  _markFieldManual('statementDay'),
                              validator: (value) {
                                if ((value ?? '').trim().isEmpty) {
                                  return l10n.valRequired;
                                }
                                return _optionalDayError(value);
                              },
                            ),
                          ],
                          const SizedBox(height: 16),
                          AppTextFormField(
                            key: const Key('facility-installment-due-day'),
                            controller: _installmentDueDayController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: l10n.cardInstallmentDueDay,
                            ),
                            validator: _optionalDayError,
                          ),
                          const SizedBox(height: 16),
                          AppTextFormField(
                            key: const Key('facility-grace-period-days'),
                            controller: _gracePeriodController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: l10n.cardGracePeriodDays,
                            ),
                            validator: (value) {
                              final days = int.tryParse(value?.trim() ?? '');
                              return days == null || days < 0 || days > 90
                                  ? l10n.valGracePeriodDays
                                  : null;
                            },
                          ),
                          const SizedBox(height: 16),
                          AppTextFormField(
                            key: const Key('facility-last-four'),
                            controller: _lastFourController,
                            keyboardType: TextInputType.number,
                            maxLength: 4,
                            decoration: InputDecoration(
                              labelText:
                                  '${l10n.facilityLastFour} '
                                  '(${l10n.commonOptional})',
                              counterText: '',
                            ),
                            validator: (v) {
                              final text = v?.trim() ?? '';
                              if (text.isEmpty) return null;
                              return RegExp(r'^[0-9]{4}$').hasMatch(text)
                                  ? null
                                  : l10n.valFacilityLastFour;
                            },
                          ),
                          const SizedBox(height: 16),
                          AppSelectionField<MinPaymentMethod>(
                            key: ValueKey(
                              'facility-min-method-$_minPaymentMethod',
                            ),
                            initialValue: _minPaymentMethod,
                            decoration: InputDecoration(
                              labelText: l10n.minPaymentLabel,
                              helperText: l10n.minPaymentHelp,
                              helperMaxLines: 3,
                            ),
                            items: [
                              for (final method in MinPaymentMethod.values)
                                DropdownMenuItem(
                                  value: method,
                                  child: Text(
                                    minPaymentMethodLabel(l10n, method),
                                  ),
                                ),
                            ],
                            onChanged: (v) => setState(() {
                              _minPaymentMethod = v ?? MinPaymentMethod.full;
                              _markFieldManual('minPaymentMethod');
                            }),
                          ),
                          if (_minPaymentUsesFixed) ...[
                            const SizedBox(height: 16),
                            AppTextFormField(
                              key: const Key('facility-min-fixed'),
                              controller: _minFixedController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: moneyInputFormatters(),
                              decoration: InputDecoration(
                                labelText: l10n.minPaymentFixedAmount,
                                suffixText: _currencyCode,
                              ),
                              onChanged: (_) =>
                                  _markFieldManual('minPaymentFixed'),
                              validator: (v) {
                                final e = Validators.positiveAmount(
                                  v,
                                  currencyCode: _currencyCode,
                                );
                                return e == null
                                    ? null
                                    : validationMessage(context, e);
                              },
                            ),
                          ],
                          if (_minPaymentUsesPercent) ...[
                            const SizedBox(height: 16),
                            AppTextFormField(
                              key: const Key('facility-min-percent'),
                              controller: _minPercentController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: l10n.minPaymentPercentAmount,
                                suffixText: '%',
                              ),
                              onChanged: (_) =>
                                  _markFieldManual('minPaymentPercent'),
                              validator: (v) => _minPaymentBasisPoints == null
                                  ? l10n.valMinPaymentPercent
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            AppSelectionField<MinPaymentPercentageBasis>(
                              key: ValueKey(
                                'facility-min-basis-'
                                '$_minPaymentPercentageBasis',
                              ),
                              initialValue: _minPaymentPercentageBasis,
                              decoration: InputDecoration(
                                labelText: l10n.minPaymentPercentageBasis,
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: MinPaymentPercentageBasis
                                      .revolvingNoninstallment,
                                  child: Text(l10n.minPaymentBasisRevolving),
                                ),
                                DropdownMenuItem(
                                  value:
                                      MinPaymentPercentageBasis.statementTotal,
                                  child: Text(l10n.minPaymentBasisStatement),
                                ),
                              ],
                              onChanged: (value) => setState(() {
                                _minPaymentPercentageBasis =
                                    value ??
                                    MinPaymentPercentageBasis.statementTotal;
                              }),
                            ),
                          ],
                          SwitchListTile.adaptive(
                            key: const Key('facility-min-include-installments'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.minPaymentIncludeInstallments),
                            value: _minPaymentIncludeInstallments,
                            onChanged: (value) => setState(
                              () => _minPaymentIncludeInstallments = value,
                            ),
                          ),
                          SwitchListTile.adaptive(
                            key: const Key('facility-min-include-bank-fees'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.minPaymentIncludeBankFees),
                            value: _minPaymentIncludeBankFees,
                            onChanged: (value) => setState(
                              () => _minPaymentIncludeBankFees = value,
                            ),
                          ),
                          SwitchListTile.adaptive(
                            key: const Key('facility-min-include-overdue'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.minPaymentIncludeOverdue),
                            value: _minPaymentIncludeOverdue,
                            onChanged: (value) => setState(
                              () => _minPaymentIncludeOverdue = value,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n.purchaseInterestTitle,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          AppSelectionField<CardRuleState>(
                            key: ValueKey(
                              'facility-interest-state-$_interestState',
                            ),
                            initialValue: _interestState,
                            decoration: InputDecoration(
                              labelText: l10n.purchaseInterestState,
                              helperText: l10n.purchaseInterestStateHelp,
                              helperMaxLines: 3,
                            ),
                            items: [
                              for (final state in CardRuleState.values)
                                DropdownMenuItem(
                                  value: state,
                                  child: Text(cardRuleStateLabel(l10n, state)),
                                ),
                            ],
                            onChanged: (value) => setState(() {
                              _interestState = value ?? CardRuleState.unknown;
                              _interestDirty = true;
                            }),
                          ),
                          if (_interestState == CardRuleState.configured) ...[
                            const SizedBox(height: 16),
                            AppTextFormField(
                              key: const Key('facility-interest-rate'),
                              controller: _interestRateController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: l10n.purchaseInterestRate,
                                suffixText: '%',
                              ),
                              onChanged: (_) => _interestDirty = true,
                              validator: (_) => _interestRateBasisPoints == null
                                  ? l10n.valPurchaseInterestRate
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            AppSelectionField<CardInterestRatePeriod>(
                              key: ValueKey(
                                'facility-interest-period-'
                                '$_interestRatePeriod',
                              ),
                              initialValue: _interestRatePeriod,
                              decoration: InputDecoration(
                                labelText: l10n.purchaseInterestRatePeriod,
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: CardInterestRatePeriod.monthly,
                                  child: Text(
                                    l10n.purchaseInterestPeriodMonthly,
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: CardInterestRatePeriod.annual,
                                  child: Text(
                                    l10n.purchaseInterestPeriodAnnual,
                                  ),
                                ),
                              ],
                              onChanged: (value) => setState(() {
                                _interestRatePeriod =
                                    value ?? CardInterestRatePeriod.monthly;
                                _interestDirty = true;
                              }),
                            ),
                          ],
                          const SizedBox(height: 16),
                          AppSelectionField<CardInterestAccrualMethod>(
                            key: ValueKey(
                              'facility-interest-accrual-'
                              '$_interestAccrualMethod',
                            ),
                            initialValue: _interestAccrualMethod,
                            decoration: InputDecoration(
                              labelText: l10n.purchaseInterestAccrual,
                            ),
                            items: [
                              DropdownMenuItem(
                                value:
                                    CardInterestAccrualMethod.bankPostedManual,
                                child: Text(l10n.purchaseInterestAccrualManual),
                              ),
                              DropdownMenuItem(
                                value: CardInterestAccrualMethod.dailyAccrual,
                                child: Text(l10n.purchaseInterestAccrualDaily),
                              ),
                            ],
                            onChanged: (value) => setState(() {
                              _interestAccrualMethod =
                                  value ??
                                  CardInterestAccrualMethod.bankPostedManual;
                              _interestDirty = true;
                            }),
                          ),
                          const SizedBox(height: 16),
                          AppSelectionField<CardInterestStart>(
                            key: ValueKey(
                              'facility-interest-start-$_interestStarts',
                            ),
                            initialValue: _interestStarts,
                            decoration: InputDecoration(
                              labelText: l10n.purchaseInterestStarts,
                            ),
                            items: [
                              DropdownMenuItem(
                                value: CardInterestStart.purchaseDate,
                                child: Text(
                                  l10n.purchaseInterestStartTransaction,
                                ),
                              ),
                              DropdownMenuItem(
                                value: CardInterestStart.statementClose,
                                child: Text(
                                  l10n.purchaseInterestStartStatement,
                                ),
                              ),
                              DropdownMenuItem(
                                value: CardInterestStart.paymentDue,
                                child: Text(
                                  l10n.purchaseInterestStartPaymentDue,
                                ),
                              ),
                              DropdownMenuItem(
                                value: CardInterestStart.graceExpiry,
                                child: Text(
                                  l10n.purchaseInterestStartGraceExpiry,
                                ),
                              ),
                            ],
                            onChanged: (value) => setState(() {
                              _interestStarts =
                                  value ?? CardInterestStart.graceExpiry;
                              _interestDirty = true;
                            }),
                          ),
                          SwitchListTile.adaptive(
                            key: const Key('facility-interest-grace-applies'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.purchaseInterestGraceApplies),
                            value: _interestGraceApplies,
                            onChanged: (value) => setState(() {
                              _interestGraceApplies = value;
                              _interestDirty = true;
                            }),
                          ),
                          ListTile(
                            key: const Key('facility-interest-effective-date'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.purchaseInterestEffectiveFrom),
                            subtitle: Text(_interestEffectiveFrom.toIso()),
                            trailing: const Icon(Icons.calendar_today_outlined),
                            onTap: _pickInterestEffectiveDate,
                          ),
                          const SizedBox(height: 8),
                          AppSelectionField<String>(
                            key: ValueKey(
                              'facility-interest-category-'
                              '$selectedInterestCategoryId',
                            ),
                            initialValue: selectedInterestCategoryId,
                            decoration: InputDecoration(
                              labelText: l10n.purchaseInterestCategory,
                            ),
                            validator: (value) =>
                                expenseCategories.isNotEmpty && value == null
                                ? l10n.valPurchaseInterestCategory
                                : null,
                            items: [
                              for (final category in expenseCategories)
                                DropdownMenuItem(
                                  value: category.id,
                                  child: Text(
                                    category.displayName(expenseCategories),
                                  ),
                                ),
                            ],
                            onChanged: (value) => setState(() {
                              _interestCategoryId = value;
                              _interestDirty = true;
                            }),
                          ),
                          const SizedBox(height: 16),
                          AppTextFormField(
                            key: const Key('facility-fx-markup'),
                            controller: _fxMarkupController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText:
                                  '${l10n.fxMarkupLabel} '
                                  '(${l10n.commonOptional})',
                              helperText: l10n.fxMarkupHelp,
                              helperMaxLines: 3,
                              suffixText: '%',
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return null;
                              return _fxMarkupBasisPoints == null
                                  ? l10n.valFxMarkupPercent
                                  : null;
                            },
                          ),
                        ],
                        const SizedBox(height: 16),
                        AppSelectionField<int>(
                          key: ValueKey(
                            'facility-reminder-days-$_reminderLeadDays',
                          ),
                          initialValue:
                              _reminderLeadChoices.contains(_reminderLeadDays)
                              ? _reminderLeadDays
                              : 3,
                          decoration: InputDecoration(
                            labelText: l10n.facilityReminderDays,
                            helperText: l10n.facilityReminderDaysHelp,
                            helperMaxLines: 3,
                          ),
                          items: [
                            for (final days in _reminderLeadChoices)
                              DropdownMenuItem(
                                value: days,
                                child: Text(
                                  days == 0
                                      ? l10n.facilityReminderOnDueDay
                                      : l10n.facilityReminderDaysBefore(days),
                                ),
                              ),
                          ],
                          onChanged: (v) =>
                              setState(() => _reminderLeadDays = v ?? 3),
                        ),
                        if (_isEdit && _existingFacility != null) ...[
                          const SizedBox(height: 16),
                          AppSelectionField<FacilityStatus>(
                            key: ValueKey('facility-status-$_facilityStatus'),
                            initialValue: _facilityStatus,
                            decoration: InputDecoration(
                              labelText: l10n.facilityStatusLabel,
                              helperText: l10n.facilityStatusHelp,
                              helperMaxLines: 3,
                            ),
                            items: [
                              for (final status in FacilityStatus.values)
                                DropdownMenuItem(
                                  value: status,
                                  child: Text(
                                    facilityStatusLabel(l10n, status),
                                  ),
                                ),
                            ],
                            onChanged: (v) => setState(
                              () =>
                                  _facilityStatus = v ?? FacilityStatus.active,
                            ),
                          ),
                        ],
                      ] else ...[
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.accAllowNegative),
                          value: _allowNegative,
                          onChanged: (v) => setState(() => _allowNegative = v),
                        ),
                      ],
                      SwitchListTile(
                        key: const Key('account-hide-from-home'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.accHideFromHome),
                        subtitle: Text(l10n.accHideFromHomeHelp),
                        value: _hideFromHome,
                        onChanged: (v) => setState(() => _hideFromHome = v),
                      ),
                      const SizedBox(height: 8),
                      AppTextFormField(
                        controller: _notesController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText:
                              '${l10n.commonNotes} (${l10n.commonOptional})',
                        ),
                        validator: (v) {
                          final e = Validators.optionalText(v);
                          return e == null
                              ? null
                              : validationMessage(context, e);
                        },
                      ),
                      if (_isEdit && _isLiability) ...[
                        const SizedBox(height: 24),
                        Text(
                          l10n.facilityLifecycleTitle,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.facilityLifecycleBody,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          key: const Key('facility-archive'),
                          onPressed: _busy
                              ? null
                              : () => _setArchived(!(_existing!.isArchived)),
                          icon: const Icon(Icons.archive_outlined),
                          label: Text(
                            _existing?.isArchived == true
                                ? l10n.facilityUnarchiveAction
                                : l10n.facilityArchiveAction,
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          key: const Key('facility-delete'),
                          onPressed: _busy ? null : _deleteFacility,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.error,
                          ),
                          icon: const Icon(Icons.delete_outline),
                          label: Text(l10n.facilityDeleteAction),
                        ),
                      ],
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

/// Picks the colour of a physical card. A fixed swatch set rather than a
/// free colour wheel: each option is dark enough for white text, so the card
/// tiles stay readable whatever the user chooses.
class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.accColorLabel, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _Swatch(
              key: const Key('facility-color-default'),
              color: theme.colorScheme.surfaceContainerHighest,
              semanticLabel: l10n.accColorDefault,
              selected: selected == null,
              checkColor: theme.colorScheme.onSurface,
              onTap: () => onChanged(null),
            ),
            for (final (index, color) in FacilitySwatches.values.indexed)
              _Swatch(
                key: Key('facility-color-${FacilitySwatches.hexOf(color)}'),
                color: color,
                semanticLabel: l10n.accColorSwatch(index + 1),
                selected:
                    selected?.toUpperCase() == FacilitySwatches.hexOf(color),
                checkColor: FacilitySwatches.foregroundOn(color),
                onTap: () => onChanged(FacilitySwatches.hexOf(color)),
              ),
          ],
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    super.key,
    required this.color,
    required this.semanticLabel,
    required this.selected,
    required this.checkColor,
    required this.onTap,
  });

  final Color color;
  final String semanticLabel;
  final bool selected;
  final Color checkColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: selected
              ? Icon(Icons.check, size: 20, color: checkColor)
              : null,
        ),
      ),
    );
  }
}

/// The "Let AI help do it" secondary action (task spec section 2): opens
/// the identification sheet and shows a small deterministic status line
/// while research/autofill is in flight. Manual fields stay fully usable
/// the whole time — this never disables the rest of the form.
class _AiAutofillEntryPoint extends StatelessWidget {
  const _AiAutofillEntryPoint({
    required this.phase,
    required this.catalogVerifiedAt,
    required this.onPressed,
  });

  final AiAutofillPhase phase;
  final DateTime? catalogVerifiedAt;
  final VoidCallback onPressed;

  bool get _busy =>
      phase == AiAutofillPhase.researching ||
      phase == AiAutofillPhase.applyingAutofill ||
      phase == AiAutofillPhase.validating ||
      phase == AiAutofillPhase.needsDisambiguation;

  String? _statusText(AppLocalizations l10n) => switch (phase) {
    AiAutofillPhase.researching => l10n.aiResearchStatusFinding,
    AiAutofillPhase.applyingAutofill ||
    AiAutofillPhase.validating => l10n.aiResearchStatusFilling,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = _statusText(l10n);
    return ProFeatureGate(
      featureKey: CommercialFeatureKeys.aiCardResearch,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              key: const Key('ai-autofill-button'),
              onPressed: _busy ? null : onPressed,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: Text(l10n.aiAutofillButtonLabel),
            ),
            const SizedBox(height: 8),
            Text(l10n.aiAutofillHelperText, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              l10n.aiAutofillCautionText,
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
            if (catalogVerifiedAt != null) ...[
              const SizedBox(height: 8),
              Row(
                key: const Key('catalog-verified-indicator'),
                children: [
                  Icon(
                    Icons.verified_outlined,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.aiResearchCatalogVerifiedOn(
                        MaterialLocalizations.of(
                          context,
                        ).formatMediumDate(catalogVerifiedAt!.toLocal()),
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
            if (status != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(status, key: const Key('ai-autofill-status')),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
