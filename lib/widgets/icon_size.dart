import 'package:monet_ui/fonts/optical_font_size.dart' as libmonet;
import 'package:monet_ui/fonts/text_metrics.dart';
import 'package:pixel_snap_fork/material.dart'
    show BuildContext, MediaQuery, TextStyle;

/// Icon size that matches the letters of [style] in every font.
///
/// The one place telosnex sizes icons from text. It calls libmonet's
/// [libmonet.iconSizeFor]: the font size before the size equalizer scaled
/// it. To compare with the old behavior, return `style.fontSize!` here.
double iconSizeForTextStyle(TextStyle style) => libmonet.iconSizeFor(style);

/// Height of one line of [style] as laid out: the font size, text scale, and
/// the line height the theme sets per font (docs/design/ADR_font_line_height.md).
///
/// Use it to size a box that holds one line of text. 1.5 is only for styles
/// with no height.
double lineHeightForTextStyle(BuildContext context, TextStyle style) =>
    lineHeightForTextScaler(MediaQuery.textScalerOf(context), style);

/// [iconSizeForTextStyle], or null if [style] or its font size is null.
///
/// For call sites where a null size means the widget's default.
double? iconSizeForTextStyleOrNull(TextStyle? style) =>
    style?.fontSize == null ? null : iconSizeForTextStyle(style!);
