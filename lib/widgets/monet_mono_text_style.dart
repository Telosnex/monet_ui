import 'package:monet_ui/fonts/optical_font_size.dart';
import 'package:monet_ui/fonts/text_metrics.dart';
import 'package:pixel_snap_fork/material.dart';

/// Supplies the monospace [TextStyle] Monet widgets use for values.
///
/// An app provides it once, near the root, and updates it when the user's
/// font settings change. Without a provider, widgets use [fallback].
class MonetMonoTextStyle extends InheritedWidget {
  const MonetMonoTextStyle({
    super.key,
    required this.style,
    required super.child,
  });

  /// The monospace style, including its font family and line height.
  final TextStyle style;

  /// The style used when no [MonetMonoTextStyle] is above the widget.
  static const fallback = TextStyle(fontFamily: 'monospace');

  /// The monospace style.
  static TextStyle of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MonetMonoTextStyle>()?.style ??
      fallback;

  /// The monospace style, sized to look as large as [surrounding].
  static TextStyle sizedTo(BuildContext context, TextStyle surrounding) {
    final mono = of(context);
    return mono.copyWith(fontSize: matchedFontSize(surrounding, mono));
  }

  /// Font size at which [mono] looks as large as [surrounding].
  static double matchedFontSize(TextStyle surrounding, TextStyle mono) =>
      snapFontSize(
        opticallyMatchedFontSize(
          referenceFontSize: surrounding.fontSize ?? 16,
          referenceFontFamily: surrounding.fontFamily,
          fontFamily: mono.fontFamily,
        ),
      );

  @override
  bool updateShouldNotify(MonetMonoTextStyle oldWidget) =>
      style != oldWidget.style;
}
