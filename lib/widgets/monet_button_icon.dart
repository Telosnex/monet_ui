import 'package:flutter/widgets.dart' as flutter;
import 'package:monet_ui/widgets/animated_color_hook.dart';
import 'package:monet_ui/widgets/material_icon_ink.dart';
import 'package:monet_ui/widgets/monet_icon.dart';
import 'package:pixel_snap_fork/material.dart';

/// Shared ink-width icon treatment for inline labels, rows, and loading.
///
/// A Flutter or pixel_snap [Icon] draws as a [MonetIcon]. Without its own
/// color, it follows the paint bus of the enclosing
/// [PaintDrivenColorScope], and [paintShadows] follow it too (ADR 002, D3).
/// Custom widgets keep their own geometry and paint behavior.
class MonetButtonIcon extends StatelessWidget {
  const MonetButtonIcon({
    super.key,
    required this.child,
    this.paintDriven = true,
    this.shadows = const [],
    this.paintShadows,
    this.trimInk = true,
  });

  final Widget child;

  /// True fits the icon's box to its ink, so the caller's padding is the
  /// visible space (`MaterialIconInk`). False keeps the icon's square box, so
  /// every icon of one size takes the same width.
  final bool trimInk;

  /// False prevents a static button from inheriting an unrelated outer bus.
  final bool paintDriven;
  final List<Shadow> shadows;
  final List<Shadow> Function()? paintShadows;

  @override
  Widget build(BuildContext context) {
    final scope = paintDriven ? PaintDrivenColorScope.dependOn(context) : null;
    final icon = monetIconFor(
      child,
      shadows: shadows,
      paintColorListenable: scope?.repaint,
      paintColor: scope?.paintIconColor,
      staticColor: scope?.iconColor,
      paintShadows: paintShadows,
    );
    final result = icon ?? child;
    return trimInk ? MaterialIconInk.wrap(result) : result;
  }
}

/// [icon] as a [MonetIcon] when it is a Flutter, pixel_snap or Monet icon;
/// otherwise null.
///
/// [shadows] draw after the icon's own. When the icon has no color of its
/// own, it draws in [staticColor] and follows [paintColor]. [paintShadows]
/// replace [shadows] at paint time; the icon's own shadows stay first. With
/// [paintDrivenByAncestor], an ancestor that listens to the paint bus
/// repaints the icon.
MonetIcon? monetIconFor(
  Widget icon, {
  List<Shadow> shadows = const [],
  Listenable? paintColorListenable,
  Color Function()? paintColor,
  Color? staticColor,
  List<Shadow> Function()? paintShadows,
  bool paintDrivenByAncestor = false,
}) {
  final fields = switch (icon) {
    flutter.Icon() => _IconFields(
      icon.icon,
      icon.size,
      icon.fill,
      icon.weight,
      icon.grade,
      icon.opticalSize,
      icon.color,
      icon.shadows,
      icon.semanticLabel,
      icon.textDirection,
      icon.applyTextScaling,
      icon.blendMode,
      icon.fontWeight,
    ),
    Icon() => _IconFields(
      icon.icon,
      icon.size,
      icon.fill,
      icon.weight,
      icon.grade,
      icon.opticalSize,
      icon.color,
      icon.shadows,
      icon.semanticLabel,
      icon.textDirection,
      icon.applyTextScaling,
      icon.blendMode,
      icon.fontWeight,
    ),
    _ => null,
  };
  if (fields == null) return null;
  final _IconFields(
    :data,
    :size,
    :fill,
    :weight,
    :grade,
    :opticalSize,
    :color,
    :ownShadows,
    :semanticLabel,
    :textDirection,
    :applyTextScaling,
    :blendMode,
    :fontWeight,
  ) = fields;
  if (data == null) return null;
  final followsBus = color == null && paintColor != null;
  final allShadows = [...?ownShadows, ...shadows];
  return MonetIcon(
    data,
    key: icon.key,
    size: size,
    fill: fill,
    weight: weight,
    grade: grade,
    opticalSize: opticalSize,
    color: color ?? staticColor,
    shadows: allShadows.isEmpty ? ownShadows : allShadows,
    semanticLabel: semanticLabel,
    textDirection: textDirection,
    applyTextScaling: applyTextScaling,
    blendMode: blendMode,
    fontWeight: fontWeight,
    paintColorListenable: followsBus || paintShadows != null
        ? paintColorListenable
        : null,
    paintColor: followsBus ? paintColor : null,
    paintShadows: paintShadows == null
        ? null
        : () => [...?ownShadows, ...paintShadows()],
    paintDrivenByAncestor: paintDrivenByAncestor,
  );
}

/// The fields of a Flutter or pixel_snap [Icon] that [monetIconFor] copies.
final class const _IconFields(
  final IconData? data,
  final double? size,
  final double? fill,
  final double? weight,
  final double? grade,
  final double? opticalSize,
  final Color? color,
  final List<Shadow>? ownShadows,
  final String? semanticLabel,
  final TextDirection? textDirection,
  final bool? applyTextScaling,
  final BlendMode? blendMode,
  final FontWeight? fontWeight,
);
