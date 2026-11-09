import 'package:monet_ui/theming/monet_shape_theme.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/monet_theme_data.dart';
import 'package:pixel_snap_fork/material.dart';

/// The corner radius of menus, popovers and other overlays.
const kOverlayRadius = 16.0;

/// The shapes Monet controls use when no [MonetTheme] gives shapes:
/// superellipse corners at a quarter of the touch size.
const kMonetFallbackShapeTheme = MonetShapeTheme(
  borderRadius: .all(.circular(MonetThemeData.touchSize / 4)),
  inputGapPadding: 0,
  borderBuilder: RoundedSuperellipseBorder.new,
);

/// The theme's shapes, or [kMonetFallbackShapeTheme] at scale 1 when no
/// [MonetTheme] is above [context]. For widgets that can be built outside a
/// Monet theme, such as overlays and copied third-party widgets.
MonetShapes monetShapesOrDefault(BuildContext context) =>
    MonetTheme.maybeShapesOf(context) ??
    const .new(theme: kMonetFallbackShapeTheme, linearScale: 1);
