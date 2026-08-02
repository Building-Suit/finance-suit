import 'package:flutter/material.dart';
import 'package:work_tracker/core/widgets/selection_focus.dart';

/// The canonical single-line text input used by application forms.
///
/// Unless a field defines its own submit behavior, pressing the keyboard's
/// Enter/Next action advances to the next eligible control. Multiline fields
/// keep Enter for new lines, while explicit Done/Search/submit handlers remain
/// untouched.
class AppTextFormField extends TextFormField {
  AppTextFormField({
    super.key,
    super.controller,
    super.initialValue,
    super.focusNode,
    super.decoration,
    super.keyboardType,
    super.textCapitalization,
    TextInputAction? textInputAction,
    super.autofocus,
    super.obscureText,
    super.autocorrect,
    super.enableSuggestions,
    super.maxLines,
    super.maxLength,
    super.onChanged,
    super.validator,
    super.enabled,
    super.autofillHints,
    ValueChanged<String>? onFieldSubmitted,
    VoidCallback? onEditingComplete,
    super.inputFormatters,
  }) : super(
         textInputAction:
             _shouldAdvance(
               maxLines: maxLines,
               textInputAction: textInputAction,
               onFieldSubmitted: onFieldSubmitted,
               onEditingComplete: onEditingComplete,
             )
             ? TextInputAction.next
             : textInputAction,
         // EditableText otherwise performs its own nextFocus before invoking
         // onFieldSubmitted, which would make our traversal advance twice.
         onEditingComplete:
             _shouldAdvance(
               maxLines: maxLines,
               textInputAction: textInputAction,
               onFieldSubmitted: onFieldSubmitted,
               onEditingComplete: onEditingComplete,
             )
             ? _keepCurrentFocus
             : onEditingComplete,
         onFieldSubmitted:
             _shouldAdvance(
               maxLines: maxLines,
               textInputAction: textInputAction,
               onFieldSubmitted: onFieldSubmitted,
               onEditingComplete: onEditingComplete,
             )
             ? _advance
             : onFieldSubmitted,
       );

  static bool _shouldAdvance({
    required int? maxLines,
    required TextInputAction? textInputAction,
    required ValueChanged<String>? onFieldSubmitted,
    required VoidCallback? onEditingComplete,
  }) {
    if (maxLines != 1 ||
        onFieldSubmitted != null ||
        onEditingComplete != null) {
      return false;
    }
    return textInputAction == null || textInputAction == TextInputAction.next;
  }

  static void _keepCurrentFocus() {}

  static void _advance(String _) => advanceFocusAfterTextInput();
}
