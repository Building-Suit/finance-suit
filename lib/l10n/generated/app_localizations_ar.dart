// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'Finance Suit';

  @override
  String get tabHome => 'الرئيسية';

  @override
  String get tabWork => 'العمل';

  @override
  String get tabMoney => 'المال';

  @override
  String get tabReports => 'التقارير';

  @override
  String get tabSettings => 'الإعدادات';

  @override
  String get menuOpenTooltip => 'فتح القائمة';

  @override
  String get menuCloseTooltip => 'إغلاق القائمة';

  @override
  String get menuNavigationLabel => 'قائمة التنقل';

  @override
  String get menuGroupGeneral => 'عام';

  @override
  String get menuGroupAutomation => 'الأتمتة';

  @override
  String get menuCategories => 'الفئات';

  @override
  String get globalAddLabel => 'إضافة عنصر جديد';

  @override
  String get commonSave => 'حفظ';

  @override
  String get commonCancel => 'إلغاء';

  @override
  String get commonDelete => 'حذف';

  @override
  String get commonEdit => 'تعديل';

  @override
  String get commonRetry => 'إعادة المحاولة';

  @override
  String get commonConfirm => 'تأكيد';

  @override
  String get commonBack => 'رجوع';

  @override
  String get commonNext => 'التالي';

  @override
  String get commonDone => 'تم';

  @override
  String get commonClose => 'إغلاق';

  @override
  String get commonUndo => 'تراجع';

  @override
  String get commonAll => 'الكل';

  @override
  String get commonNone => 'لا شيء';

  @override
  String get commonOptional => 'اختياري';

  @override
  String get commonError => 'حدث خطأ ما';

  @override
  String get commonLoading => 'جارٍ التحميل…';

  @override
  String get commonEmpty => 'لا يوجد شيء هنا بعد';

  @override
  String get commonOffline =>
      'يبدو أنك غير متصل بالإنترنت. تحقق من الاتصال وأعد المحاولة.';

  @override
  String get commonNotes => 'ملاحظات';

  @override
  String get commonAmount => 'المبلغ';

  @override
  String get commonDate => 'التاريخ';

  @override
  String get commonToday => 'اليوم';

  @override
  String get commonSeeAll => 'عرض الكل';

  @override
  String get commonApply => 'تطبيق';

  @override
  String get commonAdd => 'إضافة';

  @override
  String get addSectionMoneyControl => 'إدارة المال';

  @override
  String get addSectionWorkControl => 'إدارة العمل';

  @override
  String get errInvalidCredentials =>
      'البريد الإلكتروني أو كلمة المرور غير صحيحة.';

  @override
  String get errEmailNotConfirmed => 'يرجى تأكيد بريدك الإلكتروني أولاً.';

  @override
  String get errDuplicateEmail =>
      'يوجد حساب مسجل بهذا البريد الإلكتروني بالفعل.';

  @override
  String get errWeakPassword =>
      'كلمة المرور ضعيفة جداً. استخدم 8 أحرف على الأقل.';

  @override
  String get errExpiredLink =>
      'هذا الرابط غير صالح أو منتهي الصلاحية أو مستخدم من قبل. اطلب رابطاً جديداً.';

  @override
  String get errRateLimited =>
      'محاولات كثيرة جداً. انتظر قليلاً ثم حاول مرة أخرى.';

  @override
  String get errSessionExpired =>
      'انتهت صلاحية جلستك. يرجى تسجيل الدخول مرة أخرى.';

  @override
  String get errAuthGeneric => 'فشلت المصادقة. حاول مرة أخرى.';

  @override
  String get errNotAuthorized => 'غير مسموح لك بتنفيذ هذا الإجراء.';

  @override
  String get errTimeout => 'انتهت مهلة الطلب. حاول مرة أخرى.';

  @override
  String get errConstraint => 'هذا التغيير يتعارض مع البيانات الموجودة.';

  @override
  String get errNotFound => 'العنصر المطلوب غير موجود.';

  @override
  String get errRealtime => 'التحديثات المباشرة غير متاحة مؤقتاً.';

  @override
  String get errInsufficientFunds => 'هذا الحساب لا يسمح برصيد سالب.';

  @override
  String get errCurrencyMismatch => 'يجب أن يستخدم كلا الحسابين نفس العملة.';

  @override
  String get errSameAccounts => 'يجب أن يختلف حساب المصدر عن حساب الوجهة.';

  @override
  String get errAccountUnavailable => 'الحساب المحدد غير متاح أو مؤرشف.';

  @override
  String get errAlreadyPaid => 'تم دفع راتب هذه الفترة بالفعل.';

  @override
  String get errNotFinalized => 'قم بإقفال فترة الراتب قبل تسجيل الدفع.';

  @override
  String get errInvalidAmount => 'أدخل مبلغاً صالحاً.';

  @override
  String get valRequired => 'هذا الحقل مطلوب.';

  @override
  String get valInvalidEmail => 'أدخل بريداً إلكترونياً صالحاً.';

  @override
  String get valPasswordTooShort => 'يجب أن تكون كلمة المرور 8 أحرف على الأقل.';

  @override
  String get valPasswordsDoNotMatch => 'كلمتا المرور غير متطابقتين.';

  @override
  String get valAmountNotPositive => 'يجب أن يكون المبلغ أكبر من صفر.';

  @override
  String get valInvalidDate => 'أدخل تاريخاً صالحاً.';

  @override
  String get valStartAfterEnd =>
      'يجب ألا يكون تاريخ البداية بعد تاريخ النهاية.';

  @override
  String get valInvalidDuration => 'أدخل مدة صالحة.';

  @override
  String get valBreakTooLong =>
      'يجب أن تكون الاستراحة أقصر من المدة الإجمالية.';

  @override
  String get valTooLong => 'النص طويل جداً.';

  @override
  String get valInvalidMultiplier => 'يجب أن يكون المعامل بين 0% و1000%.';

  @override
  String get valInvalidDayFraction => 'يجب أن يكون جزء اليوم بين 0.01 و2.';

  @override
  String get valInvalidDayOfMonth => 'اختر يوماً بين 1 و28.';

  @override
  String get authLoginTitle => 'مرحباً بعودتك';

  @override
  String get authLoginSubtitle => 'سجّل الدخول إلى حسابك';

  @override
  String get authEmail => 'البريد الإلكتروني';

  @override
  String get authPassword => 'كلمة المرور';

  @override
  String get authConfirmPassword => 'تأكيد كلمة المرور';

  @override
  String get authFullName => 'الاسم الكامل';

  @override
  String get authLogin => 'تسجيل الدخول';

  @override
  String get authRegister => 'إنشاء حساب';

  @override
  String get authRegisterTitle => 'أنشئ حسابك';

  @override
  String get authForgotPassword => 'هل نسيت كلمة المرور؟';

  @override
  String get authNoAccount => 'ليس لديك حساب؟ سجّل الآن';

  @override
  String get authHaveAccount => 'لديك حساب بالفعل؟ سجّل الدخول';

  @override
  String get authForgotTitle => 'إعادة تعيين كلمة المرور';

  @override
  String get authForgotSubtitle =>
      'أدخل بريدك الإلكتروني وسنرسل لك رابط إعادة التعيين.';

  @override
  String get authSendResetLink => 'إرسال رابط إعادة التعيين';

  @override
  String get authResetSent =>
      'إذا كان هناك حساب بهذا البريد، فقد تم إرسال رابط إعادة التعيين.';

  @override
  String get authResetTitle => 'تعيين كلمة مرور جديدة';

  @override
  String get authNewPassword => 'كلمة المرور الجديدة';

  @override
  String get authUpdatePassword => 'تحديث كلمة المرور';

  @override
  String get authPasswordUpdated => 'تم تحديث كلمة المرور.';

  @override
  String get authConfirmEmailTitle => 'أكّد بريدك الإلكتروني';

  @override
  String authConfirmEmailBody(String email) {
    return 'أرسلنا رابط تأكيد إلى $email. افتحه على هذا الجهاز لتفعيل حسابك.';
  }

  @override
  String get authResend => 'إعادة إرسال البريد';

  @override
  String authResendIn(int seconds) {
    return 'يمكن إعادة الإرسال خلال $seconds ثانية';
  }

  @override
  String get authResendDone => 'تمت إعادة إرسال بريد التأكيد.';

  @override
  String get authChangeEmail => 'استخدام بريد إلكتروني آخر';

  @override
  String get authLogout => 'تسجيل الخروج';

  @override
  String get authPasswordStrengthWeak => 'كلمة مرور ضعيفة';

  @override
  String get authPasswordStrengthFair => 'كلمة مرور مقبولة';

  @override
  String get authPasswordStrengthStrong => 'كلمة مرور قوية';

  @override
  String get onbStepProfile => 'عنك';

  @override
  String get onbStepSalary => 'مصدر الدخل';

  @override
  String get onbStepAccount => 'الحساب الأول';

  @override
  String get onbStepReview => 'المراجعة';

  @override
  String get onbWelcome => 'لنقم بإعداد مساحة عملك';

  @override
  String get onbLanguage => 'اللغة';

  @override
  String get onbCurrency => 'العملة';

  @override
  String get onbTimezone => 'المنطقة الزمنية';

  @override
  String get onbWeekStart => 'يبدأ الأسبوع يوم';

  @override
  String get onbWeekendDays => 'أيام العطلة الأسبوعية';

  @override
  String onbStepProgress(int current, int total) {
    return 'الخطوة $current من $total';
  }

  @override
  String get onbReviewTitle => 'راجع إعداداتك';

  @override
  String get onbFinish => 'إنهاء الإعداد';

  @override
  String get salBaseSalary => 'الراتب الأساسي';

  @override
  String get salPeriodStartDay => 'يوم بداية الفترة';

  @override
  String get salPaymentDay => 'يوم الدفع';

  @override
  String get salPaymentMonthOffset => 'شهر الدفع';

  @override
  String get salOffsetSameMonth => 'نفس الشهر';

  @override
  String get salOffsetNextMonth => 'الشهر التالي';

  @override
  String get salOffsetSecondMonth => 'بعد شهرين';

  @override
  String get salStandardPaidDays => 'أيام العمل المدفوعة القياسية في الفترة';

  @override
  String get salStandardHours => 'ساعات العمل القياسية في اليوم';

  @override
  String get salDayRate => 'أجر اليوم';

  @override
  String get salHourRate => 'أجر الساعة';

  @override
  String get salRateDerived => 'محسوب تلقائياً';

  @override
  String get salRateManual => 'يدوي';

  @override
  String get salManualDayRate => 'أجر اليوم اليدوي';

  @override
  String get salManualHourRate => 'أجر الساعة اليدوي';

  @override
  String get salMultipliers => 'المعاملات';

  @override
  String get salExtraDayMultiplier => 'معامل اليوم الإضافي (%)';

  @override
  String get salHolidayMultiplier => 'معامل العطلة الرسمية (%)';

  @override
  String get salOvertimeMultiplier => 'معامل العمل الإضافي (%)';

  @override
  String get salHolidaySemantics => 'طريقة احتساب أجر العطلة';

  @override
  String get salSemanticsAdditional => 'أجر إضافي فوق الأساسي';

  @override
  String get salSemanticsTotal => 'الإجمالي شاملاً الأساسي';

  @override
  String salDerivedDayRate(String amount) {
    return 'أجر اليوم المحسوب: $amount';
  }

  @override
  String salDerivedHourRate(String amount) {
    return 'أجر الساعة المحسوب: $amount';
  }

  @override
  String get accName => 'اسم الحساب';

  @override
  String get accType => 'نوع الحساب';

  @override
  String get accTypeCurrent => 'الرصيد الجاري';

  @override
  String get accTypeSavings => 'مدخرات';

  @override
  String get accTypeCash => 'نقدي';

  @override
  String get accTypeBank => 'بنك';

  @override
  String get accTypeWallet => 'محفظة';

  @override
  String get accTypeEmergency => 'صندوق الطوارئ';

  @override
  String get accTypeVacation => 'صندوق الإجازات';

  @override
  String get accTypeCustom => 'مخصص';

  @override
  String get accOpeningBalance => 'الرصيد الافتتاحي';

  @override
  String get accAllowNegative => 'السماح بالرصيد السالب';

  @override
  String get setAppearance => 'المظهر';

  @override
  String get setSecurity => 'الخصوصية والأمان';

  @override
  String get privacyMoneyTitle => 'إخفاء المبالغ المالية';

  @override
  String get privacyMoneyHelp =>
      'تمويه الأرصدة والمبالغ. اضغط على مبلغ مخفي ثم أكّد هويتك ببصمة الإصبع أو الوجه أو قفل شاشة الهاتف لإظهاره.';

  @override
  String get privacyAppLockTitle => 'قفل Finance Suit بأمان الجهاز';

  @override
  String get privacyAppLockHelp =>
      'اطلب بصمة الإصبع أو الوجه أو رمز PIN أو النمط أو كلمة المرور أو رمز الدخول عند فتح التطبيق أو العودة إليه.';

  @override
  String get privacyDeviceAuthUnavailableHelp =>
      'أعِدّ رمز PIN أو كلمة مرور أو رمز دخول أو نمطًا أو بصمة إصبع أو وجهًا على هذا الهاتف لاستخدام هذه الخيارات.';

  @override
  String get privacyDeviceAuthUnavailable =>
      'أمان الجهاز غير متاح. أعِدّ قفل شاشة الهاتف أولًا.';

  @override
  String get privacyDeviceAuthFailed => 'تعذّر تأكيد هويتك. حاول مرة أخرى.';

  @override
  String get privacyEnableMoneyReason =>
      'أكّد هويتك لحماية المبالغ المالية في Finance Suit.';

  @override
  String get privacyEnableAppLockReason =>
      'أكّد هويتك لتفعيل قفل تطبيق Finance Suit.';

  @override
  String get privacyDisableMoneyReason =>
      'أكّد هويتك لإيقاف إخفاء المبالغ المالية في Finance Suit.';

  @override
  String get privacyDisableAppLockReason =>
      'أكّد هويتك لتعطيل قفل تطبيق Finance Suit.';

  @override
  String get privacyRevealReason =>
      'أكّد هويتك لإظهار المبالغ المالية في Finance Suit.';

  @override
  String get privacyHiddenAmountLabel => 'مبلغ مالي مخفي';

  @override
  String get privacyRevealAmountHint =>
      'استخدم القياسات الحيوية أو قفل شاشة الهاتف لإظهاره';

  @override
  String get privacyUnlockReason => 'أكّد هويتك لفتح Finance Suit.';

  @override
  String get privacyUnlockTitle => 'Finance Suit مقفل';

  @override
  String get privacyUnlockBody =>
      'استخدم بصمة الإصبع أو التعرّف على الوجه أو رمز PIN أو النمط أو كلمة مرور الهاتف أو رمز الدخول.';

  @override
  String get privacyUnlockButton => 'فتح بأمان الجهاز';

  @override
  String get privacyUsePassword =>
      'استخدام كلمة مرور Finance Suit بدلًا من ذلك';

  @override
  String get setTheme => 'السمة';

  @override
  String get setThemeSystem => 'النظام';

  @override
  String get setThemeLight => 'فاتح';

  @override
  String get setThemeDark => 'داكن';

  @override
  String get setProfileSection => 'الملف الشخصي';

  @override
  String get setDisplayName => 'الاسم المعروض';

  @override
  String get setChangePassword => 'تغيير كلمة المرور';

  @override
  String get setChangeEmail => 'تغيير البريد الإلكتروني';

  @override
  String get setNewEmail => 'البريد الإلكتروني الجديد';

  @override
  String get setEmailChangeSent =>
      'تم إرسال رابط تأكيد إلى البريد الإلكتروني الجديد.';

  @override
  String get setSalarySection => 'إعدادات الراتب';

  @override
  String get setPreferencesSection => 'التفضيلات';

  @override
  String get setAccountSection => 'الحساب';

  @override
  String get setSignOutConfirmTitle => 'تسجيل الخروج؟';

  @override
  String get setSignOutConfirmBody => 'يمكنك تسجيل الدخول مرة أخرى في أي وقت.';

  @override
  String get setSaved => 'تم الحفظ';

  @override
  String get setAboutSection => 'حول التطبيق';

  @override
  String get setAppVersion => 'إصدار التطبيق';

  @override
  String get setPrivacyPolicy => 'سياسة الخصوصية';

  @override
  String get setTerms => 'الشروط والأحكام';

  @override
  String get setDeleteAccount => 'حذف الحساب';

  @override
  String get setDeleteAccountSubtitle => 'حذف حسابك وبيانات التطبيق نهائياً';

  @override
  String get deleteAccountTitle => 'حذف حسابك';

  @override
  String get deleteAccountWarning => 'هذا الإجراء نهائي ولا يمكن التراجع عنه.';

  @override
  String get deleteAccountDataList =>
      'سيتم حذف ملف Finance Suit وإعدادات الراتب وسجلات العمل والحسابات والفئات والمعاملات والماكرو والمبالغ المعلّقة. سيبقى تسجيل الدخول المشترك وبيانات البوابات الأخرى.';

  @override
  String get deleteAccountPasswordPrompt => 'أكّد كلمة المرور';

  @override
  String get deleteAccountAcknowledge =>
      'أفهم أنه سيتم حذف ملف Finance Suit وبياناته نهائياً.';

  @override
  String get deleteAccountFinalTitle => 'هل تريد حذف الحساب نهائياً؟';

  @override
  String get deleteAccountFinalBody =>
      'سيحذف Finance Suit ملفك وبيانات التطبيق النشطة الآن. سيبقى تسجيل الدخول المشترك وبيانات البوابات الأخرى، وسيتم تسجيل خروجك من هذا الجهاز.';

  @override
  String get deleteAccountConfirmButton => 'حذف حسابي';

  @override
  String get deleteAccountFailure =>
      'تعذّر حذف حسابك. تحقق من الاتصال وكلمة المرور ثم حاول مرة أخرى أو تواصل مع الدعم.';

  @override
  String get deleteAccountPolicy => 'كيف يعمل حذف الحساب';

  @override
  String get moneyAccountsTab => 'الحسابات';

  @override
  String get moneyTransactionsTab => 'المعاملات';

  @override
  String get moneyTotalBalance => 'الرصيد الإجمالي';

  @override
  String get moneyNewAccount => 'حساب جديد';

  @override
  String get moneyEditAccount => 'تعديل الحساب';

  @override
  String get moneyNoAccounts => 'لا توجد حسابات بعد. أضف حسابًا للبدء.';

  @override
  String get moneyNoTransactions => 'لا توجد معاملات بعد.';

  @override
  String get moneyDefaultLabel => 'افتراضي';

  @override
  String get moneyArchivedLabel => 'مؤرشف';

  @override
  String get moneySetDefault => 'تعيين كافتراضي';

  @override
  String get moneyArchive => 'أرشفة';

  @override
  String get moneyUnarchive => 'إلغاء الأرشفة';

  @override
  String get moneyShowArchived => 'عرض المؤرشفة';

  @override
  String get moneyArchiveConfirmTitle => 'أرشفة الحساب؟';

  @override
  String get moneyArchiveConfirmBody =>
      'الحسابات المؤرشفة تختفي من القوائم ولا تستقبل معاملات جديدة. يبقى السجل السابق كما هو.';

  @override
  String get txExpense => 'مصروف';

  @override
  String get txAllowance => 'مصروف شخصي لشخص آخر';

  @override
  String get txCustomIncome => 'دخل آخر';

  @override
  String get txFreelanceIncome => 'دخل عمل حر';

  @override
  String get txSalaryIncome => 'راتب';

  @override
  String get txTransfer => 'تحويل';

  @override
  String get txAddTitle => 'إضافة معاملة';

  @override
  String get txEditTitle => 'تعديل المعاملة';

  @override
  String get txAccount => 'الحساب';

  @override
  String get txFromAccount => 'من حساب';

  @override
  String get txToAccount => 'إلى حساب';

  @override
  String get txCategory => 'الفئة';

  @override
  String get txNoCategory => 'بدون فئة';

  @override
  String get txCounterparty => 'أُعطي إلى';

  @override
  String get txTitleField => 'العنوان';

  @override
  String get txDeleteConfirmTitle => 'حذف المعاملة؟';

  @override
  String get txDeleteConfirmBody =>
      'سيؤدي هذا إلى حذف المعاملة نهائيًا وتحديث أرصدة الحسابات.';

  @override
  String get txSalaryLocked =>
      'تُدار دفعات الراتب من فترات الراتب ولا يمكن تعديلها هنا.';

  @override
  String get macrosTitle => 'الماكرو';

  @override
  String get macroManage => 'إدارة الماكرو';

  @override
  String get macroNew => 'ماكرو جديد';

  @override
  String get macroEditTitle => 'تعديل الماكرو';

  @override
  String get macroName => 'اسم الماكرو';

  @override
  String get macroActions => 'الإجراءات';

  @override
  String get macroAddAction => 'إضافة إجراء';

  @override
  String get macroNoActions => 'أضف إجراءً واحدًا على الأقل.';

  @override
  String get macroReversible => 'قابل للعكس';

  @override
  String get macroReversibleHint =>
      'يُدرج هذا الإجراء عند تشغيل الماكرو بالعكس';

  @override
  String get macroReversibleBadge => 'قابل للعكس';

  @override
  String get macroRun => 'تشغيل';

  @override
  String get macroRunReverse => 'تشغيل بالعكس';

  @override
  String macroRunTo(String name) {
    return 'إلى $name';
  }

  @override
  String macroRunFrom(String name) {
    return 'من $name';
  }

  @override
  String macroApplied(int count) {
    return 'تمت إضافة $count من المعاملات';
  }

  @override
  String macroActionCount(int count) {
    return '$count من الإجراءات';
  }

  @override
  String get macroEmpty =>
      'لا توجد ماكرو بعد. احفظ المعاملات المتكررة وشغّلها بلمسة واحدة.';

  @override
  String get macroDeleteConfirmTitle => 'حذف الماكرو؟';

  @override
  String get macroDeleteConfirmBody =>
      'سيُحذف الماكرو وإجراءاته، وتبقى المعاملات التي أنشأها.';

  @override
  String get errMacroNotReversible =>
      'لا يحتوي هذا الماكرو على إجراءات قابلة للعكس.';

  @override
  String get errMacroEmpty => 'يحتاج الماكرو إلى إجراء واحد على الأقل.';

  @override
  String get moneyHeldTab => 'محجوز';

  @override
  String get heldTitle => 'المبالغ المحجوزة';

  @override
  String get heldNew => 'مبلغ محجوز جديد';

  @override
  String get heldEditTitle => 'تعديل المبلغ المحجوز';

  @override
  String get heldDirection => 'الاتجاه';

  @override
  String get heldDirectionIOwe => 'أنا مدين لشخص';

  @override
  String get heldDirectionOwedToMe => 'مستحق لي';

  @override
  String get heldOwedTo => 'مستحق لـ';

  @override
  String get heldOwedBy => 'مستحق على';

  @override
  String get heldTotalIOwe => 'إجمالي ما عليّ';

  @override
  String get heldTotalOwedToMe => 'إجمالي المستحق لي';

  @override
  String get heldEmpty =>
      'لا توجد مبالغ محجوزة بعد. تتبّع ما عليك من أموال أو ما هو مستحق لك، بشكل مستقل أو مرتبط بمعاملة.';

  @override
  String get heldSettle => 'تحديد كمُسدد';

  @override
  String get heldUnsettle => 'إعادة تنشيط';

  @override
  String get heldSettledLabel => 'مُسدد';

  @override
  String get heldShowSettled => 'عرض المُسدد';

  @override
  String get heldLinkedTransaction => 'مرتبط بمعاملة';

  @override
  String get heldHoldForTransaction => 'حجز مبلغ لهذه المعاملة';

  @override
  String get heldDeleteConfirmTitle => 'حذف المبلغ المحجوز؟';

  @override
  String get heldDeleteConfirmBody =>
      'سيُحذف المبلغ المحجوز. إذا أنشأ معاملة حساب، فستُحذف المعاملة أيضًا ويتحدث الرصيد.';

  @override
  String get catManage => 'إدارة الفئات';

  @override
  String get catNew => 'فئة جديدة';

  @override
  String get catName => 'اسم الفئة';

  @override
  String get catKind => 'نوع الفئة';

  @override
  String get catKindExpense => 'فئة مصروفات';

  @override
  String get catKindAllowance => 'فئة مصروف شخصي';

  @override
  String get catKindIncome => 'فئة دخل';

  @override
  String get catNoneYet => 'لا توجد فئات من هذا النوع بعد.';

  @override
  String get salPeriodsTitle => 'فترات الراتب';

  @override
  String get salCurrentPeriod => 'الفترة الحالية';

  @override
  String salEstimatedFor(String month) {
    return 'راتب $month المقدر';
  }

  @override
  String salBasedOn(String start, String end) {
    return 'بناءً على العمل من $start إلى $end';
  }

  @override
  String salExpectedPayment(String date) {
    return 'تاريخ الدفع المتوقع: $date';
  }

  @override
  String get salStatusOpen => 'مفتوحة';

  @override
  String get salStatusFinalized => 'مُثبتة';

  @override
  String get salStatusPaid => 'مدفوعة';

  @override
  String get salBreakdown => 'التفاصيل';

  @override
  String get salEstimatedTotal => 'الإجمالي المقدر';

  @override
  String get salItemExtraDays => 'أيام إضافية';

  @override
  String get salItemHolidays => 'عطلات رسمية تم العمل فيها';

  @override
  String get salItemOvertime => 'عمل إضافي';

  @override
  String get salItemBonuses => 'مكافآت';

  @override
  String get salItemDeductions => 'خصومات';

  @override
  String get salAdjustments => 'التعديلات';

  @override
  String get salNewAdjustment => 'تعديل جديد';

  @override
  String get salEditAdjustment => 'تحرير التعديل';

  @override
  String get salAdjBonus => 'مكافأة';

  @override
  String get salAdjDeduction => 'خصم';

  @override
  String get salEffectiveDate => 'تاريخ السريان';

  @override
  String get salNoAdjustments => 'لا توجد تعديلات في هذه الفترة.';

  @override
  String get salDeleteAdjTitle => 'حذف التعديل؟';

  @override
  String get salDeleteAdjBody => 'سيؤدي هذا إلى إزالة التعديل نهائيًا.';

  @override
  String get salFinalize => 'تثبيت الفترة';

  @override
  String get salFinalizeConfirmTitle => 'تثبيت هذه الفترة؟';

  @override
  String get salFinalizeConfirmBody =>
      'سيتم حفظ لقطة ثابتة من الحساب الحالي، ولن تتأثر بتغييرات الإعدادات اللاحقة.';

  @override
  String get salReopen => 'إعادة فتح الفترة';

  @override
  String get salReopenConfirmTitle => 'إعادة فتح هذه الفترة؟';

  @override
  String get salReopenConfirmBody =>
      'سيتم استبدال اللقطة المحفوظة عند التثبيت مرة أخرى.';

  @override
  String get salMarkPaid => 'تسجيل الاستلام';

  @override
  String get salActualAmount => 'المبلغ الفعلي المستلم';

  @override
  String get salReceivedDate => 'تاريخ الاستلام';

  @override
  String get salDestinationAccount => 'حساب الإيداع';

  @override
  String get salActualReceived => 'المستلم فعليًا';

  @override
  String get salDifference => 'الفرق عن التقدير';

  @override
  String get salNoPeriods => 'لا توجد فترات راتب بعد.';

  @override
  String get salNoOpenPeriods => 'لا توجد فترات راتب مفتوحة متاحة.';

  @override
  String get salPeriodNoLongerOpen =>
      'لم تعد فترة الراتب هذه مفتوحة. حدّث القائمة واختر فترة مفتوحة.';

  @override
  String get salWarnBaseZero => 'لم يتم ضبط الراتب الأساسي بعد.';

  @override
  String get salWarnMissingAmounts => 'بعض سجلات العمل بلا مبلغ محفوظ.';

  @override
  String get workEntryType => 'نوع السجل';

  @override
  String get workEntryRegular => 'يوم عمل عادي';

  @override
  String get workEntryOvertime => 'عمل إضافي';

  @override
  String get workEntryExtraDay => 'يوم إضافي';

  @override
  String get workEntryHoliday => 'عمل في عطلة رسمية';

  @override
  String get workAddEntry => 'إضافة سجل عمل';

  @override
  String get workEditEntry => 'تعديل سجل العمل';

  @override
  String get workNoEntries => 'لا توجد سجلات عمل هذا الشهر.';

  @override
  String get workNoEntriesForDay => 'لا توجد سجلات في هذا اليوم.';

  @override
  String get workStartTime => 'وقت البدء';

  @override
  String get workEndTime => 'وقت الانتهاء';

  @override
  String get workBreakMinutes => 'الاستراحة (دقائق)';

  @override
  String get workDurationMinutes => 'المدة (دقائق)';

  @override
  String get workDayUnits => 'أيام العمل (مثال: 1 أو 0.5)';

  @override
  String get workMultiplier => 'نسبة المضاعف %';

  @override
  String get workCustomRate => 'سعر مخصص';

  @override
  String get workLinkedHoliday => 'العطلة الرسمية';

  @override
  String get workEstimatedPay => 'الأجر الإضافي المقدر';

  @override
  String get workHolidays => 'العطلات الرسمية';

  @override
  String get workNewHoliday => 'عطلة جديدة';

  @override
  String get workEditHoliday => 'تعديل العطلة';

  @override
  String get workHolidayName => 'اسم العطلة';

  @override
  String get workNoHolidays => 'لا توجد عطلات رسمية بعد.';

  @override
  String get workDeleteEntryTitle => 'حذف سجل العمل؟';

  @override
  String get workDeleteEntryBody => 'سيؤدي هذا إلى حذف سجل العمل نهائيًا.';

  @override
  String get workDeleteHolidayTitle => 'حذف العطلة؟';

  @override
  String get workDeleteHolidayBody =>
      'تحتفظ سجلات العمل المرتبطة بأجرها المسجل لكنها تفقد الارتباط بالعطلة.';

  @override
  String get workMonthTotal => 'الأجر الإضافي هذا الشهر';

  @override
  String workDurationHm(int hours, int minutes) {
    return '$hoursس $minutesد';
  }

  @override
  String get homeBalance => 'الرصيد';

  @override
  String get homeDefaultAccount => 'الحساب الافتراضي';

  @override
  String get homeSavings => 'المدخرات';

  @override
  String get homeCashFlow => 'التدفق النقدي';

  @override
  String get homeSalary => 'الراتب';

  @override
  String get homeRecentActivity => 'النشاط الأخير';

  @override
  String get homeNoRecentActivity => 'لا يوجد نشاط حديث.';

  @override
  String get historyTitle => 'السجل';

  @override
  String get historyNoItems => 'لا توجد سجلات مطابقة لهذه الفلاتر.';

  @override
  String get historyLoadMore => 'تحميل المزيد';

  @override
  String get historyBusinessDate => 'تاريخ السجل';

  @override
  String get historyActiveFilters => 'الفلاتر النشطة';

  @override
  String get historyCustomRange => 'نطاق مخصص';

  @override
  String get historySortRecordDesc => 'أحدث تاريخ سجل';

  @override
  String get historySortRecordAsc => 'أقدم تاريخ سجل';

  @override
  String get historySortAmountDesc => 'أعلى مبلغ';

  @override
  String get historySortAmountAsc => 'أقل مبلغ';

  @override
  String get historySortCreatedDesc => 'الأحدث إنشاءً';

  @override
  String get historyFilterWork => 'العمل';

  @override
  String get historyFilterRegularWork => 'عمل عادي';

  @override
  String get historyFilterSalaryAdjustment => 'تعديل راتب';

  @override
  String get rangeCurrentMonth => 'الشهر الحالي';

  @override
  String get rangeLast30 => 'آخر 30 يومًا';

  @override
  String get rangePreviousMonth => 'الشهر السابق';

  @override
  String get rangeLast90 => 'آخر 90 يومًا';

  @override
  String get rangeToday => 'اليوم';

  @override
  String get rangeLast7 => 'آخر 7 أيام';

  @override
  String get rangeCurrentYear => 'السنة الحالية';

  @override
  String get reportsCashFlow => 'الدخل والمصروفات والمصروفات الشخصية';

  @override
  String get reportsNetOverTime => 'صافي التدفق النقدي بمرور الوقت';

  @override
  String get reportsExpensesByCategory => 'المصروفات حسب الفئة';

  @override
  String get reportsAllowancesByCategory => 'المصروفات الشخصية حسب الفئة';

  @override
  String get reportsIncomeByCategory => 'الدخل حسب المصدر';

  @override
  String get reportsAccountBalance => 'رصيد الحساب بمرور الوقت';

  @override
  String get reportsSalaryComparison => 'الراتب المقدر مقابل الفعلي';

  @override
  String get reportsWorkCompensation => 'تعويضات العمل حسب فترة الراتب';

  @override
  String get reportsWorkingHours => 'ساعات العمل';

  @override
  String get reportsNoData => 'لا توجد بيانات تقارير في هذا النطاق.';

  @override
  String get reportsBucketDay => 'يومي';

  @override
  String get reportsBucketWeek => 'أسبوعي';

  @override
  String get reportsBucketMonth => 'شهري';

  @override
  String get reportIncome => 'الدخل';

  @override
  String get reportExpenses => 'المصروفات';

  @override
  String get reportAllowances => 'المصروفات الشخصية';

  @override
  String get reportNet => 'الصافي';

  @override
  String get reportEstimated => 'المقدر';

  @override
  String get reportActual => 'الفعلي';

  @override
  String get reportOvertime => 'عمل إضافي';

  @override
  String get reportExtraDays => 'أيام إضافية';

  @override
  String get reportHolidays => 'عطلات';

  @override
  String get reportHours => 'ساعات';

  @override
  String get catParent => 'الفئة الرئيسية (اختياري)';

  @override
  String get catTopLevel => 'بدون فئة رئيسية — فئة عادية';

  @override
  String catSubcategoryOf(String parent) {
    return 'فئة فرعية من $parent';
  }

  @override
  String get catSubcategoryOptional => 'الفئة الفرعية (اختياري)';

  @override
  String get catUseParentCategory => 'بدون فئة فرعية — استخدم الفئة الرئيسية';

  @override
  String get catAddSubcategory => 'إضافة فئة فرعية';

  @override
  String catSubcategoryCount(int count) {
    return '$count فئات فرعية';
  }

  @override
  String get catMissingParent => 'الفئة الرئيسية مفقودة';

  @override
  String get catArchiveChildrenFirst => 'أرشف الفئات الفرعية المفعلة أولًا.';

  @override
  String get catRestoreParentFirst =>
      'استعد الفئة الرئيسية قبل استعادة هذه الفئة الفرعية.';

  @override
  String get incomeHasSalary => 'أتقاضى راتبًا';

  @override
  String get incomeHasSalaryHelp =>
      'أوقف هذا الخيار إذا كان دخلك مصروفًا دوريًا أو من مصادر أخرى.';

  @override
  String get incomeSourcesTitle => 'أتمتة مصادر الدخل';

  @override
  String get incomeSourcesSubtitle =>
      'جدولة الراتب والمصروف الدوري ومصادر الدخل الأخرى';

  @override
  String get incomeAddSource => 'إضافة مصدر دخل';

  @override
  String get incomeEditSource => 'تعديل مصدر الدخل';

  @override
  String get incomeNoSources => 'لا توجد مصادر دخل آلية بعد.';

  @override
  String incomeMonthlyOnDay(int day) {
    return 'شهريًا في يوم $day';
  }

  @override
  String get incomeSourceType => 'نوع الدخل';

  @override
  String get incomeSourceName => 'اسم مصدر الدخل';

  @override
  String get incomeExpectedAmount => 'المبلغ المتوقع';

  @override
  String get incomeRemainderAccount => 'حساب الإيداع والمتبقي';

  @override
  String get incomePromptBefore => 'التنبيه قبل الموعد بأيام';

  @override
  String get incomeStartDate => 'تاريخ بدء الأتمتة';

  @override
  String get incomeSplitTitle => 'تقسيم تلقائي بين الحسابات';

  @override
  String get incomeSplitHelp =>
      'أضف قواعد مرتبة للتحويل من حساب الإيداع. يبقى أي مبلغ متبقٍ في حساب الإيداع.';

  @override
  String get incomeInvalidPercentage => 'أدخل نسبة من 0 إلى 100.';

  @override
  String get incomeSplitAddRule => 'إضافة قاعدة تقسيم';

  @override
  String get incomeSplitNoRules =>
      'لا توجد قواعد تقسيم. يبقى كامل المبلغ في حساب الإيداع.';

  @override
  String incomeSplitRuleNumber(int number) {
    return 'قاعدة $number';
  }

  @override
  String get incomeSplitDestinationAccount => 'حساب الوجهة';

  @override
  String get incomeSplitMethod => 'طريقة التقسيم';

  @override
  String get incomeSplitMethodPercentage => 'نسبة مئوية';

  @override
  String get incomeSplitMethodFixed => 'مبلغ ثابت';

  @override
  String get incomeSplitCalculationBasis => 'أساس النسبة';

  @override
  String get incomeSplitBasisOriginal => 'المبلغ الأصلي';

  @override
  String get incomeSplitBasisRemaining => 'المبلغ المتبقي';

  @override
  String get incomeSplitMoveUp => 'تحريك القاعدة لأعلى';

  @override
  String get incomeSplitMoveDown => 'تحريك القاعدة لأسفل';

  @override
  String get incomeSplitInvalidAccount => 'اختر حسابًا مفعّلًا بنفس العملة.';

  @override
  String get incomeSplitIncludeExtraWork =>
      'احتساب الساعات والأيام الإضافية ضمن النسب';

  @override
  String get incomeSplitIncludeExtraWorkHelp =>
      'تظل المكافآت والخصومات جزءًا عاديًا من الراتب.';

  @override
  String get incomeSplitRouteExtraWork =>
      'حوّل كل دخل العمل الإضافي المحمي إلى حساب آخر';

  @override
  String get incomeSplitExtraWorkAccount => 'حساب وجهة العمل الإضافي';

  @override
  String get incomeRolloverTitle => 'حوّل رصيد الشهر السابق إلى الادخار';

  @override
  String get incomeRolloverHelp =>
      'عند قبول هذا الراتب، حوّل أي رصيد موجب موجود في حساب الإيداع إلى حساب الادخار المحدد قبل إيداع الراتب.';

  @override
  String get incomeRolloverNoSavings =>
      'أنشئ حساب ادخار مفعّلًا بالعملة نفسها لتفعيل هذا الخيار.';

  @override
  String get incomeRolloverAccount => 'وجهة رصيد الشهر السابق';

  @override
  String get incomeSplitPreviewTitle => 'ملخص المعاينة';

  @override
  String incomeSplitPreviewDeposit(String amount, String account) {
    return 'يدخل $amount إلى $account أولًا.';
  }

  @override
  String incomeSplitPreviewPercentageRule(
    int number,
    String percentage,
    String basis,
    String amount,
    String account,
  ) {
    return 'القاعدة $number: $percentage% من $basis = $amount إلى $account.';
  }

  @override
  String incomeSplitPreviewFixedRule(
    int number,
    String amount,
    String account,
  ) {
    return 'القاعدة $number: مبلغ ثابت $amount إلى $account.';
  }

  @override
  String get incomeSplitPreviewExtraIncluded =>
      'تدخل أرباح العمل الإضافي ضمن حساب النسب.';

  @override
  String incomeSplitPreviewExtraRouted(String account) {
    return 'تذهب أرباح العمل الإضافي المحمية إلى $account.';
  }

  @override
  String incomeSplitPreviewExtraKept(String account) {
    return 'تبقى أرباح العمل الإضافي المحمية في $account.';
  }

  @override
  String incomeRolloverPreviewMoved(
    String sourceAccount,
    String destinationAccount,
  ) {
    return 'قبل إيداع هذا الراتب، ينتقل أي رصيد موجب موجود في $sourceAccount إلى $destinationAccount.';
  }

  @override
  String incomeRolloverPreviewKept(String account) {
    return 'يبقى الرصيد الموجود في $account كما هو.';
  }

  @override
  String incomeSplitPreviewLine(String amount, String account) {
    return '$amount إلى $account';
  }

  @override
  String incomeSplitPreviewRemainder(String amount, String account) {
    return 'يبقى $amount في $account';
  }

  @override
  String get incomeSplitPreviewError => 'هذه القواعد تتجاوز الدخل المتاح.';

  @override
  String get incomeKindSalary => 'راتب';

  @override
  String get incomeKindAllowance => 'مصروف دوري مستلم';

  @override
  String get incomeKindFreelance => 'دخل عمل حر';

  @override
  String get incomeKindOther => 'دخل آخر';

  @override
  String get incomeKindNone => 'لا يوجد دخل دوري حاليًا';

  @override
  String get incomePrimaryType => 'كيف تستلم دخلك عادةً؟';

  @override
  String get incomeNoPrimaryHelp =>
      'يمكنك إكمال الإعداد بدون راتب وإضافة أي مصدر دخل لاحقًا من الإعدادات.';

  @override
  String get incomePendingTitle => 'دخل بانتظار الموافقة';

  @override
  String incomeDue(String date) {
    return 'كان متوقعًا في $date — أكّده عند وصوله';
  }

  @override
  String incomeUpcoming(String date) {
    return 'متوقع في $date — يمكنك قبوله مبكرًا';
  }

  @override
  String incomeAcceptTitle(String name) {
    return 'قبول $name؟';
  }

  @override
  String get incomeAcceptHelp =>
      'لن تُنشأ معاملة الدخل وتقسيماتها بين الحسابات إلا بعد التأكيد.';

  @override
  String get incomeAccept => 'قبول الدخل';

  @override
  String get incomeSkipTitle => 'تخطي هذا الدخل؟';

  @override
  String incomeSkipHelp(String name) {
    return 'لن ينشئ $name معاملة لهذا الشهر.';
  }

  @override
  String get incomeSkip => 'تخطي';

  @override
  String get incomeLater => 'لاحقًا';

  @override
  String get incomeRemindLater => 'تم التأجيل لمدة 24 ساعة.';

  @override
  String get incomeSnoozeFailed => 'تعذر تأجيل هذا الدخل. حاول مرة أخرى.';

  @override
  String get incomeAcceptedMessage => 'تم قبول الدخل.';

  @override
  String get incomeSkippedMessage => 'تم تخطي الدخل.';

  @override
  String get salaryBaseAmount => 'المبلغ الأساسي';

  @override
  String get salaryExtraDays => 'الأيام الإضافية';

  @override
  String get salaryOvertimeDuration => 'الوقت الإضافي';

  @override
  String get salaryHolidayWorked => 'عمل يوم عطلة';

  @override
  String get salaryEstimatedTotal => 'الإجمالي المتوقع';

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '$hoursس $minutesد';
  }

  @override
  String get incomeAutomationCenter => 'أتمتة مصادر الدخل';

  @override
  String get incomeAutomationOverview =>
      'حدد الموعد المتوقع وتقسيم الحسابات. لن يتغير رصيدك حتى توافق على الدفعة.';

  @override
  String get incomeActiveAutomations => 'الأتمتة المفعّلة';

  @override
  String get incomePausedAutomations => 'الأتمتة المتوقفة';

  @override
  String get incomeAutomationEnabled => 'الأتمتة مفعلة';

  @override
  String get incomeAutomationEnabledHelp =>
      'أوقف هذا المصدر مؤقتًا دون حذف الجدول أو قواعد التقسيم.';

  @override
  String incomeActiveCount(int count) {
    return '$count مفعّل';
  }

  @override
  String incomePausedCount(int count) {
    return '$count متوقف';
  }

  @override
  String incomePendingCount(int count) {
    return '$count بانتظارك';
  }

  @override
  String get incomeActive => 'مفعّل';

  @override
  String get incomePaused => 'متوقف';

  @override
  String get incomePause => 'إيقاف مؤقت';

  @override
  String get incomeResume => 'استئناف';

  @override
  String incomeDepositAccount(String account) {
    return 'حساب الإيداع: $account';
  }

  @override
  String incomeSplitAccount(String percentage, String account) {
    return '$percentage% إلى $account';
  }

  @override
  String incomeSplitFixedAccount(String amount, String account) {
    return '$amount إلى $account';
  }

  @override
  String incomeRemainderSplit(String percentage, String account) {
    return 'يبقى $percentage% في $account';
  }

  @override
  String get incomeNoPending => 'لا يوجد دخل ينتظر موافقتك.';

  @override
  String get addSectionAutomationControl => 'التحكم في الأتمتة';

  @override
  String get addAutomation => 'إضافة أتمتة';

  @override
  String get manageAutomations => 'إدارة الأتمتة';

  @override
  String get addAutomationControlHelp =>
      'جدولة الراتب أو الدخل الدوري والموافقة عليه قبل تغيير الأرصدة.';

  @override
  String get incomeAddAutomationEmpty =>
      'أضف أتمتة لجدولة الدخل الدوري. لن يتغير رصيدك حتى توافق عليه.';

  @override
  String get incomeTypeLockedOnEdit =>
      'لا يمكن تغيير نوع الأتمتة أثناء التعديل. أنشئ أتمتة جديدة لاستخدام نوع آخر.';

  @override
  String get incomeSalaryAlreadyExists =>
      'توجد أتمتة راتب بالفعل. عدّلها أو استأنفها بدلاً من ذلك.';

  @override
  String get homePartialDataError =>
      'تعذر تحميل بعض أقسام لوحة التحكم. ستظل البيانات الأخرى المتاحة ظاهرة.';

  @override
  String get reportStartingBalance => 'رصيد البداية';

  @override
  String get reportEndingBalance => 'رصيد النهاية';

  @override
  String get selectionSearchHint => 'ابحث في الخيارات';

  @override
  String get heldLinkedTransactionReference => 'المعاملة الأصلية مرتبطة كمرجع';

  @override
  String get heldSettlementTransactionHelp =>
      'ينشئ التحصيل أو السداد معاملة منفصلة للحساب المحدد.';

  @override
  String get onboardingSubmitFailed =>
      'تعذر إكمال الإعداد. راجع البيانات وحاول مرة أخرى.';

  @override
  String get updateAvailableTitle => 'تحديث متاح';

  @override
  String get updateAvailableBody =>
      'يتوفر إصدار جديد من Finance Suit. حدّث الآن للحصول على أحدث التحسينات.';

  @override
  String get updateLater => 'لاحقًا';

  @override
  String get updateNow => 'تحديث';

  @override
  String get heldTypeLabel => 'النوع';

  @override
  String get heldSettleTitle => 'تسوية المبلغ المعلق';

  @override
  String get heldSettleDateLabel => 'تاريخ التسوية';

  @override
  String get heldSettleHelp => 'سيتم تسجيل المعاملة بهذا التاريخ.';
}
