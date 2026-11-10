import 'dart:math' show min;

import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/palette.dart';
import 'package:monet_ui/widgets/control_row_header.dart';
import 'package:monet_ui/widgets/monet_handedness.dart';
import 'package:monet_ui/widgets/padding.dart';
import 'package:monet_ui/widgets/screen_breakpoints.dart';
import 'package:monet_ui/widgets/settings_row.dart';
import 'package:monet_ui/widgets/text_field_entry_type.dart';
import 'package:monet_ui/widgets/text_field_input_decoration.dart';
import 'package:monet_ui/widgets/theme_selection.dart';
import 'package:pixel_snap_fork/material.dart';

class TextFieldRow extends HookWidget {
  final String label;
  final Key? textFieldKey;
  final Function(String newValue) onChanged;
  final String tooltip;
  final String value;
  final bool readOnly;
  final int? maxLines;
  final bool forceSmallWidth;
  final Color? labelColor;
  final Function(String)? onSubmitted;
  final VoidCallback? onFocusLost;
  final Palette? colors;
  final Widget? suffixIcon;
  final TextFieldEntryType entryType;
  final String? hintText;
  final bool allowNewLines;
  final bool showLabel;

  const TextFieldRow({
    super.key,
    this.textFieldKey,
    required this.label,
    required this.value,
    required this.tooltip,
    this.readOnly = false,
    this.maxLines = 3,
    required this.onChanged,
    this.forceSmallWidth = false,
    this.labelColor,
    this.onSubmitted,
    this.onFocusLost,
    this.colors,
    this.suffixIcon,
    this.entryType = TextFieldEntryType.text,
    this.hintText,
    this.allowNewLines = true,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final TextEditingController controller = useTextEditingController(
      text: value,
    );
    final focusNode = useFocusNode();

    // Handle focus changes
    useEffect(() {
      void listener() {
        if (!focusNode.hasFocus && onFocusLost != null) {
          onFocusLost!();
        }
      }

      focusNode.addListener(listener);
      return () => focusNode.removeListener(listener);
    }, [focusNode, onFocusLost]);
    // Keep the controller's text in sync with the incoming `value` from
    // the outside world, but avoid resetting the cursor position on every
    // keystroke which makes the caret jump to the end of the field while
    // editing.
    //
    // We only update the controller when the underlying value coming from
    // Riverpod actually differs from the current controller value.  When we
    // do update we also try to preserve the previous selection so that the
    // caret (or selection) stays where the user expects it to be.
    useEffect(
      // ignore: function-always-returns-null
      () {
        Future.microtask(() {
          if (controller.text != value) {
            final oldSelection = controller.selection;
            controller.text = value;
            // Clamp the previous selection positions to the new text length in
            // case it shrunk.
            final baseOffset = min(oldSelection.baseOffset, value.length);
            final extentOffset = min(oldSelection.extentOffset, value.length);
            controller.selection = oldSelection.copyWith(
              baseOffset: baseOffset,
              extentOffset: extentOffset,
            );
          }
        });
        return null;
      },
      [value],
    );
    useEffect(() {
      listener() {
        onChanged(controller.text);
      }

      controller.addListener(listener);
      return () {
        controller.removeListener(listener);
      };
    }, [onChanged]);

    final isSmall =
        ScreenBreakpoints.isScreenSmallWidth(context) || forceSmallWidth;
    final textField = ThemeSelection(
      colors: colors,
      child: TextField(
        autocorrect: entryType.isAutocorrectEnabled,
        keyboardType: entryType.keyboardType,
        textInputAction: allowNewLines ? null : .done,
        inputFormatters: allowNewLines
            ? null
            : [FilteringTextInputFormatter.deny(RegExp(r'[\r\n]'))],
        key: textFieldKey,
        decoration: TFID
            .get(context, colors ?? MonetTheme.of(context).primary)
            .copyWith(hintText: hintText, suffixIcon: suffixIcon),
        minLines: 1,
        maxLines: allowNewLines ? maxLines : 1,
        readOnly: readOnly,
        controller: controller,
        focusNode: focusNode,
        onSubmitted: onSubmitted ?? (_) => focusNode.unfocus(),
        style: Theme.of(context).textTheme.bodyLarge!.copyWith(
          fontFeatures: [const FontFeature.tabularFigures()],
          color:
              colors?.backgroundText ??
              MonetTheme.of(context).primary.backgroundText,
        ),
      ),
    );
    if (!showLabel) return textField;
    final handededness = MonetHandedness.of(context);
    final labelWidget = ControlRowHeader(
      label: label,
      tooltip: tooltip,
      isSmall: isSmall,
      hand: handededness,
      colors: colors ?? MonetTheme.of(context).primary,
      respectHandednessInSmall: false,
      gap: const HorizontalPadding(),
      includeGapOnlyInSmall: true,
    );
    if (isSmall) {
      // Always left-align the header in small layouts
      return Column(
        crossAxisAlignment: .start,
        children: [labelWidget, textField],
      );
    }
    final flexibleTextField = Flexible(child: textField);
    return Row(
      mainAxisAlignment: handededness == .right ? .start : .end,
      children: handededness == .right
          ? [labelWidget, const HorizontalPadding(), flexibleTextField]
          : [
              flexibleTextField,
              const HorizontalPadding(),
              labelWidget,
              const HorizontalPadding(),
              SizedBox(width: SettingsRow.valueWidth(context), height: 0),
            ],
    );
  }
}
