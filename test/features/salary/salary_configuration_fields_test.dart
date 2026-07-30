import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/salary/domain/salary_settings.dart';
import 'package:work_tracker/features/salary/presentation/models/salary_configuration_draft.dart';
import 'package:work_tracker/features/salary/presentation/widgets/salary_configuration_fields.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

void main() {
  test('shared draft owns defaults and derived rates', () {
    final draft = SalaryConfigurationDraft.defaults();
    addTearDown(draft.dispose);
    draft.baseSalaryController.text = '2200';

    expect(draft.derivedDayRate('EGP')!.minor, 10000);
    expect(draft.derivedHourRate('EGP')!.minor, 1250);
    expect(draft.periodStartDay, 1);
    expect(draft.paymentDay, 1);
    expect(draft.paymentMonthOffset, 1);
  });

  test('disabling salary preserves the last configured amount', () {
    const settings = SalarySettings(
      salaryEnabled: true,
      baseSalaryMinor: 123456,
      currencyCode: 'EGP',
      salaryPeriodStartDay: 2,
      paymentDay: 25,
      paymentMonthOffset: 1,
      standardPaidDaysPerPeriod: 22,
      standardMinutesPerDay: 480,
      dayRateMode: RateMode.derived,
      manualDayRateMinor: null,
      hourRateMode: RateMode.derived,
      manualHourRateMinor: null,
      extraDayMultiplierPct: 100,
      officialHolidayMultiplierPct: 200,
      overtimeMultiplierPct: 150,
      holidaySemantics: HolidayMultiplierSemantics.additionalPay,
      roundingMode: RoundingMode.halfUp,
    );
    final draft = SalaryConfigurationDraft.fromSettings(settings);
    addTearDown(draft.dispose);
    final disabled = draft.toSettings(
      salaryEnabled: false,
      currencyCode: 'EGP',
      fallback: settings,
    );

    expect(disabled.salaryEnabled, isFalse);
    expect(disabled.baseSalaryMinor, 123456);
    expect(disabled.paymentDay, 25);
  });

  testWidgets(
    'shared fields expose canonical validation and fit a small phone',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final draft = SalaryConfigurationDraft.defaults();
      addTearDown(draft.dispose);
      final formKey = GlobalKey<FormState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: SalaryConfigurationFields(
                  draft: draft,
                  currencyCode: 'EGP',
                  onChanged: () {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(formKey.currentState!.validate(), isFalse);
      await tester.enterText(find.byType(TextFormField).first, '2200');
      expect(formKey.currentState!.validate(), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
