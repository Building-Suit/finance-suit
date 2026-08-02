import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/widgets/app_money_text.dart';

Widget _host(Widget child, {Locale locale = const Locale('en')}) =>
    ProviderScope(
      child: MaterialApp(
        locale: locale,
        theme: AppTheme.light(locale: locale),
        home: Directionality(textDirection: TextDirection.rtl, child: child),
      ),
    );

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('renders amount before currency and supports explicit signs', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const Column(
          children: [
            AppMoneyText(money: Money(minor: 159123, currencyCode: 'EGP')),
            AppMoneyText(
              money: Money(minor: 46123, currencyCode: 'EGP'),
              sign: AppMoneySign.explicit,
            ),
            AppMoneyText(
              money: Money(minor: -130347, currencyCode: 'EGP'),
              sign: AppMoneySign.explicit,
            ),
          ],
        ),
      ),
    );

    expect(find.textContaining('1,591.23'), findsOneWidget);
    expect(find.textContaining('+461.23'), findsOneWidget);
    expect(find.textContaining('-1,303.47'), findsOneWidget);
    expect(find.textContaining('EGP'), findsNWidgets(3));
  });

  testWidgets('uses an internal LTR direction in Arabic', (tester) async {
    await tester.pumpWidget(
      _host(
        const AppMoneyText(money: Money(minor: 159123, currencyCode: 'EGP')),
        locale: const Locale('ar'),
      ),
    );

    final directionality = tester.widget<Directionality>(
      find
          .ancestor(
            of: find.textContaining('EGP'),
            matching: find.byType(Directionality),
          )
          .first,
    );
    expect(directionality.textDirection, TextDirection.ltr);
  });
}
