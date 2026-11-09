import 'package:pixel_snap_fork/material.dart';

import 'package:monet_ui/util/lru_cache.dart';

const _kShadowCacheCapacity = 64;
final _ShadowListCache<Color, List<Shadow>> _headerProtectionShadowsCache =
    .new(capacity: _kShadowCacheCapacity);
final _ShadowListCache<Color, List<Shadow>> _protectionShadowsCache = .new(
  capacity: _kShadowCacheCapacity,
);
final _ShadowListCache<Color, List<BoxShadow>> _defaultAestheticShadowsCache =
    .new(capacity: _kShadowCacheCapacity);
final _ShadowListCache<_AestheticShadowsCacheKey, List<BoxShadow>>
_aestheticShadowsCache = .new(capacity: _kShadowCacheCapacity);

/// Keeps hit lookup to one non-mutating hash-table read. [LruCache]'s regular
/// lookup promotes entries with remove/reinsert, which costs more than these
/// tiny shadow builders. The LRU owns the bound and eviction callbacks; shadow
/// working sets normally fit entirely, so recency only matters during churn.
class _ShadowListCache<K, V extends Object> {
  final int capacity;
  final Map<K, _ShadowListCacheEntry<K, V>> _entries = {};

  _ShadowListCache({required this.capacity});

  late final LruCache<K, _ShadowListCacheEntry<K, V>> _eviction = .new(
    capacity: capacity,
    onEvict: (entry) {
      if (identical(_entries[entry.key], entry)) {
        _entries.remove(entry.key);
      }
    },
  );

  V? lookup(K key) => _entries[key]?.value;

  void store(K key, V value) {
    final entry = _ShadowListCacheEntry(key, value);
    _eviction[key] = entry;
    _entries[key] = entry;
  }

  void clear() {
    _eviction.clear();
    _entries.clear();
  }
}

class _ShadowListCacheEntry<K, V> {
  final K key;
  final V value;

  const _ShadowListCacheEntry(this.key, this.value);
}

class _AestheticShadowsCacheKey {
  final Color color;
  final double blurRadius;
  final bool includeOutline;
  final int _hashCode;

  _AestheticShadowsCacheKey({
    required this.color,
    required this.blurRadius,
    required this.includeOutline,
  }) : _hashCode = Object.hash(color, blurRadius, includeOutline);

  @override
  bool operator ==(Object other) =>
      other is _AestheticShadowsCacheKey &&
      other.color == color &&
      other.blurRadius == blurRadius &&
      other.includeOutline == includeOutline;

  @override
  int get hashCode => _hashCode;
}

/// The protection recipes were tuned with device-pixel blur on a 2x view.
const kShadowReferencePixelRatio = 2.0;
const _kRadiusToSigma = 0.57735;

/// A legacy recipe radius converted to logical pixels on every platform.
/// Normalize sigma, not radius: Flutter's radius-to-sigma adds 0.5. Dividing
/// the radius alone would change the halo even at the reference ratio.
/// The old Linux-only adjustment does not describe the Impeller blur rule.
double blurRadiusForPlatform(double spec) => spec <= 0
    ? 0
    : radiusForBlurSigma(
        (spec * _kRadiusToSigma + 0.5) / kShadowReferencePixelRatio,
      );

/// Encodes sigma for Flutter's Shadow API. A zero sigma stays unblurred.
/// Very small sigmas cannot be represented by a nonnegative blur radius.
double radiusForBlurSigma(double sigma) =>
    sigma <= 0.5 ? 0 : (sigma - 0.5) / _kRadiusToSigma;

/// Flutter's paragraph shadows ignore the canvas scale on Skia and Impeller.
/// Encode their logical sigma in device pixels before recording a paragraph.
/// Offsets remain logical; spread is drawn by a foreground Paint separately.
List<Shadow> textShadowsAtScale(List<Shadow> shadows, double scale) =>
    scale == 1 || shadows.isEmpty
    ? shadows
    : [
        for (final shadow in shadows)
          Shadow(
            color: shadow.color,
            offset: shadow.offset,
            blurRadius: shadow.blurRadius <= 0
                ? 0
                : radiusForBlurSigma(shadow.blurSigma * scale),
          ),
      ];

