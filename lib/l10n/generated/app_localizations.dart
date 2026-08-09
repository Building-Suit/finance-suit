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
  /// **'Finance Suit'**
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

  /// No description provided for @menuOpenTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open menu'**
  String get menuOpenTooltip;

  /// No description provided for @menuCloseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Close menu'**
  String get menuCloseTooltip;

  /// No description provided for @menuNavigationLabel.
  ///
  /// In en, this message translates to:
  /// **'Navigation menu'**
  String get menuNavigationLabel;

  /// No description provided for @menuGroupGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get menuGroupGeneral;

  /// No description provided for @menuGroupAutomation.
  ///
  /// In en, this message translates to:
  /// **'Automation'**
  String get menuGroupAutomation;

  /// No description provided for @menuCategories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get menuCategories;

  /// No description provided for @globalAddLabel.
  ///
  /// In en, this message translates to:
  /// **'Add new item'**
  String get globalAddLabel;

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

  /// No description provided for @commonAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// No description provided for @addSectionMoneyControl.
  ///
  /// In en, this message translates to:
  /// **'Money Control'**
  String get addSectionMoneyControl;

  /// No description provided for @addSectionWorkControl.
  ///
  /// In en, this message translates to:
  /// **'Work Control'**
  String get addSectionWorkControl;

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
  /// **'Income source'**
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

  /// No description provided for @accHideFromHome.
  ///
  /// In en, this message translates to:
  /// **'Hide from the Home tab'**
  String get accHideFromHome;

  /// No description provided for @accHideFromHomeHelp.
  ///
  /// In en, this message translates to:
  /// **'The account stays available everywhere else — Money tab, pickers, and reports.'**
  String get accHideFromHomeHelp;

  /// No description provided for @txCardOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open card settings'**
  String get txCardOpenSettings;

  /// No description provided for @setAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get setAppearance;

  /// No description provided for @setSecurity.
  ///
  /// In en, this message translates to:
  /// **'Privacy and security'**
  String get setSecurity;

  /// No description provided for @privacyMoneyTitle.
  ///
  /// In en, this message translates to:
  /// **'Hide money amounts'**
  String get privacyMoneyTitle;

  /// No description provided for @privacyMoneyHelp.
  ///
  /// In en, this message translates to:
  /// **'Blur balances and amounts. Tap a hidden amount and confirm with fingerprint, face, or your phone screen lock to reveal it.'**
  String get privacyMoneyHelp;

  /// No description provided for @privacyAppLockTitle.
  ///
  /// In en, this message translates to:
  /// **'Lock Finance Suit with device security'**
  String get privacyAppLockTitle;

  /// No description provided for @privacyAppLockHelp.
  ///
  /// In en, this message translates to:
  /// **'Require fingerprint, face, PIN, pattern, password, or passcode when opening or returning to the app.'**
  String get privacyAppLockHelp;

  /// No description provided for @privacyBiometricLoginTitle.
  ///
  /// In en, this message translates to:
  /// **'Login with fingerprint or device security'**
  String get privacyBiometricLoginTitle;

  /// No description provided for @privacyBiometricLoginHelp.
  ///
  /// In en, this message translates to:
  /// **'After you log out, sign in again with fingerprint, face, PIN, pattern, password, or passcode without replacing email and password login.'**
  String get privacyBiometricLoginHelp;

  /// No description provided for @privacyDeviceAuthUnavailableHelp.
  ///
  /// In en, this message translates to:
  /// **'Set up a PIN, password, passcode, pattern, fingerprint, or face unlock on this phone to use these options.'**
  String get privacyDeviceAuthUnavailableHelp;

  /// No description provided for @privacyDeviceAuthUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Device security is not available. Set up a phone screen lock first.'**
  String get privacyDeviceAuthUnavailable;

  /// No description provided for @privacyDeviceAuthFailed.
  ///
  /// In en, this message translates to:
  /// **'We could not confirm your identity. Try again.'**
  String get privacyDeviceAuthFailed;

  /// No description provided for @privacyEnableMoneyReason.
  ///
  /// In en, this message translates to:
  /// **'Confirm your identity to protect financial amounts in Finance Suit.'**
  String get privacyEnableMoneyReason;

  /// No description provided for @privacyEnableAppLockReason.
  ///
  /// In en, this message translates to:
  /// **'Confirm your identity to enable Finance Suit app lock.'**
  String get privacyEnableAppLockReason;

  /// No description provided for @privacyEnableBiometricLoginReason.
  ///
  /// In en, this message translates to:
  /// **'Confirm your identity to enable secure quick login for Finance Suit.'**
  String get privacyEnableBiometricLoginReason;

  /// No description provided for @privacyConfirmPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm your Finance Suit password'**
  String get privacyConfirmPasswordTitle;

  /// No description provided for @privacyConfirmPasswordHelp.
  ///
  /// In en, this message translates to:
  /// **'Enter your current password once to securely set up quick login on this phone.'**
  String get privacyConfirmPasswordHelp;

  /// No description provided for @privacyIncorrectPassword.
  ///
  /// In en, this message translates to:
  /// **'That password is incorrect. Quick login was not enabled.'**
  String get privacyIncorrectPassword;

  /// No description provided for @privacyDisableMoneyReason.
  ///
  /// In en, this message translates to:
  /// **'Confirm your identity to stop hiding financial amounts in Finance Suit.'**
  String get privacyDisableMoneyReason;

  /// No description provided for @privacyDisableAppLockReason.
  ///
  /// In en, this message translates to:
  /// **'Confirm your identity to disable Finance Suit app lock.'**
  String get privacyDisableAppLockReason;

  /// No description provided for @privacyDisableBiometricLoginReason.
  ///
  /// In en, this message translates to:
  /// **'Confirm your identity to disable secure quick login for Finance Suit.'**
  String get privacyDisableBiometricLoginReason;

  /// No description provided for @privacyRevealReason.
  ///
  /// In en, this message translates to:
  /// **'Confirm your identity to reveal financial amounts in Finance Suit.'**
  String get privacyRevealReason;

  /// No description provided for @privacyShowAmountsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Show money amounts'**
  String get privacyShowAmountsTooltip;

  /// No description provided for @privacyHideAmountsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Hide money amounts'**
  String get privacyHideAmountsTooltip;

  /// No description provided for @privacyHiddenAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Hidden financial amount'**
  String get privacyHiddenAmountLabel;

  /// No description provided for @privacyRevealAmountHint.
  ///
  /// In en, this message translates to:
  /// **'Authenticate with biometrics or the phone screen lock to reveal it'**
  String get privacyRevealAmountHint;

  /// No description provided for @privacyUnlockReason.
  ///
  /// In en, this message translates to:
  /// **'Confirm your identity to unlock Finance Suit.'**
  String get privacyUnlockReason;

  /// No description provided for @privacyUnlockTitle.
  ///
  /// In en, this message translates to:
  /// **'Finance Suit is locked'**
  String get privacyUnlockTitle;

  /// No description provided for @privacyUnlockBody.
  ///
  /// In en, this message translates to:
  /// **'Use fingerprint, face recognition, or your phone PIN, pattern, password, or passcode.'**
  String get privacyUnlockBody;

  /// No description provided for @privacyUnlockButton.
  ///
  /// In en, this message translates to:
  /// **'Unlock with device security'**
  String get privacyUnlockButton;

  /// No description provided for @privacyUsePassword.
  ///
  /// In en, this message translates to:
  /// **'Use Finance Suit password instead'**
  String get privacyUsePassword;

  /// No description provided for @authBiometricLogin.
  ///
  /// In en, this message translates to:
  /// **'Login with fingerprint or device security'**
  String get authBiometricLogin;

  /// No description provided for @authBiometricLoginReason.
  ///
  /// In en, this message translates to:
  /// **'Confirm your identity to login to Finance Suit.'**
  String get authBiometricLoginReason;

  /// No description provided for @authBiometricSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Secure quick login has expired. Login with your email and password, then enable it again in Settings.'**
  String get authBiometricSessionExpired;

  /// No description provided for @authBiometricLoginFailed.
  ///
  /// In en, this message translates to:
  /// **'Secure quick login failed. Try again or use your email and password.'**
  String get authBiometricLoginFailed;

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

  /// No description provided for @setAboutSection.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get setAboutSection;

  /// No description provided for @setAppVersion.
  ///
  /// In en, this message translates to:
  /// **'App version'**
  String get setAppVersion;

  /// No description provided for @setPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get setPrivacyPolicy;

  /// No description provided for @setTerms.
  ///
  /// In en, this message translates to:
  /// **'Terms and conditions'**
  String get setTerms;

  /// No description provided for @setDeleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get setDeleteAccount;

  /// No description provided for @setDeleteAccountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete your account and app data'**
  String get setDeleteAccountSubtitle;

  /// No description provided for @deleteAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete your account'**
  String get deleteAccountTitle;

  /// No description provided for @deleteAccountWarning.
  ///
  /// In en, this message translates to:
  /// **'This action is permanent and cannot be undone.'**
  String get deleteAccountWarning;

  /// No description provided for @deleteAccountDataList.
  ///
  /// In en, this message translates to:
  /// **'Your Finance Suit profile, salary settings, work records, accounts, categories, transactions, macros, and held amounts will be deleted. Your shared sign-in and other portal data will be kept.'**
  String get deleteAccountDataList;

  /// No description provided for @deleteAccountPasswordPrompt.
  ///
  /// In en, this message translates to:
  /// **'Confirm your password'**
  String get deleteAccountPasswordPrompt;

  /// No description provided for @deleteAccountAcknowledge.
  ///
  /// In en, this message translates to:
  /// **'I understand that my Finance Suit profile and data will be permanently deleted.'**
  String get deleteAccountAcknowledge;

  /// No description provided for @deleteAccountFinalTitle.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete account?'**
  String get deleteAccountFinalTitle;

  /// No description provided for @deleteAccountFinalBody.
  ///
  /// In en, this message translates to:
  /// **'Finance Suit will delete your Finance Suit profile and active app data now. Your shared sign-in and other portal data will remain, and you will be logged out on this device.'**
  String get deleteAccountFinalBody;

  /// No description provided for @deleteAccountConfirmButton.
  ///
  /// In en, this message translates to:
  /// **'Delete my account'**
  String get deleteAccountConfirmButton;

  /// No description provided for @deleteAccountFailure.
  ///
  /// In en, this message translates to:
  /// **'We could not delete your account. Check your connection and password, then try again or contact support.'**
  String get deleteAccountFailure;

  /// No description provided for @deleteAccountPolicy.
  ///
  /// In en, this message translates to:
  /// **'How account deletion works'**
  String get deleteAccountPolicy;

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

  /// No description provided for @txAccountUnavailable.
  ///
  /// In en, this message translates to:
  /// **'unavailable'**
  String get txAccountUnavailable;

  /// No description provided for @txAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get txAccount;

  /// No description provided for @txClearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get txClearFilters;

  /// No description provided for @txFilterNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No transactions match these filters.'**
  String get txFilterNoMatches;

  /// No description provided for @txFilters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get txFilters;

  /// No description provided for @txApplyWithCount.
  ///
  /// In en, this message translates to:
  /// **'Apply ({count})'**
  String txApplyWithCount(int count);

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

  /// No description provided for @macrosTitle.
  ///
  /// In en, this message translates to:
  /// **'Macros'**
  String get macrosTitle;

  /// No description provided for @macroManage.
  ///
  /// In en, this message translates to:
  /// **'Manage macros'**
  String get macroManage;

  /// No description provided for @macroNew.
  ///
  /// In en, this message translates to:
  /// **'New macro'**
  String get macroNew;

  /// No description provided for @macroEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit macro'**
  String get macroEditTitle;

  /// No description provided for @macroName.
  ///
  /// In en, this message translates to:
  /// **'Macro name'**
  String get macroName;

  /// No description provided for @macroActions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get macroActions;

  /// No description provided for @macroAddAction.
  ///
  /// In en, this message translates to:
  /// **'Add action'**
  String get macroAddAction;

  /// No description provided for @macroNoActions.
  ///
  /// In en, this message translates to:
  /// **'Add at least one action.'**
  String get macroNoActions;

  /// No description provided for @macroReversible.
  ///
  /// In en, this message translates to:
  /// **'Reversible'**
  String get macroReversible;

  /// No description provided for @macroReversibleHint.
  ///
  /// In en, this message translates to:
  /// **'Include this action when the macro runs in reverse'**
  String get macroReversibleHint;

  /// No description provided for @macroReversibleBadge.
  ///
  /// In en, this message translates to:
  /// **'Reversible'**
  String get macroReversibleBadge;

  /// No description provided for @macroRun.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get macroRun;

  /// No description provided for @macroRunReverse.
  ///
  /// In en, this message translates to:
  /// **'Run in reverse'**
  String get macroRunReverse;

  /// No description provided for @macroRunTo.
  ///
  /// In en, this message translates to:
  /// **'To {name}'**
  String macroRunTo(String name);

  /// No description provided for @macroRunFrom.
  ///
  /// In en, this message translates to:
  /// **'From {name}'**
  String macroRunFrom(String name);

  /// No description provided for @macroApplied.
  ///
  /// In en, this message translates to:
  /// **'{count} transactions added'**
  String macroApplied(int count);

  /// No description provided for @macroActionCount.
  ///
  /// In en, this message translates to:
  /// **'{count} actions'**
  String macroActionCount(int count);

  /// No description provided for @macroEmpty.
  ///
  /// In en, this message translates to:
  /// **'No macros yet. Save repeated transactions and run them in one tap.'**
  String get macroEmpty;

  /// No description provided for @macroDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete macro?'**
  String get macroDeleteConfirmTitle;

  /// No description provided for @macroDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This removes the macro and its actions. Transactions it created are kept.'**
  String get macroDeleteConfirmBody;

  /// No description provided for @errMacroNotReversible.
  ///
  /// In en, this message translates to:
  /// **'This macro has no reversible actions.'**
  String get errMacroNotReversible;

  /// No description provided for @errMacroEmpty.
  ///
  /// In en, this message translates to:
  /// **'A macro needs at least one action.'**
  String get errMacroEmpty;

  /// No description provided for @moneyHeldTab.
  ///
  /// In en, this message translates to:
  /// **'Held'**
  String get moneyHeldTab;

  /// No description provided for @heldTitle.
  ///
  /// In en, this message translates to:
  /// **'Held amounts'**
  String get heldTitle;

  /// No description provided for @heldNew.
  ///
  /// In en, this message translates to:
  /// **'New held amount'**
  String get heldNew;

  /// No description provided for @heldEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit held amount'**
  String get heldEditTitle;

  /// No description provided for @heldDirection.
  ///
  /// In en, this message translates to:
  /// **'Direction'**
  String get heldDirection;

  /// No description provided for @heldDirectionIOwe.
  ///
  /// In en, this message translates to:
  /// **'I owe someone'**
  String get heldDirectionIOwe;

  /// No description provided for @heldDirectionOwedToMe.
  ///
  /// In en, this message translates to:
  /// **'Owed to me'**
  String get heldDirectionOwedToMe;

  /// No description provided for @heldOwedTo.
  ///
  /// In en, this message translates to:
  /// **'Owed to'**
  String get heldOwedTo;

  /// No description provided for @heldOwedBy.
  ///
  /// In en, this message translates to:
  /// **'Owed by'**
  String get heldOwedBy;

  /// No description provided for @heldTotalIOwe.
  ///
  /// In en, this message translates to:
  /// **'Total I owe'**
  String get heldTotalIOwe;

  /// No description provided for @heldTotalOwedToMe.
  ///
  /// In en, this message translates to:
  /// **'Total owed to me'**
  String get heldTotalOwedToMe;

  /// No description provided for @heldEmpty.
  ///
  /// In en, this message translates to:
  /// **'No held amounts yet. Track money you owe or money owed to you, on its own or linked to a transaction.'**
  String get heldEmpty;

  /// No description provided for @heldSettle.
  ///
  /// In en, this message translates to:
  /// **'Mark as settled'**
  String get heldSettle;

  /// No description provided for @heldUnsettle.
  ///
  /// In en, this message translates to:
  /// **'Mark as active'**
  String get heldUnsettle;

  /// No description provided for @heldSettledLabel.
  ///
  /// In en, this message translates to:
  /// **'Settled'**
  String get heldSettledLabel;

  /// No description provided for @heldShowSettled.
  ///
  /// In en, this message translates to:
  /// **'Show settled'**
  String get heldShowSettled;

  /// No description provided for @heldLinkedTransaction.
  ///
  /// In en, this message translates to:
  /// **'Linked to a transaction'**
  String get heldLinkedTransaction;

  /// No description provided for @heldHoldForTransaction.
  ///
  /// In en, this message translates to:
  /// **'Hold an amount for this transaction'**
  String get heldHoldForTransaction;

  /// No description provided for @heldDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete held amount?'**
  String get heldDeleteConfirmTitle;

  /// No description provided for @heldDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This removes the held amount. If it created an account transaction, that transaction is also removed and the balance is updated.'**
  String get heldDeleteConfirmBody;

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

  /// No description provided for @catKind.
  ///
  /// In en, this message translates to:
  /// **'Category type'**
  String get catKind;

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

  /// No description provided for @salNoOpenPeriods.
  ///
  /// In en, this message translates to:
  /// **'No open salary periods are available.'**
  String get salNoOpenPeriods;

  /// No description provided for @salPeriodNoLongerOpen.
  ///
  /// In en, this message translates to:
  /// **'This salary period is no longer open. Refresh and choose an open period.'**
  String get salPeriodNoLongerOpen;

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

  /// No description provided for @homeNoRecentActivity.
  ///
  /// In en, this message translates to:
  /// **'No recent activity.'**
  String get homeNoRecentActivity;

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

  /// No description provided for @catParent.
  ///
  /// In en, this message translates to:
  /// **'Parent category (optional)'**
  String get catParent;

  /// No description provided for @catTopLevel.
  ///
  /// In en, this message translates to:
  /// **'No parent — regular category'**
  String get catTopLevel;

  /// No description provided for @catSubcategoryOf.
  ///
  /// In en, this message translates to:
  /// **'Subcategory of {parent}'**
  String catSubcategoryOf(String parent);

  /// No description provided for @catSubcategoryOptional.
  ///
  /// In en, this message translates to:
  /// **'Subcategory (optional)'**
  String get catSubcategoryOptional;

  /// No description provided for @catUseParentCategory.
  ///
  /// In en, this message translates to:
  /// **'No subcategory — use the parent category'**
  String get catUseParentCategory;

  /// No description provided for @catAddSubcategory.
  ///
  /// In en, this message translates to:
  /// **'Add subcategory'**
  String get catAddSubcategory;

  /// No description provided for @catSubcategoryCount.
  ///
  /// In en, this message translates to:
  /// **'{count} subcategories'**
  String catSubcategoryCount(int count);

  /// No description provided for @catMissingParent.
  ///
  /// In en, this message translates to:
  /// **'Missing parent category'**
  String get catMissingParent;

  /// No description provided for @catArchiveChildrenFirst.
  ///
  /// In en, this message translates to:
  /// **'Archive this category\'s active subcategories first.'**
  String get catArchiveChildrenFirst;

  /// No description provided for @catRestoreParentFirst.
  ///
  /// In en, this message translates to:
  /// **'Restore the parent category before restoring this subcategory.'**
  String get catRestoreParentFirst;

  /// No description provided for @incomeHasSalary.
  ///
  /// In en, this message translates to:
  /// **'I receive a salary'**
  String get incomeHasSalary;

  /// No description provided for @incomeHasSalaryHelp.
  ///
  /// In en, this message translates to:
  /// **'Turn this off if your income is allowance-based or comes from other sources.'**
  String get incomeHasSalaryHelp;

  /// No description provided for @incomeSourcesTitle.
  ///
  /// In en, this message translates to:
  /// **'Income automations'**
  String get incomeSourcesTitle;

  /// No description provided for @incomeSourcesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Schedule salary, allowance, and other recurring income'**
  String get incomeSourcesSubtitle;

  /// No description provided for @incomeAddSource.
  ///
  /// In en, this message translates to:
  /// **'Add income source'**
  String get incomeAddSource;

  /// No description provided for @incomeEditSource.
  ///
  /// In en, this message translates to:
  /// **'Edit income source'**
  String get incomeEditSource;

  /// No description provided for @incomeNoSources.
  ///
  /// In en, this message translates to:
  /// **'No automated income sources yet.'**
  String get incomeNoSources;

  /// No description provided for @incomeMonthlyOnDay.
  ///
  /// In en, this message translates to:
  /// **'Monthly on day {day}'**
  String incomeMonthlyOnDay(int day);

  /// No description provided for @incomeSourceType.
  ///
  /// In en, this message translates to:
  /// **'Income type'**
  String get incomeSourceType;

  /// No description provided for @incomeSourceName.
  ///
  /// In en, this message translates to:
  /// **'Income source name'**
  String get incomeSourceName;

  /// No description provided for @incomeExpectedAmount.
  ///
  /// In en, this message translates to:
  /// **'Expected amount'**
  String get incomeExpectedAmount;

  /// No description provided for @incomeRemainderAccount.
  ///
  /// In en, this message translates to:
  /// **'Deposit and remainder account'**
  String get incomeRemainderAccount;

  /// No description provided for @incomePromptBefore.
  ///
  /// In en, this message translates to:
  /// **'Prompt days before'**
  String get incomePromptBefore;

  /// No description provided for @incomeStartDate.
  ///
  /// In en, this message translates to:
  /// **'Automation start date'**
  String get incomeStartDate;

  /// No description provided for @incomeSplitTitle.
  ///
  /// In en, this message translates to:
  /// **'Automatic account split'**
  String get incomeSplitTitle;

  /// No description provided for @incomeSplitHelp.
  ///
  /// In en, this message translates to:
  /// **'Add ordered rules for transfers from the deposit account. Anything left stays in the deposit account.'**
  String get incomeSplitHelp;

  /// No description provided for @incomeInvalidPercentage.
  ///
  /// In en, this message translates to:
  /// **'Enter a percentage from 0 to 100.'**
  String get incomeInvalidPercentage;

  /// No description provided for @incomeSplitAddRule.
  ///
  /// In en, this message translates to:
  /// **'Add split rule'**
  String get incomeSplitAddRule;

  /// No description provided for @incomeSplitNoRules.
  ///
  /// In en, this message translates to:
  /// **'No split rules. The full amount stays in the deposit account.'**
  String get incomeSplitNoRules;

  /// No description provided for @incomeSplitRuleNumber.
  ///
  /// In en, this message translates to:
  /// **'Rule {number}'**
  String incomeSplitRuleNumber(int number);

  /// No description provided for @incomeSplitDestinationAccount.
  ///
  /// In en, this message translates to:
  /// **'Destination account'**
  String get incomeSplitDestinationAccount;

  /// No description provided for @incomeSplitMethod.
  ///
  /// In en, this message translates to:
  /// **'Split method'**
  String get incomeSplitMethod;

  /// No description provided for @incomeSplitMethodPercentage.
  ///
  /// In en, this message translates to:
  /// **'Percentage'**
  String get incomeSplitMethodPercentage;

  /// No description provided for @incomeSplitMethodFixed.
  ///
  /// In en, this message translates to:
  /// **'Fixed amount'**
  String get incomeSplitMethodFixed;

  /// No description provided for @incomeSplitCalculationBasis.
  ///
  /// In en, this message translates to:
  /// **'Percentage basis'**
  String get incomeSplitCalculationBasis;

  /// No description provided for @incomeSplitBasisOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original amount'**
  String get incomeSplitBasisOriginal;

  /// No description provided for @incomeSplitBasisRemaining.
  ///
  /// In en, this message translates to:
  /// **'Remaining amount'**
  String get incomeSplitBasisRemaining;

  /// No description provided for @incomeSplitMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Move rule up'**
  String get incomeSplitMoveUp;

  /// No description provided for @incomeSplitMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Move rule down'**
  String get incomeSplitMoveDown;

  /// No description provided for @incomeSplitInvalidAccount.
  ///
  /// In en, this message translates to:
  /// **'Choose an active account in the same currency.'**
  String get incomeSplitInvalidAccount;

  /// No description provided for @incomeSplitIncludeExtraWork.
  ///
  /// In en, this message translates to:
  /// **'Include extra hours and days in percentage calculations'**
  String get incomeSplitIncludeExtraWork;

  /// No description provided for @incomeSplitIncludeExtraWorkHelp.
  ///
  /// In en, this message translates to:
  /// **'Bonuses and deductions are still treated as ordinary salary.'**
  String get incomeSplitIncludeExtraWorkHelp;

  /// No description provided for @incomeSplitRouteExtraWork.
  ///
  /// In en, this message translates to:
  /// **'Route all protected extra-work earnings to another account'**
  String get incomeSplitRouteExtraWork;

  /// No description provided for @incomeSplitExtraWorkAccount.
  ///
  /// In en, this message translates to:
  /// **'Extra-work destination account'**
  String get incomeSplitExtraWorkAccount;

  /// No description provided for @incomeRolloverTitle.
  ///
  /// In en, this message translates to:
  /// **'Move the previous balance to savings'**
  String get incomeRolloverTitle;

  /// No description provided for @incomeRolloverHelp.
  ///
  /// In en, this message translates to:
  /// **'When this salary is accepted, move any positive balance already in the deposit account to the selected savings account before depositing the salary.'**
  String get incomeRolloverHelp;

  /// No description provided for @incomeRolloverNoSavings.
  ///
  /// In en, this message translates to:
  /// **'Create an active savings account in the same currency to enable this option.'**
  String get incomeRolloverNoSavings;

  /// No description provided for @incomeRolloverAccount.
  ///
  /// In en, this message translates to:
  /// **'Previous-balance destination'**
  String get incomeRolloverAccount;

  /// No description provided for @incomeSplitPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Summary preview'**
  String get incomeSplitPreviewTitle;

  /// No description provided for @incomeSplitPreviewDeposit.
  ///
  /// In en, this message translates to:
  /// **'{amount} enters {account} first.'**
  String incomeSplitPreviewDeposit(String amount, String account);

  /// No description provided for @incomeSplitPreviewPercentageRule.
  ///
  /// In en, this message translates to:
  /// **'Rule {number}: {percentage}% of the {basis} = {amount} to {account}.'**
  String incomeSplitPreviewPercentageRule(
    int number,
    String percentage,
    String basis,
    String amount,
    String account,
  );

  /// No description provided for @incomeSplitPreviewFixedRule.
  ///
  /// In en, this message translates to:
  /// **'Rule {number}: fixed {amount} to {account}.'**
  String incomeSplitPreviewFixedRule(int number, String amount, String account);

  /// No description provided for @incomeSplitPreviewExtraIncluded.
  ///
  /// In en, this message translates to:
  /// **'Extra-work earnings are included in percentage calculations.'**
  String get incomeSplitPreviewExtraIncluded;

  /// No description provided for @incomeSplitPreviewExtraRouted.
  ///
  /// In en, this message translates to:
  /// **'Protected extra-work earnings go to {account}.'**
  String incomeSplitPreviewExtraRouted(String account);

  /// No description provided for @incomeSplitPreviewExtraKept.
  ///
  /// In en, this message translates to:
  /// **'Protected extra-work earnings stay in {account}.'**
  String incomeSplitPreviewExtraKept(String account);

  /// No description provided for @incomeRolloverPreviewMoved.
  ///
  /// In en, this message translates to:
  /// **'Before this salary is deposited, any positive existing balance in {sourceAccount} moves to {destinationAccount}.'**
  String incomeRolloverPreviewMoved(
    String sourceAccount,
    String destinationAccount,
  );

  /// No description provided for @incomeRolloverPreviewKept.
  ///
  /// In en, this message translates to:
  /// **'The existing balance in {account} stays where it is.'**
  String incomeRolloverPreviewKept(String account);

  /// No description provided for @incomeSplitPreviewLine.
  ///
  /// In en, this message translates to:
  /// **'{amount} to {account}'**
  String incomeSplitPreviewLine(String amount, String account);

  /// No description provided for @incomeSplitPreviewRemainder.
  ///
  /// In en, this message translates to:
  /// **'{amount} remains in {account}'**
  String incomeSplitPreviewRemainder(String amount, String account);

  /// No description provided for @incomeSplitPreviewError.
  ///
  /// In en, this message translates to:
  /// **'These rules exceed the available income.'**
  String get incomeSplitPreviewError;

  /// No description provided for @incomeKindSalary.
  ///
  /// In en, this message translates to:
  /// **'Salary'**
  String get incomeKindSalary;

  /// No description provided for @incomeKindAllowance.
  ///
  /// In en, this message translates to:
  /// **'Allowance received'**
  String get incomeKindAllowance;

  /// No description provided for @incomeKindFreelance.
  ///
  /// In en, this message translates to:
  /// **'Freelance income'**
  String get incomeKindFreelance;

  /// No description provided for @incomeKindOther.
  ///
  /// In en, this message translates to:
  /// **'Other income'**
  String get incomeKindOther;

  /// No description provided for @incomeKindNone.
  ///
  /// In en, this message translates to:
  /// **'No regular income for now'**
  String get incomeKindNone;

  /// No description provided for @incomePrimaryType.
  ///
  /// In en, this message translates to:
  /// **'How do you usually receive income?'**
  String get incomePrimaryType;

  /// No description provided for @incomeNoPrimaryHelp.
  ///
  /// In en, this message translates to:
  /// **'You can finish setup without a salary and add any income source later from Settings.'**
  String get incomeNoPrimaryHelp;

  /// No description provided for @incomePendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Income to approve'**
  String get incomePendingTitle;

  /// No description provided for @incomeDue.
  ///
  /// In en, this message translates to:
  /// **'Expected on {date} — confirm when it arrives'**
  String incomeDue(String date);

  /// No description provided for @incomeUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Expected on {date} — you can accept it early'**
  String incomeUpcoming(String date);

  /// No description provided for @incomeAcceptTitle.
  ///
  /// In en, this message translates to:
  /// **'Accept {name}?'**
  String incomeAcceptTitle(String name);

  /// No description provided for @incomeAcceptHelp.
  ///
  /// In en, this message translates to:
  /// **'The income transaction and its account splits are created only after you confirm.'**
  String get incomeAcceptHelp;

  /// No description provided for @incomeAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept income'**
  String get incomeAccept;

  /// No description provided for @incomeSkipTitle.
  ///
  /// In en, this message translates to:
  /// **'Skip this income?'**
  String get incomeSkipTitle;

  /// No description provided for @incomeSkipHelp.
  ///
  /// In en, this message translates to:
  /// **'{name} will not create a transaction for this month.'**
  String incomeSkipHelp(String name);

  /// No description provided for @incomeSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get incomeSkip;

  /// No description provided for @incomeLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get incomeLater;

  /// No description provided for @incomeRemindLater.
  ///
  /// In en, this message translates to:
  /// **'Snoozed for 24 hours.'**
  String get incomeRemindLater;

  /// No description provided for @incomeSnoozeFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not snooze this income. Try again.'**
  String get incomeSnoozeFailed;

  /// No description provided for @incomeAcceptedMessage.
  ///
  /// In en, this message translates to:
  /// **'Income accepted.'**
  String get incomeAcceptedMessage;

  /// No description provided for @incomeSkippedMessage.
  ///
  /// In en, this message translates to:
  /// **'Income skipped.'**
  String get incomeSkippedMessage;

  /// No description provided for @salaryBaseAmount.
  ///
  /// In en, this message translates to:
  /// **'Base amount'**
  String get salaryBaseAmount;

  /// No description provided for @salaryExtraDays.
  ///
  /// In en, this message translates to:
  /// **'Extra days'**
  String get salaryExtraDays;

  /// No description provided for @salaryOvertimeDuration.
  ///
  /// In en, this message translates to:
  /// **'Overtime'**
  String get salaryOvertimeDuration;

  /// No description provided for @salaryHolidayWorked.
  ///
  /// In en, this message translates to:
  /// **'Holiday worked'**
  String get salaryHolidayWorked;

  /// No description provided for @salaryEstimatedTotal.
  ///
  /// In en, this message translates to:
  /// **'Estimated total'**
  String get salaryEstimatedTotal;

  /// No description provided for @durationHoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String durationHoursMinutes(int hours, int minutes);

  /// No description provided for @incomeAutomationCenter.
  ///
  /// In en, this message translates to:
  /// **'Income automations'**
  String get incomeAutomationCenter;

  /// No description provided for @incomeAutomationOverview.
  ///
  /// In en, this message translates to:
  /// **'Set the expected date and account split. Nothing changes your balance until you approve the payment.'**
  String get incomeAutomationOverview;

  /// No description provided for @incomeActiveAutomations.
  ///
  /// In en, this message translates to:
  /// **'Active automations'**
  String get incomeActiveAutomations;

  /// No description provided for @incomePausedAutomations.
  ///
  /// In en, this message translates to:
  /// **'Paused automations'**
  String get incomePausedAutomations;

  /// No description provided for @incomeAutomationEnabled.
  ///
  /// In en, this message translates to:
  /// **'Automation enabled'**
  String get incomeAutomationEnabled;

  /// No description provided for @incomeAutomationEnabledHelp.
  ///
  /// In en, this message translates to:
  /// **'Pause this source without deleting its schedule or split rules.'**
  String get incomeAutomationEnabledHelp;

  /// No description provided for @incomeActiveCount.
  ///
  /// In en, this message translates to:
  /// **'{count} active'**
  String incomeActiveCount(int count);

  /// No description provided for @incomePausedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} paused'**
  String incomePausedCount(int count);

  /// No description provided for @incomePendingCount.
  ///
  /// In en, this message translates to:
  /// **'{count} waiting'**
  String incomePendingCount(int count);

  /// No description provided for @incomeActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get incomeActive;

  /// No description provided for @incomePaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get incomePaused;

  /// No description provided for @incomePause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get incomePause;

  /// No description provided for @incomeResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get incomeResume;

  /// No description provided for @incomeDepositAccount.
  ///
  /// In en, this message translates to:
  /// **'Deposit account: {account}'**
  String incomeDepositAccount(String account);

  /// No description provided for @incomeSplitAccount.
  ///
  /// In en, this message translates to:
  /// **'{percentage}% to {account}'**
  String incomeSplitAccount(String percentage, String account);

  /// No description provided for @incomeSplitFixedAccount.
  ///
  /// In en, this message translates to:
  /// **'{amount} to {account}'**
  String incomeSplitFixedAccount(String amount, String account);

  /// No description provided for @incomeRemainderSplit.
  ///
  /// In en, this message translates to:
  /// **'{percentage}% remains in {account}'**
  String incomeRemainderSplit(String percentage, String account);

  /// No description provided for @incomeNoPending.
  ///
  /// In en, this message translates to:
  /// **'No income is waiting for approval.'**
  String get incomeNoPending;

  /// No description provided for @addSectionAutomationControl.
  ///
  /// In en, this message translates to:
  /// **'Automation Control'**
  String get addSectionAutomationControl;

  /// No description provided for @addAutomation.
  ///
  /// In en, this message translates to:
  /// **'Add automation'**
  String get addAutomation;

  /// No description provided for @manageAutomations.
  ///
  /// In en, this message translates to:
  /// **'Manage automations'**
  String get manageAutomations;

  /// No description provided for @addAutomationControlHelp.
  ///
  /// In en, this message translates to:
  /// **'Schedule salary or recurring income and approve it before balances change.'**
  String get addAutomationControlHelp;

  /// No description provided for @incomeAddAutomationEmpty.
  ///
  /// In en, this message translates to:
  /// **'Add an automation to schedule recurring income. Nothing changes your balance until you approve it.'**
  String get incomeAddAutomationEmpty;

  /// No description provided for @incomeTypeLockedOnEdit.
  ///
  /// In en, this message translates to:
  /// **'Automation type cannot be changed while editing. Create a new automation to use another type.'**
  String get incomeTypeLockedOnEdit;

  /// No description provided for @incomeSalaryAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'A salary automation already exists. Edit or resume it instead.'**
  String get incomeSalaryAlreadyExists;

  /// No description provided for @homePartialDataError.
  ///
  /// In en, this message translates to:
  /// **'Some dashboard sections could not be loaded. Other available data is still shown.'**
  String get homePartialDataError;

  /// No description provided for @reportStartingBalance.
  ///
  /// In en, this message translates to:
  /// **'Starting balance'**
  String get reportStartingBalance;

  /// No description provided for @reportEndingBalance.
  ///
  /// In en, this message translates to:
  /// **'Ending balance'**
  String get reportEndingBalance;

  /// No description provided for @selectionSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search options'**
  String get selectionSearchHint;

  /// No description provided for @heldLinkedTransactionReference.
  ///
  /// In en, this message translates to:
  /// **'Original transaction linked for reference'**
  String get heldLinkedTransactionReference;

  /// No description provided for @heldSettlementTransactionHelp.
  ///
  /// In en, this message translates to:
  /// **'Settlement creates a separate transaction for the selected account.'**
  String get heldSettlementTransactionHelp;

  /// No description provided for @onboardingSubmitFailed.
  ///
  /// In en, this message translates to:
  /// **'Setup could not be completed. Check your entries and try again.'**
  String get onboardingSubmitFailed;

  /// No description provided for @updateAvailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get updateAvailableTitle;

  /// No description provided for @updateAvailableBody.
  ///
  /// In en, this message translates to:
  /// **'A new version of Finance Suit is ready. Update now to get the latest improvements.'**
  String get updateAvailableBody;

  /// No description provided for @updateLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get updateLater;

  /// No description provided for @updateNow.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get updateNow;

  /// No description provided for @heldTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get heldTypeLabel;

  /// No description provided for @heldSettleTitle.
  ///
  /// In en, this message translates to:
  /// **'Settle held amount'**
  String get heldSettleTitle;

  /// No description provided for @heldSettleDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Settlement date'**
  String get heldSettleDateLabel;

  /// No description provided for @heldSettleHelp.
  ///
  /// In en, this message translates to:
  /// **'The transaction will be recorded on this date.'**
  String get heldSettleHelp;

  /// No description provided for @accTypeCreditCard.
  ///
  /// In en, this message translates to:
  /// **'Credit Card'**
  String get accTypeCreditCard;

  /// No description provided for @accTypeBnpl.
  ///
  /// In en, this message translates to:
  /// **'BNPL / Finance Company'**
  String get accTypeBnpl;

  /// No description provided for @accColorLabel.
  ///
  /// In en, this message translates to:
  /// **'Card colour'**
  String get accColorLabel;

  /// No description provided for @accColorDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get accColorDefault;

  /// No description provided for @accColorSwatch.
  ///
  /// In en, this message translates to:
  /// **'Colour {index}'**
  String accColorSwatch(int index);

  /// No description provided for @accOpeningOwed.
  ///
  /// In en, this message translates to:
  /// **'Opening amount owed'**
  String get accOpeningOwed;

  /// No description provided for @accOpeningOwedHelp.
  ///
  /// In en, this message translates to:
  /// **'Debt already used on this facility before you started tracking it in Finance Suit.'**
  String get accOpeningOwedHelp;

  /// No description provided for @facilityCreditLimit.
  ///
  /// In en, this message translates to:
  /// **'Credit limit'**
  String get facilityCreditLimit;

  /// No description provided for @facilityDefaultDueDay.
  ///
  /// In en, this message translates to:
  /// **'Default due day'**
  String get facilityDefaultDueDay;

  /// No description provided for @facilityStatementDay.
  ///
  /// In en, this message translates to:
  /// **'Statement day'**
  String get facilityStatementDay;

  /// No description provided for @facilityLastFour.
  ///
  /// In en, this message translates to:
  /// **'Last four digits'**
  String get facilityLastFour;

  /// No description provided for @facilityReminderDays.
  ///
  /// In en, this message translates to:
  /// **'Reminder lead days'**
  String get facilityReminderDays;

  /// No description provided for @valFacilityLastFour.
  ///
  /// In en, this message translates to:
  /// **'Enter exactly four digits'**
  String get valFacilityLastFour;

  /// No description provided for @valFacilityReminderDays.
  ///
  /// In en, this message translates to:
  /// **'Enter between 0 and 31 days'**
  String get valFacilityReminderDays;

  /// No description provided for @moneyAssetsSection.
  ///
  /// In en, this message translates to:
  /// **'Cash & bank'**
  String get moneyAssetsSection;

  /// No description provided for @moneyLiabilitiesSection.
  ///
  /// In en, this message translates to:
  /// **'Credit & installments'**
  String get moneyLiabilitiesSection;

  /// No description provided for @facilityOwed.
  ///
  /// In en, this message translates to:
  /// **'Amount owed'**
  String get facilityOwed;

  /// No description provided for @facilityAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available credit'**
  String get facilityAvailable;

  /// No description provided for @facilityUtilization.
  ///
  /// In en, this message translates to:
  /// **'Utilization'**
  String get facilityUtilization;

  /// No description provided for @facilityNextDue.
  ///
  /// In en, this message translates to:
  /// **'Next due {date}'**
  String facilityNextDue(String date);

  /// No description provided for @facilityOverdueBadge.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get facilityOverdueBadge;

  /// No description provided for @facilityDueNow.
  ///
  /// In en, this message translates to:
  /// **'Due now'**
  String get facilityDueNow;

  /// No description provided for @facilityDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Credit facility'**
  String get facilityDetailTitle;

  /// No description provided for @facilityAddPurchase.
  ///
  /// In en, this message translates to:
  /// **'Add installment purchase'**
  String get facilityAddPurchase;

  /// No description provided for @facilityMakePayment.
  ///
  /// In en, this message translates to:
  /// **'Make payment'**
  String get facilityMakePayment;

  /// No description provided for @facilityDuesSection.
  ///
  /// In en, this message translates to:
  /// **'Upcoming installments'**
  String get facilityDuesSection;

  /// No description provided for @facilityNoDues.
  ///
  /// In en, this message translates to:
  /// **'Nothing is scheduled on this facility.'**
  String get facilityNoDues;

  /// No description provided for @facilityPlansSection.
  ///
  /// In en, this message translates to:
  /// **'Installment plans'**
  String get facilityPlansSection;

  /// No description provided for @facilityNoPlans.
  ///
  /// In en, this message translates to:
  /// **'No installment plans yet.'**
  String get facilityNoPlans;

  /// No description provided for @facilityHistorySection.
  ///
  /// In en, this message translates to:
  /// **'Related activity'**
  String get facilityHistorySection;

  /// No description provided for @facilityRepaymentLabel.
  ///
  /// In en, this message translates to:
  /// **'Facility payment'**
  String get facilityRepaymentLabel;

  /// No description provided for @facilityReversalLabel.
  ///
  /// In en, this message translates to:
  /// **'Payment reversal'**
  String get facilityReversalLabel;

  /// No description provided for @facilityPurchaseLabel.
  ///
  /// In en, this message translates to:
  /// **'Credit purchase'**
  String get facilityPurchaseLabel;

  /// No description provided for @facilityActivityInstallment.
  ///
  /// In en, this message translates to:
  /// **'Installment purchase'**
  String get facilityActivityInstallment;

  /// No description provided for @facilityActivityDownPayment.
  ///
  /// In en, this message translates to:
  /// **'Installment down payment'**
  String get facilityActivityDownPayment;

  /// No description provided for @facilityActivityFee.
  ///
  /// In en, this message translates to:
  /// **'Card fee'**
  String get facilityActivityFee;

  /// No description provided for @facilityActivityWhyLocked.
  ///
  /// In en, this message translates to:
  /// **'Why can\'t I edit this?'**
  String get facilityActivityWhyLocked;

  /// No description provided for @facilityActivitySettled.
  ///
  /// In en, this message translates to:
  /// **'This charge is already on a paid statement. Reverse the payment first to correct it.'**
  String get facilityActivitySettled;

  /// No description provided for @facilityActivityFeeLocked.
  ///
  /// In en, this message translates to:
  /// **'This charge was generated by a card fee rule. Change the rule instead.'**
  String get facilityActivityFeeLocked;

  /// No description provided for @facilityActivitySystemRecord.
  ///
  /// In en, this message translates to:
  /// **'This is a system record and cannot be edited.'**
  String get facilityActivitySystemRecord;

  /// No description provided for @facilityEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No credit card or BNPL accounts yet'**
  String get facilityEmptyTitle;

  /// No description provided for @facilityEmptyAction.
  ///
  /// In en, this message translates to:
  /// **'Add credit account'**
  String get facilityEmptyAction;

  /// No description provided for @planStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get planStatusActive;

  /// No description provided for @planStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get planStatusCompleted;

  /// No description provided for @planStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get planStatusCancelled;

  /// No description provided for @planPaidOfTotal.
  ///
  /// In en, this message translates to:
  /// **'{paid} of {total} paid'**
  String planPaidOfTotal(String paid, String total);

  /// No description provided for @planBankCostPaid.
  ///
  /// In en, this message translates to:
  /// **'Bank interest & fees: {paid} of {total}'**
  String planBankCostPaid(String paid, String total);

  /// No description provided for @planCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel plan'**
  String get planCancel;

  /// No description provided for @planCancelConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel this plan?'**
  String get planCancelConfirmTitle;

  /// No description provided for @planCancelConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The financed purchase will be removed and its schedule cancelled. This is only possible before any payment.'**
  String get planCancelConfirmBody;

  /// No description provided for @dueStatusUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get dueStatusUpcoming;

  /// No description provided for @dueStatusDueToday.
  ///
  /// In en, this message translates to:
  /// **'Due today'**
  String get dueStatusDueToday;

  /// No description provided for @dueStatusOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get dueStatusOverdue;

  /// No description provided for @dueStatusPartiallyPaid.
  ///
  /// In en, this message translates to:
  /// **'Partially paid'**
  String get dueStatusPartiallyPaid;

  /// No description provided for @dueStatusPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get dueStatusPaid;

  /// No description provided for @dueStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get dueStatusCancelled;

  /// No description provided for @purchaseTitle.
  ///
  /// In en, this message translates to:
  /// **'New installment purchase'**
  String get purchaseTitle;

  /// No description provided for @purchaseFacility.
  ///
  /// In en, this message translates to:
  /// **'Facility'**
  String get purchaseFacility;

  /// No description provided for @purchaseMerchant.
  ///
  /// In en, this message translates to:
  /// **'Merchant or title'**
  String get purchaseMerchant;

  /// No description provided for @purchaseDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Purchase date'**
  String get purchaseDateLabel;

  /// No description provided for @purchasePrice.
  ///
  /// In en, this message translates to:
  /// **'Purchase price'**
  String get purchasePrice;

  /// No description provided for @purchaseDownPayment.
  ///
  /// In en, this message translates to:
  /// **'Down payment'**
  String get purchaseDownPayment;

  /// No description provided for @purchaseDownPaymentAccount.
  ///
  /// In en, this message translates to:
  /// **'Paid from'**
  String get purchaseDownPaymentAccount;

  /// No description provided for @purchaseFinancingMode.
  ///
  /// In en, this message translates to:
  /// **'Financing input'**
  String get purchaseFinancingMode;

  /// No description provided for @purchaseCardTenorDefaultHint.
  ///
  /// In en, this message translates to:
  /// **'The card\'s own rate for this number of months will be used automatically.'**
  String get purchaseCardTenorDefaultHint;

  /// No description provided for @purchaseFinancingModeFees.
  ///
  /// In en, this message translates to:
  /// **'Enter financing fees'**
  String get purchaseFinancingModeFees;

  /// No description provided for @purchaseFinancingModeTotal.
  ///
  /// In en, this message translates to:
  /// **'Enter total payable'**
  String get purchaseFinancingModeTotal;

  /// No description provided for @purchaseFinancingFees.
  ///
  /// In en, this message translates to:
  /// **'Financing fees'**
  String get purchaseFinancingFees;

  /// No description provided for @purchaseTotalPayable.
  ///
  /// In en, this message translates to:
  /// **'Total payable'**
  String get purchaseTotalPayable;

  /// No description provided for @purchaseFinancedPrincipal.
  ///
  /// In en, this message translates to:
  /// **'Financed principal'**
  String get purchaseFinancedPrincipal;

  /// No description provided for @purchaseInstallmentCount.
  ///
  /// In en, this message translates to:
  /// **'Number of installments'**
  String get purchaseInstallmentCount;

  /// No description provided for @purchaseSingleCycleHint.
  ///
  /// In en, this message translates to:
  /// **'One installment means the full amount is due on the next due date.'**
  String get purchaseSingleCycleHint;

  /// No description provided for @purchaseFirstDueDate.
  ///
  /// In en, this message translates to:
  /// **'First due date'**
  String get purchaseFirstDueDate;

  /// No description provided for @purchasePreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'What will be recorded'**
  String get purchasePreviewTitle;

  /// No description provided for @purchaseMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly schedule'**
  String get purchaseMonthly;

  /// No description provided for @purchaseAvailableBefore.
  ///
  /// In en, this message translates to:
  /// **'Available credit now'**
  String get purchaseAvailableBefore;

  /// No description provided for @purchaseAvailableAfter.
  ///
  /// In en, this message translates to:
  /// **'Available after purchase'**
  String get purchaseAvailableAfter;

  /// No description provided for @purchaseExceedsCredit.
  ///
  /// In en, this message translates to:
  /// **'This purchase exceeds the available credit'**
  String get purchaseExceedsCredit;

  /// No description provided for @valDownPaymentTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The down payment must stay below the purchase price'**
  String get valDownPaymentTooLarge;

  /// No description provided for @valTotalBelowFinanced.
  ///
  /// In en, this message translates to:
  /// **'Total payable cannot be below the financed principal'**
  String get valTotalBelowFinanced;

  /// No description provided for @valInstallmentCount.
  ///
  /// In en, this message translates to:
  /// **'Choose between 1 and 120 installments'**
  String get valInstallmentCount;

  /// No description provided for @valCategoryRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose a category'**
  String get valCategoryRequired;

  /// No description provided for @paymentTitle.
  ///
  /// In en, this message translates to:
  /// **'Pay credit facility'**
  String get paymentTitle;

  /// No description provided for @paymentSource.
  ///
  /// In en, this message translates to:
  /// **'Pay from'**
  String get paymentSource;

  /// No description provided for @paymentDate.
  ///
  /// In en, this message translates to:
  /// **'Payment date'**
  String get paymentDate;

  /// No description provided for @paymentDueNowChip.
  ///
  /// In en, this message translates to:
  /// **'Due now'**
  String get paymentDueNowChip;

  /// No description provided for @paymentNextChip.
  ///
  /// In en, this message translates to:
  /// **'Next installment'**
  String get paymentNextChip;

  /// No description provided for @paymentFullChip.
  ///
  /// In en, this message translates to:
  /// **'Full outstanding'**
  String get paymentFullChip;

  /// No description provided for @paymentAllocationPreview.
  ///
  /// In en, this message translates to:
  /// **'Will be applied to'**
  String get paymentAllocationPreview;

  /// No description provided for @paymentUnallocatedNote.
  ///
  /// In en, this message translates to:
  /// **'{amount} reduces the remaining balance owed'**
  String paymentUnallocatedNote(String amount);

  /// No description provided for @paymentNothingOwed.
  ///
  /// In en, this message translates to:
  /// **'Nothing is owed right now.'**
  String get paymentNothingOwed;

  /// No description provided for @paymentReverse.
  ///
  /// In en, this message translates to:
  /// **'Reverse payment'**
  String get paymentReverse;

  /// No description provided for @paymentReverseConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Reverse this payment?'**
  String get paymentReverseConfirmTitle;

  /// No description provided for @paymentReverseConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The money returns to the source account and the covered installments reopen.'**
  String get paymentReverseConfirmBody;

  /// No description provided for @valPaymentAboveOutstanding.
  ///
  /// In en, this message translates to:
  /// **'The payment is larger than the amount owed'**
  String get valPaymentAboveOutstanding;

  /// No description provided for @homeCardsTitle.
  ///
  /// In en, this message translates to:
  /// **'Cards'**
  String get homeCardsTitle;

  /// No description provided for @homeCardOwed.
  ///
  /// In en, this message translates to:
  /// **'{amount} owed'**
  String homeCardOwed(String amount);

  /// No description provided for @homeCardDueBy.
  ///
  /// In en, this message translates to:
  /// **'{amount} due by {date}'**
  String homeCardDueBy(String amount, String date);

  /// No description provided for @homeCardNothingDue.
  ///
  /// In en, this message translates to:
  /// **'Nothing due this month'**
  String get homeCardNothingDue;

  /// No description provided for @homeDuesTitle.
  ///
  /// In en, this message translates to:
  /// **'Installments'**
  String get homeDuesTitle;

  /// No description provided for @homeDueNow.
  ///
  /// In en, this message translates to:
  /// **'{amount} due now'**
  String homeDueNow(String amount);

  /// No description provided for @homeNextDue.
  ///
  /// In en, this message translates to:
  /// **'Next due {date}'**
  String homeNextDue(String date);

  /// No description provided for @homeOverdue.
  ///
  /// In en, this message translates to:
  /// **'{amount} overdue'**
  String homeOverdue(String amount);

  /// No description provided for @reportsDebtTitle.
  ///
  /// In en, this message translates to:
  /// **'Credit & installments'**
  String get reportsDebtTitle;

  /// No description provided for @reportsDebtRepayments.
  ///
  /// In en, this message translates to:
  /// **'Debt repayments'**
  String get reportsDebtRepayments;

  /// No description provided for @reportsDebtUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming installments'**
  String get reportsDebtUpcoming;

  /// No description provided for @reportsDebtOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get reportsDebtOverdue;

  /// No description provided for @reportsDebtOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Outstanding debt'**
  String get reportsDebtOutstanding;

  /// No description provided for @errCreditLimitBelowOutstanding.
  ///
  /// In en, this message translates to:
  /// **'The credit limit cannot be below the amount owed'**
  String get errCreditLimitBelowOutstanding;

  /// No description provided for @errFacilityArchiveBlocked.
  ///
  /// In en, this message translates to:
  /// **'Money is still owed on this facility'**
  String get errFacilityArchiveBlocked;

  /// No description provided for @errFacilityNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Set a credit limit for this facility first'**
  String get errFacilityNotConfigured;

  /// No description provided for @errPlanHasPayments.
  ///
  /// In en, this message translates to:
  /// **'Reverse the payments before cancelling this plan'**
  String get errPlanHasPayments;

  /// No description provided for @errFacilityLocked.
  ///
  /// In en, this message translates to:
  /// **'Installment records are managed from the facility screen'**
  String get errFacilityLocked;

  /// No description provided for @errAccountRoleLocked.
  ///
  /// In en, this message translates to:
  /// **'Create a new account to switch between cash and credit'**
  String get errAccountRoleLocked;

  /// No description provided for @errAlreadyReversed.
  ///
  /// In en, this message translates to:
  /// **'This payment was already reversed'**
  String get errAlreadyReversed;

  /// No description provided for @errInvalidFinancing.
  ///
  /// In en, this message translates to:
  /// **'The financing fees and total payable do not match'**
  String get errInvalidFinancing;

  /// No description provided for @errAllocationInvalid.
  ///
  /// In en, this message translates to:
  /// **'The payment split does not match the open installments'**
  String get errAllocationInvalid;

  /// No description provided for @facilityReminderDaysHelp.
  ///
  /// In en, this message translates to:
  /// **'How many days before each due date the app reminds you.'**
  String get facilityReminderDaysHelp;

  /// No description provided for @facilityReminderOnDueDay.
  ///
  /// In en, this message translates to:
  /// **'On the due day'**
  String get facilityReminderOnDueDay;

  /// No description provided for @facilityReminderDaysBefore.
  ///
  /// In en, this message translates to:
  /// **'{days} days before the due date'**
  String facilityReminderDaysBefore(int days);

  /// No description provided for @facilityStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Card status'**
  String get facilityStatusLabel;

  /// No description provided for @facilityStatusHelp.
  ///
  /// In en, this message translates to:
  /// **'Frozen and closed cards keep their history and debt but cannot fund new purchases.'**
  String get facilityStatusHelp;

  /// No description provided for @facilityStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get facilityStatusActive;

  /// No description provided for @facilityStatusFrozen.
  ///
  /// In en, this message translates to:
  /// **'Frozen'**
  String get facilityStatusFrozen;

  /// No description provided for @facilityStatusClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get facilityStatusClosed;

  /// No description provided for @facilityLifecycleTitle.
  ///
  /// In en, this message translates to:
  /// **'Archive or delete'**
  String get facilityLifecycleTitle;

  /// No description provided for @facilityLifecycleBody.
  ///
  /// In en, this message translates to:
  /// **'Archiving hides the card from pickers while any remaining debt stays visible and payable. Deleting is only possible for a card that never had any activity.'**
  String get facilityLifecycleBody;

  /// No description provided for @facilityArchiveAction.
  ///
  /// In en, this message translates to:
  /// **'Archive card'**
  String get facilityArchiveAction;

  /// No description provided for @facilityUnarchiveAction.
  ///
  /// In en, this message translates to:
  /// **'Unarchive card'**
  String get facilityUnarchiveAction;

  /// No description provided for @facilityDeleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete card'**
  String get facilityDeleteAction;

  /// No description provided for @facilityDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this card?'**
  String get facilityDeleteConfirmTitle;

  /// No description provided for @facilityDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Only a card with no purchases, payments, statements, or plans can be deleted. Anything else should be archived so history stays intact.'**
  String get facilityDeleteConfirmBody;

  /// No description provided for @pricingMethodManualFees.
  ///
  /// In en, this message translates to:
  /// **'I know the fees'**
  String get pricingMethodManualFees;

  /// No description provided for @pricingMethodMonthlyAmount.
  ///
  /// In en, this message translates to:
  /// **'I know the monthly amount'**
  String get pricingMethodMonthlyAmount;

  /// No description provided for @pricingMethodTotalPayable.
  ///
  /// In en, this message translates to:
  /// **'I know the total payable'**
  String get pricingMethodTotalPayable;

  /// No description provided for @pricingMethodInterestRate.
  ///
  /// In en, this message translates to:
  /// **'I know the interest rate'**
  String get pricingMethodInterestRate;

  /// No description provided for @pricingMethodCardTenorDefault.
  ///
  /// In en, this message translates to:
  /// **'Use the card\'s default rate for this term'**
  String get pricingMethodCardTenorDefault;

  /// No description provided for @purchaseEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit installment plan'**
  String get purchaseEditTitle;

  /// No description provided for @purchaseDownPaymentSection.
  ///
  /// In en, this message translates to:
  /// **'Paid now'**
  String get purchaseDownPaymentSection;

  /// No description provided for @purchaseDownPaymentSectionHelp.
  ///
  /// In en, this message translates to:
  /// **'The down payment and any upfront fees leave a cash account today; they are never financed.'**
  String get purchaseDownPaymentSectionHelp;

  /// No description provided for @purchaseUpfrontFees.
  ///
  /// In en, this message translates to:
  /// **'Upfront fees'**
  String get purchaseUpfrontFees;

  /// No description provided for @purchaseUpfrontFeesHelp.
  ///
  /// In en, this message translates to:
  /// **'Admin or processing fees paid in cash today from the same account as the down payment.'**
  String get purchaseUpfrontFeesHelp;

  /// No description provided for @purchaseFinancingSection.
  ///
  /// In en, this message translates to:
  /// **'Financing'**
  String get purchaseFinancingSection;

  /// No description provided for @purchaseFinancingSectionHelp.
  ///
  /// In en, this message translates to:
  /// **'Tell the app whichever number the lender quoted; everything else is derived.'**
  String get purchaseFinancingSectionHelp;

  /// No description provided for @purchaseFinancingFeesHelp.
  ///
  /// In en, this message translates to:
  /// **'The total extra cost the lender charges on top of the financed amount.'**
  String get purchaseFinancingFeesHelp;

  /// No description provided for @purchaseTotalPayableHelp.
  ///
  /// In en, this message translates to:
  /// **'Everything you will pay across all installments, as quoted by the lender.'**
  String get purchaseTotalPayableHelp;

  /// No description provided for @purchaseMonthlyAmount.
  ///
  /// In en, this message translates to:
  /// **'Monthly installment'**
  String get purchaseMonthlyAmount;

  /// No description provided for @purchaseMonthlyAmountHelp.
  ///
  /// In en, this message translates to:
  /// **'The exact amount the lender collects each month.'**
  String get purchaseMonthlyAmountHelp;

  /// No description provided for @purchaseMonthlyRate.
  ///
  /// In en, this message translates to:
  /// **'Monthly interest rate'**
  String get purchaseMonthlyRate;

  /// No description provided for @purchaseAnnualRate.
  ///
  /// In en, this message translates to:
  /// **'Annual interest rate'**
  String get purchaseAnnualRate;

  /// No description provided for @purchaseRateHelp.
  ///
  /// In en, this message translates to:
  /// **'As quoted by the bank, e.g. 2.5 for 2.5%.'**
  String get purchaseRateHelp;

  /// No description provided for @purchaseRatePeriod.
  ///
  /// In en, this message translates to:
  /// **'Rate period'**
  String get purchaseRatePeriod;

  /// No description provided for @purchaseRatePerMonth.
  ///
  /// In en, this message translates to:
  /// **'Per month'**
  String get purchaseRatePerMonth;

  /// No description provided for @purchaseRatePerYear.
  ///
  /// In en, this message translates to:
  /// **'Per year'**
  String get purchaseRatePerYear;

  /// No description provided for @purchaseInterestMethod.
  ///
  /// In en, this message translates to:
  /// **'Interest method'**
  String get purchaseInterestMethod;

  /// No description provided for @purchaseInterestMethodHelp.
  ///
  /// In en, this message translates to:
  /// **'Flat charges the rate on the full amount every month; reducing charges it on the remaining balance.'**
  String get purchaseInterestMethodHelp;

  /// No description provided for @purchaseInterestFlat.
  ///
  /// In en, this message translates to:
  /// **'Flat'**
  String get purchaseInterestFlat;

  /// No description provided for @purchaseInterestReducing.
  ///
  /// In en, this message translates to:
  /// **'Reducing balance'**
  String get purchaseInterestReducing;

  /// No description provided for @purchaseImportSection.
  ///
  /// In en, this message translates to:
  /// **'Already running plan'**
  String get purchaseImportSection;

  /// No description provided for @purchaseImportSectionHelp.
  ///
  /// In en, this message translates to:
  /// **'Track a plan you started before using the app: mark the installments you already paid and only the remainder counts as new debt.'**
  String get purchaseImportSectionHelp;

  /// No description provided for @purchaseImportToggle.
  ///
  /// In en, this message translates to:
  /// **'I already paid some installments'**
  String get purchaseImportToggle;

  /// No description provided for @purchasePaidCount.
  ///
  /// In en, this message translates to:
  /// **'Installments already paid'**
  String get purchasePaidCount;

  /// No description provided for @purchasePaidCountHelp.
  ///
  /// In en, this message translates to:
  /// **'That many dues from the start of the schedule are marked as settled outside the app.'**
  String get purchasePaidCountHelp;

  /// No description provided for @purchaseInterest.
  ///
  /// In en, this message translates to:
  /// **'Interest'**
  String get purchaseInterest;

  /// No description provided for @purchaseAlreadyPaidPortion.
  ///
  /// In en, this message translates to:
  /// **'Already paid ({count} installments)'**
  String purchaseAlreadyPaidPortion(int count);

  /// No description provided for @purchaseRemainingCharge.
  ///
  /// In en, this message translates to:
  /// **'Remaining debt to track'**
  String get purchaseRemainingCharge;

  /// No description provided for @valPaidInstallments.
  ///
  /// In en, this message translates to:
  /// **'Paid installments must stay below the total count'**
  String get valPaidInstallments;

  /// No description provided for @valInterestRate.
  ///
  /// In en, this message translates to:
  /// **'Enter a rate between 0 and 1,000%'**
  String get valInterestRate;

  /// No description provided for @facilityStatementsSection.
  ///
  /// In en, this message translates to:
  /// **'Card statements'**
  String get facilityStatementsSection;

  /// No description provided for @facilityNoStatements.
  ///
  /// In en, this message translates to:
  /// **'Charges on this card will appear here grouped by statement.'**
  String get facilityNoStatements;

  /// No description provided for @statementCycleTitle.
  ///
  /// In en, this message translates to:
  /// **'Statement closing {date}'**
  String statementCycleTitle(String date);

  /// No description provided for @statementDueOn.
  ///
  /// In en, this message translates to:
  /// **'Due {date}'**
  String statementDueOn(String date);

  /// No description provided for @statementMinimumDue.
  ///
  /// In en, this message translates to:
  /// **'Minimum due'**
  String get statementMinimumDue;

  /// No description provided for @statementStatusOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get statementStatusOpen;

  /// No description provided for @planActionsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Plan actions'**
  String get planActionsTooltip;

  /// No description provided for @planEditAction.
  ///
  /// In en, this message translates to:
  /// **'Edit plan'**
  String get planEditAction;

  /// No description provided for @planRestructureAction.
  ///
  /// In en, this message translates to:
  /// **'Restructure remaining'**
  String get planRestructureAction;

  /// No description provided for @planRevisionsAction.
  ///
  /// In en, this message translates to:
  /// **'Change history'**
  String get planRevisionsAction;

  /// No description provided for @planRestructureTitle.
  ///
  /// In en, this message translates to:
  /// **'Restructure remaining installments'**
  String get planRestructureTitle;

  /// No description provided for @planRestructureBody.
  ///
  /// In en, this message translates to:
  /// **'Paid installments stay untouched. Spread what is still owed over a new schedule; any extra cost is booked as an expense today.'**
  String get planRestructureBody;

  /// No description provided for @planRestructureRemainingTotal.
  ///
  /// In en, this message translates to:
  /// **'Remaining total'**
  String get planRestructureRemainingTotal;

  /// No description provided for @planRestructureRemainingCount.
  ///
  /// In en, this message translates to:
  /// **'Remaining installments'**
  String get planRestructureRemainingCount;

  /// No description provided for @planRestructureNextDue.
  ///
  /// In en, this message translates to:
  /// **'Next due date'**
  String get planRestructureNextDue;

  /// No description provided for @planRestructureNote.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get planRestructureNote;

  /// No description provided for @planRevisionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Plan change history'**
  String get planRevisionsTitle;

  /// No description provided for @planRevisionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'This plan has not been restructured.'**
  String get planRevisionsEmpty;

  /// No description provided for @errFacilityHasHistory.
  ///
  /// In en, this message translates to:
  /// **'This card has activity; archive it instead of deleting'**
  String get errFacilityHasHistory;

  /// No description provided for @errFacilityNotActive.
  ///
  /// In en, this message translates to:
  /// **'This card is frozen or closed and cannot fund new purchases'**
  String get errFacilityNotActive;

  /// No description provided for @errCardNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Set the card\'s statement closing day first'**
  String get errCardNotConfigured;

  /// No description provided for @errPlanControlled.
  ///
  /// In en, this message translates to:
  /// **'This purchase belongs to an installment plan; edit it from the plan'**
  String get errPlanControlled;

  /// No description provided for @errFeeChargeLocked.
  ///
  /// In en, this message translates to:
  /// **'This charge comes from a card fee rule; change the rule instead'**
  String get errFeeChargeLocked;

  /// No description provided for @errStatementSettled.
  ///
  /// In en, this message translates to:
  /// **'That statement is already paid; reverse the payment before correcting it'**
  String get errStatementSettled;

  /// No description provided for @errInvalidKind.
  ///
  /// In en, this message translates to:
  /// **'This record is edited from its own flow'**
  String get errInvalidKind;

  /// No description provided for @errInvalidPaidInstallments.
  ///
  /// In en, this message translates to:
  /// **'Paid installments must stay below the total count'**
  String get errInvalidPaidInstallments;

  /// No description provided for @errPlanPartiallyPaidDue.
  ///
  /// In en, this message translates to:
  /// **'Settle the partially paid installment before restructuring'**
  String get errPlanPartiallyPaidDue;

  /// No description provided for @purchaseFinancedFees.
  ///
  /// In en, this message translates to:
  /// **'Financed fees'**
  String get purchaseFinancedFees;

  /// No description provided for @purchaseFinancedFeesHelp.
  ///
  /// In en, this message translates to:
  /// **'Extra fees rolled into the schedule and paid across the installments.'**
  String get purchaseFinancedFeesHelp;

  /// No description provided for @setNotificationsSection.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get setNotificationsSection;

  /// No description provided for @notifDueRemindersTitle.
  ///
  /// In en, this message translates to:
  /// **'Due date reminders'**
  String get notifDueRemindersTitle;

  /// No description provided for @notifDueRemindersHelp.
  ///
  /// In en, this message translates to:
  /// **'Remind me before installments and card statements fall due.'**
  String get notifDueRemindersHelp;

  /// No description provided for @notifOverdueRemindersTitle.
  ///
  /// In en, this message translates to:
  /// **'Overdue alerts'**
  String get notifOverdueRemindersTitle;

  /// No description provided for @notifOverdueRemindersHelp.
  ///
  /// In en, this message translates to:
  /// **'Keep alerting me while a payment stays overdue.'**
  String get notifOverdueRemindersHelp;

  /// No description provided for @notifPaymentConfirmationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment confirmations'**
  String get notifPaymentConfirmationsTitle;

  /// No description provided for @notifPaymentConfirmationsHelp.
  ///
  /// In en, this message translates to:
  /// **'Notify me when a facility payment is recorded.'**
  String get notifPaymentConfirmationsHelp;

  /// No description provided for @notifShowAmountsTitle.
  ///
  /// In en, this message translates to:
  /// **'Show amounts in notifications'**
  String get notifShowAmountsTitle;

  /// No description provided for @notifShowAmountsHelp.
  ///
  /// In en, this message translates to:
  /// **'Off by default so balances never appear on the lock screen.'**
  String get notifShowAmountsHelp;

  /// No description provided for @minPaymentLabel.
  ///
  /// In en, this message translates to:
  /// **'Minimum payment'**
  String get minPaymentLabel;

  /// No description provided for @minPaymentHelp.
  ///
  /// In en, this message translates to:
  /// **'How the minimum due of each monthly statement is calculated.'**
  String get minPaymentHelp;

  /// No description provided for @minPaymentFull.
  ///
  /// In en, this message translates to:
  /// **'Full statement balance'**
  String get minPaymentFull;

  /// No description provided for @minPaymentFixed.
  ///
  /// In en, this message translates to:
  /// **'Fixed amount'**
  String get minPaymentFixed;

  /// No description provided for @minPaymentPercent.
  ///
  /// In en, this message translates to:
  /// **'Percent of statement'**
  String get minPaymentPercent;

  /// No description provided for @minPaymentGreaterOf.
  ///
  /// In en, this message translates to:
  /// **'Greater of fixed or percent'**
  String get minPaymentGreaterOf;

  /// No description provided for @minPaymentFixedAmount.
  ///
  /// In en, this message translates to:
  /// **'Minimum fixed amount'**
  String get minPaymentFixedAmount;

  /// No description provided for @minPaymentPercentAmount.
  ///
  /// In en, this message translates to:
  /// **'Minimum percent'**
  String get minPaymentPercentAmount;

  /// No description provided for @valMinPaymentPercent.
  ///
  /// In en, this message translates to:
  /// **'Enter a percent between 0.01 and 100.'**
  String get valMinPaymentPercent;

  /// No description provided for @fxMarkupLabel.
  ///
  /// In en, this message translates to:
  /// **'Foreign exchange markup'**
  String get fxMarkupLabel;

  /// No description provided for @fxMarkupHelp.
  ///
  /// In en, this message translates to:
  /// **'Charged as a second expense whenever a purchase on this card is flagged in foreign currency.'**
  String get fxMarkupHelp;

  /// No description provided for @valFxMarkupPercent.
  ///
  /// In en, this message translates to:
  /// **'Enter a percent between 0.01 and 100.'**
  String get valFxMarkupPercent;

  /// No description provided for @feeRulesSection.
  ///
  /// In en, this message translates to:
  /// **'Card fees'**
  String get feeRulesSection;

  /// No description provided for @feeRuleAdd.
  ///
  /// In en, this message translates to:
  /// **'Add fee'**
  String get feeRuleAdd;

  /// No description provided for @feeRuleEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit fee'**
  String get feeRuleEdit;

  /// No description provided for @feeRuleName.
  ///
  /// In en, this message translates to:
  /// **'Fee name'**
  String get feeRuleName;

  /// No description provided for @feeRuleType.
  ///
  /// In en, this message translates to:
  /// **'Fee type'**
  String get feeRuleType;

  /// No description provided for @feeRuleState.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get feeRuleState;

  /// No description provided for @ruleStateConfigured.
  ///
  /// In en, this message translates to:
  /// **'Configured'**
  String get ruleStateConfigured;

  /// No description provided for @ruleStateUnknown.
  ///
  /// In en, this message translates to:
  /// **'I don\'t know yet'**
  String get ruleStateUnknown;

  /// No description provided for @ruleStateDisabled.
  ///
  /// In en, this message translates to:
  /// **'Not charged'**
  String get ruleStateDisabled;

  /// No description provided for @feeRuleUnknownHint.
  ///
  /// In en, this message translates to:
  /// **'This fee won\'t be charged until you know the rate. Finance Suit will flag any transaction it affects so you can fill it in later.'**
  String get feeRuleUnknownHint;

  /// No description provided for @feeRuleEditRateHint.
  ///
  /// In en, this message translates to:
  /// **'To change the rate, delete this fee and add it again with the new rate and start date.'**
  String get feeRuleEditRateHint;

  /// No description provided for @feeTypeAnnualMembership.
  ///
  /// In en, this message translates to:
  /// **'Annual membership'**
  String get feeTypeAnnualMembership;

  /// No description provided for @feeTypeInsurance.
  ///
  /// In en, this message translates to:
  /// **'Insurance'**
  String get feeTypeInsurance;

  /// No description provided for @feeTypeAdministration.
  ///
  /// In en, this message translates to:
  /// **'Administration'**
  String get feeTypeAdministration;

  /// No description provided for @feeTypeStampTax.
  ///
  /// In en, this message translates to:
  /// **'Stamp tax'**
  String get feeTypeStampTax;

  /// No description provided for @feeTypeForeignTransaction.
  ///
  /// In en, this message translates to:
  /// **'Foreign transaction'**
  String get feeTypeForeignTransaction;

  /// No description provided for @feeTypeCashAdvance.
  ///
  /// In en, this message translates to:
  /// **'Cash advance'**
  String get feeTypeCashAdvance;

  /// No description provided for @feeTypeInternationalCashAdvance.
  ///
  /// In en, this message translates to:
  /// **'International cash advance'**
  String get feeTypeInternationalCashAdvance;

  /// No description provided for @feeTypeWalletFee.
  ///
  /// In en, this message translates to:
  /// **'Wallet load fee'**
  String get feeTypeWalletFee;

  /// No description provided for @feeTypeStatementFee.
  ///
  /// In en, this message translates to:
  /// **'Statement / SMS fee'**
  String get feeTypeStatementFee;

  /// No description provided for @feeTypeEarlySettlement.
  ///
  /// In en, this message translates to:
  /// **'Early settlement fee'**
  String get feeTypeEarlySettlement;

  /// No description provided for @feeTypeLatePayment.
  ///
  /// In en, this message translates to:
  /// **'Late payment'**
  String get feeTypeLatePayment;

  /// No description provided for @feeTypeOverLimit.
  ///
  /// In en, this message translates to:
  /// **'Over limit'**
  String get feeTypeOverLimit;

  /// No description provided for @feeTypeInstallmentConversion.
  ///
  /// In en, this message translates to:
  /// **'Installment conversion'**
  String get feeTypeInstallmentConversion;

  /// No description provided for @feeTypeOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get feeTypeOther;

  /// No description provided for @feeRulePercentToggle.
  ///
  /// In en, this message translates to:
  /// **'Percent-based fee'**
  String get feeRulePercentToggle;

  /// No description provided for @feeRulePercentLabel.
  ///
  /// In en, this message translates to:
  /// **'Fee percent'**
  String get feeRulePercentLabel;

  /// No description provided for @feeRulePercentBasis.
  ///
  /// In en, this message translates to:
  /// **'Percent of'**
  String get feeRulePercentBasis;

  /// No description provided for @feeBasisStatementBalance.
  ///
  /// In en, this message translates to:
  /// **'Statement balance'**
  String get feeBasisStatementBalance;

  /// No description provided for @feeBasisOutstandingBalance.
  ///
  /// In en, this message translates to:
  /// **'Outstanding balance'**
  String get feeBasisOutstandingBalance;

  /// No description provided for @feeBasisCreditLimit.
  ///
  /// In en, this message translates to:
  /// **'Credit limit'**
  String get feeBasisCreditLimit;

  /// No description provided for @feeBasisTransactionAmount.
  ///
  /// In en, this message translates to:
  /// **'Transaction amount'**
  String get feeBasisTransactionAmount;

  /// No description provided for @feeBasisHighestStatementDueLookback.
  ///
  /// In en, this message translates to:
  /// **'Highest of recent statements'**
  String get feeBasisHighestStatementDueLookback;

  /// No description provided for @feeBasisHighestDailyBalance.
  ///
  /// In en, this message translates to:
  /// **'Highest balance in recent months'**
  String get feeBasisHighestDailyBalance;

  /// No description provided for @feeBasisRemainingPrincipal.
  ///
  /// In en, this message translates to:
  /// **'Remaining principal'**
  String get feeBasisRemainingPrincipal;

  /// No description provided for @feeBasisRemainingOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Remaining amount owed'**
  String get feeBasisRemainingOutstanding;

  /// No description provided for @feeRuleMinimum.
  ///
  /// In en, this message translates to:
  /// **'Minimum amount (optional)'**
  String get feeRuleMinimum;

  /// No description provided for @feeRuleMaximum.
  ///
  /// In en, this message translates to:
  /// **'Maximum amount (optional)'**
  String get feeRuleMaximum;

  /// No description provided for @feeRuleLookbackCycles.
  ///
  /// In en, this message translates to:
  /// **'Look back this many statements'**
  String get feeRuleLookbackCycles;

  /// No description provided for @feeRuleLookbackMonths.
  ///
  /// In en, this message translates to:
  /// **'Look back this many months'**
  String get feeRuleLookbackMonths;

  /// No description provided for @valFeeLookback.
  ///
  /// In en, this message translates to:
  /// **'Enter a number from 1 to 24'**
  String get valFeeLookback;

  /// No description provided for @feeRuleTriggerHint.
  ///
  /// In en, this message translates to:
  /// **'Charged automatically when the matching card event happens — no schedule of its own.'**
  String get feeRuleTriggerHint;

  /// No description provided for @feeRuleApplyWhen.
  ///
  /// In en, this message translates to:
  /// **'Applies when'**
  String get feeRuleApplyWhen;

  /// No description provided for @applyWhenCurrencyDiffers.
  ///
  /// In en, this message translates to:
  /// **'Billed in a foreign currency'**
  String get applyWhenCurrencyDiffers;

  /// No description provided for @applyWhenMerchantOutsideHome.
  ///
  /// In en, this message translates to:
  /// **'Merchant outside the country'**
  String get applyWhenMerchantOutsideHome;

  /// No description provided for @applyWhenEither.
  ///
  /// In en, this message translates to:
  /// **'Foreign currency or foreign merchant'**
  String get applyWhenEither;

  /// No description provided for @applyWhenBoth.
  ///
  /// In en, this message translates to:
  /// **'Foreign currency and foreign merchant'**
  String get applyWhenBoth;

  /// No description provided for @applyWhenForeignMerchantHomeCurrency.
  ///
  /// In en, this message translates to:
  /// **'Foreign merchant billed in card currency'**
  String get applyWhenForeignMerchantHomeCurrency;

  /// No description provided for @txIsForeignCurrency.
  ///
  /// In en, this message translates to:
  /// **'In foreign currency?'**
  String get txIsForeignCurrency;

  /// No description provided for @txIsForeignCurrencyHelp.
  ///
  /// In en, this message translates to:
  /// **'Adds the card\'s foreign exchange markup as a second charge.'**
  String get txIsForeignCurrencyHelp;

  /// No description provided for @feeRuleFixedAmount.
  ///
  /// In en, this message translates to:
  /// **'Fee amount'**
  String get feeRuleFixedAmount;

  /// No description provided for @feeRuleFrequency.
  ///
  /// In en, this message translates to:
  /// **'Repeats'**
  String get feeRuleFrequency;

  /// No description provided for @feeFrequencyOnce.
  ///
  /// In en, this message translates to:
  /// **'Once'**
  String get feeFrequencyOnce;

  /// No description provided for @feeFrequencyMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get feeFrequencyMonthly;

  /// No description provided for @feeFrequencyQuarterly.
  ///
  /// In en, this message translates to:
  /// **'Quarterly'**
  String get feeFrequencyQuarterly;

  /// No description provided for @feeFrequencyAnnually.
  ///
  /// In en, this message translates to:
  /// **'Annually'**
  String get feeFrequencyAnnually;

  /// No description provided for @feeFrequencyPerTransaction.
  ///
  /// In en, this message translates to:
  /// **'Per transaction'**
  String get feeFrequencyPerTransaction;

  /// No description provided for @feeRuleStartsOn.
  ///
  /// In en, this message translates to:
  /// **'First charge date'**
  String get feeRuleStartsOn;

  /// No description provided for @feeRuleNextCharge.
  ///
  /// In en, this message translates to:
  /// **'Next charge {date}'**
  String feeRuleNextCharge(String date);

  /// No description provided for @feeRuleInactive.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get feeRuleInactive;

  /// No description provided for @feeRuleDeactivate.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get feeRuleDeactivate;

  /// No description provided for @feeRuleActivate.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get feeRuleActivate;

  /// No description provided for @feeRuleDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this fee?'**
  String get feeRuleDeleteConfirmTitle;

  /// No description provided for @feeRuleDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Future charges stop. Fees already charged stay in your history.'**
  String get feeRuleDeleteConfirmBody;

  /// No description provided for @feeRulesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No fees configured for this card yet. Add the annual membership or insurance fee so it books itself.'**
  String get feeRulesEmpty;

  /// No description provided for @feeRuleNoCategoriesTitle.
  ///
  /// In en, this message translates to:
  /// **'You need an expense category first'**
  String get feeRuleNoCategoriesTitle;

  /// No description provided for @feeRuleNoCategoriesBody.
  ///
  /// In en, this message translates to:
  /// **'Fees are booked as expenses, so pick or create a category before saving this one.'**
  String get feeRuleNoCategoriesBody;

  /// No description provided for @feeRuleAddCategoryAction.
  ///
  /// In en, this message translates to:
  /// **'Add expense category'**
  String get feeRuleAddCategoryAction;

  /// No description provided for @feeRulePercentOfBasis.
  ///
  /// In en, this message translates to:
  /// **'{percent}% of {basis}'**
  String feeRulePercentOfBasis(String percent, String basis);

  /// No description provided for @valFeePercent.
  ///
  /// In en, this message translates to:
  /// **'Enter a percent between 0.01 and 1,000.'**
  String get valFeePercent;

  /// No description provided for @errCategoryInUse.
  ///
  /// In en, this message translates to:
  /// **'This category still labels records or has subcategories. Archive it instead, or remove those first.'**
  String get errCategoryInUse;

  /// No description provided for @errAlreadyDecided.
  ///
  /// In en, this message translates to:
  /// **'This entry was already handled.'**
  String get errAlreadyDecided;

  /// No description provided for @catDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this category?'**
  String get catDeleteConfirmTitle;

  /// No description provided for @catDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Deletion only works while nothing uses the category. Anything in use should be archived instead.'**
  String get catDeleteConfirmBody;

  /// No description provided for @recurringCenterTitle.
  ///
  /// In en, this message translates to:
  /// **'Recurring payments'**
  String get recurringCenterTitle;

  /// No description provided for @recurringCenterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automate rent, subscriptions, and monthly savings transfers.'**
  String get recurringCenterSubtitle;

  /// No description provided for @recurringPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Payments waiting for you'**
  String get recurringPendingTitle;

  /// No description provided for @recurringPendingCount.
  ///
  /// In en, this message translates to:
  /// **'{count} payments waiting'**
  String recurringPendingCount(int count);

  /// No description provided for @recurringRulesTitle.
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get recurringRulesTitle;

  /// No description provided for @recurringAddRule.
  ///
  /// In en, this message translates to:
  /// **'Add recurring payment'**
  String get recurringAddRule;

  /// No description provided for @recurringEditRule.
  ///
  /// In en, this message translates to:
  /// **'Edit recurring payment'**
  String get recurringEditRule;

  /// No description provided for @recurringEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No recurring payments yet. Automate rent, subscriptions, or a monthly transfer to savings.'**
  String get recurringEmptyTitle;

  /// No description provided for @recurringKindLabel.
  ///
  /// In en, this message translates to:
  /// **'What repeats'**
  String get recurringKindLabel;

  /// No description provided for @recurringKindExpense.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get recurringKindExpense;

  /// No description provided for @recurringKindTransfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer between accounts'**
  String get recurringKindTransfer;

  /// No description provided for @recurringNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get recurringNameLabel;

  /// No description provided for @recurringAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get recurringAmountLabel;

  /// No description provided for @recurringPayFrom.
  ///
  /// In en, this message translates to:
  /// **'Pay from'**
  String get recurringPayFrom;

  /// No description provided for @recurringCardSourceHint.
  ///
  /// In en, this message translates to:
  /// **'Card payments land on the card\'s monthly statement, not your cash.'**
  String get recurringCardSourceHint;

  /// No description provided for @recurringFrequencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Repeats'**
  String get recurringFrequencyLabel;

  /// No description provided for @recurringFrequencyWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get recurringFrequencyWeekly;

  /// No description provided for @recurringFrequencyMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get recurringFrequencyMonthly;

  /// No description provided for @recurringFrequencyQuarterly.
  ///
  /// In en, this message translates to:
  /// **'Quarterly'**
  String get recurringFrequencyQuarterly;

  /// No description provided for @recurringFrequencyAnnually.
  ///
  /// In en, this message translates to:
  /// **'Annually'**
  String get recurringFrequencyAnnually;

  /// No description provided for @recurringWeekdayLabel.
  ///
  /// In en, this message translates to:
  /// **'On weekday'**
  String get recurringWeekdayLabel;

  /// No description provided for @recurringDayOfMonthLabel.
  ///
  /// In en, this message translates to:
  /// **'On day of month'**
  String get recurringDayOfMonthLabel;

  /// No description provided for @recurringDayOfMonthHelp.
  ///
  /// In en, this message translates to:
  /// **'Days 1–28, so every month has the date.'**
  String get recurringDayOfMonthHelp;

  /// No description provided for @recurringScheduleOnDay.
  ///
  /// In en, this message translates to:
  /// **'{frequency} · day {day}'**
  String recurringScheduleOnDay(String frequency, int day);

  /// No description provided for @recurringPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get recurringPaused;

  /// No description provided for @recurringPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get recurringPause;

  /// No description provided for @recurringResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get recurringResume;

  /// No description provided for @recurringPayNow.
  ///
  /// In en, this message translates to:
  /// **'Record payment'**
  String get recurringPayNow;

  /// No description provided for @recurringPaidOn.
  ///
  /// In en, this message translates to:
  /// **'Paid on'**
  String get recurringPaidOn;

  /// No description provided for @recurringAcceptTitle.
  ///
  /// In en, this message translates to:
  /// **'Record this payment?'**
  String get recurringAcceptTitle;

  /// No description provided for @recurringAcceptHelp.
  ///
  /// In en, this message translates to:
  /// **'Confirm the amount and date for \"{name}\"; the entry is booked exactly like a manual one.'**
  String recurringAcceptHelp(String name);

  /// No description provided for @recurringAcceptedMessage.
  ///
  /// In en, this message translates to:
  /// **'Payment recorded.'**
  String get recurringAcceptedMessage;

  /// No description provided for @recurringSkipTitle.
  ///
  /// In en, this message translates to:
  /// **'Skip this payment?'**
  String get recurringSkipTitle;

  /// No description provided for @recurringSkipHelp.
  ///
  /// In en, this message translates to:
  /// **'Skipping records nothing for this date. The next occurrence still arrives on schedule.'**
  String get recurringSkipHelp;

  /// No description provided for @recurringDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this rule?'**
  String get recurringDeleteConfirmTitle;

  /// No description provided for @recurringDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Upcoming reminders disappear. Payments already recorded stay in your history.'**
  String get recurringDeleteConfirmBody;

  /// No description provided for @incomeRemainderTitle.
  ///
  /// In en, this message translates to:
  /// **'{name} — remaining'**
  String incomeRemainderTitle(String name);

  /// No description provided for @incomePartialTrack.
  ///
  /// In en, this message translates to:
  /// **'Keep the remaining {amount} pending'**
  String incomePartialTrack(String amount);

  /// No description provided for @incomePartialTrackHelp.
  ///
  /// In en, this message translates to:
  /// **'The shortfall stays on your pending list until you receive it or skip it. Turning this off records only what you entered.'**
  String get incomePartialTrackHelp;

  /// No description provided for @incomePartialExtraFirst.
  ///
  /// In en, this message translates to:
  /// **'Missing money is taken off your extra-day, overtime, and holiday pay first, so nothing moves to the extra-work account until it arrives. Anything the extra work cannot cover comes off the base salary, and your splits run on what you received.'**
  String get incomePartialExtraFirst;

  /// No description provided for @errInvalidPartial.
  ///
  /// In en, this message translates to:
  /// **'For a partial acceptance the amount received must be less than the amount owed.'**
  String get errInvalidPartial;

  /// No description provided for @aiAutofillButtonLabel.
  ///
  /// In en, this message translates to:
  /// **'Let AI help do it'**
  String get aiAutofillButtonLabel;

  /// No description provided for @aiAutofillHelperText.
  ///
  /// In en, this message translates to:
  /// **'Tell us which card or finance product you have. Finance Suit can research its public fees and settings and fill this form for you.'**
  String get aiAutofillHelperText;

  /// No description provided for @aiAutofillCautionText.
  ///
  /// In en, this message translates to:
  /// **'Bank terms can change. Finance Suit only uses information it can verify from public sources.'**
  String get aiAutofillCautionText;

  /// No description provided for @aiResearchStatusFinding.
  ///
  /// In en, this message translates to:
  /// **'Finding your product…'**
  String get aiResearchStatusFinding;

  /// No description provided for @aiResearchStatusFilling.
  ///
  /// In en, this message translates to:
  /// **'Filling your card settings…'**
  String get aiResearchStatusFilling;

  /// No description provided for @aiResearchSheetTitleCard.
  ///
  /// In en, this message translates to:
  /// **'Find your card'**
  String get aiResearchSheetTitleCard;

  /// No description provided for @aiResearchSheetTitleBnpl.
  ///
  /// In en, this message translates to:
  /// **'Find your account'**
  String get aiResearchSheetTitleBnpl;

  /// No description provided for @aiResearchIssuer.
  ///
  /// In en, this message translates to:
  /// **'Bank / Company'**
  String get aiResearchIssuer;

  /// No description provided for @aiResearchIssuerHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. CIB, NBE, QNB, Banque Misr, ValU, Contact, Souhoola'**
  String get aiResearchIssuerHint;

  /// No description provided for @aiResearchCountry.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get aiResearchCountry;

  /// No description provided for @aiResearchCountryRequired.
  ///
  /// In en, this message translates to:
  /// **'Country is required'**
  String get aiResearchCountryRequired;

  /// No description provided for @aiResearchWebsite.
  ///
  /// In en, this message translates to:
  /// **'Bank/company website, if you know it'**
  String get aiResearchWebsite;

  /// No description provided for @aiResearchInvalidWebsite.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid website address'**
  String get aiResearchInvalidWebsite;

  /// No description provided for @aiResearchProductCard.
  ///
  /// In en, this message translates to:
  /// **'Card / product name'**
  String get aiResearchProductCard;

  /// No description provided for @aiResearchProductBnpl.
  ///
  /// In en, this message translates to:
  /// **'Product / program name'**
  String get aiResearchProductBnpl;

  /// No description provided for @aiResearchTier.
  ///
  /// In en, this message translates to:
  /// **'Tier / variant'**
  String get aiResearchTier;

  /// No description provided for @aiResearchNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get aiResearchNetwork;

  /// No description provided for @aiResearchNetworkOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get aiResearchNetworkOther;

  /// No description provided for @aiResearchNetworkUnknown.
  ///
  /// In en, this message translates to:
  /// **'I don\'t know'**
  String get aiResearchNetworkUnknown;

  /// No description provided for @aiResearchCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency, if known'**
  String get aiResearchCurrency;

  /// No description provided for @aiResearchInvalidCurrency.
  ///
  /// In en, this message translates to:
  /// **'Enter a 3-letter currency code'**
  String get aiResearchInvalidCurrency;

  /// No description provided for @aiResearchActivationDate.
  ///
  /// In en, this message translates to:
  /// **'Issue / activation date, if known'**
  String get aiResearchActivationDate;

  /// No description provided for @aiResearchInvalidDate.
  ///
  /// In en, this message translates to:
  /// **'Enter a date as YYYY-MM-DD'**
  String get aiResearchInvalidDate;

  /// No description provided for @aiResearchCreditLimit.
  ///
  /// In en, this message translates to:
  /// **'Credit limit, if known'**
  String get aiResearchCreditLimit;

  /// No description provided for @aiResearchFinanceLimit.
  ///
  /// In en, this message translates to:
  /// **'Finance limit, if known'**
  String get aiResearchFinanceLimit;

  /// No description provided for @aiResearchStatementDay.
  ///
  /// In en, this message translates to:
  /// **'Statement closing day, if known'**
  String get aiResearchStatementDay;

  /// No description provided for @aiResearchDueDay.
  ///
  /// In en, this message translates to:
  /// **'Due day, if known'**
  String get aiResearchDueDay;

  /// No description provided for @aiResearchTenor.
  ///
  /// In en, this message translates to:
  /// **'Typical installment term (months)'**
  String get aiResearchTenor;

  /// No description provided for @aiResearchNotes.
  ///
  /// In en, this message translates to:
  /// **'Anything else we should know?'**
  String get aiResearchNotes;

  /// No description provided for @aiResearchNotesHelp.
  ///
  /// In en, this message translates to:
  /// **'For example: \"My card is the normal Platinum Mastercard\" or \"My due date is the 17th.\"'**
  String get aiResearchNotesHelp;

  /// No description provided for @aiResearchSensitiveWarning.
  ///
  /// In en, this message translates to:
  /// **'Do not enter your full card number, CVV, PIN, password, or OTP.'**
  String get aiResearchSensitiveWarning;

  /// No description provided for @aiResearchSubmitCard.
  ///
  /// In en, this message translates to:
  /// **'Find and fill my card'**
  String get aiResearchSubmitCard;

  /// No description provided for @aiResearchSubmitBnpl.
  ///
  /// In en, this message translates to:
  /// **'Find and fill my account'**
  String get aiResearchSubmitBnpl;

  /// No description provided for @aiResearchDisambiguationTitle.
  ///
  /// In en, this message translates to:
  /// **'Which one do you have?'**
  String get aiResearchDisambiguationTitle;

  /// No description provided for @aiResearchUnableToFind.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find enough reliable information. You can continue filling the form manually.'**
  String get aiResearchUnableToFind;

  /// No description provided for @aiResearchIncompleteMessage.
  ///
  /// In en, this message translates to:
  /// **'We filled what we could. Complete the highlighted fields to continue.'**
  String get aiResearchIncompleteMessage;

  /// No description provided for @aiResearchCatalogVerifiedOn.
  ///
  /// In en, this message translates to:
  /// **'Verified from Finance Suit catalog · {date}'**
  String aiResearchCatalogVerifiedOn(String date);

  /// No description provided for @cardPaymentDueDay.
  ///
  /// In en, this message translates to:
  /// **'Payment due day'**
  String get cardPaymentDueDay;

  /// No description provided for @cardStatementCloses.
  ///
  /// In en, this message translates to:
  /// **'Statement closes'**
  String get cardStatementCloses;

  /// No description provided for @cardStatementExactDay.
  ///
  /// In en, this message translates to:
  /// **'Exact day'**
  String get cardStatementExactDay;

  /// No description provided for @cardStatementEndOfMonth.
  ///
  /// In en, this message translates to:
  /// **'End of month'**
  String get cardStatementEndOfMonth;

  /// No description provided for @cardInstallmentDueDay.
  ///
  /// In en, this message translates to:
  /// **'Installment due day (optional)'**
  String get cardInstallmentDueDay;

  /// No description provided for @cardGracePeriodDays.
  ///
  /// In en, this message translates to:
  /// **'Grace period (days)'**
  String get cardGracePeriodDays;

  /// No description provided for @valGracePeriodDays.
  ///
  /// In en, this message translates to:
  /// **'Enter a grace period from 0 to 90 days.'**
  String get valGracePeriodDays;

  /// No description provided for @minPaymentPercentageBasis.
  ///
  /// In en, this message translates to:
  /// **'Minimum percent applies to'**
  String get minPaymentPercentageBasis;

  /// No description provided for @minPaymentBasisRevolving.
  ///
  /// In en, this message translates to:
  /// **'Revolving purchases and interest'**
  String get minPaymentBasisRevolving;

  /// No description provided for @minPaymentBasisStatement.
  ///
  /// In en, this message translates to:
  /// **'Full statement obligation'**
  String get minPaymentBasisStatement;

  /// No description provided for @minPaymentIncludeInstallments.
  ///
  /// In en, this message translates to:
  /// **'Include installment dues'**
  String get minPaymentIncludeInstallments;

  /// No description provided for @minPaymentIncludeBankFees.
  ///
  /// In en, this message translates to:
  /// **'Include bank fees'**
  String get minPaymentIncludeBankFees;

  /// No description provided for @minPaymentIncludeOverdue.
  ///
  /// In en, this message translates to:
  /// **'Include overdue obligations'**
  String get minPaymentIncludeOverdue;

  /// No description provided for @purchaseInterestTitle.
  ///
  /// In en, this message translates to:
  /// **'Purchase interest'**
  String get purchaseInterestTitle;

  /// No description provided for @purchaseInterestState.
  ///
  /// In en, this message translates to:
  /// **'Interest terms'**
  String get purchaseInterestState;

  /// No description provided for @purchaseInterestStateHelp.
  ///
  /// In en, this message translates to:
  /// **'Use unknown when the bank posts actual interest but you do not know the calculation rate.'**
  String get purchaseInterestStateHelp;

  /// No description provided for @purchaseInterestRate.
  ///
  /// In en, this message translates to:
  /// **'Interest rate'**
  String get purchaseInterestRate;

  /// No description provided for @purchaseInterestRatePeriod.
  ///
  /// In en, this message translates to:
  /// **'Rate period'**
  String get purchaseInterestRatePeriod;

  /// No description provided for @purchaseInterestPeriodMonthly.
  ///
  /// In en, this message translates to:
  /// **'Per month'**
  String get purchaseInterestPeriodMonthly;

  /// No description provided for @purchaseInterestPeriodAnnual.
  ///
  /// In en, this message translates to:
  /// **'Per year'**
  String get purchaseInterestPeriodAnnual;

  /// No description provided for @purchaseInterestAccrual.
  ///
  /// In en, this message translates to:
  /// **'Accrual method'**
  String get purchaseInterestAccrual;

  /// No description provided for @purchaseInterestAccrualManual.
  ///
  /// In en, this message translates to:
  /// **'Bank-posted actual amount'**
  String get purchaseInterestAccrualManual;

  /// No description provided for @purchaseInterestAccrualDaily.
  ///
  /// In en, this message translates to:
  /// **'Daily balance calculation'**
  String get purchaseInterestAccrualDaily;

  /// No description provided for @purchaseInterestStarts.
  ///
  /// In en, this message translates to:
  /// **'Interest starts from'**
  String get purchaseInterestStarts;

  /// No description provided for @purchaseInterestStartTransaction.
  ///
  /// In en, this message translates to:
  /// **'Transaction date'**
  String get purchaseInterestStartTransaction;

  /// No description provided for @purchaseInterestStartStatement.
  ///
  /// In en, this message translates to:
  /// **'Statement date'**
  String get purchaseInterestStartStatement;

  /// No description provided for @purchaseInterestStartPaymentDue.
  ///
  /// In en, this message translates to:
  /// **'Payment due date'**
  String get purchaseInterestStartPaymentDue;

  /// No description provided for @purchaseInterestStartGraceExpiry.
  ///
  /// In en, this message translates to:
  /// **'Grace period expiry'**
  String get purchaseInterestStartGraceExpiry;

  /// No description provided for @purchaseInterestGraceApplies.
  ///
  /// In en, this message translates to:
  /// **'Grace period applies'**
  String get purchaseInterestGraceApplies;

  /// No description provided for @purchaseInterestEffectiveFrom.
  ///
  /// In en, this message translates to:
  /// **'Effective from'**
  String get purchaseInterestEffectiveFrom;

  /// No description provided for @purchaseInterestCategory.
  ///
  /// In en, this message translates to:
  /// **'Interest expense category'**
  String get purchaseInterestCategory;

  /// No description provided for @valPurchaseInterestRate.
  ///
  /// In en, this message translates to:
  /// **'Enter a rate between 0.01 and 100%.'**
  String get valPurchaseInterestRate;

  /// No description provided for @valPurchaseInterestCategory.
  ///
  /// In en, this message translates to:
  /// **'Choose an expense category for interest.'**
  String get valPurchaseInterestCategory;

  /// No description provided for @feeTypePurchaseInterest.
  ///
  /// In en, this message translates to:
  /// **'Purchase interest'**
  String get feeTypePurchaseInterest;

  /// No description provided for @facilityActivityPurchaseInterest.
  ///
  /// In en, this message translates to:
  /// **'Purchase interest'**
  String get facilityActivityPurchaseInterest;

  /// No description provided for @facilityActivityInstallmentInterest.
  ///
  /// In en, this message translates to:
  /// **'Installment interest'**
  String get facilityActivityInstallmentInterest;

  /// No description provided for @purchaseImportAsOf.
  ///
  /// In en, this message translates to:
  /// **'Import position as of'**
  String get purchaseImportAsOf;

  /// No description provided for @purchasePaidThrough.
  ///
  /// In en, this message translates to:
  /// **'Paid through'**
  String get purchasePaidThrough;

  /// No description provided for @purchaseCurrentInstallmentPosted.
  ///
  /// In en, this message translates to:
  /// **'Current installment is already posted'**
  String get purchaseCurrentInstallmentPosted;

  /// No description provided for @purchaseBankOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Bank-reported principal outstanding'**
  String get purchaseBankOutstanding;

  /// No description provided for @purchaseBankOutstandingHelp.
  ///
  /// In en, this message translates to:
  /// **'Use the bank\'s figure when it differs from the calculated remaining principal; the difference is retained for reconciliation.'**
  String get purchaseBankOutstandingHelp;

  /// No description provided for @purchaseReconciliationNote.
  ///
  /// In en, this message translates to:
  /// **'Reconciliation note'**
  String get purchaseReconciliationNote;

  /// No description provided for @valFutureInstallmentPaid.
  ///
  /// In en, this message translates to:
  /// **'A future installment cannot be marked paid unless it was explicitly prepaid.'**
  String get valFutureInstallmentPaid;

  /// No description provided for @valBankOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Enter a positive outstanding amount below the financed principal.'**
  String get valBankOutstanding;

  /// No description provided for @planOutstandingPrincipal.
  ///
  /// In en, this message translates to:
  /// **'Outstanding principal'**
  String get planOutstandingPrincipal;

  /// No description provided for @planRemainingScheduledPayments.
  ///
  /// In en, this message translates to:
  /// **'Remaining scheduled payments'**
  String get planRemainingScheduledPayments;

  /// No description provided for @planRemainingFutureInterest.
  ///
  /// In en, this message translates to:
  /// **'Future interest not yet posted'**
  String get planRemainingFutureInterest;

  /// No description provided for @planInstallmentCounts.
  ///
  /// In en, this message translates to:
  /// **'{paid} paid · {current} current · {future} future'**
  String planInstallmentCounts(int paid, int current, int future);

  /// No description provided for @planBilling.
  ///
  /// In en, this message translates to:
  /// **'Plan & Billing'**
  String get planBilling;

  /// No description provided for @proEarlyAccess.
  ///
  /// In en, this message translates to:
  /// **'Pro Early Access'**
  String get proEarlyAccess;

  /// No description provided for @proIncludedEarlyAccess.
  ///
  /// In en, this message translates to:
  /// **'Pro features are currently included during Early Access.'**
  String get proIncludedEarlyAccess;

  /// No description provided for @complimentaryAccess.
  ///
  /// In en, this message translates to:
  /// **'Complimentary access'**
  String get complimentaryAccess;

  /// No description provided for @noExpiration.
  ///
  /// In en, this message translates to:
  /// **'No expiration'**
  String get noExpiration;

  /// No description provided for @availableUntil.
  ///
  /// In en, this message translates to:
  /// **'Available until: {date}'**
  String availableUntil(String date);

  /// No description provided for @daysRemaining.
  ///
  /// In en, this message translates to:
  /// **'{days} days remaining'**
  String daysRemaining(int days);

  /// No description provided for @proMonthly.
  ///
  /// In en, this message translates to:
  /// **'Pro · Monthly'**
  String get proMonthly;

  /// No description provided for @proAnnual.
  ///
  /// In en, this message translates to:
  /// **'Pro · Annual'**
  String get proAnnual;

  /// No description provided for @proComplimentary.
  ///
  /// In en, this message translates to:
  /// **'Pro · Complimentary'**
  String get proComplimentary;

  /// No description provided for @proEarlyAccessSummary.
  ///
  /// In en, this message translates to:
  /// **'Pro · Early Access'**
  String get proEarlyAccessSummary;

  /// No description provided for @freePlan.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get freePlan;

  /// No description provided for @billingNotReady.
  ///
  /// In en, this message translates to:
  /// **'Billing is not ready yet. Pro is included during Early Access.'**
  String get billingNotReady;
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
