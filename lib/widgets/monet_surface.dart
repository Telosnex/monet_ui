import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/palette.dart';
import 'package:monet_ui/widgets/monet_button.dart';
import 'package:monet_ui/widgets/monet_button_core.dart';
import 'package:pixel_snap_fork/material.dart';

/// A button's surface and shadow around arbitrary content: a card, such as a
/// chat tile, or a backdrop for controls in its [child].
///
/// Unlike [MonetButton] there is no icon, label or content animation: a card
/// does not animate its size when its content changes. Without [onPressed]
/// it only paints. It has no press, hover, focus or button semantics, and
/// keeps its enabled colors.
class MonetSurface extends StatelessWidget {
  const MonetSurface({
    super.key,
    required this.colors,
    this.kind = .background,
    required this.child,
    this.onPressed,
    this.statesController,
    this.style,
    this.shadowColor,
    this.internalPadding = MonetButton.regularPadding,
    this.isolateAnimationRepaints = false,
  });

  final Palette colors;
  final MonetButtonKind kind;
  final Widget child;
  final VoidCallback? onPressed;
  final WidgetStatesController? statesController;

  /// Merged over [kind]'s style.
  final ButtonStyle? style;

  /// Defaults to [kind]'s shadow.
  final Color? shadowColor;
  final double internalPadding;

  /// For a complex [child]: see [MonetButtonCore.isolateAnimationRepaints].
  final bool isolateAnimationRepaints;

  @override
  Widget build(BuildContext context) {
    final kindStyle = MonetButton.kindStyle(
      kind,
      colors,
      MonetTheme.of(context).scale,
    );
    final onPressed = this.onPressed;
    return MonetButtonCore(
      style: style?.merge(kindStyle) ?? kindStyle,
      shadowColor: shadowColor ?? MonetButton.kindShadow(context, kind, colors),
      outlineColorWhenNoShadow: kind == .outline
          ? colors.backgroundBorder
          : null,
      statesController: statesController,
      internalPadding: internalPadding,
      isolateAnimationRepaints: isolateAnimationRepaints,
      interactive: onPressed != null,
      // ignore: no-empty-block
      onPressed: onPressed ?? () {},
      icon: null,
      label: child,
    );
  }
}
