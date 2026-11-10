// ignore_for_file: prefer-single-widget-per-file

import 'package:monet_ui/colorspaces/color_model.dart';
import 'package:monet_ui/colorspaces/hct.dart';
import 'package:monet_ui/contrast/contrast.dart';
import 'package:monet_ui/effects/uv_harmony.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/monet_theme_data.dart';
import 'package:monet_ui/theming/palette.dart';
import 'package:monet_ui/util/lru_cache.dart';
import 'package:monet_ui/widgets/monet_icon.dart';
import 'package:pixel_snap_fork/material.dart';

/// Gives descendants a position in a set of [count] sibling sections whose
/// icons share one color harmony.
///
/// Headers below this widget that support it (for example
/// `MonetExpansion` with a `titleIcon`) render a [HarmonyIcon] for [index].
class HarmonyIconSlot extends InheritedWidget {
  final int index;
  final int count;

  const HarmonyIconSlot({
    super.key,
    required this.index,
    required this.count,
    required super.child,
  }) : assert(count > 0),
       assert(index >= 0 && index < count);

  static HarmonyIconSlot? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType();

  @override
  bool updateShouldNotify(HarmonyIconSlot oldWidget) =>
      index != oldWidget.index || count != oldWidget.count;
}

/// An icon using color [index] from [count] harmony colors around the theme's
/// primary color.
///
/// The glyph uses the harmony palette's fill, with no background.
class HarmonyIcon extends StatelessWidget {
  final IconData icon;
  final double iconSize;
  final int index;
  final int count;

  const HarmonyIcon({
    super.key,
    required this.icon,
    required this.iconSize,
    required this.index,
    required this.count,
  }) : assert(count > 0),
       assert(index >= 0 && index < count);

  @override
  Widget build(BuildContext context) {
    final palette = harmonyPalettes(
      MonetTheme.of(context).monetThemeData,
      count,
    )[index];
    return MonetIcon(icon, size: iconSize, color: palette.fill);
  }
}

/// The inputs of [harmonyPalettes] that change its result.
final class const _HarmonyKey(
  final int seed,
  final int count,
  final double backgroundTone,
  final double contrast,
  final Algo algo,
  final ColorModel colorModel,
) {
  @override
  bool operator ==(Object other) =>
      other is _HarmonyKey &&
      other.seed == seed &&
      other.count == count &&
      other.backgroundTone == backgroundTone &&
      other.contrast == contrast &&
      other.algo == algo &&
      other.colorModel == colorModel;

  @override
  int get hashCode =>
      Object.hash(seed, count, backgroundTone, contrast, algo, colorModel);
}

final _paletteCache = LruCache<_HarmonyKey, List<Palette>>(capacity: 8);

/// [count] palettes whose colors are evenly spaced in u'v' direction around
/// the white point, starting at the primary color of [theme].
///
/// Each color keeps the HCT chroma of the primary color, so every palette is
/// equally vivid. The palettes use the background tone, contrast, and
/// algorithm of [theme].
///
/// While a theme animates, the palettes are for the theme's target. This
/// keeps the work to one calculation for each theme.
List<Palette> harmonyPalettes(MonetThemeData theme, int count) {
  assert(count > 0);
  final target = theme.target;
  final seed = target.primary.color;
  final key = _HarmonyKey(
    seed.toARGB32(),
    count,
    target.backgroundTone,
    target.contrast,
    target.algo,
    target.colorModel,
  );
  final cached = _paletteCache[key];
  if (cached != null) return cached;

  final seedHct = Hct.fromColor(seed, model: target.colorModel);
  final colors = count < 2
      ? [seedHct]
      : harmony(seedHct, count, tonePolicy: .fitHctChroma);
  final palettes = List<Palette>.unmodifiable([
    for (final color in colors)
      Palette.from(
        color.color,
        backgroundTone: target.backgroundTone,
        contrast: target.contrast,
        algo: target.algo,
        colorModel: target.colorModel,
      ),
  ]);
  _paletteCache[key] = palettes;
  return palettes;
}
