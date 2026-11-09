import 'package:pixel_snap_fork/material.dart';

/// A [Material] surface with its implicit animation disabled.
///
/// This is deliberately a wrapper rather than a [Material] subclass. Flutter's
/// `debugCheckHasMaterial` uses
/// `LookupBoundary.findAncestorWidgetOfExactType<Material>`, so subclasses do
/// not satisfy Material-dependent widgets such as [InkWell]. [build] therefore
/// inserts an actual [Material] between this widget and [child].
///
/// `Material.build` unconditionally wraps its child in an
/// `AnimatedDefaultTextStyle(theme.textTheme.bodyMedium, duration:
/// animationDuration)`. Every `Text` depends on the nearest `DefaultTextStyle`,
/// so each time the ambient `ThemeData` changes, every `Text` beneath the
/// `Material` rebuilds on every frame of that tween. The default duration is
/// 200 ms, or roughly 12 frames.
///
/// `MonetTheme` already owns theme transitions: `AnimatedMonetTheme` publishes
/// intermediate themes, or `MonetThemeCrossfade` dissolves the previous raster.
/// Material's tween is redundant with both and lags the former. This wrapper
/// passes every Material property through except `animationDuration`, which is
/// always zero so text follows the Monet theme in lockstep.
class MonetMaterial extends StatelessWidget {
  const MonetMaterial({
    super.key,
    this.type = .canvas,
    this.elevation = 0.0,
    this.color,
    this.shadowColor,
    this.surfaceTintColor,
    this.textStyle,
    this.borderRadius,
    this.shape,
    this.borderOnForeground = true,
    this.clipBehavior = .none,
    this.child,
    this.animateColor = false,
  }) : assert(elevation >= 0.0),
       assert(shape == null || borderRadius == null),
       assert(type != .circle || borderRadius == null && shape == null);

  final Widget? child;
  final MaterialType type;
  final bool animateColor;
  final double elevation;
  final Color? color;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final TextStyle? textStyle;
  final ShapeBorder? shape;
  final bool borderOnForeground;
  final Clip clipBehavior;
  final BorderRadiusGeometry? borderRadius;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: type,
      elevation: elevation,
      color: color,
      shadowColor: shadowColor,
      surfaceTintColor: surfaceTintColor,
      textStyle: textStyle,
      borderRadius: borderRadius,
      shape: shape,
      borderOnForeground: borderOnForeground,
      clipBehavior: clipBehavior,
      animationDuration: .zero,
      animateColor: animateColor,
      child: child,
    );
  }
}
