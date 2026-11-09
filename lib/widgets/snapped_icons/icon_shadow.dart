import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'package:monet_ui/widgets/monet_perf_debug_switches.dart';
import 'package:monet_ui/widgets/raster_cache_diagnostics.dart';
import 'package:monet_ui/widgets/snapped_icons/icon_grid_fit.dart';
import 'package:monet_ui/widgets/snapped_icons/icon_outline.dart';

/// Icon shadows use logical blur, as text and decoration shadows do.
/// The canvas applies the device and ancestor scale exactly once.
double iconShadowBlurDivisor(double _) => 1;

/// Paints [shadows] of the icon [path], in order, as text paints them
/// (ADR 002, R3 and D6).
///
/// Runs of blurred layers in one color come from [IconShadowCache]: one
/// white image per outline, size, scale and layer shape, tinted when drawn.
/// Impeller draws each blurred path with its own offscreen blur passes,
/// about 64 µs each, and keeps nothing between frames; text shadows avoid
/// that with the engine's text shadow cache. Unblurred layers, such as the
/// 1 px ring, stay vector, aligned with the fitted fill [path].
///
/// [path] is in the icon square's coordinates, (0, 0) to ([size], [size]),
/// already mirrored when [flipX]. [memo], kept by the icon between paints,
/// skips the cache lookup while the shadows keep their shape.
int paintIconShadows(
  Canvas canvas,
  Path path,
  List<Shadow> shadows, {
  required IconOutline outline,
  required double size,
  required double deviceScale,
  bool flipX = false,
  IconShadowMemo? memo,
  bool cache = true,
}) {
  var runIndex = 0;
  var blurs = 0;
  final visible = [
    for (final shadow in shadows)
      if (shadow.color.a > 0) shadow,
  ];
  var i = 0;
  while (i < visible.length) {
    final first = visible[i];
    if (first.blurRadius <= 0) {
      blurs += paintIconShadow(
        canvas,
        path,
        first,
        flipX: flipX,
        deviceScale: deviceScale,
      );
      i++;
      continue;
    }
    var end = i + 1;
    while (end < visible.length &&
        visible[end].blurRadius > 0 &&
        _sameRgb(visible[end].color, first.color)) {
      end++;
    }
    final run = visible.sublist(i, end);
    final cached =
        cache &&
        IconShadowCache.instance.paint(
          canvas,
          run,
          outline: outline,
          size: size,
          deviceScale: deviceScale,
          flipX: flipX,
          memo: memo,
          run: runIndex++,
        );
    if (!cached) {
      for (final shadow in run) {
        blurs += paintIconShadow(
          canvas,
          path,
          shadow,
          flipX: flipX,
          deviceScale: deviceScale,
        );
      }
    }
    i = end;
  }
  return blurs;
}

/// Paints [shadow] of the icon [path] as vector, as text paints it.
///
/// The path at the shadow's offset is a text shadow, blurred by its sigma
/// over [iconShadowBlurDivisor]. A [BoxShadow] with a spread also draws a
/// round-joined stroke 2 × spread wide around the path. Text draws that ring
/// with a foreground paint (`paint_strategy.dart`), which blurs in logical
/// pixels.
///
/// With [flipX], the icon is mirrored, so the offset is too, as [Icon]'s
/// mirror transform does.
///
/// Returns how many blurred paths it drew. A picture blurs each of them
/// again on every frame that draws it.
int paintIconShadow(
  Canvas canvas,
  Path path,
  Shadow shadow, {
  bool flipX = false,
  required double deviceScale,
}) {
  if (shadow.color.a <= 0) return 0;
  final offset = flipX
      ? Offset(-shadow.offset.dx, shadow.offset.dy)
      : shadow.offset;
  // Translate the canvas, not the path: Path.shift copies the path.
  final shifted = offset != .zero;
  if (shifted) {
    canvas
      ..save()
      ..translate(offset.dx, offset.dy);
  }
  canvas.drawPath(
    path,
    iconShadowPaint(shadow, divisor: iconShadowBlurDivisor(deviceScale)),
  );
  final blurred = shadow.blurRadius > 0 ? 1 : 0;
  final spread = shadow is BoxShadow ? shadow.spreadRadius : 0.0;
  if (spread > 0) {
    canvas.drawPath(
      path,
      iconShadowPaint(shadow)
        ..style = .stroke
        ..strokeWidth = 2 * spread
        ..strokeJoin = .round,
    );
  }
  if (shifted) canvas.restore();
  return spread > 0 ? 2 * blurred : blurred;
}

