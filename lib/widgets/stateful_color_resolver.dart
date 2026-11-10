import 'package:monet_ui/theming/palette.dart';
import 'package:monet_ui/util/lru_cache.dart';
import 'package:pixel_snap_fork/material.dart';

// rationale for 360 is # of hues
final LruCache<String, Palette> _safeColorsCache = LruCache(capacity: 360);

/// Resolves icon/text color from [SafeColors] based on widget states.
Color resolveBackgroundTextColor(Palette colors, Set<WidgetState> states) {
  if (states.contains(WidgetState.pressed)) {
    return colors.backgroundSplashedText;
  }
  if (states.contains(WidgetState.hovered)) {
    return colors.backgroundHoveredText;
  }
  return colors.text;
}

/// Resolves icon/text color from [SafeColors] based on widget states.
Color resolveBackgroundFillColor(Palette colors, Set<WidgetState> states) {
  if (states.contains(WidgetState.pressed)) {
    return colors.backgroundSplashedFill;
  }
  if (states.contains(WidgetState.hovered)) {
    return colors.backgroundHoveredFill;
  }
  return colors.fill;
}

/// Resolves background color from [SafeColors] based on widget states.
Color resolveBackgroundColor(Palette colors, Set<WidgetState> states) {
  if (states.contains(WidgetState.pressed)) {
    return colors.backgroundSplashed;
  }
  if (states.contains(WidgetState.hovered)) {
    return colors.backgroundHovered;
  }

  // Avoid background intended only for states showing up when the widget is
  // "active", i.e. intending to animate icon colors.
  return Colors.transparent;
}

/// Creates a cached [Palette] without consulting inherited widgets.
///
/// Paint-driven controls capture tone/contrast during build, then call this
/// from their paint-time color resolvers. That keeps inherited dependency
/// registration in build while avoiding widget rebuilds on animation ticks.
Palette safeColorsFromColor({
  required Color color,
  required double backgroundTone,
  required double contrast,
}) {
  final cacheKey =
      '$color:${backgroundTone.round()}:${(contrast * 100).round()}';
  final cached = _safeColorsCache[cacheKey];
  if (cached != null) {
    return cached;
  }

  final generated = Palette.from(
    color,
    backgroundTone: backgroundTone,
    contrast: contrast,
  );
  _safeColorsCache[cacheKey] = generated;
  return generated;
}
