import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Work Tracker'**
  String get appTitle;

  /// No description provided for @tabHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get tabHome;

  /// No description provided for @tabWork.
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get tabWork;

  /// No description provided for @tabMoney.
  ///
  /// In en, this message translates to:
  /// **'Money'**
  String get tabMoney;

  /// No description provided for @tabReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get tabReports;

  /// No description provided for @tabSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tabSettings;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get commonConfirm;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get commonNext;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get commonUndo;

  /// No description provided for @commonAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get commonAll;

  /// No description provided for @commonNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get commonNone;

  /// No description provided for @commonOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get commonOptional;

  /// No description provided for @commonError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get commonError;

  /// No description provided for @commonLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get commonLoading;

  /// No description provided for @commonEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get commonEmpty;

  /// No description provided for @commonOffline.
  ///
  /// In en, this message translates to:
  /// **'You appear to be offline. Check your connection and retry.'**
  String get commonOffline;

  /// No description provided for @commonNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get commonNotes;

  /// No description provided for @commonAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get commonAmount;

  /// No description provided for @commonDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get commonDate;

  /// No description provided for @commonToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get commonToday;

  /// No description provided for @commonSeeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get commonSeeAll;

  /// No description provided for @commonApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get commonApply;

  /// No description provided for @errInvalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Incorrect email or password.'**
  String get errInvalidCredentials;

  /// No description provided for @errEmailNotConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Please confirm your email address first.'**
  String get errEmailNotConfirmed;

  /// No description provided for @errDuplicateEmail.
  ///
  /// In en, this message translates to:
  /// **'An account with this email already exists.'**
  String get errDuplicateEmail;

  /// No description provided for @errWeakPassword.
  ///
  /// In en, this message translates to:
  /// **'Password is too weak. Use at least 8 characters.'**
  String get errWeakPassword;

  /// No description provided for @errExpiredLink.
  ///
  /// In en, this message translates to:
  /// **'This link is invalid, expired, or already used. Request a new one.'**
  String get errExpiredLink;

  /// No description provided for @errRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please wait a moment and try again.'**
  String get errRateLimited;

  /// No description provided for @errSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Please log in again.'**
  String get errSessionExpired;

  /// No description provided for @errAuthGeneric.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed. Please try again.'**
  String get errAuthGeneric;

  /// No description provided for @errNotAuthorized.
  ///
  /// In en, this message translates to:
  /// **'You are not allowed to perform this action.'**
  String get errNotAuthorized;

  /// No description provided for @errTimeout.
  ///
  /// In en, this message translates to:
  /// **'The request timed out. Please try again.'**
  String get errTimeout;

  /// No description provided for @errConstraint.
  ///
  /// In en, this message translates to:
  /// **'This change conflicts with existing data.'**
  String get errConstraint;

  /// No description provided for @errNotFound.
  ///
  /// In en, this message translates to:
  /// **'The requested item was not found.'**
  String get errNotFound;

  /// No description provided for @errRealtime.
  ///
  /// In en, this message translates to:
  /// **'Live updates are temporarily unavailable.'**
  String get errRealtime;

  /// No description provided for @errInsufficientFunds.
  ///
  /// In en, this message translates to:
  /// **'This account does not allow a negative balance.'**
  String get errInsufficientFunds;

  /// No description provided for @errCurrencyMismatch.
  ///
  /// In en, this message translates to:
  /// **'Both accounts must use the same currency.'**
  String get errCurrencyMismatch;

  /// No description provided for @errSameAccounts.
  ///
  /// In en, this message translates to:
  /// **'Source and destination accounts must differ.'**
  String get errSameAccounts;

  /// No description provided for @errAccountUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The selected account is unavailable or archived.'**
  String get errAccountUnavailable;

  /// No description provided for @errAlreadyPaid.
  ///
  /// In en, this message translates to:
  /// **'This salary period has already been paid.'**
  String get errAlreadyPaid;

  /// No description provided for @errNotFinalized.
  ///
  /// In en, this message translates to:
  /// **'Finalize the salary period before recording payment.'**
  String get errNotFinalized;

  /// No description provided for @errInvalidAmount.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount.'**
  String get errInvalidAmount;

  /// No description provided for @valRequired.
  ///
  /// In en, this message translates to:
  /// **'This field is required.'**
  String get valRequired;

  /// No description provided for @valInvalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get valInvalidEmail;

  /// No description provided for @valPasswordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters.'**
  String get valPasswordTooShort;

  /// No description provided for @valPasswordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match.'**
  String get valPasswordsDoNotMatch;

  /// No description provided for @valAmountNotPositive.
  ///
  /// In en, this message translates to:
  /// **'Amount must be greater than zero.'**
  String get valAmountNotPositive;

  /// No description provided for @valInvalidDate.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid date.'**
  String get valInvalidDate;

  /// No description provided for @valStartAfterEnd.
  ///
  /// In en, this message translates to:
  /// **'Start date must not be after end date.'**
  String get valStartAfterEnd;

  /// No description provided for @valInvalidDuration.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid duration.'**
  String get valInvalidDuration;

  /// No description provided for @valBreakTooLong.
  ///
  /// In en, this message translates to:
  /// **'Break must be shorter than the total duration.'**
  String get valBreakTooLong;

  /// No description provided for @valTooLong.
  ///
  /// In en, this message translates to:
  /// **'Text is too long.'**
  String get valTooLong;

  /// No description provided for @valInvalidMultiplier.
  ///
  /// In en, this message translates to:
  /// **'Multiplier must be between 0% and 1000%.'**
  String get valInvalidMultiplier;

  /// No description provided for @valInvalidDayFraction.
  ///
  /// In en, this message translates to:
  /// **'Day fraction must be between 0.01 and 2.'**
  String get valInvalidDayFraction;

  /// No description provided for @valInvalidDayOfMonth.
  ///
  /// In en, this message translates to:
  /// **'Choose a day between 1 and 28.'**
  String get valInvalidDayOfMonth;

  /// No description provided for @authLoginTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get authLoginTitle;

  /// No description provided for @authLoginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Log in to your account'**
  String get authLoginSubtitle;

  /// No description provided for @authEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmail;

  /// No description provided for @authPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPassword;

  /// No description provided for @authConfirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get authConfirmPassword;

  /// No description provided for @authFullName.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get authFullName;

  /// No description provided for @authLogin.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get authLogin;

  /// No description provided for @authRegister.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authRegister;

  /// No description provided for @authRegisterTitle.
  ///
  /// In en, this message translates to:
  /// **'Create your account'**
  String get authRegisterTitle;

  /// No description provided for @authForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get authForgotPassword;

  /// No description provided for @authNoAccount.
  ///
  /// In en, this message translates to:
  /// **'No account yet? Register'**
  String get authNoAccount;

  /// No description provided for @authHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Log in'**
  String get authHaveAccount;

  /// No description provided for @authForgotTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset your password'**
  String get authForgotTitle;

  /// No description provided for @authForgotSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your email and we will send you a reset link.'**
  String get authForgotSubtitle;

  /// No description provided for @authSendResetLink.
  ///
  /// In en, this message translates to:
  /// **'Send reset link'**
  String get authSendResetLink;

  /// No description provided for @authResetSent.
  ///
  /// In en, this message translates to:
  /// **'If an account exists for this email, a reset link has been sent.'**
  String get authResetSent;

  /// No description provided for @authResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Set a new password'**
  String get authResetTitle;

  /// No description provided for @authNewPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get authNewPassword;

  /// No description provided for @authUpdatePassword.
  ///
  /// In en, this message translates to:
  /// **'Update password'**
  String get authUpdatePassword;

  /// No description provided for @authPasswordUpdated.
  ///
  /// In en, this message translates to:
  /// **'Your password has been updated.'**
  String get authPasswordUpdated;

  /// No description provided for @authConfirmEmailTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm your email'**
  String get authConfirmEmailTitle;

  /// No description provided for @authConfirmEmailBody.
  ///
  /// In en, this message translates to:
  /// **'We sent a confirmation link to {email}. Open it on this device to activate your account.'**
  String authConfirmEmailBody(String email);

  /// No description provided for @authResend.
  ///
  /// In en, this message translates to:
  /// **'Resend email'**
  String get authResend;

  /// No description provided for @authResendIn.
  ///
  /// In en, this message translates to:
  /// **'Resend available in {seconds}s'**
  String authResendIn(int seconds);

  /// No description provided for @authResendDone.
  ///
  /// In en, this message translates to:
  /// **'Confirmation email sent again.'**
  String get authResendDone;

  /// No description provided for @authChangeEmail.
  ///
  /// In en, this message translates to:
  /// **'Use a different email'**
  String get authChangeEmail;

  /// No description provided for @authLogout.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get authLogout;

  /// No description provided for @authPasswordStrengthWeak.
  ///
  /// In en, this message translates to:
  /// **'Weak password'**
  String get authPasswordStrengthWeak;

  /// No description provided for @authPasswordStrengthFair.
  ///
  /// In en, this message translates to:
  /// **'Fair password'**
  String get authPasswordStrengthFair;

  /// No description provided for @authPasswordStrengthStrong.
  ///
  /// In en, this message translates to:
  /// **'Strong password'**
  String get authPasswordStrengthStrong;

  /// No description provided for @onbStepProfile.
  ///
  /// In en, this message translates to:
  /// **'About you'**
  String get onbStepProfile;

  /// No description provided for @onbStepSalary.
  ///
  /// In en, this message translates to:
  /// **'Salary'**
  String get onbStepSalary;

  /// No description provided for @onbStepAccount.
  ///
  /// In en, this message translates to:
  /// **'First account'**
  String get onbStepAccount;

  /// No description provided for @onbStepReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get onbStepReview;

  /// No description provided for @onbWelcome.
  ///
  /// In en, this message translates to:
  /// **'Let\'s set up your workspace'**
  String get onbWelcome;

  /// No description provided for @onbLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get onbLanguage;

  /// No description provided for @onbCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get onbCurrency;

  /// No description provided for @onbTimezone.
  ///
  /// In en, this message translates to:
  /// **'Timezone'**
  String get onbTimezone;

  /// No description provided for @onbWeekStart.
  ///
  /// In en, this message translates to:
  /// **'Week starts on'**
  String get onbWeekStart;

  /// No description provided for @onbWeekendDays.
  ///
  /// In en, this message translates to:
  /// **'Weekend days'**
  String get onbWeekendDays;

  /// No description provided for @onbStepProgress.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String onbStepProgress(int current, int total);

  /// No description provided for @onbReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review your setup'**
  String get onbReviewTitle;

  /// No description provided for @onbFinish.
  ///
  /// In en, this message translates to:
  /// **'Finish setup'**
  String get onbFinish;

  /// No description provided for @salBaseSalary.
  ///
  /// In en, this message translates to:
  /// **'Base salary'**
  String get salBaseSalary;

  /// No description provided for @salPeriodStartDay.
  ///
  /// In en, this message translates to:
  /// **'Period start day'**
  String get salPeriodStartDay;

  /// No description provided for @salPaymentDay.
  ///
  /// In en, this message translates to:
  /// **'Payment day'**
  String get salPaymentDay;

  /// No description provided for @salPaymentMonthOffset.
  ///
  /// In en, this message translates to:
  /// **'Payment month'**
  String get salPaymentMonthOffset;

  /// No description provided for @salOffsetSameMonth.
  ///
  /// In en, this message translates to:
  /// **'Same month'**
  String get salOffsetSameMonth;

  /// No description provided for @salOffsetNextMonth.
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get salOffsetNextMonth;

  /// No description provided for @salOffsetSecondMonth.
  ///
  /// In en, this message translates to:
  /// **'Two months later'**
  String get salOffsetSecondMonth;

  /// No description provided for @salStandardPaidDays.
  ///
  /// In en, this message translates to:
  /// **'Standard paid days per period'**
  String get salStandardPaidDays;

  /// No description provided for @salStandardHours.
  ///
  /// In en, this message translates to:
  /// **'Standard hours per day'**
  String get salStandardHours;

  /// No description provided for @salDayRate.
  ///
  /// In en, this message translates to:
  /// **'Day rate'**
  String get salDayRate;

  /// No description provided for @salHourRate.
  ///
  /// In en, this message translates to:
  /// **'Hourly rate'**
  String get salHourRate;

  /// No description provided for @salRateDerived.
  ///
  /// In en, this message translates to:
  /// **'Derived automatically'**
  String get salRateDerived;

  /// No description provided for @salRateManual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get salRateManual;

  /// No description provided for @salManualDayRate.
  ///
  /// In en, this message translates to:
  /// **'Manual day rate'**
  String get salManualDayRate;

  /// No description provided for @salManualHourRate.
  ///
  /// In en, this message translates to:
  /// **'Manual hourly rate'**
  String get salManualHourRate;

  /// No description provided for @salMultipliers.
  ///
  /// In en, this message translates to:
  /// **'Multipliers'**
  String get salMultipliers;

  /// No description provided for @salExtraDayMultiplier.
  ///
  /// In en, this message translates to:
  /// **'Extra day multiplier (%)'**
  String get salExtraDayMultiplier;

  /// No description provided for @salHolidayMultiplier.
  ///
  /// In en, this message translates to:
  /// **'Holiday multiplier (%)'**
  String get salHolidayMultiplier;

  /// No description provided for @salOvertimeMultiplier.
  ///
  /// In en, this message translates to:
  /// **'Overtime multiplier (%)'**
  String get salOvertimeMultiplier;

  /// No description provided for @salHolidaySemantics.
  ///
  /// In en, this message translates to:
  /// **'Holiday pay semantics'**
  String get salHolidaySemantics;

  /// No description provided for @salSemanticsAdditional.
  ///
  /// In en, this message translates to:
  /// **'Additional pay on top of base'**
  String get salSemanticsAdditional;

  /// No description provided for @salSemanticsTotal.
  ///
  /// In en, this message translates to:
  /// **'Total including base'**
  String get salSemanticsTotal;

  /// No description provided for @salDerivedDayRate.
  ///
  /// In en, this message translates to:
  /// **'Derived day rate: {amount}'**
  String salDerivedDayRate(String amount);

  /// No description provided for @salDerivedHourRate.
  ///
  /// In en, this message translates to:
  /// **'Derived hourly rate: {amount}'**
  String salDerivedHourRate(String amount);

  /// No description provided for @accName.
  ///
  /// In en, this message translates to:
  /// **'Account name'**
  String get accName;

  /// No description provided for @accType.
  ///
  /// In en, this message translates to:
  /// **'Account type'**
  String get accType;

  /// No description provided for @accTypeCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current balance'**
  String get accTypeCurrent;

  /// No description provided for @accTypeSavings.
  ///
  /// In en, this message translates to:
  /// **'Savings'**
  String get accTypeSavings;

  /// No description provided for @accTypeCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get accTypeCash;

  /// No description provided for @accTypeBank.
  ///
  /// In en, this message translates to:
  /// **'Bank'**
  String get accTypeBank;

  /// No description provided for @accTypeWallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get accTypeWallet;

  /// No description provided for @accTypeEmergency.
  ///
  /// In en, this message translates to:
  /// **'Emergency fund'**
  String get accTypeEmergency;

  /// No description provided for @accTypeVacation.
  ///
  /// In en, this message translates to:
  /// **'Vacation fund'**
  String get accTypeVacation;

  /// No description provided for @accTypeCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get accTypeCustom;

  /// No description provided for @accOpeningBalance.
  ///
  /// In en, this message translates to:
  /// **'Opening balance'**
  String get accOpeningBalance;

  /// No description provided for @accAllowNegative.
  ///
  /// In en, this message translates to:
  /// **'Allow negative balance'**
  String get accAllowNegative;

  /// No description provided for @setAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get setAppearance;

  /// No description provided for @setTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get setTheme;

  /// No description provided for @setThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get setThemeSystem;

  /// No description provided for @setThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get setThemeLight;

  /// No description provided for @setThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get setThemeDark;

  /// No description provided for @setProfileSection.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get setProfileSection;

  /// No description provided for @setDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get setDisplayName;

  /// No description provided for @setChangePassword.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get setChangePassword;

  /// No description provided for @setChangeEmail.
  ///
  /// In en, this message translates to:
  /// **'Change email'**
  String get setChangeEmail;

  /// No description provided for @setNewEmail.
  ///
  /// In en, this message translates to:
  /// **'New email'**
  String get setNewEmail;

  /// No description provided for @setEmailChangeSent.
  ///
  /// In en, this message translates to:
  /// **'A confirmation link was sent to the new email.'**
  String get setEmailChangeSent;

  /// No description provided for @setSalarySection.
  ///
  /// In en, this message translates to:
  /// **'Salary settings'**
  String get setSalarySection;

  /// No description provided for @setPreferencesSection.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get setPreferencesSection;

  /// No description provided for @setAccountSection.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get setAccountSection;

  /// No description provided for @setSignOutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Log out?'**
  String get setSignOutConfirmTitle;

  /// No description provided for @setSignOutConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'You can log back in anytime.'**
  String get setSignOutConfirmBody;

  /// No description provided for @setSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get setSaved;

  /// No description provided for @moneyAccountsTab.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get moneyAccountsTab;

  /// No description provided for @moneyTransactionsTab.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get moneyTransactionsTab;

  /// No description provided for @moneyTotalBalance.
  ///
  /// In en, this message translates to:
  /// **'Total balance'**
  String get moneyTotalBalance;

  /// No description provided for @moneyNewAccount.
  ///
  /// In en, this message translates to:
  /// **'New account'**
  String get moneyNewAccount;

  /// No description provided for @moneyEditAccount.
  ///
  /// In en, this message translates to:
  /// **'Edit account'**
  String get moneyEditAccount;

  /// No description provided for @moneyNoAccounts.
  ///
  /// In en, this message translates to:
  /// **'No accounts yet. Add one to start tracking.'**
  String get moneyNoAccounts;

  /// No description provided for @moneyNoTransactions.
  ///
  /// In en, this message translates to:
  /// **'No transactions yet.'**
  String get moneyNoTransactions;

  /// No description provided for @moneyDefaultLabel.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get moneyDefaultLabel;

  /// No description provided for @moneyArchivedLabel.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get moneyArchivedLabel;

  /// No description provided for @moneySetDefault.
  ///
  /// In en, this message translates to:
  /// **'Set as default'**
  String get moneySetDefault;

  /// No description provided for @moneyArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get moneyArchive;

  /// No description provided for @moneyUnarchive.
  ///
  /// In en, this message translates to:
  /// **'Unarchive'**
  String get moneyUnarchive;

  /// No description provided for @moneyShowArchived.
  ///
  /// In en, this message translates to:
  /// **'Show archived'**
  String get moneyShowArchived;

  /// No description provided for @moneyArchiveConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Archive account?'**
  String get moneyArchiveConfirmTitle;

  /// No description provided for @moneyArchiveConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Archived accounts are hidden from pickers and cannot receive new transactions. Existing history stays intact.'**
  String get moneyArchiveConfirmBody;

  /// No description provided for @txExpense.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get txExpense;

  /// No description provided for @txAllowance.
  ///
  /// In en, this message translates to:
  /// **'Allowance'**
  String get txAllowance;

  /// No description provided for @txCustomIncome.
  ///
  /// In en, this message translates to:
  /// **'Other income'**
  String get txCustomIncome;

  /// No description provided for @txFreelanceIncome.
  ///
  /// In en, this message translates to:
  /// **'Freelance income'**
  String get txFreelanceIncome;

  /// No description provided for @txSalaryIncome.
  ///
  /// In en, this message translates to:
  /// **'Salary'**
  String get txSalaryIncome;

  /// No description provided for @txTransfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get txTransfer;

  /// No description provided for @txAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add transaction'**
  String get txAddTitle;

  /// No description provided for @txEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit transaction'**
  String get txEditTitle;

  /// No description provided for @txAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get txAccount;

  /// No description provided for @txFromAccount.
  ///
  /// In en, this message translates to:
  /// **'From account'**
  String get txFromAccount;

  /// No description provided for @txToAccount.
  ///
  /// In en, this message translates to:
  /// **'To account'**
  String get txToAccount;

  /// No description provided for @txCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get txCategory;

  /// No description provided for @txNoCategory.
  ///
  /// In en, this message translates to:
  /// **'No category'**
  String get txNoCategory;

  /// No description provided for @txCounterparty.
  ///
  /// In en, this message translates to:
  /// **'Given to'**
  String get txCounterparty;

  /// No description provided for @txTitleField.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get txTitleField;

  /// No description provided for @txDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete transaction?'**
  String get txDeleteConfirmTitle;

  /// No description provided for @txDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently removes the transaction and updates account balances.'**
  String get txDeleteConfirmBody;

  /// No description provided for @txSalaryLocked.
  ///
  /// In en, this message translates to:
  /// **'Salary payments are managed from salary periods and cannot be edited here.'**
  String get txSalaryLocked;

  /// No description provided for @catManage.
  ///
  /// In en, this message translates to:
  /// **'Manage categories'**
  String get catManage;

  /// No description provided for @catNew.
  ///
  /// In en, this message translates to:
  /// **'New category'**
  String get catNew;

  /// No description provided for @catName.
  ///
  /// In en, this message translates to:
  /// **'Category name'**
  String get catName;

  /// No description provided for @catKindExpense.
  ///
  /// In en, this message translates to:
  /// **'Expense category'**
  String get catKindExpense;

  /// No description provided for @catKindAllowance.
  ///
  /// In en, this message translates to:
  /// **'Allowance category'**
  String get catKindAllowance;

  /// No description provided for @catKindIncome.
  ///
  /// In en, this message translates to:
  /// **'Income category'**
  String get catKindIncome;

  /// No description provided for @catNoneYet.
  ///
  /// In en, this message translates to:
  /// **'No categories of this kind yet.'**
  String get catNoneYet;

  /// No description provided for @salPeriodsTitle.
  ///
  /// In en, this message translates to:
  /// **'Salary periods'**
  String get salPeriodsTitle;

  /// No description provided for @salCurrentPeriod.
  ///
  /// In en, this message translates to:
  /// **'Current period'**
  String get salCurrentPeriod;

  /// No description provided for @salEstimatedFor.
  ///
  /// In en, this message translates to:
  /// **'Estimated {month} salary'**
  String salEstimatedFor(String month);

  /// No description provided for @salBasedOn.
  ///
  /// In en, this message translates to:
  /// **'Based on work from {start} to {end}'**
  String salBasedOn(String start, String end);

  /// No description provided for @salExpectedPayment.
  ///
  /// In en, this message translates to:
  /// **'Expected payment: {date}'**
  String salExpectedPayment(String date);

  /// No description provided for @salStatusOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get salStatusOpen;

  /// No description provided for @salStatusFinalized.
  ///
  /// In en, this message translates to:
  /// **'Finalized'**
  String get salStatusFinalized;

  /// No description provided for @salStatusPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get salStatusPaid;

  /// No description provided for @salBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Breakdown'**
  String get salBreakdown;

  /// No description provided for @salEstimatedTotal.
  ///
  /// In en, this message translates to:
  /// **'Estimated total'**
  String get salEstimatedTotal;

  /// No description provided for @salItemExtraDays.
  ///
  /// In en, this message translates to:
  /// **'Extra days'**
  String get salItemExtraDays;

  /// No description provided for @salItemHolidays.
  ///
  /// In en, this message translates to:
  /// **'Official holidays worked'**
  String get salItemHolidays;

  /// No description provided for @salItemOvertime.
  ///
  /// In en, this message translates to:
  /// **'Overtime'**
  String get salItemOvertime;

  /// No description provided for @salItemBonuses.
  ///
  /// In en, this message translates to:
  /// **'Bonuses'**
  String get salItemBonuses;

  /// No description provided for @salItemDeductions.
  ///
  /// In en, this message translates to:
  /// **'Deductions'**
  String get salItemDeductions;

  /// No description provided for @salAdjustments.
  ///
  /// In en, this message translates to:
  /// **'Adjustments'**
  String get salAdjustments;

  /// No description provided for @salNewAdjustment.
  ///
  /// In en, this message translates to:
  /// **'New adjustment'**
  String get salNewAdjustment;

  /// No description provided for @salEditAdjustment.
  ///
  /// In en, this message translates to:
  /// **'Edit adjustment'**
  String get salEditAdjustment;

  /// No description provided for @salAdjBonus.
  ///
  /// In en, this message translates to:
  /// **'Bonus'**
  String get salAdjBonus;

  /// No description provided for @salAdjDeduction.
  ///
  /// In en, this message translates to:
  /// **'Deduction'**
  String get salAdjDeduction;

  /// No description provided for @salEffectiveDate.
  ///
  /// In en, this message translates to:
  /// **'Effective date'**
  String get salEffectiveDate;

  /// No description provided for @salNoAdjustments.
  ///
  /// In en, this message translates to:
  /// **'No adjustments in this period.'**
  String get salNoAdjustments;

  /// No description provided for @salDeleteAdjTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete adjustment?'**
  String get salDeleteAdjTitle;

  /// No description provided for @salDeleteAdjBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently removes the adjustment.'**
  String get salDeleteAdjBody;

  /// No description provided for @salFinalize.
  ///
  /// In en, this message translates to:
  /// **'Finalize period'**
  String get salFinalize;

  /// No description provided for @salFinalizeConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Finalize this period?'**
  String get salFinalizeConfirmTitle;

  /// No description provided for @salFinalizeConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'An immutable snapshot of the current calculation will be stored. Later settings changes will not affect it.'**
  String get salFinalizeConfirmBody;

  /// No description provided for @salReopen.
  ///
  /// In en, this message translates to:
  /// **'Reopen period'**
  String get salReopen;

  /// No description provided for @salReopenConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Reopen this period?'**
  String get salReopenConfirmTitle;

  /// No description provided for @salReopenConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The stored snapshot will be replaced when you finalize again.'**
  String get salReopenConfirmBody;

  /// No description provided for @salMarkPaid.
  ///
  /// In en, this message translates to:
  /// **'Mark as paid'**
  String get salMarkPaid;

  /// No description provided for @salActualAmount.
  ///
  /// In en, this message translates to:
  /// **'Actual amount received'**
  String get salActualAmount;

  /// No description provided for @salReceivedDate.
  ///
  /// In en, this message translates to:
  /// **'Received date'**
  String get salReceivedDate;

  /// No description provided for @salDestinationAccount.
  ///
  /// In en, this message translates to:
  /// **'Destination account'**
  String get salDestinationAccount;

  /// No description provided for @salActualReceived.
  ///
  /// In en, this message translates to:
  /// **'Actual received'**
  String get salActualReceived;

  /// No description provided for @salDifference.
  ///
  /// In en, this message translates to:
  /// **'Difference vs estimate'**
  String get salDifference;

  /// No description provided for @salNoPeriods.
  ///
  /// In en, this message translates to:
  /// **'No salary periods yet.'**
  String get salNoPeriods;

  /// No description provided for @salWarnBaseZero.
  ///
  /// In en, this message translates to:
  /// **'Base salary is not configured yet.'**
  String get salWarnBaseZero;

  /// No description provided for @salWarnMissingAmounts.
  ///
  /// In en, this message translates to:
  /// **'Some work entries have no stored amount.'**
  String get salWarnMissingAmounts;

  /// No description provided for @workEntryType.
  ///
  /// In en, this message translates to:
  /// **'Entry type'**
  String get workEntryType;

  /// No description provided for @workEntryRegular.
  ///
  /// In en, this message translates to:
  /// **'Regular day'**
  String get workEntryRegular;

  /// No description provided for @workEntryOvertime.
  ///
  /// In en, this message translates to:
  /// **'Overtime'**
  String get workEntryOvertime;

  /// No description provided for @workEntryExtraDay.
  ///
  /// In en, this message translates to:
  /// **'Extra day'**
  String get workEntryExtraDay;

  /// No description provided for @workEntryHoliday.
  ///
  /// In en, this message translates to:
  /// **'Holiday worked'**
  String get workEntryHoliday;

  /// No description provided for @workAddEntry.
  ///
  /// In en, this message translates to:
  /// **'Add work entry'**
  String get workAddEntry;

  /// No description provided for @workEditEntry.
  ///
  /// In en, this message translates to:
  /// **'Edit work entry'**
  String get workEditEntry;

  /// No description provided for @workNoEntries.
  ///
  /// In en, this message translates to:
  /// **'No work entries this month.'**
  String get workNoEntries;

  /// No description provided for @workNoEntriesForDay.
  ///
  /// In en, this message translates to:
  /// **'No entries on this day.'**
  String get workNoEntriesForDay;

  /// No description provided for @workStartTime.
  ///
  /// In en, this message translates to:
  /// **'Start time'**
  String get workStartTime;

  /// No description provided for @workEndTime.
  ///
  /// In en, this message translates to:
  /// **'End time'**
  String get workEndTime;

  /// No description provided for @workBreakMinutes.
  ///
  /// In en, this message translates to:
  /// **'Break (minutes)'**
  String get workBreakMinutes;

  /// No description provided for @workDurationMinutes.
  ///
  /// In en, this message translates to:
  /// **'Duration (minutes)'**
  String get workDurationMinutes;

  /// No description provided for @workDayUnits.
  ///
  /// In en, this message translates to:
  /// **'Days worked (e.g. 1 or 0.5)'**
  String get workDayUnits;

  /// No description provided for @workMultiplier.
  ///
  /// In en, this message translates to:
  /// **'Multiplier %'**
  String get workMultiplier;

  /// No description provided for @workCustomRate.
  ///
  /// In en, this message translates to:
  /// **'Custom rate'**
  String get workCustomRate;

  /// No description provided for @workLinkedHoliday.
  ///
  /// In en, this message translates to:
  /// **'Official holiday'**
  String get workLinkedHoliday;

  /// No description provided for @workEstimatedPay.
  ///
  /// In en, this message translates to:
  /// **'Estimated extra pay'**
  String get workEstimatedPay;

  /// No description provided for @workHolidays.
  ///
  /// In en, this message translates to:
  /// **'Official holidays'**
  String get workHolidays;

  /// No description provided for @workNewHoliday.
  ///
  /// In en, this message translates to:
  /// **'New holiday'**
  String get workNewHoliday;

  /// No description provided for @workEditHoliday.
  ///
  /// In en, this message translates to:
  /// **'Edit holiday'**
  String get workEditHoliday;

  /// No description provided for @workHolidayName.
  ///
  /// In en, this message translates to:
  /// **'Holiday name'**
  String get workHolidayName;

  /// No description provided for @workNoHolidays.
  ///
  /// In en, this message translates to:
  /// **'No official holidays yet.'**
  String get workNoHolidays;

  /// No description provided for @workDeleteEntryTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete work entry?'**
  String get workDeleteEntryTitle;

  /// No description provided for @workDeleteEntryBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently removes the work entry.'**
  String get workDeleteEntryBody;

  /// No description provided for @workDeleteHolidayTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete holiday?'**
  String get workDeleteHolidayTitle;

  /// No description provided for @workDeleteHolidayBody.
  ///
  /// In en, this message translates to:
  /// **'Linked work entries keep their recorded pay but lose the holiday link.'**
  String get workDeleteHolidayBody;

  /// No description provided for @workMonthTotal.
  ///
  /// In en, this message translates to:
  /// **'Extra pay this month'**
  String get workMonthTotal;

  /// No description provided for @workDurationHm.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String workDurationHm(int hours, int minutes);

  /// No description provided for @homeBalance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get homeBalance;

  /// No description provided for @homeDefaultAccount.
  ///
  /// In en, this message translates to:
  /// **'Default account'**
  String get homeDefaultAccount;

  /// No description provided for @homeSavings.
  ///
  /// In en, this message translates to:
  /// **'Savings'**
  String get homeSavings;

  /// No description provided for @homeCashFlow.
  ///
  /// In en, this message translates to:
  /// **'Cash flow'**
  String get homeCashFlow;

  /// No description provided for @homeSalary.
  ///
  /// In en, this message translates to:
  /// **'Salary'**
  String get homeSalary;

  /// No description provided for @homeRecentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get homeRecentActivity;

  /// No description provided for @homeQuickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick actions'**
  String get homeQuickActions;

  /// No description provided for @homeNoRecentActivity.
  ///
  /// In en, this message translates to:
  /// **'No recent activity.'**
  String get homeNoRecentActivity;

  /// No description provided for @homeAddExpense.
  ///
  /// In en, this message translates to:
  /// **'Add expense'**
  String get homeAddExpense;

  /// No description provided for @homeGiveAllowance.
  ///
  /// In en, this message translates to:
  /// **'Give allowance'**
  String get homeGiveAllowance;

  /// No description provided for @homeAddIncome.
  ///
  /// In en, this message translates to:
  /// **'Add income'**
  String get homeAddIncome;

  /// No description provided for @homeTransfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer money'**
  String get homeTransfer;

  /// No description provided for @homeAddOvertime.
  ///
  /// In en, this message translates to:
  /// **'Add overtime'**
  String get homeAddOvertime;

  /// No description provided for @homeAddExtraDay.
  ///
  /// In en, this message translates to:
  /// **'Add extra day'**
  String get homeAddExtraDay;

  /// No description provided for @homeAddHoliday.
  ///
  /// In en, this message translates to:
  /// **'Add holiday worked'**
  String get homeAddHoliday;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTitle;

  /// No description provided for @historyNoItems.
  ///
  /// In en, this message translates to:
  /// **'No records match these filters.'**
  String get historyNoItems;

  /// No description provided for @historyLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get historyLoadMore;

  /// No description provided for @historyBusinessDate.
  ///
  /// In en, this message translates to:
  /// **'Business date'**
  String get historyBusinessDate;

  /// No description provided for @historyActiveFilters.
  ///
  /// In en, this message translates to:
  /// **'Active filters'**
  String get historyActiveFilters;

  /// No description provided for @historyCustomRange.
  ///
  /// In en, this message translates to:
  /// **'Custom range'**
  String get historyCustomRange;

  /// No description provided for @historySortRecordDesc.
  ///
  /// In en, this message translates to:
  /// **'Newest business date'**
  String get historySortRecordDesc;

  /// No description provided for @historySortRecordAsc.
  ///
  /// In en, this message translates to:
  /// **'Oldest business date'**
  String get historySortRecordAsc;

  /// No description provided for @historySortAmountDesc.
  ///
  /// In en, this message translates to:
  /// **'Highest amount'**
  String get historySortAmountDesc;

  /// No description provided for @historySortAmountAsc.
  ///
  /// In en, this message translates to:
  /// **'Lowest amount'**
  String get historySortAmountAsc;

  /// No description provided for @historySortCreatedDesc.
  ///
  /// In en, this message translates to:
  /// **'Newest created'**
  String get historySortCreatedDesc;

  /// No description provided for @historyFilterWork.
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get historyFilterWork;

  /// No description provided for @historyFilterRegularWork.
  ///
  /// In en, this message translates to:
  /// **'Regular work'**
  String get historyFilterRegularWork;

  /// No description provided for @historyFilterSalaryAdjustment.
  ///
  /// In en, this message translates to:
  /// **'Salary adjustment'**
  String get historyFilterSalaryAdjustment;

  /// No description provided for @rangeCurrentMonth.
  ///
  /// In en, this message translates to:
  /// **'Current month'**
  String get rangeCurrentMonth;

  /// No description provided for @rangeLast30.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get rangeLast30;

  /// No description provided for @rangePreviousMonth.
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get rangePreviousMonth;

  /// No description provided for @rangeLast90.
  ///
  /// In en, this message translates to:
  /// **'Last 90 days'**
  String get rangeLast90;

  /// No description provided for @rangeToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get rangeToday;

  /// No description provided for @rangeLast7.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get rangeLast7;

  /// No description provided for @rangeCurrentYear.
  ///
  /// In en, this message translates to:
  /// **'Current year'**
  String get rangeCurrentYear;

  /// No description provided for @reportsCashFlow.
  ///
  /// In en, this message translates to:
  /// **'Income, expenses and allowances'**
  String get reportsCashFlow;

  /// No description provided for @reportsNetOverTime.
  ///
  /// In en, this message translates to:
  /// **'Net cash flow over time'**
  String get reportsNetOverTime;

  /// No description provided for @reportsExpensesByCategory.
  ///
  /// In en, this message translates to:
  /// **'Expenses by category'**
  String get reportsExpensesByCategory;

  /// No description provided for @reportsAllowancesByCategory.
  ///
  /// In en, this message translates to:
  /// **'Allowances by category'**
  String get reportsAllowancesByCategory;

  /// No description provided for @reportsIncomeByCategory.
  ///
  /// In en, this message translates to:
  /// **'Income by source'**
  String get reportsIncomeByCategory;

  /// No description provided for @reportsAccountBalance.
  ///
  /// In en, this message translates to:
  /// **'Account balance over time'**
  String get reportsAccountBalance;

  /// No description provided for @reportsSalaryComparison.
  ///
  /// In en, this message translates to:
  /// **'Estimated vs actual salary'**
  String get reportsSalaryComparison;

  /// No description provided for @reportsWorkCompensation.
  ///
  /// In en, this message translates to:
  /// **'Work compensation by salary period'**
  String get reportsWorkCompensation;

  /// No description provided for @reportsWorkingHours.
  ///
  /// In en, this message translates to:
  /// **'Working hours'**
  String get reportsWorkingHours;

  /// No description provided for @reportsNoData.
  ///
  /// In en, this message translates to:
  /// **'No report data in this range.'**
  String get reportsNoData;

  /// No description provided for @reportsBucketDay.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get reportsBucketDay;

  /// No description provided for @reportsBucketWeek.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get reportsBucketWeek;

  /// No description provided for @reportsBucketMonth.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get reportsBucketMonth;

  /// No description provided for @reportIncome.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get reportIncome;

  /// No description provided for @reportExpenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get reportExpenses;

  /// No description provided for @reportAllowances.
  ///
  /// In en, this message translates to:
  /// **'Allowances'**
  String get reportAllowances;

  /// No description provided for @reportNet.
  ///
  /// In en, this message translates to:
  /// **'Net'**
  String get reportNet;

  /// No description provided for @reportEstimated.
  ///
  /// In en, this message translates to:
  /// **'Estimated'**
  String get reportEstimated;

  /// No description provided for @reportActual.
  ///
  /// In en, this message translates to:
  /// **'Actual'**
  String get reportActual;

  /// No description provided for @reportOvertime.
  ///
  /// In en, this message translates to:
  /// **'Overtime'**
  String get reportOvertime;

  /// No description provided for @reportExtraDays.
  ///
  /// In en, this message translates to:
  /// **'Extra days'**
  String get reportExtraDays;

  /// No description provided for @reportHolidays.
  ///
  /// In en, this message translates to:
  /// **'Holidays'**
  String get reportHolidays;

  /// No description provided for @reportHours.
  ///
  /// In en, this message translates to:
  /// **'Hours'**
  String get reportHours;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
