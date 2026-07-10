// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Work Tracker';

  @override
  String get tabHome => 'Home';

  @override
  String get tabWork => 'Work';

  @override
  String get tabMoney => 'Money';

  @override
  String get tabReports => 'Reports';

  @override
  String get tabSettings => 'Settings';

  @override
  String get commonSave => 'Save';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonBack => 'Back';

  @override
  String get commonNext => 'Next';

  @override
  String get commonDone => 'Done';

  @override
  String get commonClose => 'Close';

  @override
  String get commonUndo => 'Undo';

  @override
  String get commonAll => 'All';

  @override
  String get commonNone => 'None';

  @override
  String get commonOptional => 'Optional';

  @override
  String get commonError => 'Something went wrong';

  @override
  String get commonLoading => 'Loading…';

  @override
  String get commonEmpty => 'Nothing here yet';

  @override
  String get commonOffline =>
      'You appear to be offline. Check your connection and retry.';

  @override
  String get commonNotes => 'Notes';

  @override
  String get commonAmount => 'Amount';

  @override
  String get commonDate => 'Date';

  @override
  String get commonToday => 'Today';

  @override
  String get commonSeeAll => 'See all';

  @override
  String get errInvalidCredentials => 'Incorrect email or password.';

  @override
  String get errEmailNotConfirmed => 'Please confirm your email address first.';

  @override
  String get errDuplicateEmail => 'An account with this email already exists.';

  @override
  String get errWeakPassword =>
      'Password is too weak. Use at least 8 characters.';

  @override
  String get errExpiredLink =>
      'This link is invalid, expired, or already used. Request a new one.';

  @override
  String get errRateLimited =>
      'Too many attempts. Please wait a moment and try again.';

  @override
  String get errSessionExpired =>
      'Your session has expired. Please log in again.';

  @override
  String get errAuthGeneric => 'Authentication failed. Please try again.';

  @override
  String get errNotAuthorized => 'You are not allowed to perform this action.';

  @override
  String get errTimeout => 'The request timed out. Please try again.';

  @override
  String get errConstraint => 'This change conflicts with existing data.';

  @override
  String get errNotFound => 'The requested item was not found.';

  @override
  String get errRealtime => 'Live updates are temporarily unavailable.';

  @override
  String get errInsufficientFunds =>
      'This account does not allow a negative balance.';

  @override
  String get errCurrencyMismatch => 'Both accounts must use the same currency.';

  @override
  String get errSameAccounts => 'Source and destination accounts must differ.';

  @override
  String get errAccountUnavailable =>
      'The selected account is unavailable or archived.';

  @override
  String get errAlreadyPaid => 'This salary period has already been paid.';

  @override
  String get errNotFinalized =>
      'Finalize the salary period before recording payment.';

  @override
  String get errInvalidAmount => 'Enter a valid amount.';

  @override
  String get valRequired => 'This field is required.';

  @override
  String get valInvalidEmail => 'Enter a valid email address.';

  @override
  String get valPasswordTooShort => 'Password must be at least 8 characters.';

  @override
  String get valPasswordsDoNotMatch => 'Passwords do not match.';

  @override
  String get valAmountNotPositive => 'Amount must be greater than zero.';

  @override
  String get valInvalidDate => 'Enter a valid date.';

  @override
  String get valStartAfterEnd => 'Start date must not be after end date.';

  @override
  String get valInvalidDuration => 'Enter a valid duration.';

  @override
  String get valBreakTooLong =>
      'Break must be shorter than the total duration.';

  @override
  String get valTooLong => 'Text is too long.';

  @override
  String get valInvalidMultiplier => 'Multiplier must be between 0% and 1000%.';

  @override
  String get valInvalidDayFraction =>
      'Day fraction must be between 0.01 and 2.';

  @override
  String get valInvalidDayOfMonth => 'Choose a day between 1 and 28.';

  @override
  String get authLoginTitle => 'Welcome back';

  @override
  String get authLoginSubtitle => 'Log in to your account';

  @override
  String get authEmail => 'Email';

  @override
  String get authPassword => 'Password';

  @override
  String get authConfirmPassword => 'Confirm password';

  @override
  String get authFullName => 'Full name';

  @override
  String get authLogin => 'Log in';

  @override
  String get authRegister => 'Create account';

  @override
  String get authRegisterTitle => 'Create your account';

  @override
  String get authForgotPassword => 'Forgot password?';

  @override
  String get authNoAccount => 'No account yet? Register';

  @override
  String get authHaveAccount => 'Already have an account? Log in';

  @override
  String get authForgotTitle => 'Reset your password';

  @override
  String get authForgotSubtitle =>
      'Enter your email and we will send you a reset link.';

  @override
  String get authSendResetLink => 'Send reset link';

  @override
  String get authResetSent =>
      'If an account exists for this email, a reset link has been sent.';

  @override
  String get authResetTitle => 'Set a new password';

  @override
  String get authNewPassword => 'New password';

  @override
  String get authUpdatePassword => 'Update password';

  @override
  String get authPasswordUpdated => 'Your password has been updated.';

  @override
  String get authConfirmEmailTitle => 'Confirm your email';

  @override
  String authConfirmEmailBody(String email) {
    return 'We sent a confirmation link to $email. Open it on this device to activate your account.';
  }

  @override
  String get authResend => 'Resend email';

  @override
  String authResendIn(int seconds) {
    return 'Resend available in ${seconds}s';
  }

  @override
  String get authResendDone => 'Confirmation email sent again.';

  @override
  String get authChangeEmail => 'Use a different email';

  @override
  String get authLogout => 'Log out';

  @override
  String get authPasswordStrengthWeak => 'Weak password';

  @override
  String get authPasswordStrengthFair => 'Fair password';

  @override
  String get authPasswordStrengthStrong => 'Strong password';
}
