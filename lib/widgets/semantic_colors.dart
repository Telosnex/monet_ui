import 'dart:ui' show Color;

import 'package:monet_ui/colorspaces/color_model.dart';
import 'package:monet_ui/contrast/contrast.dart';
import 'package:monet_ui/core/argb_srgb_xyz_lab.dart';
import 'package:monet_ui/core/hex_codes.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/palette.dart';
import 'package:pixel_snap_fork/material.dart' show BuildContext;
import 'package:monet_ui/util/lru_cache.dart';

// Structural keys require every policy input and include each in equality/hash.
final class const _PaletteCacheKey({
  required final double tone,
  required final double contrast,
  required final Color? background,
  required final Algo algo,
  required final ColorModel colorModel,
}) {
  @override
  bool operator ==(Object other) =>
      other is _PaletteCacheKey &&
      other.tone == tone &&
      other.contrast == contrast &&
      other.background == background &&
      other.algo == algo &&
      other.colorModel == colorModel;

  @override
  int get hashCode => Object.hash(tone, contrast, background, algo, colorModel);
}

/// Colors that carry a meaning (error, success, info, warning), and
/// palettes of them that are readable on a background.
abstract final class SemanticColors {
  // The error red is from a photo of a fire truck:
  // https://www.opb.org/article/2023/02/18/electric-fire-truck-portland/
  static const colorError = Color(0xffC40308);
  static const colorSuccess = Color(0xff009E60);
  static const colorInfo = Color(0xff1976D2);
  static const colorWarning = Color(0xffFFC107); // Based on Colors.amber

  static const _cacheCapacity = 32;

  // Palettes are cached because about 100 files build them in build(), some
  // every frame. A miss costs about 200 times as much as a hit. The caches
  // hold 32 entries so that a screen with many tinted backgrounds, like the
  // on-device model grid, doesn't miss on every build.
  //
  // They don't use Eicher lighting: it shifts the hue and loses chroma, so
  // warning amber would become a dark gold.
  static Palette _fromContext(
    BuildContext context,
    Color? bgColor,
    Palette Function({
      double? bgTone,
      Color? bgColor,
      required double contrast,
      Algo algo,
      ColorModel colorModel,
    })
    build,
  ) {
    final monet = MonetTheme.of(context);
    return build(
      bgTone: bgColor == null ? monet.backgroundTone : null,
      bgColor: bgColor,
      contrast: monet.contrast,
      algo: monet.algo,
      colorModel: monet.colorModel,
    );
  }

  /// Pass [bgColor] to build against that color, or [bgTone] alone to build
  /// against a background of that tone.
  ///
  /// With [bgColor], [bgTone] defaults to the color's own tone. Pass it too
  /// only when the tinted color stands in for a shared nominal tone, so that
  /// sibling surfaces pick the same text polarity (see render_ui).
  static Palette _cached(
    LruCache<_PaletteCacheKey, Palette> cache,
    Color color, {
    required double? bgTone,
    required Color? bgColor,
    required double contrast,
    required Algo algo,
    required ColorModel colorModel,
  }) {
    assert(bgTone != null || bgColor != null, 'Pass bgTone or bgColor.');
    final key = _PaletteCacheKey(
      tone: bgTone ?? lstarFromArgb(bgColor!.argb),
      contrast: contrast,
      background: bgColor,
      algo: algo,
      colorModel: colorModel,
    );
    return cache[key] ??= bgColor != null
        ? Palette.fromColorAndBackground(
            color,
            bgColor,
            backgroundTone: bgTone,
            contrast: contrast,
            algo: algo,
            colorModel: colorModel,
          )
        : Palette.from(
            color,
            backgroundTone: bgTone!,
            contrast: contrast,
            algo: algo,
            colorModel: colorModel,
          );
  }

  static final LruCache<_PaletteCacheKey, Palette> _errorPaletteCache =
      LruCache(capacity: _cacheCapacity);

  static Palette errorPalette(BuildContext context, {Color? bgColor}) =>
      _fromContext(context, bgColor, errorPaletteFromBgAndContrast);

  static Palette errorPaletteFromBgAndContrast({
    double? bgTone,
    Color? bgColor,
    required double contrast,
    Algo algo = .apca,
    ColorModel colorModel = .kDefault,
  }) => _cached(
    _errorPaletteCache,
    colorError,
    bgTone: bgTone,
    bgColor: bgColor,
    contrast: contrast,
    algo: algo,
    colorModel: colorModel,
  );

  static final LruCache<_PaletteCacheKey, Palette> _successPaletteCache =
      LruCache(capacity: _cacheCapacity);

  static Palette successPalette(BuildContext context, {Color? bgColor}) =>
      _fromContext(context, bgColor, successPaletteFromBgAndContrast);

  static Palette successPaletteFromBgAndContrast({
    double? bgTone,
    Color? bgColor,
    required double contrast,
    Algo algo = .apca,
    ColorModel colorModel = .kDefault,
  }) => _cached(
    _successPaletteCache,
    colorSuccess,
    bgTone: bgTone,
    bgColor: bgColor,
    contrast: contrast,
    algo: algo,
    colorModel: colorModel,
  );

  static final LruCache<_PaletteCacheKey, Palette> _infoPaletteCache = LruCache(
    capacity: _cacheCapacity,
  );

  static Palette infoPalette(BuildContext context, {Color? bgColor}) =>
      _fromContext(context, bgColor, infoPaletteFromBgAndContrast);

  static Palette infoPaletteFromBgAndContrast({
    double? bgTone,
    Color? bgColor,
    required double contrast,
    Algo algo = .apca,
    ColorModel colorModel = .kDefault,
  }) => _cached(
    _infoPaletteCache,
    colorInfo,
    bgTone: bgTone,
    bgColor: bgColor,
    contrast: contrast,
    algo: algo,
    colorModel: colorModel,
  );

  static final LruCache<_PaletteCacheKey, Palette> _warningPaletteCache =
      LruCache(capacity: _cacheCapacity);

  static Palette warningPalette(BuildContext context, {Color? bgColor}) =>
      _fromContext(context, bgColor, warningPaletteFromBgAndContrast);

  static Palette warningPaletteFromBgAndContrast({
    double? bgTone,
    Color? bgColor,
    required double contrast,
    Algo algo = .apca,
    ColorModel colorModel = .kDefault,
  }) => _cached(
    _warningPaletteCache,
    colorWarning,
    bgTone: bgTone,
    bgColor: bgColor,
    contrast: contrast,
    algo: algo,
    colorModel: colorModel,
  );
}
