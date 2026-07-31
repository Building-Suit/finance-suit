import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// A form-compatible mobile selection field backed by a modal bottom sheet.
///
/// [DropdownMenuItem] is intentionally accepted as lightweight option data so
/// existing forms can migrate without duplicating their translated labels.
class AppSelectionField<T> extends FormField<T> {
  AppSelectionField({
    super.key,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
    super.initialValue,
    InputDecoration decoration = const InputDecoration(),
    super.validator,
    super.onSaved,
    super.enabled = true,
    bool isExpanded = false,
    String? sheetTitle,
    String? searchHint,
  }) : super(
         builder: (state) {
           final selected = items
               .where((item) => item.value == state.value)
               .firstOrNull;
           final effectiveDecoration = decoration
               .applyDefaults(Theme.of(state.context).inputDecorationTheme)
               .copyWith(errorText: state.errorText);

           Future<void> openSheet() async {
             if (!enabled || onChanged == null) return;
             final result = await showModalBottomSheet<_SelectionResult<T>>(
               context: state.context,
               isScrollControlled: true,
               showDragHandle: true,
               useSafeArea: true,
               useRootNavigator: true,
               builder: (context) => _SelectionSheet<T>(
                 items: items,
                 selectedValue: state.value,
                 title: sheetTitle ?? decoration.labelText,
                 searchHint: searchHint,
               ),
             );
             if (result == null) return;
             state.didChange(result.value);
             onChanged(result.value);
           }

           return Semantics(
             button: true,
             enabled: enabled && onChanged != null,
             label: decoration.labelText,
             value: _optionText(selected),
             child: InkWell(
               onTap: enabled && onChanged != null ? openSheet : null,
               borderRadius: BorderRadius.circular(4),
               child: InputDecorator(
                 isEmpty: selected == null,
                 isFocused: false,
                 decoration: effectiveDecoration,
                 child: ConstrainedBox(
                   constraints: const BoxConstraints(minHeight: 24),
                   child: Row(
                     children: [
                       Expanded(
                         child:
                             selected?.child ??
                             Text(
                               decoration.hintText ?? '',
                               overflow: isExpanded
                                   ? TextOverflow.visible
                                   : TextOverflow.ellipsis,
                             ),
                       ),
                       const SizedBox(width: 8),
                       const FinanceSuitIcon(FinanceSuitIcons.expandMore),
                     ],
                   ),
                 ),
               ),
             ),
           );
         },
       );
}

class _SelectionResult<T> {
  const _SelectionResult(this.value);

  final T? value;
}

class _SelectionSheet<T> extends StatefulWidget {
  const _SelectionSheet({
    required this.items,
    required this.selectedValue,
    this.title,
    this.searchHint,
  });

  final List<DropdownMenuItem<T>> items;
  final T? selectedValue;
  final String? title;
  final String? searchHint;

  @override
  State<_SelectionSheet<T>> createState() => _SelectionSheetState<T>();
}

class _SelectionSheetState<T> extends State<_SelectionSheet<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxHeight = math.min(media.size.height * .75, 640.0);
    final query = _query.trim().toLowerCase();
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    final visible = query.isEmpty
        ? widget.items
        : widget.items
              .where((item) => _optionText(item).toLowerCase().contains(query))
              .toList(growable: false);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8 + media.viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.title != null) ...[
                Text(
                  widget.title!,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
              ],
              if (widget.items.length > 8) ...[
                TextField(
                  autofocus: false,
                  decoration: InputDecoration(
                    hintText:
                        widget.searchHint ??
                        l10n?.selectionSearchHint ??
                        'Search options',
                    prefixIcon: const FinanceSuitIcon(FinanceSuitIcons.search),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: 8),
              ],
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final item = visible[index];
                    final selected = item.value == widget.selectedValue;
                    return Semantics(
                      selected: selected,
                      child: ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        enabled: item.enabled,
                        minVerticalPadding: 8,
                        leading: selected
                            ? const FinanceSuitIcon(FinanceSuitIcons.check)
                            : const SizedBox(width: 24),
                        title: item.child,
                        onTap: item.enabled
                            ? () => Navigator.of(
                                context,
                              ).pop(_SelectionResult<T>(item.value))
                            : null,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _optionText(DropdownMenuItem<dynamic>? item) {
  final child = item?.child;
  if (child is Text) return child.data ?? child.textSpan?.toPlainText() ?? '';
  return item?.value?.toString() ?? '';
}
