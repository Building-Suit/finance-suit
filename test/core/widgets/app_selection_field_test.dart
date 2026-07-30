import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/widgets/app_selection_field.dart';

enum _Choice { first, second }

Widget _host(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  locale: locale,
  theme: AppTheme.light(locale: locale),
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

void main() {
  testWidgets('selects enum and integer values through the bottom sheet', (
    tester,
  ) async {
    _Choice? choice;
    int? day;
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            AppSelectionField<_Choice>(
              key: const Key('enum-field'),
              initialValue: _Choice.first,
              decoration: const InputDecoration(labelText: 'Choice'),
              items: const [
                DropdownMenuItem(value: _Choice.first, child: Text('First')),
                DropdownMenuItem(value: _Choice.second, child: Text('Second')),
              ],
              onChanged: (value) => choice = value,
            ),
            AppSelectionField<int>(
              key: const Key('day-field'),
              initialValue: 1,
              decoration: const InputDecoration(labelText: 'Day'),
              items: const [
                DropdownMenuItem(value: 1, child: Text('1')),
                DropdownMenuItem(value: 2, child: Text('2')),
              ],
              onChanged: (value) => day = value,
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('enum-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second').last);
    await tester.pumpAndSettle();
    expect(choice, _Choice.second);

    await tester.tap(find.byKey(const Key('day-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2').last);
    await tester.pumpAndSettle();
    expect(day, 2);
  });

  testWidgets('explicit nullable choice differs from dismissing the sheet', (
    tester,
  ) async {
    var calls = 0;
    String? value = 'account';
    await tester.pumpWidget(
      _host(
        AppSelectionField<String?>(
          key: const Key('nullable-field'),
          initialValue: value,
          decoration: const InputDecoration(labelText: 'Category'),
          items: const [
            DropdownMenuItem(value: null, child: Text('No category')),
            DropdownMenuItem(value: 'account', child: Text('Account')),
          ],
          onChanged: (selected) {
            calls++;
            value = selected;
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('nullable-field')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(value, 'account');

    await tester.tap(find.byKey(const Key('nullable-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No category'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(value, isNull);
  });

  testWidgets('supports validation and search for long option lists', (
    tester,
  ) async {
    final key = GlobalKey<FormState>();
    String? selected;
    await tester.pumpWidget(
      _host(
        Form(
          key: key,
          child: AppSelectionField<String>(
            key: const Key('search-field'),
            decoration: const InputDecoration(labelText: 'Account'),
            items: [
              for (var index = 0; index < 10; index++)
                DropdownMenuItem(
                  value: 'account-$index',
                  child: Text('Account $index'),
                ),
            ],
            validator: (value) => value == null ? 'Required' : null,
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );

    expect(key.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Required'), findsOneWidget);
    await tester.tap(find.byKey(const Key('search-field')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Account 9');
    await tester.pump();
    expect(find.text('Account 9'), findsWidgets);
    await tester.tap(find.widgetWithText(ListTile, 'Account 9'));
    await tester.pumpAndSettle();
    expect(selected, 'account-9');
    expect(key.currentState!.validate(), isTrue);
  });

  testWidgets('long Arabic labels fit a small RTL viewport', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _host(
        AppSelectionField<String>(
          key: const Key('rtl-field'),
          initialValue: 'long',
          decoration: const InputDecoration(labelText: 'الحساب'),
          items: const [
            DropdownMenuItem(
              value: 'long',
              child: Text('حساب توفير طويل الاسم للاختبار على شاشة صغيرة'),
            ),
          ],
          onChanged: (_) {},
        ),
        locale: const Locale('ar'),
      ),
    );
    await tester.tap(find.byKey(const Key('rtl-field')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('حساب توفير'), findsWidgets);
  });
}
