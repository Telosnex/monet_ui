import 'dart:math' as math;

import 'package:monet_ui/theming/button_style.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/palette.dart';
import 'package:monet_ui/widgets/monet_icon.dart';
import 'package:monet_ui/widgets/monet_icon_button_child.dart';
import 'package:monet_ui/widgets/monet_tooltip.dart';
import 'package:pixel_snap_fork/material.dart';

/// An icon button that draws a [MonetIcon] with no space around it.
///
/// The icon is [size], or the [IconTheme] size. The button is as wide as the
/// icon, so two adjacent buttons touch. Its height is exactly
/// [targetHeight], or [targetHeightFor] the icon.
///
/// [MonetIconButtonChild] sets the size. [styleFor] sets only the colors and
/// turns off Material sizing. For a button that handles taps itself, such as
/// `MenuButton` with `naturalSize: true`, use [styleFor] and a
/// [MonetIconButtonChild] child to get the same size.
class MonetIconButton extends StatelessWidget {
  const MonetIconButton(
    this.icon, {
    super.key,
    required this.onPressed,
    this.size,
    this.targetHeight,
    this.palette,
    this.tooltip,
    this.color,
    this.shadows,
    this.strokeColor,
    this.paintColorListenable,
    this.paintColor,
    this.paintStrokeColor,
    this.paintShadows,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  /// The icon's size. Null uses the [IconTheme] size.
  final double? size;

  /// The button's height. Null uses [targetHeightFor].
  final double? targetHeight;

  /// The hover and press colors. Null uses the theme's primary palette.
  final Palette? palette;

  /// Shown on hover, and the icon's semantic label.
  final String? tooltip;

  /// The icon's color. Null uses the palette's stateful icon color.
  final Color? color;
  final List<Shadow>? shadows;
  final Color? strokeColor;

  /// See [MonetIcon.paintColorListenable].
  final Listenable? paintColorListenable;
  final Color Function()? paintColor;
  final Color Function()? paintStrokeColor;
  final List<Shadow> Function()? paintShadows;

  /// [size], or the [IconTheme] size.
  static double iconSizeOf(BuildContext context, [double? size]) =>
      size ?? IconTheme.of(context).size ?? 24.0;

  /// The default height for an icon of [iconSize]: the height of other
  /// Monet buttons, or the icon if that is taller.
  ///
  /// libmonet button styles use [VisualDensity.compact], which lowers the
  /// theme's minimum touch size by 8 px on every platform. This gives the
  /// same height directly.
  static double targetHeightFor(BuildContext context, double iconSize) {
    final minimum = minimumSizeForScale(MonetTheme.of(context).scale).height;
    final compact = minimum + VisualDensity.compact.baseSizeAdjustment.dy;
    return math.max(compact, iconSize);
  }

  /// [iconButtonStyle] with no Material sizing: no minimum size, padding,
  /// density, or tap-target padding. The button is the size of its child, a
  /// [MonetIconButtonChild].
  static ButtonStyle styleFor(Palette palette) {
    return iconButtonStyle(palette).copyWith(
      visualDensity: .standard,
      tapTargetSize: .shrinkWrap,
      minimumSize: const WidgetStatePropertyAll(Size.zero),
      maximumSize: const WidgetStatePropertyAll(Size.infinite),
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = this.palette ?? MonetTheme.of(context).primary;
    final iconSize = iconSizeOf(context, size);
    final tooltip = this.tooltip;
    final button = IconButton(
      onPressed: onPressed,
      style: styleFor(palette)
          .copyWith(iconSize: WidgetStatePropertyAll(iconSize)),
      icon: MonetIconButtonChild(
        height: targetHeight ?? targetHeightFor(context, iconSize),
        icon: MonetIcon(
          icon,
          size: iconSize,
          color: color,
          shadows: shadows,
          strokeColor: strokeColor,
          semanticLabel: tooltip,
          paintColorListenable: paintColorListenable,
          paintColor: paintColor,
          paintStrokeColor: paintStrokeColor,
          paintShadows: paintShadows,
        ),
      ),
    );
    if (tooltip == null) return button;
    return MonetTooltip(
      colors: palette,
      content: Text(tooltip),
      // Don't hijack taps/long-presses: those belong to the button.
      allowTapForToolip: false,
      allowLongPressForTooltip: false,
      child: button,
    );
  }
}
