import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/widgets/app_selection_field.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Regression tests for automatic focus advancement after committing a
/// value in the canonical selection field.
void main() {
  Widget host(Widget child, {Locale locale = const Locale('en')}) {
    return MaterialApp(
      theme: AppTheme.light(locale: locale),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );
  }

  Finder fieldInkWell(Key key) =>
      find.descendant(of: find.byKey(key), matching: find.byType(InkWell));

  Future<void> selectOption(
    WidgetTester tester,
    Key fieldKey,
    String option,
  ) async {
    await tester.tap(fieldInkWell(fieldKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  AppSelectionField<int> selection({
    required Key key,
    required ValueChanged<int?>? onChanged,
    bool enabled = true,
    String label = 'Select',
  }) {
    return AppSelectionField<int>(
      key: key,
      enabled: enabled,
      decoration: InputDecoration(labelText: label),
      items: const [
        DropdownMenuItem(value: 1, child: Text('One')),
        DropdownMenuItem(value: 2, child: Text('Two')),
      ],
      onChanged: onChanged,
    );
  }

  testWidgets('select commits then focuses the next select input', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        Column(
          children: [
            selection(key: const Key('first'), onChanged: (_) {}),
            selection(key: const Key('second'), onChanged: (_) {}),
          ],
        ),
      ),
    );

    await selectOption(tester, const Key('first'), 'One');

    final secondNode = Focus.of(
      tester.element(
        find.descendant(
          of: fieldInkWell(const Key('second')),
          matching: find.byType(InputDecorator),
        ),
      ),
    );
    expect(secondNode.hasFocus, isTrue);

    // The advanced-to select shows its focus visibly through the decorator.
    final decorator = tester.widget<InputDecorator>(
      find.descendant(
        of: fieldInkWell(const Key('second')),
        matching: find.byType(InputDecorator),
      ),
    );
    expect(decorator.isFocused, isTrue);
  });

  testWidgets('select commits then focuses the next text input', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        Column(
          children: [
            selection(key: const Key('first'), onChanged: (_) {}),
            TextFormField(controller: controller),
          ],
        ),
      ),
    );

    await selectOption(tester, const Key('first'), 'Two');

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
  });

  testWidgets('select commits then focuses the next numeric input', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        Column(
          children: [
            selection(key: const Key('first'), onChanged: (_) {}),
            TextFormField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
          ],
        ),
      ),
    );

    await selectOption(tester, const Key('first'), 'One');

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
    expect(
      editable.keyboardType,
      const TextInputType.numberWithOptions(decimal: true),
    );
  });

  testWidgets('skips disabled and hidden controls', (tester) async {
    await tester.pumpWidget(
      host(
        Column(
          children: [
            selection(key: const Key('first'), onChanged: (_) {}),
            const TextField(key: Key('disabled'), enabled: false),
            Visibility(
              visible: false,
              maintainState: true,
              child: TextFormField(key: const Key('hidden')),
            ),
            selection(key: const Key('third'), onChanged: (_) {}),
          ],
        ),
      ),
    );

    await selectOption(tester, const Key('first'), 'One');

    final thirdNode = Focus.of(
      tester.element(
        find.descendant(
          of: fieldInkWell(const Key('third')),
          matching: find.byType(InputDecorator),
        ),
      ),
    );
    expect(thirdNode.hasFocus, isTrue);
  });

  testWidgets('focuses a conditionally revealed next field', (tester) async {
    int? chosen;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              selection(
                key: const Key('first'),
                onChanged: (value) => setState(() => chosen = value),
              ),
              if (chosen != null) TextFormField(key: const Key('revealed')),
            ],
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('revealed')), findsNothing);

    await selectOption(tester, const Key('first'), 'One');

    expect(find.byKey(const Key('revealed')), findsOneWidget);
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
  });

  testWidgets('cancelling the sheet does not advance focus', (tester) async {
    await tester.pumpWidget(
      host(
        Column(
          children: [
            selection(key: const Key('first'), onChanged: (_) {}),
            TextFormField(key: const Key('after')),
          ],
        ),
      ),
    );

    await tester.tap(fieldInkWell(const Key('first')));
    await tester.pumpAndSettle();
    // Dismiss without choosing.
    await tester.tapAt(const Offset(400, 20));
    await tester.pumpAndSettle();

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isFalse);
  });

  testWidgets('the final select releases focus without crashing', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(selection(key: const Key('only'), onChanged: (_) {})),
    );

    await selectOption(tester, const Key('only'), 'Two');
    expect(tester.takeException(), isNull);

    final focused = FocusManager.instance.primaryFocus;
    // Focus is released to a scope, not left on a form control.
    expect(focused, anyOf(isNull, isA<FocusScopeNode>()));
  });

  testWidgets('advances in Arabic RTL as well', (tester) async {
    await tester.pumpWidget(
      host(
        Column(
          children: [
            selection(key: const Key('first'), onChanged: (_) {}),
            TextFormField(key: const Key('after')),
          ],
        ),
        locale: const Locale('ar'),
      ),
    );

    await selectOption(tester, const Key('first'), 'One');
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
  });
}
