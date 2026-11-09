import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';

import 'package:monet_ui/widgets/text_field_entry_type.dart';

/// Auto-save `TextField` that
/// 1. Streams *every* keystroke to [onTextChanged] **while the field has focus**
/// 2. Updates its own `TextEditingController` from [externalText] **only when it
///    is *not* focused** (preventing the cursor-jump issue)
///
/// The pattern is designed to be reused wherever you need bidirectional text
/// synchronisation without losing the caret position.
class AutoSaveTextField extends HookWidget {
  const AutoSaveTextField({
    super.key,
    required this.externalText,

    /// Called on every keystroke *while the field has focus*. Do *NOT* update
    /// the [controller] here.
    required this.onTextChanged,
    this.focusNode,
    this.controller,
    this.decoration = const InputDecoration(),
    this.readOnly = false,
    this.style,
    this.minLines,
    this.maxLines,
    this.scrollPhysics = const NeverScrollableScrollPhysics(),
    this.onSubmitted,
    this.onTapOutside,
    this.entryType = TextFieldEntryType.text,
  });

  /// The text field will be configured for proper entry of this type: for
  /// instance, URLs will disable autocorrect and set the keyboard type to
  /// [TextInputType.url] i.e. for Android and iOS soft keyboards.
  final TextFieldEntryType entryType;

  /// The authoritative text that comes from your state-management layer.
  final String externalText;

  /// Called on every keystroke *while the field has focus*.
  final ValueChanged<String> onTextChanged;

  /// Provide your own [FocusNode] if you need to interact with it from outside.
  final FocusNode? focusNode;

  /// Provide your own [TextEditingController] if other widgets need it.
  final TextEditingController? controller;

  final InputDecoration decoration;
  final TextStyle? style;
  final int? maxLines;
  final int? minLines;
  final ScrollPhysics scrollPhysics;
  final ValueChanged<String>? onSubmitted;
  final void Function(PointerDownEvent)? onTapOutside;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final effectiveController = controller ?? useTextEditingController();
    final effectiveFocusNode = focusNode ?? useFocusNode();
    useListenable(effectiveFocusNode);

    // ---------------------------------------------------------------------
    // 1. Keystrokes -> external listener (real-time auto-save)
    // ---------------------------------------------------------------------
    useEffect(() {
      void keystrokeListener() {
        if (effectiveFocusNode.hasFocus) {
          if (effectiveController.text != externalText) {
            onTextChanged(effectiveController.text);
          }
        }
      }

      effectiveController.addListener(keystrokeListener);
      return () => effectiveController.removeListener(keystrokeListener);
    }, [effectiveController, effectiveFocusNode, externalText]);

    // ---------------------------------------------------------------------
    // 2. Provider -> controller (only when NOT focused)
    // ---------------------------------------------------------------------
    // ignore: function-always-returns-null
    useEffect(() {
      if (effectiveFocusNode.hasFocus) return null; // Skip while typing

      if (effectiveController.text != externalText) {
        effectiveController.text = externalText;
      }
      return null;
    }, [externalText, effectiveFocusNode.hasFocus]);

    return TextField(
      controller: effectiveController,
      focusNode: effectiveFocusNode,
      decoration: decoration,
      autocorrect: entryType.isAutocorrectEnabled,
      keyboardType: entryType.keyboardType,
      style: style,
      minLines: minLines,
      maxLines: maxLines,
      scrollPhysics: scrollPhysics,
      onTapOutside: onTapOutside,
      onSubmitted: (value) {
        // Publish before submission consumes or clears the draft.
        onTextChanged(value);
        onSubmitted?.call(value);
      },
      readOnly: readOnly,
    );
  }
}
