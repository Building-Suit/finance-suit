import 'package:flutter/widgets.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Maps a typed failure to a localized, user-safe message.
String failureMessage(BuildContext context, AppFailure failure) {
  final l10n = AppLocalizations.of(context);
  return switch (failure) {
    AuthFailure(:final kind) => switch (kind) {
      AuthFailureKind.invalidCredentials => l10n.errInvalidCredentials,
      AuthFailureKind.emailNotConfirmed => l10n.errEmailNotConfirmed,
      AuthFailureKind.duplicateEmail => l10n.errDuplicateEmail,
      AuthFailureKind.weakPassword => l10n.errWeakPassword,
      AuthFailureKind.expiredLink => l10n.errExpiredLink,
      AuthFailureKind.usedLink => l10n.errExpiredLink,
      AuthFailureKind.rateLimited => l10n.errRateLimited,
      AuthFailureKind.sessionMissing => l10n.errSessionExpired,
      AuthFailureKind.unknown => l10n.errAuthGeneric,
    },
    AuthorizationFailure() => l10n.errNotAuthorized,
    ValidationFailure(:final message) => _dbValidationMessage(l10n, message),
    NetworkFailure() => l10n.commonOffline,
    TimeoutFailure() => l10n.errTimeout,
    ConstraintFailure() => l10n.errConstraint,
    NotFoundFailure() => l10n.errNotFound,
    RealtimeFailure() => l10n.errRealtime,
    ConfigurationFailure() => l10n.commonError,
    UnknownFailure() => l10n.commonError,
  };
}

/// Database functions raise coded messages like `insufficient_funds: ...`.
String _dbValidationMessage(AppLocalizations l10n, String raw) {
  final code = raw.split(':').first.trim();
  return switch (code) {
    'insufficient_funds' => l10n.errInsufficientFunds,
    'currency_mismatch' => l10n.errCurrencyMismatch,
    'invalid_transfer' => l10n.errSameAccounts,
    'invalid_account' => l10n.errAccountUnavailable,
    'account_archived' => l10n.errAccountUnavailable,
    'already_paid' => l10n.errAlreadyPaid,
    'not_finalized' => l10n.errNotFinalized,
    'invalid_amount' => l10n.errInvalidAmount,
    'macro_not_reversible' => l10n.errMacroNotReversible,
    'macro_empty' => l10n.errMacroEmpty,
    'not_found' => l10n.errNotFound,
    'account_deletion_failed' => l10n.deleteAccountFailure,
    'active_subcategories_exist' => l10n.catArchiveChildrenFirst,
    'parent_category_archived' => l10n.catRestoreParentFirst,
    'insufficient_credit' => l10n.purchaseExceedsCredit,
    'credit_limit_below_outstanding' => l10n.errCreditLimitBelowOutstanding,
    'facility_archive_blocked' => l10n.errFacilityArchiveBlocked,
    'facility_not_configured' => l10n.errFacilityNotConfigured,
    'overpayment_rejected' => l10n.valPaymentAboveOutstanding,
    'plan_has_payments' => l10n.errPlanHasPayments,
    'plan_locked' => l10n.errFacilityLocked,
    'facility_transaction_locked' => l10n.errFacilityLocked,
    'facility_rows_locked' => l10n.errFacilityLocked,
    'account_role_locked' => l10n.errAccountRoleLocked,
    'already_reversed' => l10n.errAlreadyReversed,
    'invalid_financing' => l10n.errInvalidFinancing,
    'invalid_installments' => l10n.valInstallmentCount,
    'invalid_date' => l10n.valInvalidDate,
    'invalid_category' => l10n.valCategoryRequired,
    'allocation_exceeds_due' => l10n.errAllocationInvalid,
    'allocation_exceeds_payment' => l10n.errAllocationInvalid,
    'invalid_allocations' => l10n.errAllocationInvalid,
    'facility_has_history' => l10n.errFacilityHasHistory,
    'facility_not_active' => l10n.errFacilityNotActive,
    'card_not_configured' => l10n.errCardNotConfigured,
    'invalid_paid_installments' => l10n.errInvalidPaidInstallments,
    'plan_partially_paid_due' => l10n.errPlanPartiallyPaidDue,
    _ => l10n.commonError,
  };
}

/// Maps a form validation error to a localized message.
String validationMessage(BuildContext context, ValidationError error) {
  final l10n = AppLocalizations.of(context);
  return switch (error) {
    ValidationError.required => l10n.valRequired,
    ValidationError.invalidEmail => l10n.valInvalidEmail,
    ValidationError.passwordTooShort => l10n.valPasswordTooShort,
    ValidationError.passwordsDoNotMatch => l10n.valPasswordsDoNotMatch,
    ValidationError.invalidAmount => l10n.errInvalidAmount,
    ValidationError.amountNotPositive => l10n.valAmountNotPositive,
    ValidationError.invalidDate => l10n.valInvalidDate,
    ValidationError.startAfterEnd => l10n.valStartAfterEnd,
    ValidationError.invalidDuration => l10n.valInvalidDuration,
    ValidationError.breakTooLong => l10n.valBreakTooLong,
    ValidationError.sameAccounts => l10n.errSameAccounts,
    ValidationError.tooLong => l10n.valTooLong,
    ValidationError.invalidMultiplier => l10n.valInvalidMultiplier,
    ValidationError.invalidDayFraction => l10n.valInvalidDayFraction,
    ValidationError.invalidDayOfMonth => l10n.valInvalidDayOfMonth,
  };
}
