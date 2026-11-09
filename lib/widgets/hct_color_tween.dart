import 'package:flutter/foundation.dart';

import 'package:monet_ui/colorspaces/cam16V11/cam16_v11.dart';
import 'package:monet_ui/colorspaces/hct.dart';
import 'package:monet_ui/core/argb_srgb_xyz_lab.dart';
import 'package:monet_ui/core/hex_codes.dart';
import 'package:pixel_snap_fork/material.dart';

import 'package:monet_ui/util/lru_cache.dart';

/// A specialised `Tween<Color>` optimised for Hct colour interpolation.
///
/// The heavy conversions to `Cam16`/`Hct` space are executed **once** in the
/// constructor and the numeric components are cached.  The `lerp` method then
/// performs only inexpensive arithmetic, reducing per-frame allocations by
/// roughly an order of magnitude.
///
/// Results are further cached based on rounded parameter values to avoid
/// redundant computations for similar inputs.
class HctColorTween extends Tween<Color?> {
  /// Cache of already computed colors for both keepChroma=true and keepChroma=false cases
  /// 25-05-16 observations showed there's ~600 misses per theme and a
  /// persistent 3:1 cache hit ratio until all colors have been "hit" during
  /// a theme.
  static final _cartesianCache = LruCache<String, Color>(capacity: 1000);
  static final _hueLockedCache = LruCache<String, Color>(capacity: 1000);

  /// Dev-only instrumentation for the lerp caches. Gated on [kDebugMode] so it
  /// never runs in release/profile builds. Flip the `&& false` to `&& true` to
  /// enable locally when tuning cache capacity; we leave it disabled by
  /// default even in debug so that integration tests don't spam the console.
  static const bool _kLogCacheStats = kDebugMode && false;
  static int _cacheHits = 0;
  static int _cacheMisses = 0;
  HctColorTween({
    required Color begin,
    required Color end,
    required this._keepChroma,
  }) : _beginCam = Cam16V11.fromInt(begin.argb),
       _endCam = Cam16V11.fromInt(end.argb),
       _beginTone = lstarFromArgb(begin.argb),
       _endTone = lstarFromArgb(end.argb),
       _beginHct = Hct.fromInt(begin.argb),
       _endHct = Hct.fromInt(end.argb),
       super(begin: begin, end: end);

  // ---------------------------------------------------------------------------
  final bool _keepChroma;

  // Cartesian branch cache
  final Cam16V11 _beginCam;
  final Cam16V11 _endCam;
  final double _beginTone;
  final double _endTone;

  // Hue-locked branch cache
  final Hct _beginHct;
  final Hct _endHct;

  @override
  Color? lerp(double t) {
    if (begin == null || end == null) return null;

    // Round t to reduce cache key variations
    final tKey = (t * 100).round();

    if (_keepChroma) {
      // Equivalent to hctLerpCartesian except it is using cached values for
      // begin and end.
      final aStar = _beginCam.astar + (_endCam.astar - _beginCam.astar) * t;
      final bStar = _beginCam.bstar + (_endCam.bstar - _beginCam.bstar) * t;
      final jStar = _beginCam.jstar + (_endCam.jstar - _beginCam.jstar) * t;
      final tone = _beginTone + (_endTone - _beginTone) * t;

      // Round values for cache key
      final aStarKey = aStar.round();
      final bStarKey = bStar.round();
      final jStarKey = jStar.round();
      final toneKey = tone.round();

      // Create cache key from all parameters
      final cacheKey = '$tKey:$aStarKey:$bStarKey:$jStarKey:$toneKey';

      // Check cache first
      final cachedColor = _cartesianCache.getValue(cacheKey);
      if (cachedColor != null) {
        if (_kLogCacheStats) {
          _cacheHits++;
          if (_cacheHits % 100 == 0) {
            debugPrint(
              'HctColorTween cache hits: $_cacheHits, misses: $_cacheMisses',
            );
          }
        }
        return cachedColor;
      }

      final cam = Cam16V11.fromUcs(jStar, aStar, bStar);
      final color = Hct.from(cam.hue, cam.chroma, tone).color;

      // Cache the computed color
      _cartesianCache.putValue(cacheKey, color);
      if (_kLogCacheStats) {
        _cacheMisses++;
      }
      return color;
    }

    // Hct.lerpKeepHue equivalent, but using cached values for begin and end.
    // Constant-hue branch
    final chroma = _beginHct.chroma + (_endHct.chroma - _beginHct.chroma) * t;
    final tone = _beginHct.tone + (_endHct.tone - _beginHct.tone) * t;

    // Round values for cache key
    final chromaKey = chroma.round();
    final toneKey = tone.round();
    final hueKey = _beginHct.hue.round(); // Hue is constant in this branch

    // Create cache key
    final cacheKey = '$tKey:$hueKey:$chromaKey:$toneKey';

    // Check cache first
    final cachedColor = _hueLockedCache.getValue(cacheKey);
    if (cachedColor != null) {
      if (_kLogCacheStats) {
        _cacheHits++;
      }
      return cachedColor;
    }

    final color = Hct.from(_beginHct.hue, chroma, tone).color;

    // Cache the computed color
    _hueLockedCache.putValue(cacheKey, color);
    if (_kLogCacheStats) {
      _cacheMisses++;
    }
    return color;
  }
}
