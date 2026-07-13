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
  String get commonApply => 'Apply';

  @override
  String get commonAdd => 'Add';

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
  String get onbStepSalary => 'Salary';

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
  String get setAppearance => 'Appearance';

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
  String get txAccount => 'Account';

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
  String get heldOwedTo => 'Owed to';

  @override
  String get heldTotal => 'Total held';

  @override
  String get heldEmpty =>
      'No held amounts yet. Track money you owe someone, on its own or linked to a transaction.';

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
      'Only this record is removed; transactions are not changed.';

  @override
  String get catManage => 'Manage categories';

  @override
  String get catNew => 'New category';

  @override
  String get catName => 'Category name';

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
}
