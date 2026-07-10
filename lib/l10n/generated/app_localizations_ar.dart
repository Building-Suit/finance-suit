// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'متتبع العمل';

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
}