/// [shadow] as text paints it: its color, blurred with the normal style by
/// its sigma over [divisor]. [BoxShadow.toPaint] would also take its blur
/// style, and in tests drop the blur (`debugDisableShadows`); text shadows
/// do neither.
Paint iconShadowPaint(Shadow shadow, {double divisor = 1}) {
  final paint = Paint()..color = shadow.color;
  if (shadow.blurRadius > 0) {
    paint.maskFilter = MaskFilter.blur(.normal, shadow.blurSigma / divisor);
  }
  return paint;
}

/// Vector blurs that attached icons' last paints recorded.
///
/// A blurred path in a picture is blurred again on every frame that draws
/// the picture, so [blurs] approximates the GPU blurs icons cost each frame.
/// Icons draw shadows from [IconShadowCache] when snapped; an icon under an
/// undeclared scale (ADR 002, D7) draws vector blurs instead. A screen that
/// holds a nonzero count while idle has that problem.
///
/// Counts icons in the render tree, not only those on screen.
abstract final class IconVectorBlurCensus {
  /// Attached icons whose last paint drew at least one vector blur.
  static int get icons => _icons;

  /// Vector blurs those paints drew.
  static int get blurs => _blurs;

  static var _icons = 0;
  static var _blurs = 0;

  /// One icon's last paint drew [now] vector blurs, replacing [previous].
  static void update(int previous, int now) {
    if (previous == now) return;
    _blurs += now - previous;
    if (previous == 0) _icons++;
    if (now == 0) _icons--;
  }
}

bool _sameRgb(Color a, Color b) =>
    a.r == b.r && a.g == b.g && a.b == b.b && a.colorSpace == b.colorSpace;

/// What one icon's last paint found in [IconShadowCache], per blurred run.
///
/// While a run keeps its outline, size, scale and layer shapes, the next
/// paint reuses the image without building a key. A palette tick changes
/// only colors, so it takes this path.
final class IconShadowMemo {
  final _runs = <_RunMemo>[];

  _RunMemo _run(int i) {
    while (_runs.length <= i) {
      _runs.add(_RunMemo());
    }
    return _runs[i];
  }

  /// Forgets every image, as when the icon detaches.
  void clear() => _runs.clear();
}

final class _RunMemo {
  _ShadowKey? key;
  _ShadowImage? image;

  /// Whether [run] at [scale] has [key]'s shape, without allocating.
  bool matches(
    List<Shadow> run,
    IconOutline outline,
    double size,
    double scale,
  ) {
    final key = this.key;
    if (key == null ||
        !identical(key.outline, outline) ||
        key.size != size ||
        key.scale != scale ||
        key.layers.length != run.length * _ShadowKey.fieldsPerLayer) {
      return false;
    }
    var i = 0;
    for (final shadow in run) {
      if (key.layers[i++] != shadow.offset.dx ||
          key.layers[i++] != shadow.offset.dy ||
          key.layers[i++] != shadow.blurRadius ||
          key.layers[i++] != _spread(shadow) ||
          key.layers[i++] != _alpha(shadow)) {
        return false;
      }
    }
    return true;
  }
}

double _spread(Shadow shadow) => shadow is BoxShadow ? shadow.spreadRadius : 0;

double _alpha(Shadow shadow) => (shadow.color.a * 255).roundToDouble();

/// Images of blurred icon shadow layers, shared by every icon.
///
/// An image holds a run of layers in white, at their alphas, around the
/// unfitted outline. Drawing tints it with a `srcIn` color filter, which
/// Impeller draws as one textured quad. Changing the color, as palette ticks
/// do, reuses the image; changing an alpha, blur, spread or offset makes a
/// new one. A blur needs no pixel phase, so the image is drawn where the
/// fitted fill is, with linear sampling.
///
/// The cache holds at most [maxBytes] of images, evicting the least recently
/// used; an image wider than [maxSide] pixels is not cached.
final class IconShadowCache {
  IconShadowCache._();

