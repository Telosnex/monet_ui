import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_svg/svg.dart';
import 'package:loggy/loggy.dart';
import 'package:monet_ui/core/hex_codes.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/util/lru_cache.dart';
import 'package:pixel_snap_fork/material.dart';
import 'package:vector_graphics/vector_graphics.dart';

class SvgAsset extends HookWidget with UiLoggy {
  // Static cache to store loaded SVG data
  // 25-04-22: Raised from 10 to 20 - noticed dragging temperature slider
  // seemed laggy. It turned out LLMs section in AI Controls was rebuilding
  // when it changed, and 10 was just short enough that ~4 local models had
  // SVGs that weren't in cache.
  static final LruCache _assetCache = LruCache<String, _AssetData>(
    capacity: 20,
  );

  // Option to use vector_graphics implementation
  static bool useVectorGraphics = false;

  @visibleForTesting
  static void debugClearCache() => _assetCache.clear();

  @visibleForTesting
  static void debugPutCacheEntry({
    required String key,
    required Uint8List bytes,
    required double naturalWidth,
    required double naturalHeight,
  }) {
    _assetCache[key] = _AssetData(
      bytes: bytes,
      aspectRatio: naturalWidth / naturalHeight,
      naturalWidth: naturalWidth,
      naturalHeight: naturalHeight,
    );
  }

  @visibleForTesting
  static bool debugCacheContainsKey(String key) => _assetCache.containsKey(key);

  final String asset;
  final String? string;
  final double? height;
  final double? width;
  final BoxFit fit;
  final ui.ColorFilter? colorFilter;
  final AlignmentGeometry alignment;

  /// Whether to scale the rendered dimensions with the ambient Monet theme.
  final bool scaleWithTheme;

  /// Map of colors to substitute in the SVG before rendering.
  ///
  /// * **Keys** – colour *to be replaced* (what exists in the SVG). Provide
  ///   them as strings – e.g. `'#000'`, `'#000000'`, `'black'`, `'white'`…
  /// * **Values** – colour *to replace with*.  These can be either a `String`
  ///   (any CSS-style colour literal that an SVG will accept) **or** a
  ///   `Color` object which will automatically be converted to the CSS hex
  ///   form `#RRGGBB`.
  ///
  /// Example:
  /// ```dart
  /// SvgAsset(
  ///   asset: 'icon.svg',
  ///   substitutions: {
  ///     'black': Colors.blue,          // Color
  ///     '#ffffff': '#FF5722',          // String
  ///   },
  /// )
  /// ```
  ///
  /// Smart handling: If you provide `'black'` or `'white'` as keys, it will
  /// automatically match common representations like `#000000`, `#000`,
  /// `'black'`, etc.
  final Map<String, Object?>? substitutions;

  const SvgAsset({
    super.key,
    required this.asset,
    // If string is provided, it will be used instead of loading an asset.
    this.string,
    this.height,
    this.width,
    this.fit = BoxFit.contain,
    this.alignment = AlignmentGeometry.center,
    this.colorFilter,
    this.substitutions,
    this.scaleWithTheme = true,
  });

  /// Apply color substitutions to the SVG string with smart white/black handling
  String _applySubstitutions(String svgString) {
    if (substitutions == null || substitutions!.isEmpty) return svgString;

    var result = svgString;

    substitutions!.forEach((from, rawTo) {
      // Convert replacement into a CSS-compatible colour string
      String to;
      if (rawTo is Color) {
        // ARGB to RRGGBB (#AARRGGBB is not universally supported by SVG)
        // Ignore alpha – SVG uses separate opacity; we only take RGB so that
        // we always end up with 7-char string like #RRGGBB
        final rgb = rawTo.argb & 0x00FFFFFF;
        to = '#${rgb.toRadixString(16).padLeft(6, '0')}';
      } else {
        to = rawTo!.toString();
      }

      // Smart handling for 'black' - replace common black representations
      if (from.toLowerCase() == 'black') {
        result = result.replaceAll('#000000', to);
        result = result.replaceAll('#000', to);
        result = result.replaceAll('black', to);
        result = result.replaceAll('rgb(0,0,0)', to);
        result = result.replaceAll('rgb(0, 0, 0)', to);
      }
      // Smart handling for 'white' - replace common white representations
      else if (from.toLowerCase() == 'white') {
        result = result.replaceAll('#ffffff', to);
        result = result.replaceAll('#fff', to);
        result = result.replaceAll('white', to);
        result = result.replaceAll('rgb(255,255,255)', to);
        result = result.replaceAll('rgb(255, 255, 255)', to);
      }
      // Direct replacement for other cases
      else {
        result = result.replaceAll(from, to);
      }
    });

    return result;
  }

