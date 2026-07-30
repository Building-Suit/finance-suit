import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/widgets/app_selection_field.dart';
import 'package:work_tracker/features/finance/domain/transaction_category.dart';
import 'package:work_tracker/features/finance/presentation/widgets/category_selector.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

const parent = TransactionCategory(
  id: 'home',
  name: 'Home',
  kind: CategoryKind.expense,
  icon: 'label',
  sortOrder: 0,
  isArchived: false,
);

const child = TransactionCategory(
  id: 'repairs',
  name: 'Repairs',
  kind: CategoryKind.expense,
  icon: 'label',
  sortOrder: 0,
  isArchived: false,
  parentCategoryId: 'home',
);

Future<void> pumpSelector(
  WidgetTester tester, {
  required String? selected,
  required ValueChanged<String?> onChanged,
}) => tester.pumpWidget(
  MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: CategorySelector(
        categories: const [parent, child],
        selectedCategoryId: selected,
        onChanged: onChanged,
      ),
    ),
  ),
);

void main() {
  testWidgets('parent category remains directly selectable', (tester) async {
    String? changed;
    await pumpSelector(
      tester,
      selected: parent.id,
      onChanged: (value) => changed = value,
    );

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Subcategory (optional)'), findsOneWidget);

    await tester.tap(find.byType(AppSelectionField<String?>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Repairs').last);
    await tester.pumpAndSettle();

    expect(changed, child.id);
  });

  testWidgets('clearing the optional child stores the parent', (tester) async {
    String? changed;
    await pumpSelector(
      tester,
      selected: child.id,
      onChanged: (value) => changed = value,
    );

    await tester.tap(find.byType(AppSelectionField<String?>).last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('No subcategory — use the parent category').last,
    );
    await tester.pumpAndSettle();

    expect(changed, parent.id);
  });
}