  static final instance = IconShadowCache._();

  static const maxBytes = 16 << 20;
  static const maxSide = 512;

  /// Draws vector shadows instead, for tests that compare the two.
  @visibleForTesting
  static bool debugDisabled = false;

  /// Replaces [maxBytes] in tests.
  @visibleForTesting
  static int? debugMaxBytes;

  final _entries = <_ShadowKey, _ShadowImage>{};
  int _debugBytes = 0;

  /// Counts uses. Each image keeps the count of its last use, so a hit
  /// costs one store instead of reordering the map.
  int _clock = 0;

  /// The tint paint of the last color. Icons that paint one after another
  /// share a palette color, and setting a color filter allocates a native
  /// filter.
  Color? _tint;
  final _tintPaint = Paint()..filterQuality = .low;

  @visibleForTesting
  int get debugImageCount => _entries.length;

  @visibleForTesting
  int get debugBytes => _debugBytes;

  /// Images made since start or [debugClear].
  @visibleForTesting
  int debugCreated = 0;

  @visibleForTesting
  void debugClear() {
    for (final entry in _entries.values) {
      entry.dispose();
    }
    _entries.clear();
    _debugBytes = 0;
    debugCreated = 0;
  }

  /// Paints [layers], blurred and in one color, under an icon whose square
  /// is at the canvas origin. [run] numbers this run of layers in the icon's
  /// [memo]. False when it is not cached; the caller then paints vector.
  bool paint(
    Canvas canvas,
    List<Shadow> layers, {
    required IconOutline outline,
    required double size,
    required double deviceScale,
    required bool flipX,
    IconShadowMemo? memo,
    int run = 0,
  }) {
    if (debugDisabled || MonetPerfDebugSwitches.disableCachedRendering) {
      return false;
    }
    if (size <= 0 || deviceScale <= 0) return false;
    // Steps of 1/8 hold the common ratios (1.75, 2.625, 3.5) exactly, and
    // bound the images that a scale animation makes.
    final scale = (deviceScale * 8).round() / 8;
    final runMemo = memo?._run(run);
    var entry = runMemo?.image;
    if (entry == null ||
        entry.disposed ||
        !runMemo!.matches(layers, outline, size, scale)) {
      entry = _lookup(layers, outline, size, scale, runMemo);
      if (entry == null) return false;
    } else {
      RasterCacheDiagnostics.record(.icon, .hit);
    }
    entry.lastUse = ++_clock;

    final image = entry.image;
    final side = image.width.toDouble();
    canvas.save();
    if (flipX) {
      // The image mirrors about the square's center, offsets included.
      canvas
        ..translate(size, 0)
        ..scale(-1, 1);
    }
    canvas
      ..drawImageRect(
        image,
        Rect.fromLTWH(0, 0, side, side),
        Rect.fromLTWH(-entry.pad, -entry.pad, side / scale, side / scale),
        _tintFor(layers.first.color),
      )
      ..restore();
    return true;
  }

  Paint _tintFor(Color color) {
    final opaque = color.withValues(alpha: 1);
    if (opaque != _tint) {
      _tint = opaque;
      _tintPaint.colorFilter = ColorFilter.mode(opaque, .srcIn);
    }
    return _tintPaint;
  }

  _ShadowImage? _lookup(
    List<Shadow> run,
    IconOutline outline,
    double size,
    double scale,
    _RunMemo? memo,
  ) {
    final key = _ShadowKey(outline, size, scale, [
      for (final shadow in run) ...[
        shadow.offset.dx,
        shadow.offset.dy,
        shadow.blurRadius,
        _spread(shadow),
        _alpha(shadow),
      ],
    ]);
    var entry = _entries[key];
    if (entry == null) {
      RasterCacheDiagnostics.record(.icon, .miss);
      entry = _render(run, outline, size, scale);
      if (entry == null) return null;
      debugCreated++;
      RasterCacheDiagnostics.record(.icon, .created);
      RasterCacheDiagnostics.record(.icon, .createdPixels, entry.pixels);
      _entries[key] = entry;
      _debugBytes += entry.pixels * 4;
      // The new image is the most recent, so eviction keeps it.
      entry.lastUse = ++_clock;
      _evict();
    } else {
      RasterCacheDiagnostics.record(.icon, .hit);
    }
    memo
      ?..key = key
      ..image = entry;
    return entry;
  }