  @visibleForTesting
  String debugApplySubstitutions(String svgString) =>
      _applySubstitutions(svgString);

  @visibleForTesting
  Widget debugBuildWithVectorGraphics(Future<String>? processedStringFuture) =>
      _buildWithVectorGraphics(processedStringFuture);

  String get _substitutionsKey =>
      substitutions == null || substitutions!.isEmpty
      ? 'no-substitutions'
      : substitutions!.entries
            .map((entry) => '${entry.key}:${entry.value}')
            .join('|');

  String get _colorFilterKey =>
      colorFilter == null ? 'no-color-filter' : '$colorFilter';

  String _variantKey(Brightness brightness) =>
      '$asset:$brightness:$_substitutionsKey:$_colorFilterKey';

  @override
  Widget build(BuildContext context) {
    // Create cache key that includes substitutions, color filter, and theme
    // brightness to avoid visual variants leaking into other SvgAsset callers.
    final brightness = Theme.brightnessOf(context);
    final cacheKey = _variantKey(brightness);

    final cachedData = string == null ? _assetCache[cacheKey] : null;
    final requestGeneration = useRef(0);

    // Hooks must be called on every build and in the same order. In
    // particular, a cache hit must not return before disposing an in-flight
    // request for an older visual variant.
    final future = useMemoized<Future<_AssetData?>?>(() {
      final generation = ++requestGeneration.value;
      if (useVectorGraphics || cachedData != null) return null;
      return () async {
        PictureInfo? pictureInfo;
        final ByteData byteData;

        try {
          if (string != null) {
            final processedString = _applySubstitutions(string!);
            pictureInfo = await vg.loadPicture(
              SvgStringLoader(processedString),
              context,
            );
            byteData = ByteData.sublistView(
              Uint8List.fromList(utf8.encode(processedString)),
            );
          } else {
            final rawString = await rootBundle.loadString(asset);
            final processedString = _applySubstitutions(rawString);
            byteData = ByteData.sublistView(
              Uint8List.fromList(utf8.encode(processedString)),
            );
            if (!context.mounted) {
              loggy.debug('Context is not mounted, no need to load.');
              return null;
            }
            pictureInfo = await vg.loadPicture(
              SvgStringLoader(processedString),
              context,
            );
          }

          if (!context.mounted) {
            loggy.debug('Context is not mounted, no need to load.');
            return null;
          }

          final viewBox = pictureInfo.size;

          // Convert the `ByteData` we produced above into a single `Uint8List`
          // instance.  We *must not* recreate this list during future rebuilds –
          // doing so would defeat the whole purpose of this change.  Therefore we
          // create it once here and stash it inside `_AssetData`.
          final Uint8List bytes = byteData.buffer.asUint8List();

          final data = _AssetData(
            bytes: bytes,
            aspectRatio: viewBox.width / viewBox.height,
            naturalWidth: viewBox.width,
            naturalHeight: viewBox.height,
          );

          // A superseded request may finish after a newer color variant.
          // Return its data to its (now-unsubscribed) future, but do not let it
          // churn the global LRU or evict the current variant.
          if (string == null && generation == requestGeneration.value) {
            _assetCache[cacheKey] = data;
          }

          return data;
        } finally {
          // `vg.loadPicture` transfers disposal responsibility to the caller.
          // SvgAsset only needs the decoded picture long enough to read its
          // viewBox/size; the actual render path below re-decodes from cached SVG
          // bytes via `SvgPicture.memory`, which owns its own picture lifecycle.
          pictureInfo?.picture.dispose();
        }
      }();
    }, [useVectorGraphics, cacheKey, string, cachedData]);

    // A completed value belongs only to the request that produced it. Keeping
    // data from the previous future can otherwise render old substituted SVG
    // bytes under the new variant key while a retarget is loading.
    final snapshot = useFuture(future, preserveState: false);

    // Keep this hook above every return even though its value is only consumed
    // by the vector branch; hooks cannot be invoked conditionally.
    // ignore: move-variable-closer-to-its-usage
    final processedStringFuture = useMemoized<Future<String>?>(() {
      if (!useVectorGraphics ||
          string != null ||
          substitutions == null ||
          substitutions!.isEmpty) {
        return null;
      }
      return rootBundle.loadString(asset).then(_applySubstitutions);
    }, [useVectorGraphics, cacheKey, string]);

    if (cachedData != null) {
      final scale = scaleWithTheme
          ? (MonetTheme.maybeOf(context)?.monetThemeData.scale ?? 1.0)
          : 1.0;
      return _buildSvgFromData(cachedData, scale, cacheKey);
    }

    if (useVectorGraphics && string == null) {
      return _buildWithVectorGraphics(processedStringFuture);
    }

    if (!snapshot.hasData) {
      // print('🔄 SvgAsset: No data yet for $cacheKey, snapshot state: ${snapshot.connectionState}');
      // We don’t have the new bytes yet (e.g. because the substitutions just
      // changed), but in virtually every case the SVG’s *geometry* (view-box
      // size & therefore aspect-ratio) is still the same.  If we already
      // loaded *any* variant of this asset earlier we can reuse its size to
      // create a placeholder of the correct dimensions.  This avoids the
      // briefly-collapsing-to-0-width blink that was noticeable while the
      // new picture was loading.

      // 1. An entry for this exact cache-key may already exist (e.g. hot-
      //    reload, different widget instance, ...)
      var placeholder = _assetCache[cacheKey];

      // 2. Plain assets can fall back to the plain theme-aware entry. Do not
      //    fall back across substitution/color-filter variants because that can
      //    leak a styled SVG into another caller while the new variant loads.
      final isPlainAssetVariant =
          (substitutions == null || substitutions!.isEmpty) &&
          colorFilter == null;
      if (placeholder == null && isPlainAssetVariant) {
        final baseKey = '$asset:$brightness:no-substitutions:no-color-filter';
        placeholder = _assetCache[baseKey];
      }

      // 3. No need to search the entire cache: for non-plain variants, showing
      //    a different variant as a placeholder can briefly display the wrong
      //    color/filter.

      if (placeholder != null) {
        // Show the previously-cached picture while the new one is decoding so
        // that we don’t flash an empty box.  Using the same helper ensures we
        // honour width / height / fit exactly the same way the “real” render
        // does.
        final scale = scaleWithTheme
            ? (MonetTheme.maybeOf(context)?.monetThemeData.scale ?? 1.0)
            : 1.0;
        return _buildSvgFromData(placeholder, scale, cacheKey);
      }

      // Fallback: nothing cached – use the explicit width/height if provided
      // otherwise let the box shrink (this is identical to the previous
      // behaviour but will only happen the very first time an asset is ever
      // displayed).
      return SizedBox(width: width, height: height);
    }

    final data = snapshot.data!;
    final scale = scaleWithTheme
        ? (MonetTheme.maybeOf(context)?.monetThemeData.scale ?? 1.0)
        : 1.0;
    return _buildSvgFromData(data, scale, cacheKey);
  }

