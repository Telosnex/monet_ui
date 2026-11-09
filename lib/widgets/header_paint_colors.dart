import 'package:flutter/widgets.dart';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:monet_ui/theming/monet_paint_colors.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/monet_theme_data.dart';
import 'package:monet_ui/theming/palette.dart';

import 'package:monet_ui/util/blur_radius.dart';
import 'package:monet_ui/widgets/use_paint_palette.dart';

/// Foregrounds used by header call sites. Getter reads retain their paint roles.
enum HeaderForeground { text, backgroundText, colorText, fillText }

/// Text, stroke, and protection shadows read from one palette subscription.
/// The owner of the hook owns [binding]; consumers must not dispose it.
class HeaderPaintColors {
  HeaderPaintColors(
    this.binding, {
    required this.foreground,
    required this.onColorSurface,
    required this.protect,
    this.themeOverride,
    this.shadowsForColor = headerProtectionShadows,
  });

  final MonetPaletteBinding binding;
  final HeaderForeground foreground;
  final bool onColorSurface;
  final bool protect;

  /// A nested static theme also owns status-bar brightness and Material styles.
  /// Null for the scope's built-in palette or a caller's explicit palette.
  final MonetThemeData? themeOverride;
  final List<Shadow> Function(Color) shadowsForColor;
  Color? _shadowColor;
  List<Shadow>? _shadows;

  Color readTextColor() => switch (foreground) {
    .text => binding.value.text,
    .backgroundText => binding.value.backgroundText,
    .colorText => binding.value.colorText,
    .fillText => binding.value.fillText,
  };

  Color readStrokeColor() => protect
      ? (onColorSurface ? binding.value.color : binding.value.background)
      : const .new(0x00000000);

  List<Shadow> readShadows() {
    if (!protect) return const [];
    final color = readStrokeColor();
    if (_shadowColor != color || _shadows == null) {
      _shadowColor = color;
      _shadows = shadowsForColor(color);
    }
    return _shadows!;
  }
}

/// The nearest theme's selected built-in palette, or an explicit palette from the
/// wallpaper/header providers. A supplied palette is the complete recipe key:
/// its resolver ignores the ambient theme, so it cannot inherit the wrong seed,
/// contrast, or background. Recipe changes use the scope's existing clock and
/// duration; the app-wide zero-duration bus still snaps under its raster fade.
///
/// Always call this hook, including when [enabled] is false, to release demand.
HeaderPaintColors? useHeaderPaintColors(
  BuildContext context, {
  Palette? palette,
  MonetPalette themePalette = .primary,
  HeaderForeground foreground = .backgroundText,
  bool onColorSurface = false,
  bool protect = true,
  bool enabled = true,
  List<Shadow> Function(Color) shadowsForColor = headerProtectionShadows,
}) {
  final bus = MonetPaintColorsScope.maybeOf(context);
  var source = palette;
  MonetThemeData? themeOverride;
  if (enabled && bus != null && source == null) {
    themeOverride = headerStaticThemeOverrideOf(context);
    if (themeOverride != null) source = themePalette.resolve(themeOverride);
  }
  final selected = source;
  final binding = useMonetPaintPalette(
    bus,
    selected ?? themePalette,
    !enabled
        ? null
        : selected == null
        ? themePalette.resolve
        : (_) => selected,
  );
  return useMemoized(
    () => binding == null
        ? null
        : HeaderPaintColors(
            binding,
            foreground: foreground,
            onColorSurface: onColorSurface,
            protect: protect,
            themeOverride: themeOverride,
            shadowsForColor: shadowsForColor,
          ),
    [
      binding,
      foreground,
      onColorSurface,
      protect,
      themeOverride,
      shadowsForColor,
    ],
  );
}

/// Logical theme for header geometry, button styles, and popup colors. RGB
/// animation is read through bindings, not an inherited theme dependency.
/// Static overrides still subscribe to their endpoint changes.
MonetThemeData headerThemeEndpointOf(BuildContext context) {
  final bus = MonetPaintColorsScope.maybeOf(context);
  return bus == null
      ? MonetTheme.of(context).monetThemeData
      : (headerStaticThemeOverrideOf(context) ?? bus.target);
}

/// A static theme below the nearest paint scope owns its palette endpoints.
MonetThemeData? headerStaticThemeOverrideOf(BuildContext context) {
  // AnimatedMonetTheme puts one MonetTheme inside its paint scope. Another
  // MonetTheme below it is a static override, not the outer bus's palette.
  var themes = 0;
  context.visitAncestorElements((element) {
    if (element.widget is MonetPaintColorsScope) return false;
    if (element.widget is MonetTheme) themes++;
    return themes < 2;
  });
  return themes > 1 ? MonetTheme.of(context).monetThemeData : null;
}