  /// Evicts least recently used images until within budget. Scans every
  /// entry per eviction; evictions are rare, hits are every paint.
  void _evict() {
    while (_debugBytes > (debugMaxBytes ?? maxBytes) && _entries.length > 1) {
      MapEntry<_ShadowKey, _ShadowImage>? oldest;
      for (final entry in _entries.entries) {
        if (oldest == null || entry.value.lastUse < oldest.value.lastUse) {
          oldest = entry;
        }
      }
      _entries.remove(oldest!.key);
      _debugBytes -= oldest.value.pixels * 4;
      oldest.value.dispose();
      RasterCacheDiagnostics.record(.icon, .budgetEviction);
    }
  }

  static _ShadowImage? _render(
    List<Shadow> run,
    IconOutline outline,
    double size,
    double scale,
  ) {
    // Logical distance from the square that any layer reaches: offset,
    // spread, and three sigmas of the wider of its two blurs, plus a pixel
    // for antialiasing.
    var reach = 0.0;
    for (final shadow in run) {
      final spread = shadow is BoxShadow ? shadow.spreadRadius : 0.0;
      final fill = shadow.blurSigma / iconShadowBlurDivisor(scale);
      final blur = spread > 0 ? math.max(fill, shadow.blurSigma) : fill;
      reach = math.max(
        reach,
        math.max(shadow.offset.dx.abs(), shadow.offset.dy.abs()) +
            spread +
            3 * blur,
      );
    }
    final pad = (reach + 1 / scale).ceilToDouble();
    final side = ((size + 2 * pad) * scale).ceil();
    if (side > maxSide) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(scale)
      ..translate(pad, pad);
    // The unfitted outline: a blur needs no pixel phase, and it mirrors
    // exactly.
    final path = gridFitIconOutline(
      outline,
      size: size,
      deviceScale: scale,
      phase: .zero,
      snap: false,
    );
    for (final shadow in run) {
      const white = Color(0xffffffff);
      final color = white.withValues(alpha: shadow.color.a);
      paintIconShadow(
        canvas,
        path,
        shadow is BoxShadow
            ? BoxShadow(
                color: color,
                offset: shadow.offset,
                blurRadius: shadow.blurRadius,
                spreadRadius: shadow.spreadRadius,
              )
            : Shadow(
                color: color,
                offset: shadow.offset,
                blurRadius: shadow.blurRadius,
              ),
        deviceScale: scale,
      );
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(side, side);
    picture.dispose();
    return _ShadowImage(image, pad, side * side);
  }
}

final class _ShadowImage {
  _ShadowImage(this.image, this.pad, this.pixels);

  final ui.Image image;

  /// Logical distance from the image's edge to the icon square.
  final double pad;
  final int pixels;

  /// [IconShadowCache._clock] at the last use.
  int lastUse = 0;

  /// Set when evicted. An icon's memo may still hold this image.
  bool disposed = false;

  void dispose() {
    disposed = true;
    image.dispose();
  }
}

final class _ShadowKey {
  _ShadowKey(this.outline, this.size, this.scale, this.layers)
    : hashCode = Object.hash(
        identityHashCode(outline),
        size,
        scale,
        Object.hashAll(layers),
      );

  final IconOutline outline;
  final double size;
  final double scale;

  static const fieldsPerLayer = 5;

  /// Per layer: offset x and y, blur radius, spread, alpha × 255.
  final List<double> layers;

  @override
  final int hashCode;

  @override
  bool operator ==(Object other) =>
      other is _ShadowKey &&
      identical(other.outline, outline) &&
      other.size == size &&
      other.scale == scale &&
      listEquals(other.layers, layers);
}
