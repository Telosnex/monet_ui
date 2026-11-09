import 'dart:math' as math;

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:monet_ui/widgets/auto_size_title_field.dart';
import 'package:monet_ui/widgets/editable_text_stroke.dart';
import 'package:monet_ui/widgets/theme_selection.dart';
import 'package:pixel_snap_fork/material.dart';

class TitleTextField extends HookWidget {
  final String? hintText;
  final TextStyle? hintStyle;
  final TextEditingController controller;
  final TextAlign textAlign;
  final TextStyle style;
  final bool enabled;
  final Color cursorColor;

  /// A stroke on the glyph edges, drawn under the fill as
  /// `MonetRichText` draws it. Null draws none.
  final Color? strokeColor;
  const TitleTextField({
    required this.controller,
    this.textAlign = TextAlign.start,
    this.hintStyle,
    this.hintText,
    required this.cursorColor,
    required this.style,
    this.enabled = true,
    this.strokeColor,
    super.key,
  });
  @override
  Widget build(BuildContext context) {
    double? hintWidth;
    if (hintText != null) {
      // Measure width of hint text.
      final finalHintStyle = hintStyle ?? style;
      final painter = TextPainter(
        text: TextSpan(text: hintText, style: finalHintStyle),
        textDirection: .ltr,
      );
      painter.layout();
      hintWidth = painter.width + 96;
      painter.dispose();
    }
    final styleOrHeadlineMedium = style;
    final bodyMediumFontSize = Theme.of(context).textTheme.bodyMedium!.fontSize!
        .ceilToDouble();
    final styleOrHeadlineMediumFontSize = styleOrHeadlineMedium.fontSize!
        .ceilToDouble();
    final maxFontSize = math.max(
      styleOrHeadlineMediumFontSize,
      bodyMediumFontSize,
    );
    final minFontSize = math.min(
      styleOrHeadlineMediumFontSize,
      bodyMediumFontSize,
    );
    return ThemeSelection(
      child: AbsorbPointer(
        // Note: [enabled] is not set on [TextField] to avoid any unexpected
        // visual changes. There doesn't seem to be any due, even when set, due to
        // the visuals not including a border etc.
        absorbing: !enabled,
        child: EditableTextStroke(
          strokeColor: strokeColor,
          child: AutoSizeTitleField(
            cursorColor: cursorColor,
            maxFontSize: maxFontSize,
            minFontSize: minFontSize,
            minWidth: hintWidth ?? 0,
            decoration: InputDecoration(
              hintText: hintText,
              isCollapsed: false,
              isDense: true,
              filled: false,
              hoverColor: Colors.transparent,
              contentPadding: EdgeInsets.zero,
              border: .none,
              focusedBorder: .none,
              enabledBorder: .none,
              disabledBorder: .none,
              // Note: error borders are intentionally suppressed. This widget
              // is a chrome-less title field and must not render validation
              // affordances inline. Any validation (and its user-facing
              // feedback) should be handled externally to this widget.
              errorBorder: .none,
              focusedErrorBorder: .none,
            ),
            textAlign: textAlign,
            style: style,
            controller: controller,
          ),
        ),
      ),
    );
  }
}
