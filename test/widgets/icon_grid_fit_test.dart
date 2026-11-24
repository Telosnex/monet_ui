import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:monet_ui/widgets/raster_cache_diagnostics.dart';
import 'package:monet_ui/widgets/snapped_icons/icon_grid_fit.dart';
import 'package:monet_ui/widgets/snapped_icons/icon_outline.dart';

import 'paint_reuse_fixtures.dart';

void main() {
  const phase = 0.5;
  final outline = _dotOutline();

  test('cached axes produce the same coordinates at all phase pairs', () {
    final cache = IconPathCache();
    for (final shape in [outline, barsOutline()]) {
      for (final flip in [false, true]) {
        // These two sizes round to the same path-key size, but exact axis
        // fits must not be shared when the underlying scale differs.
        for (final size in [23.5, 23.50001]) {
          final before = RasterCacheDiagnostics.snapshot();
          for (var x = 0; x < 8; x++) {
            for (var y = 0; y < 8; y++) {
              Float64List points(IconPathCache? using) => gridFitIconPoints(
                shape,
                size: size,
                deviceScale: 1.75,
                phaseX: x / 8,
                phaseY: y / 8,
                flipX: flip,
                cache: using,
              );
              expect(points(cache), orderedEquals(points(null)));
            }
          }
          final counts = RasterCacheDiagnostics.since(before);
          expect(counts['icon.axisFitBuilt'], 16);
          expect(counts['icon.axisFitReused'], 112);
        }
      }
    }
  });

  for (final (size, boundary) in [(48.0, 'position'), (45.5, 'parity')]) {
    test('mirrored dot rows share a placement across a $boundary boundary', () {
      final points = gridFitIconPoints(
        outline,
        size: size,
        deviceScale: 1,
        phaseX: phase,
        phaseY: phase,
      );
      // Read each dot center from its top and bottom extrema.
      double center(int dot) =>
          (points[26 * dot + 7] + points[26 * dot + 19]) / 2 + phase;
      final mirror = center(0);
      for (final y in [mirror, center(1), center(2)]) {
        expect(2 * y, closeTo((2 * y).round(), 1e-9));
      }
      expect(center(1), lessThan(mirror));
      expect(center(2), greaterThan(mirror));
      expect(center(1) + center(2), closeTo(2 * mirror, 1e-9));
    });
  }
}

/// A center dot and a pair like the two Fitbit dots whose bounds differ
/// by one font unit, plus two outer dots to pin the mirror at y=256.
IconOutline _dotOutline() {
  final verbs = <int>[];
  final points = <int>[];
  void dot(int x, int top, int bottom) {
    final y = (top + bottom) ~/ 2;
    final radius = (bottom - top) ~/ 2;
    final control = (radius * 0.55).round();
    final left = x - radius, right = x + radius;
    verbs.addAll([
      OutlineVerb.move,
      for (var i = 0; i < 4; i++) OutlineVerb.cubic,
      OutlineVerb.close,
    ]);
    final curve = [
      (left, y),
      (left, y - control),
      (x - control, top),
      (x, top),
      (x + control, top),
      (right, y - control),
      (right, y),
      (right, y + control),
      (x + control, bottom),
      (x, bottom),
      (x - control, bottom),
      (left, y + control),
      (left, y),
    ];
    for (final (x, y) in curve) {
      points.addAll([x, y]);
    }
  }

  dot(100, 218, 294);
  dot(200, 139, 192);
  dot(200, 320, 374);
  // Equal outer bounds pin the designed mirror even though the inner pair
  // does not mirror exactly.
  dot(300, 43, 105);
  dot(300, 407, 469);
  return IconOutline(Uint8List.fromList(verbs), Int16List.fromList(points));
}
