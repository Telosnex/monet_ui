import 'package:flutter/widgets.dart' as flutter;

import 'package:pixel_snap_fork/widgets.dart' hide Icon;
import 'package:pixel_snap_fork/widgets.dart' as ps show Icon;

import 'package:monet_ui/widgets/snapped_icons/icon_box.dart';
import 'package:monet_ui/widgets/snapped_icons/icon_outline.dart';

/// The glyph of [widget] when it is a Flutter, pixel_snap or Monet icon.
///
/// A [MonetIcon] is a [flutter.Icon] and not a pixel_snap `Icon`, so an
/// `is Icon` check against pixel_snap's misses it.
IconData? iconDataOfWidget(Widget widget) => switch (widget) {
  flutter.Icon(:final icon) => icon,
  ps.Icon(:final icon) => icon,
  _ => null,
};

/// Whether [widget] is a Flutter, pixel_snap or Monet icon.
bool isIconWidget(Widget widget) => widget is flutter.Icon || widget is ps.Icon;

/// The app's icon widget. Replaces pixel_snap's and Flutter's
/// [flutter.Icon], with the same constructor, theme handling, layout and semantics.
///
/// Draws icons whose outlines were registered with [registerIconOutlines]
/// as paths. Fitted outlines, such as MaterialIcons, get straight edges on
/// device pixels and keep mirror symmetry. Other icons, and any [fontWeight], draw
/// with the font where [flutter.Icon] draws them, with the baseline on a
/// whole device pixel. Like pixel_snap's Icon, an explicit [size] is snapped
/// to device pixels.
///
/// [strokeColor] and [strokeWidth] draw a stroke on the glyph's edge, as
/// `MonetRichText` does: shadows first, then the stroke, then the fill.
///
/// [paintColorListenable], [paintColor], [paintStrokeColor], [paintShadows]
/// and [paintDrivenByAncestor] follow the paint bus as `MonetRichText`
/// does: a tick repaints the icon without a rebuild (Mod ADR 004).
///
/// It is a [flutter.Icon], so `find.byIcon` and `is Icon` checks match it.
/// MaterialIcons has no variable axes, so [fill], [weight], [grade] and
/// [opticalSize] do not change its glyphs.
class MonetIcon extends flutter.Icon {
  const MonetIcon(
    super.icon, {
    super.key,
    super.size,
    super.fill,
    super.weight,
    super.grade,
    super.opticalSize,
    super.color,
    super.shadows,
    super.semanticLabel,
    super.textDirection,
    super.applyTextScaling,
    super.blendMode,
    super.fontWeight,
    this.strokeColor,
    this.strokeWidth = 1,
    this.paintColorListenable,
    this.paintColor,
    this.paintStrokeColor,
    this.paintShadows,
    this.paintDrivenByAncestor = false,
  });

  /// The stroke's color, or null for no stroke.
  final Color? strokeColor;

  /// The visible outer stroke's width in logical pixels. Defaults to 1.
  /// The renderer doubles it for the centered stroke under the fill.
  final double strokeWidth;

  /// When this notifies, the icon repaints with [paintColor],
  /// [paintStrokeColor] and [paintShadows]. Unless [paintDrivenByAncestor], the icon listens and is
  /// a repaint boundary.
  final Listenable? paintColorListenable;

  /// The current color, read at paint time. Replaces [color] and the icon
  /// theme's color. The icon theme's opacity applies.
  final Color Function()? paintColor;

  /// The current stroke color, read at paint time. Replaces [strokeColor].
  final Color Function()? paintStrokeColor;

  /// The current shadows, read at paint time. Replace [shadows] and the
  /// icon theme's shadows.
  final List<Shadow> Function()? paintShadows;

  /// An ancestor listens to [paintColorListenable] and repaints this icon,
  /// so the icon neither listens nor is a repaint boundary.
  final bool paintDrivenByAncestor;

  @override
  Widget build(BuildContext context) {
    final size = this.size?.pixelSnap(PixelSnap.of(context));
    final icon = this.icon;
    if (icon == null) {
      if (size == this.size) return super.build(context);
      // No glyph to stroke: an empty Icon with the snapped size.
      // ignore: telosnex_lints/telosnex_prefer_monet_icon
      return flutter.Icon(
        icon,
        size: size,
        fill: fill,
        weight: weight,
        grade: grade,
        opticalSize: opticalSize,
        color: color,
        shadows: shadows,
        semanticLabel: semanticLabel,
        textDirection: textDirection,
        applyTextScaling: applyTextScaling,
        blendMode: blendMode,
        fontWeight: fontWeight,
      );
    }
    // The steps of Flutter's Icon.build that apply to an outline.
    assert(textDirection != null || debugCheckHasDirectionality(context));
    final direction = textDirection ?? Directionality.of(context);
    final iconTheme = IconTheme.of(context);
    final tentativeIconSize = size ?? iconTheme.size ?? kDefaultFontSize;
    final iconSize = (applyTextScaling ?? iconTheme.applyTextScaling ?? false)
        ? MediaQuery.textScalerOf(context).scale(tentativeIconSize)
        : tentativeIconSize;
    final iconOpacity = iconTheme.opacity ?? 1.0;
    Color withOpacity(Color color) => iconOpacity == 1.0
        ? color
        : color.withValues(alpha: color.a * iconOpacity);
    final iconColor = withOpacity(color ?? iconTheme.color!);
    final paintColor = this.paintColor;
    final variations = [
      if ((fill ?? iconTheme.fill) case final value?)
        FontVariation('FILL', value),
      if ((weight ?? iconTheme.weight) case final value?)
        FontVariation('wght', value),
      if ((grade ?? iconTheme.grade) case final value?)
        FontVariation('GRAD', value),
      if ((opticalSize ?? iconTheme.opticalSize) case final value?)
        FontVariation('opsz', value),
    ];
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: IconBox(
          icon: icon,
          outline: fontWeight == null ? iconOutline(icon) : null,
          size: iconSize,
          color: iconColor,
          flipX: icon.matchTextDirection && direction == .rtl,
          shadows: shadows ?? iconTheme.shadows,
          blendMode: blendMode,
          fontWeight: fontWeight,
          fontVariations: variations.isEmpty ? null : variations,
          paintColorListenable: paintColorListenable,
          paintColor: paintColor == null
              ? null
              : () => withOpacity(paintColor()),
          strokeColor: strokeColor,
          strokeWidth: strokeWidth,
          paintStrokeColor: paintStrokeColor,
          paintShadows: paintShadows,
          paintDrivenByAncestor: paintDrivenByAncestor,
        ),
      ),
    );
  }
}