const kDefaultProtectionBlurRadius = 4.0;
const kDefaultProtectionHaloOffset = 1.0;
const kDefaultProtectionHaloAlpha = 0.70;

double protectionBlurRadius() {
  return blurRadiusForPlatform(kDefaultProtectionBlurRadius);
}

Shadow _logicalShadow({
  required Color color,
  double blurRadius = 0.0,
  Offset offset = .zero,
}) {
  return Shadow(
    color: color,
    blurRadius: blurRadiusForPlatform(blurRadius),
    offset: offset,
  );
}

BoxShadow _logicalBoxShadow({
  required Color color,
  double blurRadius = 0.0,
  double spreadRadius = 0.0,
  Offset offset = .zero,
}) {
  return BoxShadow(
    color: color,
    blurRadius: blurRadiusForPlatform(blurRadius),
    spreadRadius: spreadRadius,
    offset: offset,
  );
}

/// Passing in [Colors.transparent] will result in no shadows.
/// The returned list is immutable and shared by equal calls.
List<Shadow> headerProtectionShadows(Color baseColor) {
  if (baseColor == Colors.transparent) {
    return const [];
  }
  final cached = _headerProtectionShadowsCache.lookup(baseColor);
  if (cached != null) return cached;
  final shadows = List<Shadow>.unmodifiable([
    _logicalBoxShadow(color: baseColor, blurRadius: 8),
  ]);
  _headerProtectionShadowsCache.store(baseColor, shadows);
  return shadows;
}

/// Use with MonetRichText or MonetIcon.
/// Passing in [Colors.transparent] will result in no shadows.
/// The returned list is immutable and shared by equal calls.
List<Shadow> protectionShadows(Color baseColor) {
  if (baseColor == Colors.transparent) {
    return const [];
  }
  final cached = _protectionShadowsCache.lookup(baseColor);
  if (cached != null) return cached;
  final shadows = List<Shadow>.unmodifiable([
    for (var i = 0; i < 3; i++)
      _logicalBoxShadow(color: baseColor, blurRadius: 8),
    _logicalBoxShadow(color: baseColor, blurRadius: 0, spreadRadius: 1),
  ]);
  _protectionShadowsCache.store(baseColor, shadows);
  return shadows;
}

/// Scales [shadows] for [homeScaleProvider]-style zoom, preserving
/// [BoxShadow.spreadRadius].
///
/// Mapping a [BoxShadow] to a plain [Shadow] silently drops spread, which is
/// how [protectionShadows] draws its crisp outline: text and MonetIcon draw
/// spread by stroking the glyph, and only when the shadow is still a
/// [BoxShadow].
List<Shadow> scaleShadows(List<Shadow> shadows, double? scale) {
  if (scale == null || scale == 1.0 || shadows.isEmpty) return shadows;
  return List.unmodifiable(shadows.map((e) => _scaleShadow(e, scale)));
}

/// [scaleShadows] for lists that must stay [BoxShadow], e.g. `BoxDecoration`.
List<BoxShadow> scaleBoxShadows(List<BoxShadow> shadows, double? scale) {
  if (scale == null || scale == 1.0 || shadows.isEmpty) return shadows;
  return List.unmodifiable(shadows.map((e) => _scaleBoxShadow(e, scale)));
}

Shadow _scaleShadow(Shadow shadow, double scale) {
  if (shadow is BoxShadow) return _scaleBoxShadow(shadow, scale);
  return Shadow(
    color: shadow.color,
    blurRadius: shadow.blurRadius * scale,
    offset: shadow.offset * scale,
  );
}

BoxShadow _scaleBoxShadow(BoxShadow shadow, double scale) {
  return BoxShadow(
    color: shadow.color,
    blurRadius: shadow.blurRadius * scale,
    spreadRadius: shadow.spreadRadius * scale,
    offset: shadow.offset * scale,
    blurStyle: shadow.blurStyle,
  );
}

