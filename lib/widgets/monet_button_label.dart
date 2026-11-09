import 'package:monet_ui/widgets/animated_color_hook.dart';
import 'package:monet_ui/widgets/monet_rich_text.dart';
import 'package:monet_ui/widgets/padding.dart';
import 'package:pixel_snap_fork/material.dart';
import 'package:monet_ui/widgets/monet_button_icon.dart';

/// String label shared by the button factories and the compact/regular family.
/// The icon flows inline with the text so wrapped lines use the full width.
///
/// Static and paint-driven labels use the same renderer, which centres the
/// label font's capitals on the icon (see [MonetRichText.centerCapHeight])
/// and follows the platform text size and bold-text settings.
class MonetButtonLabel extends StatelessWidget {
  const MonetButtonLabel({
    super.key,
    required this.label,
    this.labelKey,
    this.icon,
    this.fontSize,
    this.paintDriven = false,
    this.gap = HorizontalPadding.amount,
    this.shadows = const [],
    this.paintShadows,
    this.trimInk = true,
  });

  final String label;
  final Key? labelKey;
  final Widget? icon;
  final double? fontSize;
  final bool paintDriven;
  final double gap;
  final List<Shadow> shadows;
  final List<Shadow> Function()? paintShadows;

  /// False keeps the icon's square box, so labels in a column of headers
  /// start at the same x whatever the icon. See [MonetButtonIcon.trimInk].
  final bool trimInk;

  @override
  Widget build(BuildContext context) {
    final sizeStyle = fontSize != null
        ? TextStyle(fontSize: fontSize, leadingDistribution: .even)
        : null;
    final scope = paintDriven ? PaintDrivenColorScope.dependOn(context) : null;
    final icon = this.icon;
    final leading = icon == null
        ? null
        : Padding(
            padding: EdgeInsetsDirectional.only(end: gap),
            child: MonetButtonIcon(
              paintDriven: paintDriven,
              shadows: shadows,
              paintShadows: paintShadows,
              trimInk: trimInk,
              child: icon,
            ),
          );

    final baseStyle = DefaultTextStyle.of(context).style;
    var textStyle = sizeStyle == null ? baseStyle : baseStyle.merge(sizeStyle);
    // Follow the platform text size and bold-text settings, as Text does.
    if (MediaQuery.boldTextOf(context)) {
      textStyle = textStyle.merge(const TextStyle(fontWeight: .bold));
    }
    return MonetRichText.rich(
      key: labelKey,
      textSpan: TextSpan(text: label),
      textStyle: textStyle,
      textAlign: .center,
      textScaler: MediaQuery.textScalerOf(context),
      leading: [?leading],
      paintColorListenable: scope?.repaint,
      paintColor: scope?.paintColor,
      paintShadows: scope == null ? null : paintShadows,
    );
  }
}
