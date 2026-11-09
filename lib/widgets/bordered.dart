import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:pixel_snap_fork/material.dart';
import 'package:monet_ui/util/use_animation_controller2.dart';
import 'package:monet_ui/widgets/border_metrics.dart';
import 'package:monet_ui/widgets/monet_fallback_shapes.dart';
import 'package:monet_ui/widgets/monet_material.dart';

class Bordered extends HookWidget {
  static const kBorderWidth = kTelosnexBorderWidth;

  final Color backgroundColor;
  final Color borderColor;
  final Widget child;
  final bool isTopRound;
  final bool isBottomRound;
  final List<BoxShadow>? shadows;
  final double? radius;
  final double borderWidth;
  final bool clip;
  final bool isInvisible;

  const Bordered({
    super.key,
    required this.backgroundColor,
    required this.borderColor,
    required this.child,
    this.isTopRound = true,
    this.isBottomRound = true,
    this.shadows,
    this.radius,
    this.borderWidth = kBorderWidth,
    this.clip = false,
    // If true, won't render the border or background, but will still clip and
    // round corners. Useful for Mods animating background <-> no bg.
    this.isInvisible = false,
  });

  @override
  Widget build(BuildContext context) {
    final shapes =
        MonetTheme.maybeShapesOf(context) ??
        kMonetFallbackShapeTheme.resolve(1);
    final textDirection = Directionality.of(context);
    // ── Animation controller driven by [isInvisible] ────────────────
    final controller = useAnimationController2(
      duration: kThemeAnimationDuration,
      initialValue: isInvisible ? 1.0 : 0.0,
    );
    // ignore: function-always-returns-null
    useEffect(() {
      if (isInvisible) {
        controller.forward();
      } else {
        controller.reverse();
      }
      return null;
    }, [isInvisible]);

    // ── Stable border radius (changes with theme/corner config) ─────
    final designBorderRadius = useMemoized(
      () {
        // A null radius follows the active, already scale-resolved Monet shape
        // theme. Explicit radii remain literal call-site overrides.
        final resolved = radius == null
            ? shapes.theme.borderRadius.resolve(textDirection)
            : BorderRadius.circular(radius!);
        return BorderRadius.only(
          topLeft: isTopRound ? resolved.topLeft : .zero,
          topRight: isTopRound ? resolved.topRight : .zero,
          bottomLeft: isBottomRound ? resolved.bottomLeft : .zero,
          bottomRight: isBottomRound ? resolved.bottomRight : .zero,
        );
      },
      [
        shapes.theme.borderRadius,
        textDirection,
        isTopRound,
        isBottomRound,
        radius,
      ],
    );

    // ── Stable clip shape (geometry only, no colour) ────────────────
    final clipShape = useMemoized(
      () => shapes.border(
        side: BorderSide(width: borderWidth, color: Colors.transparent),
        borderRadius: designBorderRadius,
      ),
      [shapes, borderWidth, designBorderRadius],
    );

    // ── Stable child — never rebuilt by animation ticks ─────────────
    final stableChild = useMemoized(() {
      final inner = MonetMaterial(type: .transparency, child: child);
      if (!clip) return inner;
      return ClipPath(
        clipper: ShapeBorderClipper(shape: clipShape),
        child: inner,
      );
    }, [child, clip, clipShape]);

    final animatedBorder = shapes.border(
      side: BorderSide(color: Colors.transparent, width: borderWidth),
      borderRadius: designBorderRadius,
    );
    final finalBorder = shapes.border(
      side: BorderSide(color: borderColor, width: borderWidth),
      borderRadius: designBorderRadius,
    );
    // ── AnimatedBuilder: only the DecoratedBox rebuilds per tick ─────
    return AnimatedBuilder(
      animation: controller,
      child: stableChild,
      builder: (context, child) {
        final t = controller.value;
        final ShapeDecoration decoration;

        // Fully invisible.
        if (t == 1.0) {
          return stableChild;
        }

        if (t == 0.0) {
          decoration = ShapeDecoration(
            shape: finalBorder,
            color: backgroundColor,
            shadows: shadows,
          );
        } else {
          decoration = ShapeDecoration(
            shape: animatedBorder,
            color: Color.lerp(backgroundColor, Colors.transparent, t)!,
            shadows: [],
          );
        }
        return DecoratedBox(decoration: decoration, child: child!);
      },
    );
  }
}