  // Helper method to build SVG from cached data
  Widget _buildSvgFromData(_AssetData data, double scale, String cacheKey) {
    // Calculate dimensions
    double? finalWidth;
    double? finalHeight;

    if (width != null && height != null) {
      // Both dimensions specified - use as is
      finalWidth = width;
      finalHeight = height;
    } else if (width != null) {
      // Only width specified - calculate height maintaining aspect ratio
      finalWidth = width;
      finalHeight = width! / data.aspectRatio;
    } else if (height != null) {
      // Only height specified - calculate width maintaining aspect ratio
      finalHeight = height;
      finalWidth = height! * data.aspectRatio;
    } else {
      // No dimensions specified - use natural size
      finalWidth = data.naturalWidth;
      finalHeight = data.naturalHeight;
    }

    final scaledWidth = finalWidth != null
        ? finalWidth * math.sqrt(scale)
        : null;
    final scaledHeight = finalHeight != null
        ? finalHeight * math.sqrt(scale)
        : null;

    return SvgPicture.memory(
      data.bytes,
      key: ValueKey(cacheKey),
      width: scaledWidth,
      height: scaledHeight,
      fit: fit,
      alignment: alignment,
      colorFilter: colorFilter,
    );
  }

  // Helper method to build using vector_graphics
  Widget _buildWithVectorGraphics(Future<String>? processedStringFuture) {
    // Create cache key that includes substitutions and color filter to avoid
    // visual variants leaking into other SvgAsset callers.
    final cacheKey = _variantKey(.light);

    // Create appropriate loader
    BytesLoader loader;
    if (string != null) {
      final processedString = _applySubstitutions(string!);
      loader = SvgBytesLoader(utf8.encode(processedString), theme: null);
    } else {
      // For asset loading with vector_graphics, we need to handle substitutions differently
      // since AssetBytesLoader doesn't let us modify the content
      if (substitutions != null &&
          substitutions!.isNotEmpty &&
          processedStringFuture != null) {
        // Load, process, and use as string
        return FutureBuilder(
          future: processedStringFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return SizedBox(width: width, height: height);
            }
            final processedString = snapshot.data!;
            final processedLoader = SvgBytesLoader(
              utf8.encode(processedString),
              theme: null,
            );

            // Calculate dimensions based on cached data if available
            double? finalWidth = width;
            double? finalHeight = height;

            if (_assetCache.containsKey(cacheKey)) {
              final data = _assetCache[cacheKey]!;

              if (width != null && height == null) {
                finalHeight = width! / data.aspectRatio;
              } else if (height != null && width == null) {
                finalWidth = height! * data.aspectRatio;
              } else if (width == null && height == null) {
                finalWidth = data.naturalWidth;
                finalHeight = data.naturalHeight;
              }
            }

            return VectorGraphic(
              loader: processedLoader,
              width: finalWidth,
              height: finalHeight,
              fit: fit,
              alignment: alignment,
              colorFilter: colorFilter,
            );
          },
        );
      } else {
        loader = AssetBytesLoader(asset);
      }
    }

    // Calculate dimensions based on cached data if available
    double? finalWidth = width;
    double? finalHeight = height;

    if (_assetCache.containsKey(cacheKey)) {
      final data = _assetCache[cacheKey]!;

      if (width != null && height == null) {
        finalHeight = width! / data.aspectRatio;
      } else if (height != null && width == null) {
        finalWidth = height! * data.aspectRatio;
      } else if (width == null && height == null) {
        finalWidth = data.naturalWidth;
        finalHeight = data.naturalHeight;
      }
    }

    return VectorGraphic(
      loader: loader,
      width: finalWidth,
      height: finalHeight,
      fit: fit,
      alignment: alignment,
      colorFilter: colorFilter,
    );
  }
}

class _AssetData {
  // Store the raw SVG bytes as a *single* `Uint8List` instance so that we
  // can hand the **exact same** list to `SvgPicture.memory` on every build.
  //
  // If we were to call `ByteData.buffer.asUint8List()` each time we build the
  // widget (as we did previously) a *new* `Uint8List` view would be created
  // for every rebuild.  `SvgPicture.memory` treats a change in the list’s
  // identity as a completely new image which forces the picture to be
  // re-decoded.  When the window is resized Flutter usually rebuilds the
  // subtree; the momentary re-decoding introduced a single-frame “blink”
  // where the SVG disappeared and then re-appeared.
  //
  // By preserving the same `Uint8List` instance we guarantee that the
  // `PictureProvider` sees the bytes as unchanged and therefore reuses the
  // already decoded picture – no more flicker.
  final Uint8List bytes;
  final double aspectRatio;
  final double naturalWidth;
  final double naturalHeight;

  const _AssetData({
    required this.bytes,
    required this.aspectRatio,
    required this.naturalWidth,
    required this.naturalHeight,
  });
}
