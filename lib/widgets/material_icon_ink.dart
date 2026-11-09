import 'package:material_ui/material_ui.dart';
import 'package:monet_ui/widgets/icon_glyph_baseline.dart';
import 'package:monet_ui/widgets/icon_ink_bounds.dart';
import 'package:pixel_snap_fork/material.dart' as ps;
import 'package:monet_ui/widgets/monet_icon.dart';

/// Removes horizontal font whitespace from icons with registered ink bounds
/// (see [registerIconInkBounds]), and
/// with [trimVertical], vertical whitespace too. [size] is the actual,
/// already-resolved square size of [child]. The child retains its original
/// painting/semantics, including unclipped shadows.
///
/// Also corrects the glyph's vertical position of a Flutter or pixel_snap
/// [Icon]. Those draw as text, and SkParagraph draws a glyph at its
/// alphabetic baseline rounded to a whole logical pixel. At a fractional
/// icon size, such as 17.5 at 2x, the glyph is drawn up to half a logical
/// pixel too low. This widget moves the child back by the rounding error.
/// See [iconBaselineRoundingError]. A [MonetIcon] places its glyph itself.
class MaterialIconInk extends StatelessWidget {
  const MaterialIconInk({
    super.key,
    required this.icon,
    required this.size,
    this.textDirection,
    this.trimVertical = false,
    required this.child,
  });

  final IconData icon;
  final double size;
  final TextDirection? textDirection;

  /// Whether the box is as tall as the ink instead of [size] (ADR 002, D11).
  /// The parent places the box, usually centered. A trimmed icon loses the
  /// designer's vertical offset, and its height changes with the glyph.
  final bool trimVertical;

  final Widget child;

  /// Adapt plain Flutter and pixel_snap Icons without changing their properties.
  /// Everything else (including an already-corrected chip icon) passes through.
  /// Resolve theme/scaling under the button's IconTheme, not at its call site.
  static Widget wrap(Widget child) {
    final properties = switch (child) {
      Icon(
        :final icon,
        :final size,
        :final textDirection,
        :final applyTextScaling,
        :final fontWeight,
      ) ||
      ps.Icon(
        :final icon,
        :final size,
        :final textDirection,
        :final applyTextScaling,
        :final fontWeight,
      ) => _IconProperties(
        icon,
        size,
        textDirection,
        applyTextScaling,
        fontWeight,
      ),
      _ => null,
    };
    if (properties == null) return child;
    final _IconProperties(:icon, :size, :direction, :applyScaling, :weight) =
        properties;
    if (icon == null ||
        materialIconBoundsFor(icon) == null ||
        (weight != null && weight != .normal)) {
      return child;
    }
    final monet = child is MonetIcon;
    return Builder(
      builder: (context) {
        final theme = IconTheme.of(context);
        // pixel_snap rounds only an explicitly supplied size, as does the
        // MonetIcon.
        final explicitSize = child is ps.Icon || monet
            ? size?.pixelSnap(ps.PixelSnap.of(context))
            : size;
        final nominalSize = explicitSize ?? theme.size ?? kDefaultFontSize;
        final effectiveSize = (applyScaling ?? theme.applyTextScaling ?? false)
            ? MediaQuery.textScalerOf(context).scale(nominalSize)
            : nominalSize;
        // ignore: avoid-recursive-widget-calls
        return MaterialIconInk(
          icon: icon,
          size: effectiveSize,
          textDirection: direction,
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bounds = materialIconBoundsFor(icon);
    if (bounds == null) return child;
    final flipped =
        icon.matchTextDirection &&
        (textDirection ?? Directionality.of(context)) == .rtl;
    final scale = size / kIconInkBoundsEm;
    final left =
        (flipped ? kIconInkBoundsEm - bounds.right : bounds.left) * scale;
    // Applying the correction to a MonetIcon would move its glyph twice.
    final top = child is! MonetIcon
        ? iconBaselineRoundingError(
            icon,
            size,
            MediaQuery.devicePixelRatioOf(context),
          )
        : 0.0;
    final inkTop = trimVertical ? bounds.top * scale : 0.0;
    return SizedBox(
      width: bounds.width * scale,
      height: trimVertical ? bounds.height * scale : size,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: size,
        maxWidth: size,
        minHeight: size,
        maxHeight: size,
        child: Transform.translate(
          offset: Offset(-left, -top - inkTop),
          child: child,
        ),
      ),
    );
  }
}

/// How far below its intended position [Icon] draws the [icon] glyph at
/// [size], in whole physical pixels.
///
/// The glyph is drawn at [iconDrawnBaseline], snapped to a physical pixel by
/// the rasterizer. It should be at [iconExactBaseline], snapped the same way.
/// The two differ at some fractional sizes, such as 17.5 at 2x. At others,
/// such as 17.33 at 3x, the rounding of the paragraph height cancels the
/// rounding of the baseline.
///
/// Assumes the icon's box starts on a physical pixel. Returns zero unless
/// [size] is a whole number of physical pixels. Sizes from pixel_snap always
/// are. For other sizes, the box is usually off the pixel grid too.
double iconBaselineRoundingError(
  IconData icon,
  double size,
  double devicePixelRatio,
) {
  final physicalSize = size * devicePixelRatio;
  if (size <= 0 || (physicalSize - physicalSize.roundToDouble()).abs() > 1e-3) {
    return 0;
  }
  // The rasterizer rounds glyph positions half up. At 17.33 at 3x the drawn
  // baseline is exactly 51.5 physical pixels; the epsilon keeps floating-
  // point noise from rounding it down.
  double snap(double logical) =>
      (logical * devicePixelRatio + 0.5 + 1e-6).floorToDouble();
  return (snap(iconDrawnBaseline(icon, size)) -
          snap(iconExactBaseline(icon, size))) /
      devicePixelRatio;
}

/// The em size of registered ink bounds: [IconInkBounds] coordinates are
/// in 1/512 of the icon's square.
const kIconInkBoundsEm = 512;

/// Font family, then code point, to ink bounds.
final _inkBounds = <String, Map<int, IconInkBounds>>{};

/// Adds ink bounds for [MaterialIconInk] and [materialIconBoundsFor], by
/// font family, then code point, in [kIconInkBoundsEm] units with the
/// glyph centered in its square as [Icon] draws it.
///
/// A family in [bounds] replaces an earlier registration of the same
/// family. The package registers none itself; without a registration,
/// icons keep their square layout.
void registerIconInkBounds(Map<String, Map<int, IconInkBounds>> bounds) {
  _inkBounds.addAll(bounds);
}

/// Physical LTR ink rectangle in [kIconInkBoundsEm] units. Font identity
/// is essential: unrelated fonts may use the same codepoint for different
/// glyphs.
IconInkBounds? materialIconBoundsFor(IconData icon) {
  if (icon.fontPackage != null ||
      (icon.fontFamilyFallback?.isNotEmpty ?? false)) {
    return null;
  }
  return _inkBounds[icon.fontFamily]?[icon.codePoint];
}

/// The properties of a Flutter or pixel_snap [Icon] that [MaterialIconInk]
/// reads.
final class const _IconProperties(
  final IconData? icon,
  final double? size,
  final TextDirection? direction,
  final bool? applyScaling,
  final FontWeight? weight,
);