/// No-blur text/icon protection halo.
///
/// Flutter text shadows do not support BoxShadow spread. Passing a [BoxShadow]
/// through `TextStyle.shadows` preserves colour/offset/blurRadius, but the text
/// paragraph path has no spread-radius primitive. A zero-blur, zero-offset shadow
/// is just an exact copy behind the fill and is mostly hidden; visible spread has
/// to be approximated with several zero-blur offset copies.
List<Shadow> hardProtectionHaloShadows(
  Color baseColor, {
  double offset = kDefaultProtectionHaloOffset,
  double alpha = kDefaultProtectionHaloAlpha,
  bool includeDiagonals = true,
}) {
  if (baseColor == Colors.transparent || alpha <= 0 || offset <= 0) {
    return const [];
  }
  final color = baseColor.withValues(alpha: alpha);
  return [
    _logicalShadow(color: color, offset: Offset(-offset, 0)),
    _logicalShadow(color: color, offset: Offset(offset, 0)),
    _logicalShadow(color: color, offset: Offset(0, -offset)),
    _logicalShadow(color: color, offset: Offset(0, offset)),
    if (includeDiagonals) ...[
      _logicalShadow(color: color, offset: Offset(-offset, -offset)),
      _logicalShadow(color: color, offset: Offset(offset, -offset)),
      _logicalShadow(color: color, offset: Offset(-offset, offset)),
      _logicalShadow(color: color, offset: Offset(offset, offset)),
    ],
  ];
}

// Only used by STT button.
List<Shadow> barelyThereProtectionShadows(Color baseColor) {
  return [
    _logicalShadow(color: baseColor, blurRadius: kDefaultProtectionBlurRadius),
    _logicalShadow(
      color: baseColor.withValues(alpha: 0.5),
      blurRadius: kDefaultProtectionBlurRadius,
    ),
  ];
}

// Used by Flushbar.
List<Shadow> surfaceShadowsForPlatform(Color baseColor) {
  const blurRadius = 6.0;
  return [
    _logicalShadow(color: baseColor, blurRadius: blurRadius),
    _logicalShadow(color: baseColor, blurRadius: blurRadius),
  ];
}

List<BoxShadow> surfaceBoxShadowsForPlatform(Color baseColor) {
  const blurRadius = 6.0;
  return [
    _logicalBoxShadow(color: baseColor, blurRadius: blurRadius),
    _logicalBoxShadow(color: baseColor, blurRadius: blurRadius),
  ];
}

/// Used by MonetButton and MonetSurface. Suggested for all containers.
///
/// The returned list is immutable and shared by calls with equal arguments.
List<BoxShadow> aestheticShadows(
  Color color, {
  double blurRadius = kDefaultProtectionBlurRadius,
  bool includeOutline = true,
}) {
  if (blurRadius == kDefaultProtectionBlurRadius && includeOutline) {
    final cached = _defaultAestheticShadowsCache.lookup(color);
    if (cached != null) return cached;
    final shadows = _createAestheticShadows(color, blurRadius, includeOutline);
    _defaultAestheticShadowsCache.store(color, shadows);
    return shadows;
  }
  final key = _AestheticShadowsCacheKey(
    color: color,
    blurRadius: blurRadius,
    includeOutline: includeOutline,
  );
  final cached = _aestheticShadowsCache.lookup(key);
  if (cached != null) return cached;
  final shadows = _createAestheticShadows(color, blurRadius, includeOutline);
  _aestheticShadowsCache.store(key, shadows);
  return shadows;
}

List<BoxShadow> _createAestheticShadows(
  Color color,
  double blurRadius,
  bool includeOutline,
) {
  return List<BoxShadow>.unmodifiable([
    if (includeOutline) outlineOnlyShadow(color),
    // Penumbra: Partial shadow
    _logicalBoxShadow(
      offset: .zero,
      blurRadius: blurRadius / 2.0, // More diffuse than umbra
      spreadRadius: 1.0, // Natural edge
      color: color.withValues(alpha: 0.3),
    ),
    // Ambient: Most diffuse, scattered light
    _logicalBoxShadow(
      offset: .zero,
      blurRadius: blurRadius, // Most diffuse
      color: color.withValues(alpha: 0.5),
    ),
  ]);
}

BoxShadow outlineOnlyShadow(Color color) {
  return _logicalBoxShadow(color: color, spreadRadius: 1);
}

List<BoxShadow> fabShadows(Color color) {
  return [
    ...?kElevationToShadow[16]?.map(
      (e) => _logicalBoxShadow(
        color: color.withValues(alpha: 0.3),
        blurRadius: e.blurRadius,
        offset: .zero,
      ),
    ),
  ];
}
