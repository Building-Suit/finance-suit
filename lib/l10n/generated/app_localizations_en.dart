// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Finance Suit';

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
  String get menuOpenTooltip => 'Open menu';

  @override
  String get menuCloseTooltip => 'Close menu';

  @override
  String get menuNavigationLabel => 'Navigation menu';

  @override
  String get menuGroupGeneral => 'General';

  @override
  String get menuGroupAutomation => 'Automation';

  @override
  String get menuBrandSubtitle => 'by Building Suit';

  @override
  String get menuCategories => 'Categories';

  @override
  String get globalAddLabel => 'Add new item';

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
  String get appBackAgainToClose => 'back again to close the app';

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
  String get notificationYesterday => 'Yesterday';

  @override
  String get notificationThisWeek => 'This week';

  @override
  String get notificationEarlier => 'Earlier';

  @override
  String get notificationEmpty => 'No notifications yet.';

  @override
  String get notificationMarkAllRead => 'Mark all as read';

  @override
  String get commonSeeAll => 'See all';

  @override
  String get commonApply => 'Apply';

  @override
  String get commonAdd => 'Add';

  @override
  String get addSectionMoneyControl => 'Money Control';

  @override
  String get addSectionWorkControl => 'Work Control';

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

  @override
  String get onbStepProfile => 'About you';

  @override
  String get onbStepSalary => 'Income source';

  @override
  String get onbStepAccount => 'First account';

  @override
  String get onbStepReview => 'Review';

  @override
  String get onbWelcome => 'Let\'s set up your workspace';

  @override
  String get onbLanguage => 'Language';

  @override
  String get onbCurrency => 'Currency';

  @override
  String get onbTimezone => 'Timezone';

  @override
  String get onbWeekStart => 'Week starts on';

  @override
  String get onbWeekendDays => 'Weekend days';

  @override
  String onbStepProgress(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get onbReviewTitle => 'Review your setup';

  @override
  String get onbFinish => 'Finish setup';

  @override
  String get salBaseSalary => 'Base salary';

  @override
  String get salPeriodStartDay => 'Period start day';

  @override
  String get salPaymentDay => 'Payment day';

  @override
  String get salPaymentMonthOffset => 'Payment month';

  @override
  String get salOffsetSameMonth => 'Same month';

  @override
  String get salOffsetNextMonth => 'Next month';

  @override
  String get salOffsetSecondMonth => 'Two months later';

  @override
  String get salStandardPaidDays => 'Standard paid days per period';

  @override
  String get salStandardHours => 'Standard hours per day';

  @override
  String get salDayRate => 'Day rate';

  @override
  String get salHourRate => 'Hourly rate';

  @override
  String get salRateDerived => 'Derived automatically';

  @override
  String get salRateManual => 'Manual';

  @override
  String get salManualDayRate => 'Manual day rate';

  @override
  String get salManualHourRate => 'Manual hourly rate';

  @override
  String get salMultipliers => 'Multipliers';

  @override
  String get salExtraDayMultiplier => 'Extra day multiplier (%)';

  @override
  String get salHolidayMultiplier => 'Holiday multiplier (%)';

  @override
  String get salOvertimeMultiplier => 'Overtime multiplier (%)';

  @override
  String get salHolidaySemantics => 'Holiday pay semantics';

  @override
  String get salSemanticsAdditional => 'Additional pay on top of base';

  @override
  String get salSemanticsTotal => 'Total including base';

  @override
  String salDerivedDayRate(String amount) {
    return 'Derived day rate: $amount';
  }

  @override
  String salDerivedHourRate(String amount) {
    return 'Derived hourly rate: $amount';
  }

  @override
  String get accName => 'Account name';

  @override
  String get accType => 'Account type';

  @override
  String get accTypeCurrent => 'Current balance';

  @override
  String get accTypeSavings => 'Savings';

  @override
  String get accTypeCash => 'Cash';

  @override
  String get accTypeBank => 'Bank';

  @override
  String get accTypeWallet => 'Wallet';

  @override
  String get accTypeEmergency => 'Emergency fund';

  @override
  String get accTypeVacation => 'Vacation fund';

  @override
  String get accTypeCustom => 'Custom';

  @override
  String get accOpeningBalance => 'Opening balance';

  @override
  String get accAllowNegative => 'Allow negative balance';

  @override
  String get accHideFromHome => 'Hide from the Home tab';

  @override
  String get accHideFromHomeHelp =>
      'The account stays available everywhere else — Money tab, pickers, and reports.';

  @override
  String get txCardOpenSettings => 'Open card settings';

  @override
  String get setAppearance => 'Appearance';

  @override
  String get setAppearanceSubtitle => 'Theme and language';

  @override
  String get setSecurity => 'Privacy and security';

  @override
  String get setSecuritySubtitle => 'Privacy, app lock and biometric';

  @override
  String get setNotificationsSubtitle => 'Alerts and reminder preferences';

  @override
  String get setProfileSubtitle => 'Personal details, sign-in, and plan';

  @override
  String get setAutomationSection => 'Automation and income';

  @override
  String get setAutomationSubtitle => 'Salary, income, and recurring payments';

  @override
  String get setAccountSubtitle =>
      'Change password, manage your plan, or delete your account';

  @override
  String get setAboutSubtitle => 'Legal documents and app information';

  @override
  String get privacyMoneyTitle => 'Hide money amounts';

  @override
  String get privacyMoneyHelp =>
      'Blur balances and amounts. Tap a hidden amount and confirm with fingerprint, face, or your phone screen lock to reveal it.';

  @override
  String get privacyAppLockTitle => 'Lock Finance Suit with device security';

  @override
  String get privacyAppLockHelp =>
      'Require fingerprint, face, PIN, pattern, password, or passcode when opening or returning to the app.';

  @override
  String get privacyBiometricLoginTitle =>
      'Login with fingerprint or device security';

  @override
  String get privacyBiometricLoginHelp =>
      'After you log out, sign in again with fingerprint, face, PIN, pattern, password, or passcode without replacing email and password login.';

  @override
  String get privacyDeviceAuthUnavailableHelp =>
      'Set up a PIN, password, passcode, pattern, fingerprint, or face unlock on this phone to use these options.';

  @override
  String get privacyDeviceAuthUnavailable =>
      'Device security is not available. Set up a phone screen lock first.';

  @override
  String get privacyDeviceAuthFailed =>
      'We could not confirm your identity. Try again.';

  @override
  String get privacyEnableMoneyReason =>
      'Confirm your identity to protect financial amounts in Finance Suit.';

  @override
  String get privacyEnableAppLockReason =>
      'Confirm your identity to enable Finance Suit app lock.';

  @override
  String get privacyEnableBiometricLoginReason =>
      'Confirm your identity to enable secure quick login for Finance Suit.';

  @override
  String get privacyConfirmPasswordTitle =>
      'Confirm your Finance Suit password';

  @override
  String get privacyConfirmPasswordHelp =>
      'Enter your current password once to securely set up quick login on this phone.';

  @override
  String get privacyIncorrectPassword =>
      'That password is incorrect. Quick login was not enabled.';

  @override
  String get privacyDisableMoneyReason =>
      'Confirm your identity to stop hiding financial amounts in Finance Suit.';

  @override
  String get privacyDisableAppLockReason =>
      'Confirm your identity to disable Finance Suit app lock.';

  @override
  String get privacyDisableBiometricLoginReason =>
      'Confirm your identity to disable secure quick login for Finance Suit.';

  @override
  String get privacyRevealReason =>
      'Confirm your identity to reveal financial amounts in Finance Suit.';

  @override
  String get privacyShowAmountsTooltip => 'Show money amounts';

  @override
  String get privacyHideAmountsTooltip => 'Hide money amounts';

  @override
  String get privacyHiddenAmountLabel => 'Hidden financial amount';

  @override
  String get privacyRevealAmountHint =>
      'Authenticate with biometrics or the phone screen lock to reveal it';

  @override
  String get privacyUnlockReason =>
      'Confirm your identity to unlock Finance Suit.';

  @override
  String get privacyUnlockTitle => 'Finance Suit is locked';

  @override
  String get privacyUnlockBody =>
      'Use fingerprint, face recognition, or your phone PIN, pattern, password, or passcode.';

  @override
  String get privacyUnlockButton => 'Unlock with device security';

  @override
  String get privacyUsePassword => 'Use Finance Suit password instead';

  @override
  String get authBiometricLogin => 'Login with fingerprint or device security';

  @override
  String get authBiometricLoginSetupHelp =>
      'Enable fingerprint login in Settings → Account → Login with fingerprint or device security.';

  @override
  String get authBiometricLoginReason =>
      'Confirm your identity to login to Finance Suit.';

  @override
  String get authBiometricSessionExpired =>
      'Secure quick login has expired. Login with your email and password, then enable it again in Settings.';

  @override
  String get authBiometricLoginFailed =>
      'Secure quick login failed. Try again or use your email and password.';

  @override
  String get setTheme => 'Theme';

  @override
  String get setThemeSystem => 'System';

  @override
  String get setThemeLight => 'Light';

  @override
  String get setThemeDark => 'Dark';

  @override
  String get setProfileSection => 'Profile';

  @override
  String get setDisplayName => 'Display name';

  @override
  String get setChangePassword => 'Change password';

  @override
  String get setChangeEmail => 'Change email';

  @override
  String get setNewEmail => 'New email';

  @override
  String get setEmailChangeSent =>
      'A confirmation link was sent to the new email.';

  @override
  String get setSalarySection => 'Salary settings';

  @override
  String get setPreferencesSection => 'Preferences';

  @override
  String get setAccountSection => 'Account';

  @override
  String get setSignOutConfirmTitle => 'Log out?';

  @override
  String get setSignOutConfirmBody => 'You can log back in anytime.';

  @override
  String get setSaved => 'Saved';

  @override
  String get setAboutSection => 'About';

  @override
  String get setAppVersion => 'App version';

  @override
  String get setPrivacyPolicy => 'Privacy policy';

  @override
  String get setTerms => 'Terms and conditions';

  @override
  String get setDeleteAccount => 'Delete account';

  @override
  String get setDeleteAccountSubtitle =>
      'Permanently delete your account and app data';

  @override
  String get deleteAccountTitle => 'Delete your account';

  @override
  String get deleteAccountWarning =>
      'This action is permanent and cannot be undone.';

  @override
  String get deleteAccountDataList =>
      'Your Finance Suit profile, salary settings, work records, accounts, categories, transactions, macros, and held amounts will be deleted. Your shared sign-in and other portal data will be kept.';

  @override
  String get deleteAccountPasswordPrompt => 'Confirm your password';

  @override
  String get deleteAccountAcknowledge =>
      'I understand that my Finance Suit profile and data will be permanently deleted.';

  @override
  String get deleteAccountFinalTitle => 'Permanently delete account?';

  @override
  String get deleteAccountFinalBody =>
      'Finance Suit will delete your Finance Suit profile and active app data now. Your shared sign-in and other portal data will remain, and you will be logged out on this device.';

  @override
  String get deleteAccountConfirmButton => 'Delete my account';

  @override
  String get deleteAccountFailure =>
      'We could not delete your account. Check your connection and password, then try again or contact support.';

  @override
  String get deleteAccountPolicy => 'How account deletion works';

  @override
  String get moneyAccountsTab => 'Accounts';

  @override
  String get moneyTransactionsTab => 'Transactions';

  @override
  String get moneyTotalBalance => 'Total balance';

  @override
  String get moneyNewAccount => 'New account';

  @override
  String get moneyEditAccount => 'Edit account';

  @override
  String get moneyNoAccounts => 'No accounts yet. Add one to start tracking.';

  @override
  String get moneyNoTransactions => 'No transactions yet.';

  @override
  String get moneyDefaultLabel => 'Default';

  @override
  String get moneyArchivedLabel => 'Archived';

  @override
  String get moneySetDefault => 'Set as default';

  @override
  String get moneyArchive => 'Archive';

  @override
  String get moneyUnarchive => 'Unarchive';

  @override
  String get moneyShowArchived => 'Show archived';

  @override
  String get moneyArchiveConfirmTitle => 'Archive account?';

  @override
  String get moneyArchiveConfirmBody =>
      'Archived accounts are hidden from pickers and cannot receive new transactions. Existing history stays intact.';

  @override
  String get txExpense => 'Expense';

  @override
  String get txAllowance => 'Allowance';

  @override
  String get txCustomIncome => 'Other income';

  @override
  String get txFreelanceIncome => 'Freelance income';

  @override
  String get txSalaryIncome => 'Salary';

  @override
  String get txTransfer => 'Transfer';

  @override
  String get txAddTitle => 'Add transaction';

  @override
  String get txEditTitle => 'Edit transaction';

  @override
  String get txAccountUnavailable => 'unavailable';

  @override
  String get txAccount => 'Account';

  @override
  String get txClearFilters => 'Clear filters';

  @override
  String get txFilterNoMatches => 'No transactions match these filters.';

  @override
  String get txFilters => 'Filters';

  @override
  String txApplyWithCount(int count) {
    return 'Apply ($count)';
  }

  @override
  String get txFromAccount => 'From account';

  @override
  String get txToAccount => 'To account';

  @override
  String get txCategory => 'Category';

  @override
  String get txNoCategory => 'No category';

  @override
  String get txCounterparty => 'Given to';

  @override
  String get txTitleField => 'Title';

  @override
  String get txDeleteConfirmTitle => 'Delete transaction?';

  @override
  String get txDeleteConfirmBody =>
      'This permanently removes the transaction and updates account balances.';

  @override
  String get txSalaryLocked =>
      'Salary payments are managed from salary periods and cannot be edited here.';

  @override
  String get macrosTitle => 'Macros';

  @override
  String get macroManage => 'Manage macros';

  @override
  String get macroNew => 'New macro';

  @override
  String get macroEditTitle => 'Edit macro';

  @override
  String get macroName => 'Macro name';

  @override
  String get macroActions => 'Actions';

  @override
  String get macroAddAction => 'Add action';

  @override
  String get macroNoActions => 'Add at least one action.';

  @override
  String get macroReversible => 'Reversible';

  @override
  String get macroReversibleHint =>
      'Include this action when the macro runs in reverse';

  @override
  String get macroReversibleBadge => 'Reversible';

  @override
  String get macroRun => 'Run';

  @override
  String get macroRunReverse => 'Run in reverse';

  @override
  String macroRunTo(String name) {
    return 'To $name';
  }

  @override
  String macroRunFrom(String name) {
    return 'From $name';
  }

  @override
  String macroApplied(int count) {
    return '$count transactions added';
  }

  @override
  String macroActionCount(int count) {
    return '$count actions';
  }

  @override
  String get macroEmpty =>
      'No macros yet. Save repeated transactions and run them in one tap.';

  @override
  String get macroDeleteConfirmTitle => 'Delete macro?';

  @override
  String get macroDeleteConfirmBody =>
      'This removes the macro and its actions. Transactions it created are kept.';

  @override
  String get errMacroNotReversible => 'This macro has no reversible actions.';

  @override
  String get errMacroEmpty => 'A macro needs at least one action.';

  @override
  String get moneyHeldTab => 'Held';

  @override
  String get heldTitle => 'Held amounts';

  @override
  String get heldNew => 'New held amount';

  @override
  String get heldEditTitle => 'Edit held amount';

  @override
  String get heldDirection => 'Direction';

  @override
  String get heldDirectionIOwe => 'I owe someone';

  @override
  String get heldDirectionOwedToMe => 'Owed to me';

  @override
  String get heldOwedTo => 'Owed to';

  @override
  String get heldOwedBy => 'Owed by';

  @override
  String get heldTotalIOwe => 'Total I owe';

  @override
  String get heldTotalOwedToMe => 'Total owed to me';

  @override
  String get heldEmpty =>
      'No held amounts yet. Track money you owe or money owed to you, on its own or linked to a transaction.';

  @override
  String get heldSettle => 'Mark as settled';

  @override
  String get heldUnsettle => 'Mark as active';

  @override
  String get heldSettledLabel => 'Settled';

  @override
  String get heldShowSettled => 'Show settled';

  @override
  String get heldLinkedTransaction => 'Linked to a transaction';

  @override
  String get heldHoldForTransaction => 'Hold an amount for this transaction';

  @override
  String get heldDeleteConfirmTitle => 'Delete held amount?';

  @override
  String get heldDeleteConfirmBody =>
      'This removes the held amount. If it created an account transaction, that transaction is also removed and the balance is updated.';

  @override
  String get catManage => 'Manage categories';

  @override
  String get catNew => 'New category';

  @override
  String get catName => 'Category name';

  @override
  String get catKind => 'Category type';

  @override
  String get catKindExpense => 'Expense category';

  @override
  String get catKindAllowance => 'Allowance category';

  @override
  String get catKindIncome => 'Income category';

  @override
  String get catNoneYet => 'No categories of this kind yet.';

  @override
  String get salPeriodsTitle => 'Salary periods';

  @override
  String get salCurrentPeriod => 'Current period';

  @override
  String salEstimatedFor(String month) {
    return 'Estimated $month salary';
  }

  @override
  String salBasedOn(String start, String end) {
    return 'Based on work from $start to $end';
  }

  @override
  String salExpectedPayment(String date) {
    return 'Expected payment: $date';
  }

  @override
  String get salStatusOpen => 'Open';

  @override
  String get salStatusFinalized => 'Finalized';

  @override
  String get salStatusPaid => 'Paid';

  @override
  String get salBreakdown => 'Breakdown';

  @override
  String get salEstimatedTotal => 'Estimated total';

  @override
  String get salItemExtraDays => 'Extra days';

  @override
  String get salItemHolidays => 'Official holidays worked';

  @override
  String get salItemOvertime => 'Overtime';

  @override
  String get salItemBonuses => 'Bonuses';

  @override
  String get salItemDeductions => 'Deductions';

  @override
  String get salAdjustments => 'Adjustments';

  @override
  String get salNewAdjustment => 'New adjustment';

  @override
  String get salEditAdjustment => 'Edit adjustment';

  @override
  String get salAdjBonus => 'Bonus';

  @override
  String get salAdjDeduction => 'Deduction';

  @override
  String get salEffectiveDate => 'Effective date';

  @override
  String get salNoAdjustments => 'No adjustments in this period.';

  @override
  String get salDeleteAdjTitle => 'Delete adjustment?';

  @override
  String get salDeleteAdjBody => 'This permanently removes the adjustment.';

  @override
  String get salFinalize => 'Finalize period';

  @override
  String get salFinalizeConfirmTitle => 'Finalize this period?';

  @override
  String get salFinalizeConfirmBody =>
      'An immutable snapshot of the current calculation will be stored. Later settings changes will not affect it.';

  @override
  String get salReopen => 'Reopen period';

  @override
  String get salReopenConfirmTitle => 'Reopen this period?';

  @override
  String get salReopenConfirmBody =>
      'The stored snapshot will be replaced when you finalize again.';

  @override
  String get salMarkPaid => 'Mark as paid';

  @override
  String get salActualAmount => 'Actual amount received';

  @override
  String get salReceivedDate => 'Received date';

  @override
  String get salDestinationAccount => 'Destination account';

  @override
  String get salActualReceived => 'Actual received';

  @override
  String get salDifference => 'Difference vs estimate';

  @override
  String get salNoPeriods => 'No salary periods yet.';

  @override
  String get salNoOpenPeriods => 'No open salary periods are available.';

  @override
  String get salPeriodNoLongerOpen =>
      'This salary period is no longer open. Refresh and choose an open period.';

  @override
  String get salWarnBaseZero => 'Base salary is not configured yet.';

  @override
  String get salWarnMissingAmounts =>
      'Some work entries have no stored amount.';

  @override
  String get workEntryType => 'Entry type';

  @override
  String get workEntryRegular => 'Regular day';

  @override
  String get workEntryOvertime => 'Overtime';

  @override
  String get workEntryExtraDay => 'Extra day';

  @override
  String get workEntryHoliday => 'Holiday worked';

  @override
  String get workAddEntry => 'Add work entry';

  @override
  String get workEditEntry => 'Edit work entry';

  @override
  String get workNoEntries => 'No work entries this month.';

  @override
  String get workNoEntriesForDay => 'No entries on this day.';

  @override
  String get workStartTime => 'Start time';

  @override
  String get workEndTime => 'End time';

  @override
  String get workBreakMinutes => 'Break (minutes)';

  @override
  String get workDurationMinutes => 'Duration (minutes)';

  @override
  String get workDayUnits => 'Days worked (e.g. 1 or 0.5)';

  @override
  String get workMultiplier => 'Multiplier %';

  @override
  String get workCustomRate => 'Custom rate';

  @override
  String get workLinkedHoliday => 'Official holiday';

  @override
  String get workEstimatedPay => 'Estimated extra pay';

  @override
  String get workHolidays => 'Official holidays';

  @override
  String get workNewHoliday => 'New holiday';

  @override
  String get workEditHoliday => 'Edit holiday';

  @override
  String get workHolidayName => 'Holiday name';

  @override
  String get workNoHolidays => 'No official holidays yet.';

  @override
  String get workDeleteEntryTitle => 'Delete work entry?';

  @override
  String get workDeleteEntryBody => 'This permanently removes the work entry.';

  @override
  String get workDeleteHolidayTitle => 'Delete holiday?';

  @override
  String get workDeleteHolidayBody =>
      'Linked work entries keep their recorded pay but lose the holiday link.';

  @override
  String get workMonthTotal => 'Extra pay this month';

  @override
  String workDurationHm(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String get homeBalance => 'Balance';

  @override
  String get homeDefaultAccount => 'Default account';

  @override
  String get homeSavings => 'Savings';

  @override
  String get homeCashFlow => 'Cash flow';

  @override
  String get homeSalary => 'Salary';

  @override
  String get homeRecentActivity => 'Recent activity';

  @override
  String get homeNoRecentActivity => 'No recent activity.';

  @override
  String get historyTitle => 'History';

  @override
  String get historyNoItems => 'No records match these filters.';

  @override
  String get historyLoadMore => 'Load more';

  @override
  String get historyBusinessDate => 'Business date';

  @override
  String get historyActiveFilters => 'Active filters';

  @override
  String get historyCustomRange => 'Custom range';

  @override
  String get historySortRecordDesc => 'Newest business date';

  @override
  String get historySortRecordAsc => 'Oldest business date';

  @override
  String get historySortAmountDesc => 'Highest amount';

  @override
  String get historySortAmountAsc => 'Lowest amount';

  @override
  String get historySortCreatedDesc => 'Newest created';

  @override
  String get historyFilterWork => 'Work';

  @override
  String get historyFilterRegularWork => 'Regular work';

  @override
  String get historyFilterSalaryAdjustment => 'Salary adjustment';

  @override
  String get rangeCurrentMonth => 'Current month';

  @override
  String get rangeLast30 => 'Last 30 days';

  @override
  String get rangePreviousMonth => 'Previous month';

  @override
  String get rangeLast90 => 'Last 90 days';

  @override
  String get rangeToday => 'Today';

  @override
  String get rangeLast7 => 'Last 7 days';

  @override
  String get rangeCurrentYear => 'Current year';

  @override
  String get reportsCashFlow => 'Income, expenses and allowances';

  @override
  String get reportsNetOverTime => 'Net cash flow over time';

  @override
  String get reportsExpensesByCategory => 'Expenses by category';

  @override
  String get reportsAllowancesByCategory => 'Allowances by category';

  @override
  String get reportsIncomeByCategory => 'Income by source';

  @override
  String get reportsAccountBalance => 'Account balance over time';

  @override
  String get reportsSalaryComparison => 'Estimated vs actual salary';

  @override
  String get reportsWorkCompensation => 'Work compensation by salary period';

  @override
  String get reportsWorkingHours => 'Working hours';

  @override
  String get reportsNoData => 'No report data in this range.';

  @override
  String get reportsBucketDay => 'Daily';

  @override
  String get reportsBucketWeek => 'Weekly';

  @override
  String get reportsBucketMonth => 'Monthly';

  @override
  String get reportIncome => 'Income';

  @override
  String get reportExpenses => 'Expenses';

  @override
  String get reportAllowances => 'Allowances';

  @override
  String get reportNet => 'Net';

  @override
  String get reportEstimated => 'Estimated';

  @override
  String get reportActual => 'Actual';

  @override
  String get reportOvertime => 'Overtime';

  @override
  String get reportExtraDays => 'Extra days';

  @override
  String get reportHolidays => 'Holidays';

  @override
  String get reportHours => 'Hours';

  @override
  String get catParent => 'Parent category (optional)';

  @override
  String get catTopLevel => 'No parent — regular category';

  @override
  String catSubcategoryOf(String parent) {
    return 'Subcategory of $parent';
  }

  @override
  String get catSubcategoryOptional => 'Subcategory (optional)';

  @override
  String get catUseParentCategory => 'No subcategory — use the parent category';

  @override
  String get catAddSubcategory => 'Add subcategory';

  @override
  String catSubcategoryCount(int count) {
    return '$count subcategories';
  }

  @override
  String get catMissingParent => 'Missing parent category';

  @override
  String get catArchiveChildrenFirst =>
      'Archive this category\'s active subcategories first.';

  @override
  String get catRestoreParentFirst =>
      'Restore the parent category before restoring this subcategory.';

  @override
  String get incomeHasSalary => 'I receive a salary';

  @override
  String get incomeHasSalaryHelp =>
      'Turn this off if your income is allowance-based or comes from other sources.';

  @override
  String get incomeSourcesTitle => 'Income automations';

  @override
  String get incomeSourcesSubtitle =>
      'Schedule salary, allowance, and other recurring income';

  @override
  String get incomeAddSource => 'Add income source';

  @override
  String get incomeEditSource => 'Edit income source';

  @override
  String get incomeNoSources => 'No automated income sources yet.';

  @override
  String incomeMonthlyOnDay(int day) {
    return 'Monthly on day $day';
  }

  @override
  String get incomeSourceType => 'Income type';

  @override
  String get incomeSourceName => 'Income source name';

  @override
  String get incomeExpectedAmount => 'Expected amount';

  @override
  String get incomeRemainderAccount => 'Deposit and remainder account';

  @override
  String get incomePromptBefore => 'Prompt days before';

  @override
  String get incomeStartDate => 'Automation start date';

  @override
  String get incomeSplitTitle => 'Automatic account split';

  @override
  String get incomeSplitHelp =>
      'Add ordered rules for transfers from the deposit account. Anything left stays in the deposit account.';

  @override
  String get incomeInvalidPercentage => 'Enter a percentage from 0 to 100.';

  @override
  String get incomeSplitAddRule => 'Add split rule';

  @override
  String get incomeSplitNoRules =>
      'No split rules. The full amount stays in the deposit account.';

  @override
  String incomeSplitRuleNumber(int number) {
    return 'Rule $number';
  }

  @override
  String get incomeSplitDestinationAccount => 'Destination account';

  @override
  String get incomeSplitMethod => 'Split method';

  @override
  String get incomeSplitMethodPercentage => 'Percentage';

  @override
  String get incomeSplitMethodFixed => 'Fixed amount';

  @override
  String get incomeSplitCalculationBasis => 'Percentage basis';

  @override
  String get incomeSplitBasisOriginal => 'Original amount';

  @override
  String get incomeSplitBasisRemaining => 'Remaining amount';

  @override
  String get incomeSplitMoveUp => 'Move rule up';

  @override
  String get incomeSplitMoveDown => 'Move rule down';

  @override
  String get incomeSplitInvalidAccount =>
      'Choose an active account in the same currency.';

  @override
  String get incomeSplitIncludeExtraWork =>
      'Include extra hours and days in percentage calculations';

  @override
  String get incomeSplitIncludeExtraWorkHelp =>
      'Bonuses and deductions are still treated as ordinary salary.';

  @override
  String get incomeSplitRouteExtraWork =>
      'Route all protected extra-work earnings to another account';

  @override
  String get incomeSplitExtraWorkAccount => 'Extra-work destination account';

  @override
  String get incomeRolloverTitle => 'Move the previous balance to savings';

  @override
  String get incomeRolloverHelp =>
      'When this salary is accepted, move any positive balance already in the deposit account to the selected savings account before depositing the salary.';

  @override
  String get incomeRolloverNoSavings =>
      'Create an active savings account in the same currency to enable this option.';

  @override
  String get incomeRolloverAccount => 'Previous-balance destination';

  @override
  String get incomeSplitPreviewTitle => 'Summary preview';

  @override
  String incomeSplitPreviewDeposit(String amount, String account) {
    return '$amount enters $account first.';
  }

  @override
  String incomeSplitPreviewPercentageRule(
    int number,
    String percentage,
    String basis,
    String amount,
    String account,
  ) {
    return 'Rule $number: $percentage% of the $basis = $amount to $account.';
  }

  @override
  String incomeSplitPreviewFixedRule(
    int number,
    String amount,
    String account,
  ) {
    return 'Rule $number: fixed $amount to $account.';
  }

  @override
  String get incomeSplitPreviewExtraIncluded =>
      'Extra-work earnings are included in percentage calculations.';

  @override
  String incomeSplitPreviewExtraRouted(String account) {
    return 'Protected extra-work earnings go to $account.';
  }

  @override
  String incomeSplitPreviewExtraKept(String account) {
    return 'Protected extra-work earnings stay in $account.';
  }

  @override
  String incomeRolloverPreviewMoved(
    String sourceAccount,
    String destinationAccount,
  ) {
    return 'Before this salary is deposited, any positive existing balance in $sourceAccount moves to $destinationAccount.';
  }

  @override
  String incomeRolloverPreviewKept(String account) {
    return 'The existing balance in $account stays where it is.';
  }

  @override
  String incomeSplitPreviewLine(String amount, String account) {
    return '$amount to $account';
  }

  @override
  String incomeSplitPreviewRemainder(String amount, String account) {
    return '$amount remains in $account';
  }

  @override
  String get incomeSplitPreviewError =>
      'These rules exceed the available income.';

  @override
  String get incomeKindSalary => 'Salary';

  @override
  String get incomeKindAllowance => 'Allowance received';

  @override
  String get incomeKindFreelance => 'Freelance income';

  @override
  String get incomeKindOther => 'Other income';

  @override
  String get incomeKindNone => 'No regular income for now';

  @override
  String get incomePrimaryType => 'How do you usually receive income?';

  @override
  String get incomeNoPrimaryHelp =>
      'You can finish setup without a salary and add any income source later from Settings.';

  @override
  String get incomePendingTitle => 'Income to approve';

  @override
  String incomeDue(String date) {
    return 'Expected on $date — confirm when it arrives';
  }

  @override
  String incomeUpcoming(String date) {
    return 'Expected on $date — you can accept it early';
  }

  @override
  String incomeAcceptTitle(String name) {
    return 'Accept $name?';
  }

  @override
  String get incomeAcceptHelp =>
      'The income transaction and its account splits are created only after you confirm.';

  @override
  String get incomeAccept => 'Accept income';

  @override
  String get incomeSkipTitle => 'Skip this income?';

  @override
  String incomeSkipHelp(String name) {
    return '$name will not create a transaction for this month.';
  }

  @override
  String get incomeSkip => 'Skip';

  @override
  String get incomeLater => 'Later';

  @override
  String get incomeRemindLater => 'Snoozed for 24 hours.';

  @override
  String get incomeSnoozeFailed => 'Could not snooze this income. Try again.';

  @override
  String get incomeAcceptedMessage => 'Income accepted.';

  @override
  String get incomeSkippedMessage => 'Income skipped.';

  @override
  String get salaryBaseAmount => 'Base amount';

  @override
  String get salaryExtraDays => 'Extra days';

  @override
  String get salaryOvertimeDuration => 'Overtime';

  @override
  String get salaryHolidayWorked => 'Holiday worked';

  @override
  String get salaryEstimatedTotal => 'Estimated total';

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String get incomeAutomationCenter => 'Income automations';

  @override
  String get incomeAutomationOverview =>
      'Set the expected date and account split. Nothing changes your balance until you approve the payment.';

  @override
  String get incomeActiveAutomations => 'Active automations';

  @override
  String get incomePausedAutomations => 'Paused automations';

  @override
  String get incomeAutomationEnabled => 'Automation enabled';

  @override
  String get incomeAutomationEnabledHelp =>
      'Pause this source without deleting its schedule or split rules.';

  @override
  String incomeActiveCount(int count) {
    return '$count active';
  }

  @override
  String incomePausedCount(int count) {
    return '$count paused';
  }

  @override
  String incomePendingCount(int count) {
    return '$count waiting';
  }

  @override
  String get incomeActive => 'Active';

  @override
  String get incomePaused => 'Paused';

  @override
  String get incomePause => 'Pause';

  @override
  String get incomeResume => 'Resume';

  @override
  String incomeDepositAccount(String account) {
    return 'Deposit account: $account';
  }

  @override
  String incomeSplitAccount(String percentage, String account) {
    return '$percentage% to $account';
  }

  @override
  String incomeSplitFixedAccount(String amount, String account) {
    return '$amount to $account';
  }

  @override
  String incomeRemainderSplit(String percentage, String account) {
    return '$percentage% remains in $account';
  }

  @override
  String get incomeNoPending => 'No income is waiting for approval.';

  @override
  String get addSectionAutomationControl => 'Automation Control';

  @override
  String get addAutomation => 'Add automation';

  @override
  String get manageAutomations => 'Manage automations';

  @override
  String get addAutomationControlHelp =>
      'Schedule salary or recurring income and approve it before balances change.';

  @override
  String get incomeAddAutomationEmpty =>
      'Add an automation to schedule recurring income. Nothing changes your balance until you approve it.';

  @override
  String get incomeTypeLockedOnEdit =>
      'Automation type cannot be changed while editing. Create a new automation to use another type.';

  @override
  String get incomeSalaryAlreadyExists =>
      'A salary automation already exists. Edit or resume it instead.';

  @override
  String get homePartialDataError =>
      'Some dashboard sections could not be loaded. Other available data is still shown.';

  @override
  String get reportStartingBalance => 'Starting balance';

  @override
  String get reportEndingBalance => 'Ending balance';

  @override
  String get selectionSearchHint => 'Search options';

  @override
  String get heldLinkedTransactionReference =>
      'Original transaction linked for reference';

  @override
  String get heldSettlementTransactionHelp =>
      'Settlement creates a separate transaction for the selected account.';

  @override
  String get onboardingSubmitFailed =>
      'Setup could not be completed. Check your entries and try again.';

  @override
  String get updateAvailableTitle => 'Update available';

  @override
  String get updateAvailableBody =>
      'A new version of Finance Suit is ready. Update now to get the latest improvements.';

  @override
  String get updateLater => 'Later';

  @override
  String get updateNow => 'Update';

  @override
  String get heldTypeLabel => 'Type';

  @override
  String get heldSettleTitle => 'Settle held amount';

  @override
  String get heldSettleDateLabel => 'Settlement date';

  @override
  String get heldSettleHelp => 'The transaction will be recorded on this date.';

  @override
  String get accTypeCreditCard => 'Credit Card';

  @override
  String get accTypeBnpl => 'BNPL / Finance Company';

  @override
  String get accColorLabel => 'Card colour';

  @override
  String get accColorDefault => 'Default';

  @override
  String accColorSwatch(int index) {
    return 'Colour $index';
  }

  @override
  String get accOpeningOwed => 'Opening amount owed';

  @override
  String get accOpeningOwedHelp =>
      'Debt already used on this facility before you started tracking it in Finance Suit.';

  @override
  String get facilityCreditLimit => 'Credit limit';

  @override
  String get facilityDefaultDueDay => 'Default due day';

  @override
  String get facilityStatementDay => 'Statement day';

  @override
  String get facilityLastFour => 'Last four digits';

  @override
  String get facilityReminderDays => 'Reminder lead days';

  @override
  String get valFacilityLastFour => 'Enter exactly four digits';

  @override
  String get valFacilityReminderDays => 'Enter between 0 and 31 days';

  @override
  String get moneyAssetsSection => 'Cash & bank';

  @override
  String get moneyLiabilitiesSection => 'Credit & installments';

  @override
  String get facilityOwed => 'Amount owed';

  @override
  String get facilityAvailable => 'Available credit';

  @override
  String get facilityUtilization => 'Utilization';

  @override
  String facilityNextDue(String date) {
    return 'Next due $date';
  }

  @override
  String get facilityOverdueBadge => 'Overdue';

  @override
  String get facilityDueNow => 'Due now';

  @override
  String get facilityDetailTitle => 'Credit facility';

  @override
  String get facilityAddPurchase => 'Add installment purchase';

  @override
  String get facilityMakePayment => 'Make payment';

  @override
  String get facilityDuesSection => 'Upcoming installments';

  @override
  String get facilityNoDues => 'Nothing is scheduled on this facility.';

  @override
  String get facilityPlansSection => 'Installment plans';

  @override
  String get facilityNoPlans => 'No installment plans yet.';

  @override
  String get facilityHistorySection => 'Related activity';

  @override
  String get facilityRepaymentLabel => 'Facility payment';

  @override
  String get facilityReversalLabel => 'Payment reversal';

  @override
  String get facilityPurchaseLabel => 'Credit purchase';

  @override
  String get facilityActivityInstallment => 'Installment purchase';

  @override
  String get facilityActivityDownPayment => 'Installment down payment';

  @override
  String get facilityActivityFee => 'Card fee';

  @override
  String get facilityActivityWhyLocked => 'Why can\'t I edit this?';

  @override
  String get facilityActivitySettled =>
      'This charge is already on a paid statement. Reverse the payment first to correct it.';

  @override
  String get facilityActivityFeeLocked =>
      'This charge was generated by a card fee rule. Change the rule instead.';

  @override
  String get facilityActivitySystemRecord =>
      'This is a system record and cannot be edited.';

  @override
  String get facilityEmptyTitle => 'No credit card or BNPL accounts yet';

  @override
  String get facilityEmptyAction => 'Add credit account';

  @override
  String get planStatusActive => 'Active';

  @override
  String get planStatusCompleted => 'Completed';

  @override
  String get planStatusCancelled => 'Cancelled';

  @override
  String planPaidOfTotal(String paid, String total) {
    return '$paid of $total paid';
  }

  @override
  String planBankCostPaid(String paid, String total) {
    return 'Bank interest & fees: $paid of $total';
  }

  @override
  String get planCancel => 'Cancel plan';

  @override
  String get planCancelConfirmTitle => 'Cancel this plan?';

  @override
  String get planCancelConfirmBody =>
      'The financed purchase will be removed and its schedule cancelled. This is only possible before any payment.';

  @override
  String get dueStatusUpcoming => 'Upcoming';

  @override
  String get dueStatusDueToday => 'Due today';

  @override
  String get dueStatusOverdue => 'Overdue';

  @override
  String get dueStatusPartiallyPaid => 'Partially paid';

  @override
  String get dueStatusPaid => 'Paid';

  @override
  String get dueStatusCancelled => 'Cancelled';

  @override
  String get purchaseTitle => 'New installment purchase';

  @override
  String get purchaseFacility => 'Facility';

  @override
  String get purchaseMerchant => 'Merchant or title';

  @override
  String get purchaseDateLabel => 'Purchase date';

  @override
  String get purchasePrice => 'Purchase price';

  @override
  String get purchaseDownPayment => 'Down payment';

  @override
  String get purchaseDownPaymentAccount => 'Paid from';

  @override
  String get purchaseFinancingMode => 'Financing input';

  @override
  String get purchaseCardTenorDefaultHint =>
      'The card\'s own rate for this number of months will be used automatically.';

  @override
  String get purchaseFinancingModeFees => 'Enter financing fees';

  @override
  String get purchaseFinancingModeTotal => 'Enter total payable';

  @override
  String get purchaseFinancingFees => 'Financing fees';

  @override
  String get purchaseTotalPayable => 'Total payable';

  @override
  String get purchaseFinancedPrincipal => 'Financed principal';

  @override
  String get purchaseInstallmentCount => 'Number of installments';

  @override
  String get purchaseSingleCycleHint =>
      'One installment means the full amount is due on the next due date.';

  @override
  String get purchaseFirstDueDate => 'First due date';

  @override
  String get purchasePreviewTitle => 'What will be recorded';

  @override
  String get purchaseMonthly => 'Monthly schedule';

  @override
  String get purchaseAvailableBefore => 'Available credit now';

  @override
  String get purchaseAvailableAfter => 'Available after purchase';

  @override
  String get purchaseExceedsCredit =>
      'This purchase exceeds the available credit';

  @override
  String get valDownPaymentTooLarge =>
      'The down payment must stay below the purchase price';

  @override
  String get valTotalBelowFinanced =>
      'Total payable cannot be below the financed principal';

  @override
  String get valInstallmentCount => 'Choose between 1 and 120 installments';

  @override
  String get valCategoryRequired => 'Choose a category';

  @override
  String get paymentTitle => 'Pay credit facility';

  @override
  String get paymentSource => 'Pay from';

  @override
  String get paymentDate => 'Payment date';

  @override
  String get paymentDueNowChip => 'Due now';

  @override
  String get paymentNextChip => 'Next installment';

  @override
  String get paymentFullChip => 'Full outstanding';

  @override
  String get paymentAllocationPreview => 'Will be applied to';

  @override
  String paymentUnallocatedNote(String amount) {
    return '$amount reduces the remaining balance owed';
  }

  @override
  String get paymentNothingOwed => 'Nothing is owed right now.';

  @override
  String get paymentReverse => 'Reverse payment';

  @override
  String get paymentReverseConfirmTitle => 'Reverse this payment?';

  @override
  String get paymentReverseConfirmBody =>
      'The money returns to the source account and the covered installments reopen.';

  @override
  String get valPaymentAboveOutstanding =>
      'The payment is larger than the amount owed';

  @override
  String get homeCardsTitle => 'Cards';

  @override
  String get homeDueCurrent => 'Current due';

  @override
  String get homeDueThisMonth => 'This month\'s due';

  @override
  String get homeDueNext => 'Next month\'s due';

  @override
  String get homeDueCurrentWindow => 'Overdue and due today';

  @override
  String homeDueThrough(String date) {
    return 'Due through $date';
  }

  @override
  String homeDueInMonth(String month) {
    return 'Due in $month';
  }

  @override
  String homeDueOn(String date) {
    return 'Due $date';
  }

  @override
  String get homeDueNothing => 'No payments are due through next month.';

  @override
  String homeCardOwed(String amount) {
    return '$amount owed';
  }

  @override
  String homeCardDueBy(String amount, String date) {
    return '$amount due by $date';
  }

  @override
  String get homeCardNothingDue => 'Nothing due this month';

  @override
  String get homeDuesTitle => 'Payments due';

  @override
  String homeDueNow(String amount) {
    return '$amount due now';
  }

  @override
  String homeNextDue(String date) {
    return 'Next due $date';
  }

  @override
  String homeOverdue(String amount) {
    return '$amount overdue';
  }

  @override
  String get reportsDebtTitle => 'Credit & installments';

  @override
  String get reportsDebtRepayments => 'Debt repayments';

  @override
  String get reportsDebtUpcoming => 'Upcoming installments';

  @override
  String get reportsDebtOverdue => 'Overdue';

  @override
  String get reportsDebtOutstanding => 'Outstanding debt';

  @override
  String get errCreditLimitBelowOutstanding =>
      'The credit limit cannot be below the amount owed';

  @override
  String get errFacilityArchiveBlocked =>
      'Money is still owed on this facility';

  @override
  String get errFacilityNotConfigured =>
      'Set a credit limit for this facility first';

  @override
  String get errPlanHasPayments =>
      'Reverse the payments before cancelling this plan';

  @override
  String get errFacilityLocked =>
      'Installment records are managed from the facility screen';

  @override
  String get errAccountRoleLocked =>
      'Create a new account to switch between cash and credit';

  @override
  String get errAlreadyReversed => 'This payment was already reversed';

  @override
  String get errInvalidFinancing =>
      'The financing fees and total payable do not match';

  @override
  String get errAllocationInvalid =>
      'The payment split does not match the open installments';

  @override
  String get facilityReminderDaysHelp =>
      'How many days before each due date the app reminds you.';

  @override
  String get facilityReminderOnDueDay => 'On the due day';

  @override
  String facilityReminderDaysBefore(int days) {
    return '$days days before the due date';
  }

  @override
  String get facilityStatusLabel => 'Card status';

  @override
  String get facilityStatusHelp =>
      'Frozen and closed cards keep their history and debt but cannot fund new purchases.';

  @override
  String get facilityStatusActive => 'Active';

  @override
  String get facilityStatusFrozen => 'Frozen';

  @override
  String get facilityStatusClosed => 'Closed';

  @override
  String get facilityLifecycleTitle => 'Archive or delete';

  @override
  String get facilityLifecycleBody =>
      'Archiving hides the card from pickers while any remaining debt stays visible and payable. Deleting is only possible for a card that never had any activity.';

  @override
  String get facilityArchiveAction => 'Archive card';

  @override
  String get facilityUnarchiveAction => 'Unarchive card';

  @override
  String get facilityDeleteAction => 'Delete card';

  @override
  String get facilityDeleteConfirmTitle => 'Delete this card?';

  @override
  String get facilityDeleteConfirmBody =>
      'Only a card with no purchases, payments, statements, or plans can be deleted. Anything else should be archived so history stays intact.';

  @override
  String get pricingMethodManualFees => 'I know the fees';

  @override
  String get pricingMethodMonthlyAmount => 'I know the monthly amount';

  @override
  String get pricingMethodTotalPayable => 'I know the total payable';

  @override
  String get pricingMethodInterestRate => 'I know the interest rate';

  @override
  String get pricingMethodCardTenorDefault =>
      'Use the card\'s default rate for this term';

  @override
  String get purchaseEditTitle => 'Edit installment plan';

  @override
  String get purchaseDownPaymentSection => 'Paid now';

  @override
  String get purchaseDownPaymentSectionHelp =>
      'The down payment and any upfront fees leave a cash account today; they are never financed.';

  @override
  String get purchaseUpfrontFees => 'Upfront fees';

  @override
  String get purchaseUpfrontFeesHelp =>
      'Admin or processing fees paid in cash today from the same account as the down payment.';

  @override
  String get purchaseFinancingSection => 'Financing';

  @override
  String get purchaseFinancingSectionHelp =>
      'Tell the app whichever number the lender quoted; everything else is derived.';

  @override
  String get purchaseFinancingFeesHelp =>
      'The total extra cost the lender charges on top of the financed amount.';

  @override
  String get purchaseTotalPayableHelp =>
      'Everything you will pay across all installments, as quoted by the lender.';

  @override
  String get purchaseMonthlyAmount => 'Monthly installment';

  @override
  String get purchaseMonthlyAmountHelp =>
      'The exact amount the lender collects each month.';

  @override
  String get purchaseMonthlyRate => 'Monthly interest rate';

  @override
  String get purchaseAnnualRate => 'Annual interest rate';

  @override
  String get purchaseRateHelp => 'As quoted by the bank, e.g. 2.5 for 2.5%.';

  @override
  String get purchaseRatePeriod => 'Rate period';

  @override
  String get purchaseRatePerMonth => 'Per month';

  @override
  String get purchaseRatePerYear => 'Per year';

  @override
  String get purchaseInterestMethod => 'Interest method';

  @override
  String get purchaseInterestMethodHelp =>
      'Flat charges the rate on the full amount every month; reducing charges it on the remaining balance.';

  @override
  String get purchaseInterestFlat => 'Flat';

  @override
  String get purchaseInterestReducing => 'Reducing balance';

  @override
  String get purchaseImportSection => 'Already running plan';

  @override
  String get purchaseImportSectionHelp =>
      'Track a plan you started before using the app: mark the installments you already paid and only the remainder counts as new debt.';

  @override
  String get purchaseImportToggle => 'I already paid some installments';

  @override
  String get purchasePaidCount => 'Installments already paid';

  @override
  String get purchasePaidCountHelp =>
      'That many dues from the start of the schedule are marked as settled outside the app.';

  @override
  String get purchaseInterest => 'Interest';

  @override
  String purchaseAlreadyPaidPortion(int count) {
    return 'Already paid ($count installments)';
  }

  @override
  String get purchaseRemainingCharge => 'Remaining debt to track';

  @override
  String get valPaidInstallments =>
      'Paid installments must stay below the total count';

  @override
  String get valInterestRate => 'Enter a rate between 0 and 1,000%';

  @override
  String get facilityStatementsSection => 'Card statements';

  @override
  String get facilityNoStatements =>
      'Charges on this card will appear here grouped by statement.';

  @override
  String statementCycleTitle(String date) {
    return 'Statement closing $date';
  }

  @override
  String statementDueOn(String date) {
    return 'Due $date';
  }

  @override
  String get statementMinimumDue => 'Minimum due';

  @override
  String get statementStatusOpen => 'Open';

  @override
  String get planActionsTooltip => 'Plan actions';

  @override
  String get planEditAction => 'Edit plan';

  @override
  String get planRestructureAction => 'Restructure remaining';

  @override
  String get planRevisionsAction => 'Change history';

  @override
  String get planRestructureTitle => 'Restructure remaining installments';

  @override
  String get planRestructureBody =>
      'Paid installments stay untouched. Spread what is still owed over a new schedule; any extra cost is booked as an expense today.';

  @override
  String get planRestructureRemainingTotal => 'Remaining total';

  @override
  String get planRestructureRemainingCount => 'Remaining installments';

  @override
  String get planRestructureNextDue => 'Next due date';

  @override
  String get planRestructureNote => 'Reason';

  @override
  String get planRevisionsTitle => 'Plan change history';

  @override
  String get planRevisionsEmpty => 'This plan has not been restructured.';

  @override
  String get errFacilityHasHistory =>
      'This card has activity; archive it instead of deleting';

  @override
  String get errFacilityNotActive =>
      'This card is frozen or closed and cannot fund new purchases';

  @override
  String get errCardNotConfigured =>
      'Set the card\'s statement closing day first';

  @override
  String get errPlanControlled =>
      'This purchase belongs to an installment plan; edit it from the plan';

  @override
  String get errFeeChargeLocked =>
      'This charge comes from a card fee rule; change the rule instead';

  @override
  String get errStatementSettled =>
      'That statement is already paid; reverse the payment before correcting it';

  @override
  String get errInvalidKind => 'This record is edited from its own flow';

  @override
  String get errInvalidPaidInstallments =>
      'Paid installments must stay below the total count';

  @override
  String get errPlanPartiallyPaidDue =>
      'Settle the partially paid installment before restructuring';

  @override
  String get purchaseFinancedFees => 'Financed fees';

  @override
  String get purchaseFinancedFeesHelp =>
      'Extra fees rolled into the schedule and paid across the installments.';

  @override
  String get setNotificationsSection => 'Notifications';

  @override
  String get notifDueRemindersTitle => 'Due date reminders';

  @override
  String get notifDueRemindersHelp =>
      'Remind me before installments and card statements fall due.';

  @override
  String get notifOverdueRemindersTitle => 'Overdue alerts';

  @override
  String get notifOverdueRemindersHelp =>
      'Keep alerting me while a payment stays overdue.';

  @override
  String get notifPaymentConfirmationsTitle => 'Payment confirmations';

  @override
  String get notifPaymentConfirmationsHelp =>
      'Notify me when a facility payment is recorded.';

  @override
  String get notifShowAmountsTitle => 'Show amounts in notifications';

  @override
  String get notifShowAmountsHelp =>
      'Off by default so balances never appear on the lock screen.';

  @override
  String get minPaymentLabel => 'Minimum payment';

  @override
  String get minPaymentHelp =>
      'How the minimum due of each monthly statement is calculated.';

  @override
  String get minPaymentFull => 'Full statement balance';

  @override
  String get minPaymentFixed => 'Fixed amount';

  @override
  String get minPaymentPercent => 'Percent of statement';

  @override
  String get minPaymentGreaterOf => 'Greater of fixed or percent';

  @override
  String get minPaymentFixedAmount => 'Minimum fixed amount';

  @override
  String get minPaymentPercentAmount => 'Minimum percent';

  @override
  String get valMinPaymentPercent => 'Enter a percent between 0.01 and 100.';

  @override
  String get fxMarkupLabel => 'Foreign exchange markup';

  @override
  String get fxMarkupHelp =>
      'Charged as a second expense whenever a purchase on this card is flagged in foreign currency.';

  @override
  String get valFxMarkupPercent => 'Enter a percent between 0.01 and 100.';

  @override
  String get feeRulesSection => 'Card fees';

  @override
  String get feeRuleAdd => 'Add fee';

  @override
  String get feeRuleEdit => 'Edit fee';

  @override
  String get feeRuleName => 'Fee name';

  @override
  String get feeRuleType => 'Fee type';

  @override
  String get feeRuleState => 'Status';

  @override
  String get ruleStateConfigured => 'Configured';

  @override
  String get ruleStateUnknown => 'I don\'t know yet';

  @override
  String get ruleStateDisabled => 'Not charged';

  @override
  String get feeRuleUnknownHint =>
      'This fee won\'t be charged until you know the rate. Finance Suit will flag any transaction it affects so you can fill it in later.';

  @override
  String get feeRuleEditRateHint =>
      'To change the rate, delete this fee and add it again with the new rate and start date.';

  @override
  String get feeTypeAnnualMembership => 'Annual membership';

  @override
  String get feeTypeInsurance => 'Insurance';

  @override
  String get feeTypeAdministration => 'Administration';

  @override
  String get feeTypeStampTax => 'Stamp tax';

  @override
  String get feeTypeForeignTransaction => 'Foreign transaction';

  @override
  String get feeTypeCashAdvance => 'Cash advance';

  @override
  String get feeTypeInternationalCashAdvance => 'International cash advance';

  @override
  String get feeTypeWalletFee => 'Wallet load fee';

  @override
  String get feeTypeStatementFee => 'Statement / SMS fee';

  @override
  String get feeTypeEarlySettlement => 'Early settlement fee';

  @override
  String get feeTypeLatePayment => 'Late payment';

  @override
  String get feeTypeOverLimit => 'Over limit';

  @override
  String get feeTypeInstallmentConversion => 'Installment conversion';

  @override
  String get feeTypeOther => 'Other';

  @override
  String get feeRulePercentToggle => 'Percent-based fee';

  @override
  String get feeRulePercentLabel => 'Fee percent';

  @override
  String get feeRulePercentBasis => 'Percent of';

  @override
  String get feeBasisStatementBalance => 'Statement balance';

  @override
  String get feeBasisOutstandingBalance => 'Outstanding balance';

  @override
  String get feeBasisCreditLimit => 'Credit limit';

  @override
  String get feeBasisTransactionAmount => 'Transaction amount';

  @override
  String get feeBasisHighestStatementDueLookback =>
      'Highest of recent statements';

  @override
  String get feeBasisHighestDailyBalance => 'Highest balance in recent months';

  @override
  String get feeBasisRemainingPrincipal => 'Remaining principal';

  @override
  String get feeBasisRemainingOutstanding => 'Remaining amount owed';

  @override
  String get feeRuleMinimum => 'Minimum amount (optional)';

  @override
  String get feeRuleMaximum => 'Maximum amount (optional)';

  @override
  String get feeRuleLookbackCycles => 'Look back this many statements';

  @override
  String get feeRuleLookbackMonths => 'Look back this many months';

  @override
  String get valFeeLookback => 'Enter a number from 1 to 24';

  @override
  String get feeRuleTriggerHint =>
      'Charged automatically when the matching card event happens — no schedule of its own.';

  @override
  String get feeRuleApplyWhen => 'Applies when';

  @override
  String get applyWhenCurrencyDiffers => 'Billed in a foreign currency';

  @override
  String get applyWhenMerchantOutsideHome => 'Merchant outside the country';

  @override
  String get applyWhenEither => 'Foreign currency or foreign merchant';

  @override
  String get applyWhenBoth => 'Foreign currency and foreign merchant';

  @override
  String get applyWhenForeignMerchantHomeCurrency =>
      'Foreign merchant billed in card currency';

  @override
  String get txIsForeignCurrency => 'In foreign currency?';

  @override
  String get txIsForeignCurrencyHelp =>
      'Adds the card\'s foreign exchange markup as a second charge.';

  @override
  String get feeRuleFixedAmount => 'Fee amount';

  @override
  String get feeRuleFrequency => 'Repeats';

  @override
  String get feeFrequencyOnce => 'Once';

  @override
  String get feeFrequencyMonthly => 'Monthly';

  @override
  String get feeFrequencyQuarterly => 'Quarterly';

  @override
  String get feeFrequencyAnnually => 'Annually';

  @override
  String get feeFrequencyPerTransaction => 'Per transaction';

  @override
  String get feeRuleStartsOn => 'First charge date';

  @override
  String feeRuleNextCharge(String date) {
    return 'Next charge $date';
  }

  @override
  String get feeRuleInactive => 'Paused';

  @override
  String get feeRuleDeactivate => 'Pause';

  @override
  String get feeRuleActivate => 'Resume';

  @override
  String get feeRuleDeleteConfirmTitle => 'Delete this fee?';

  @override
  String get feeRuleDeleteConfirmBody =>
      'Future charges stop. Fees already charged stay in your history.';

  @override
  String get feeRulesEmpty =>
      'No fees configured for this card yet. Add the annual membership or insurance fee so it books itself.';

  @override
  String get feeRuleNoCategoriesTitle => 'You need an expense category first';

  @override
  String get feeRuleNoCategoriesBody =>
      'Fees are booked as expenses, so pick or create a category before saving this one.';

  @override
  String get feeRuleAddCategoryAction => 'Add expense category';

  @override
  String feeRulePercentOfBasis(String percent, String basis) {
    return '$percent% of $basis';
  }

  @override
  String get valFeePercent => 'Enter a percent between 0.01 and 1,000.';

  @override
  String get errCategoryInUse =>
      'This category still labels records or has subcategories. Archive it instead, or remove those first.';

  @override
  String get errAlreadyDecided => 'This entry was already handled.';

  @override
  String get catDeleteConfirmTitle => 'Delete this category?';

  @override
  String get catDeleteConfirmBody =>
      'Deletion only works while nothing uses the category. Anything in use should be archived instead.';

  @override
  String get recurringCenterTitle => 'Recurring payments';

  @override
  String get recurringCenterSubtitle =>
      'Automate rent, subscriptions, and monthly savings transfers.';

  @override
  String get recurringPendingTitle => 'Payments waiting for you';

  @override
  String recurringPendingCount(int count) {
    return '$count payments waiting';
  }

  @override
  String get recurringRulesTitle => 'Rules';

  @override
  String get recurringAddRule => 'Add recurring payment';

  @override
  String get recurringEditRule => 'Edit recurring payment';

  @override
  String get recurringEmptyTitle =>
      'No recurring payments yet. Automate rent, subscriptions, or a monthly transfer to savings.';

  @override
  String get recurringKindLabel => 'What repeats';

  @override
  String get recurringKindExpense => 'Expense';

  @override
  String get recurringKindTransfer => 'Transfer between accounts';

  @override
  String get recurringNameLabel => 'Name';

  @override
  String get recurringAmountLabel => 'Amount';

  @override
  String get recurringPayFrom => 'Pay from';

  @override
  String get recurringCardSourceHint =>
      'Card payments land on the card\'s monthly statement, not your cash.';

  @override
  String get recurringFrequencyLabel => 'Repeats';

  @override
  String get recurringFrequencyWeekly => 'Weekly';

  @override
  String get recurringFrequencyMonthly => 'Monthly';

  @override
  String get recurringFrequencyQuarterly => 'Quarterly';

  @override
  String get recurringFrequencyAnnually => 'Annually';

  @override
  String get recurringWeekdayLabel => 'On weekday';

  @override
  String get recurringDayOfMonthLabel => 'On day of month';

  @override
  String get recurringDayOfMonthHelp =>
      'Days 1–28, so every month has the date.';

  @override
  String recurringScheduleOnDay(String frequency, int day) {
    return '$frequency · day $day';
  }

  @override
  String get recurringPaused => 'Paused';

  @override
  String get recurringPause => 'Pause';

  @override
  String get recurringResume => 'Resume';

  @override
  String get recurringPayNow => 'Record payment';

  @override
  String get recurringPaidOn => 'Paid on';

  @override
  String get recurringAcceptTitle => 'Record this payment?';

  @override
  String recurringAcceptHelp(String name) {
    return 'Confirm the amount and date for \"$name\"; the entry is booked exactly like a manual one.';
  }

  @override
  String get recurringAcceptedMessage => 'Payment recorded.';

  @override
  String get recurringSkipTitle => 'Skip this payment?';

  @override
  String get recurringSkipHelp =>
      'Skipping records nothing for this date. The next occurrence still arrives on schedule.';

  @override
  String get recurringDeleteConfirmTitle => 'Delete this rule?';

  @override
  String get recurringDeleteConfirmBody =>
      'Upcoming reminders disappear. Payments already recorded stay in your history.';

  @override
  String incomeRemainderTitle(String name) {
    return '$name — remaining';
  }

  @override
  String incomePartialTrack(String amount) {
    return 'Keep the remaining $amount pending';
  }

  @override
  String get incomePartialTrackHelp =>
      'The shortfall stays on your pending list until you receive it or skip it. Turning this off records only what you entered.';

  @override
  String get incomePartialExtraFirst =>
      'Missing money is taken off your extra-day, overtime, and holiday pay first, so nothing moves to the extra-work account until it arrives. Anything the extra work cannot cover comes off the base salary, and your splits run on what you received.';

  @override
  String get errInvalidPartial =>
      'For a partial acceptance the amount received must be less than the amount owed.';

  @override
  String get aiAutofillButtonLabel => 'Choose from catalog';

  @override
  String get aiAutofillHelperText =>
      'Choose a bank or provider, then select your card or finance product. Its verified public settings will fill this form for you to review.';

  @override
  String get catalogPickerTitle => 'Product catalog';

  @override
  String get catalogSearchBankHint => 'Search banks and providers';

  @override
  String get catalogSearchProductHint => 'Search cards and products';

  @override
  String get catalogUnavailable =>
      'The product catalog is unavailable right now.';

  @override
  String get catalogEmpty => 'No matching catalog products found.';

  @override
  String catalogProductCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count products',
      one: '1 product',
    );
    return '$_temp0';
  }

  @override
  String get aiAutofillCautionText =>
      'Bank terms can change. Finance Suit only uses information it can verify from public sources.';

  @override
  String get aiResearchStatusFinding => 'Finding your product…';

  @override
  String get aiResearchStatusFilling => 'Filling your card settings…';

  @override
  String get aiResearchSheetTitleCard => 'Find your card';

  @override
  String get aiResearchSheetTitleBnpl => 'Find your account';

  @override
  String get aiResearchIssuer => 'Bank / Company';

  @override
  String get aiResearchIssuerHint =>
      'e.g. CIB, NBE, QNB, Banque Misr, ValU, Contact, Souhoola';

  @override
  String get aiResearchCountry => 'Country';

  @override
  String get aiResearchCountryRequired => 'Country is required';

  @override
  String get aiResearchWebsite => 'Bank/company website, if you know it';

  @override
  String get aiResearchInvalidWebsite => 'Enter a valid website address';

  @override
  String get aiResearchProductCard => 'Card / product name';

  @override
  String get aiResearchProductBnpl => 'Product / program name';

  @override
  String get aiResearchTier => 'Tier / variant';

  @override
  String get aiResearchNetwork => 'Network';

  @override
  String get aiResearchNetworkOther => 'Other';

  @override
  String get aiResearchNetworkUnknown => 'I don\'t know';

  @override
  String get aiResearchCurrency => 'Currency, if known';

  @override
  String get aiResearchInvalidCurrency => 'Enter a 3-letter currency code';

  @override
  String get aiResearchActivationDate => 'Issue / activation date, if known';

  @override
  String get aiResearchInvalidDate => 'Enter a date as YYYY-MM-DD';

  @override
  String get aiResearchCreditLimit => 'Credit limit, if known';

  @override
  String get aiResearchFinanceLimit => 'Finance limit, if known';

  @override
  String get aiResearchStatementDay => 'Statement closing day, if known';

  @override
  String get aiResearchDueDay => 'Due day, if known';

  @override
  String get aiResearchTenor => 'Typical installment term (months)';

  @override
  String get aiResearchNotes => 'Anything else we should know?';

  @override
  String get aiResearchNotesHelp =>
      'For example: \"My card is the normal Platinum Mastercard\" or \"My due date is the 17th.\"';

  @override
  String get aiResearchSensitiveWarning =>
      'Do not enter your full card number, CVV, PIN, password, or OTP.';

  @override
  String get aiResearchSubmitCard => 'Find and fill my card';

  @override
  String get aiResearchSubmitBnpl => 'Find and fill my account';

  @override
  String get aiResearchDisambiguationTitle => 'Which one do you have?';

  @override
  String get aiResearchUnableToFind =>
      'We couldn\'t find enough reliable information. You can continue filling the form manually.';

  @override
  String get aiResearchIncompleteMessage =>
      'We filled what we could. Complete the highlighted fields to continue.';

  @override
  String aiResearchCatalogVerifiedOn(String date) {
    return 'Verified from Finance Suit catalog · $date';
  }

  @override
  String get cardPaymentDueDay => 'Payment due day';

  @override
  String get cardStatementCloses => 'Statement closes';

  @override
  String get cardStatementExactDay => 'Exact day';

  @override
  String get cardStatementEndOfMonth => 'End of month';

  @override
  String get cardInstallmentDueDay => 'Installment due day (optional)';

  @override
  String get cardGracePeriodDays => 'Grace period (days)';

  @override
  String get valGracePeriodDays => 'Enter a grace period from 0 to 90 days.';

  @override
  String get minPaymentPercentageBasis => 'Minimum percent applies to';

  @override
  String get minPaymentBasisRevolving => 'Revolving purchases and interest';

  @override
  String get minPaymentBasisStatement => 'Full statement obligation';

  @override
  String get minPaymentIncludeInstallments => 'Include installment dues';

  @override
  String get minPaymentIncludeBankFees => 'Include bank fees';

  @override
  String get minPaymentIncludeOverdue => 'Include overdue obligations';

  @override
  String get purchaseInterestTitle => 'Purchase interest';

  @override
  String get purchaseInterestState => 'Interest terms';

  @override
  String get purchaseInterestStateHelp =>
      'Use unknown when the bank posts actual interest but you do not know the calculation rate.';

  @override
  String get purchaseInterestRate => 'Interest rate';

  @override
  String get purchaseInterestRatePeriod => 'Rate period';

  @override
  String get purchaseInterestPeriodMonthly => 'Per month';

  @override
  String get purchaseInterestPeriodAnnual => 'Per year';

  @override
  String get purchaseInterestAccrual => 'Accrual method';

  @override
  String get purchaseInterestAccrualManual => 'Bank-posted actual amount';

  @override
  String get purchaseInterestAccrualDaily => 'Daily balance calculation';

  @override
  String get purchaseInterestStarts => 'Interest starts from';

  @override
  String get purchaseInterestStartTransaction => 'Transaction date';

  @override
  String get purchaseInterestStartStatement => 'Statement date';

  @override
  String get purchaseInterestStartPaymentDue => 'Payment due date';

  @override
  String get purchaseInterestStartGraceExpiry => 'Grace period expiry';

  @override
  String get purchaseInterestGraceApplies => 'Grace period applies';

  @override
  String get purchaseInterestEffectiveFrom => 'Effective from';

  @override
  String get purchaseInterestCategory => 'Interest expense category';

  @override
  String get valPurchaseInterestRate => 'Enter a rate between 0.01 and 100%.';

  @override
  String get valPurchaseInterestCategory =>
      'Choose an expense category for interest.';

  @override
  String get feeTypePurchaseInterest => 'Purchase interest';

  @override
  String get facilityActivityPurchaseInterest => 'Purchase interest';

  @override
  String get facilityActivityInstallmentInterest => 'Installment interest';

  @override
  String get purchaseImportAsOf => 'Import position as of';

  @override
  String get purchasePaidThrough => 'Paid through';

  @override
  String get purchaseCurrentInstallmentPosted =>
      'Current installment is already posted';

  @override
  String get purchaseBankOutstanding => 'Bank-reported principal outstanding';

  @override
  String get purchaseBankOutstandingHelp =>
      'Use the bank\'s figure when it differs from the calculated remaining principal; the difference is retained for reconciliation.';

  @override
  String get purchaseReconciliationNote => 'Reconciliation note';

  @override
  String get valFutureInstallmentPaid =>
      'A future installment cannot be marked paid unless it was explicitly prepaid.';

  @override
  String get valBankOutstanding =>
      'Enter a positive outstanding amount below the financed principal.';

  @override
  String get planOutstandingPrincipal => 'Outstanding principal';

  @override
  String get planRemainingScheduledPayments => 'Remaining scheduled payments';

  @override
  String get planRemainingFutureInterest => 'Future interest not yet posted';

  @override
  String planInstallmentCounts(int paid, int current, int future) {
    return '$paid paid · $current current · $future future';
  }

  @override
  String get planBilling => 'Plan & Billing';

  @override
  String get proEarlyAccess => 'Pro Early Access';

  @override
  String get proIncludedEarlyAccess =>
      'Pro features are currently included during Early Access.';

  @override
  String get complimentaryAccess => 'Complimentary access';

  @override
  String get noExpiration => 'No expiration';

  @override
  String availableUntil(String date) {
    return 'Available until: $date';
  }

  @override
  String daysRemaining(int days) {
    return '$days days remaining';
  }

  @override
  String get proMonthly => 'Pro · Monthly';

  @override
  String get proAnnual => 'Pro · Annual';

  @override
  String get proComplimentary => 'Pro · Complimentary';

  @override
  String get proEarlyAccessSummary => 'Pro · Early Access';

  @override
  String get freePlan => 'Free';

  @override
  String get proPlan => 'Pro';

  @override
  String get subscriptionUpgradePrompt => 'click here to upgrade';

  @override
  String get subscriptionUpgradeFromFree => 'Upgrade from Free';

  @override
  String get billingNotReady =>
      'Billing is not ready yet. Pro is included during Early Access.';
}
