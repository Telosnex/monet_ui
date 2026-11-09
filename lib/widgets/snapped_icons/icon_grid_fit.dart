import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:monet_ui/widgets/snapped_icons/icon_outline_analysis.dart';

/// Device pixels taken off a dot's width before rounding it to whole
/// pixels; the parity of the result picks a pixel center (odd) or a pixel
/// corner (even) for the dot's center. With 0.25 the choice switches at
/// 1.75, 2.75, and so on: where, for a round dot, the two placements leave
/// equal grey. Rounding without it, a dot 1.5 to 1.75 pixels wide sits on a
/// corner and spreads over four half-covered pixels.
const _kDotCenterBias = 0.25;

/// Builds [outline] as a path whose straight edges land on device pixels.
///
/// The path is in the icon's logical coordinates, (0, 0) to (size, size).
/// [deviceScale] is device pixels per logical pixel. [phase] is the fractional
/// device-pixel position of the icon's origin, each axis in [0, 1).
///
/// See [gridFitIconPoints].
Path gridFitIconOutline(
  IconOutline outline, {
  required double size,
  required double deviceScale,
  required Offset phase,
  bool flipX = false,
  bool snap = true,
}) {
  final points = gridFitIconPoints(
    outline,
    size: size,
    deviceScale: deviceScale,
    phaseX: phase.dx,
    phaseY: phase.dy,
    flipX: flipX,
    snap: snap,
  );
  final path = Path()..fillType = .nonZero;
  var p = 0;
  for (final verb in outline.verbs) {
    switch (verb) {
      case OutlineVerb.move:
        path.moveTo(points[p], points[p + 1]);
        p += 2;
      case OutlineVerb.line:
        path.lineTo(points[p], points[p + 1]);
        p += 2;
      case OutlineVerb.cubic:
        path.cubicTo(
          points[p],
          points[p + 1],
          points[p + 2],
          points[p + 3],
          points[p + 4],
          points[p + 5],
        );
        p += 6;
      case OutlineVerb.close:
        path.close();
    }
  }
  return path;
}

/// The points of [outline], in order, fitted as [gridFitIconOutline]
/// describes: x, y pairs in the icon's logical coordinates. An outline that
/// does not [IconOutline.fits] is only scaled.
///
/// Strokes keep one width per designed width, rounded to whole pixels, and
/// are centered on their designed position. Other points move with the edges
/// around them.
///
/// Solid round dots move as one piece. They keep their designed size and
/// shape, and their center lands on a pixel center or a pixel corner, as
/// [_kDotCenterBias] describes. Every dot in one row or column gets the same
/// choice, so the row stays straight. Snapping a dot's edges like a
/// stroke's warped its size: in lens_blur, the center dots grew from 4.5 to
/// 7 device pixels at 18 dp on a 2x screen.
///
/// Uses [IconOutline.analysis]; [analysis] replaces it.
Float64List gridFitIconPoints(
  IconOutline outline, {
  required double size,
  required double deviceScale,
  required double phaseX,
  required double phaseY,
  bool flipX = false,
  bool snap = true,
  IconOutlineAnalysis? analysis,
}) {
  final em = outline.em;
  final k = size * deviceScale / em;
  final double Function(double) mapX;
  final double Function(double) mapY;
  // Per dot contour: where its center moves.
  final dotMoves = <int, _DotMove>{};
  if (snap && outline.fits) {
    final a = analysis ?? outline.analysis(flipX: flipX);
    mapX = _axisFit(a.x, k, phaseX);
    mapY = _axisFit(a.y, k, phaseY);
    if (a.dots.isNotEmpty) {
      final tx = _placeDots(a.dots, k, 0, mapX, a.x.mirrorAxis);
      final ty = _placeDots(a.dots, k, 1, mapY, a.y.mirrorAxis);
      for (var i = 0; i < a.dots.length; i++) {
        final dot = a.dots[i];
        dotMoves[dot.contour] = _DotMove(
          (dot.left + dot.right) / 2,
          (dot.top + dot.bottom) / 2,
          tx[i],
          ty[i],
        );
      }
    }
  } else {
    mapX = (v) => phaseX + v * k;
    mapY = (v) => phaseY + v * k;
  }
  final points = Float64List(outline.points.length);
  var contour = -1;
  var p = 0;
  void point() {
    var x = outline.points[p].toDouble();
    if (flipX) x = em - x;
    final y = outline.points[p + 1].toDouble();
    final m = dotMoves[contour];
    points[p] =
        ((m == null ? mapX(x) : m.toX + (x - m.fromX) * k) - phaseX) /
        deviceScale;
    points[p + 1] =
        ((m == null ? mapY(y) : m.toY + (y - m.fromY) * k) - phaseY) /
        deviceScale;
    p += 2;
  }

  for (final verb in outline.verbs) {
    switch (verb) {
      case OutlineVerb.move:
        contour++;
        point();
      case OutlineVerb.line:
        point();
      case OutlineVerb.cubic:
        point();
        point();
        point();
      case OutlineVerb.close:
        break;
    }
  }
  return points;
}

/// Returns a monotonic map from font units on one axis to device pixels
/// (relative to the pixel grid, origin at [phase]).
double Function(double) _axisFit(AxisAnalysis axis, double k, double phase) {
  final keys = axis.clusters;
  if (keys.isEmpty) return (v) => phase + v * k;
  final stems = axis.stems;
  final runs = <_Run>[];
  runs.addAll(
    _evenRuns(
      [
        for (final s in stems)
          if (!s.counter) s,
      ],
      keys,
      k,
    ),
  );
  // Gaps between the strokes of an ink run are spaced by that run. A run
  // of gaps counts only where no ink run already sets its edges.
  final taken = {
    for (final r in runs) ...[...r.lows, ...r.highs],
  };
  runs.addAll(
    _evenRuns(
      [
        for (final s in stems)
          if (s.counter) s,
      ],
      keys,
      k,
    ).where((r) => ![...r.lows, ...r.highs].any(taken.contains)),
  );
  final mirror = axis.mirror;
  final values =
      (mirror == null
          ? null
          : _mirroredTargets(mirror, stems, runs, keys, k, phase)) ??
      _independentTargets(stems, runs, keys, k, phase);

  // Keep order; keep edges at least a pixel apart if they were.
  for (var i = 1; i < values.length; i++) {
    final apart = (keys[i] - keys[i - 1]) * k >= 0.75;
    final minimum = values[i - 1] + (apart ? 1 : 0);
    if (values[i] < minimum) values[i] = minimum;
  }
  return (v) {
    if (v <= keys.first) return values.first + (v - keys.first) * k;
    if (v >= keys.last) return values.last + (v - keys.last) * k;
    var lo = 0, hi = keys.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (keys[mid] <= v) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final t = (v - keys[lo]) / (keys[hi] - keys[lo]);
    return values[lo] + t * (values[hi] - values[lo]);
  };
}

/// Whole pixels for a stem from [a] to [b] font units.
///
/// Gaps ([counter]) round up only from 0.65 of a pixel: a crisp gap looks
/// wider than a soft one of the same size.
double _stemPixels(double a, double b, double k, {bool counter = false}) {
  // One pixel width per designed width: quantize to a quarter grid unit so
  // font rounding (42 vs 43 units) cannot split a width.
  const quarter = kIconGridUnit / 4;
  final designed = ((b - a) / quarter).round() * quarter;
  // A width exactly halfway between two pixel counts (2.5 px at 30 px)
  // rounds up: slightly bold reads better than slightly thin.
  final bias = counter ? 0.35 : 0.5;
  return math.max(1, (designed * k + bias + 1e-9).floor()).toDouble();
}

double _widthOf(OutlineStem stem, List<double> clusterCoord, double k) =>
    _stemPixels(
      clusterCoord[stem.low],
      clusterCoord[stem.high],
      k,
      counter: stem.counter,
    );

/// Fills [targets] for the clusters of [stems], keeping each stem's pixel
/// width. Positions are on the grid of values `n + offset`. [ideal] is a
/// cluster's unsnapped position.
void _snapStems(
  Iterable<OutlineStem> stems,
  List<double> clusterCoord,
  double k,
  double Function(int cluster) ideal,
  List<double?> targets, {
  double offset = 0,
}) {
  for (final stem in stems) {
    final width = _widthOf(stem, clusterCoord, k);
    final tLow = targets[stem.low], tHigh = targets[stem.high];
    if (tLow != null && tHigh != null) continue;
    if (tLow != null) {
      targets[stem.high] = tLow + width;
    } else if (tHigh != null) {
      targets[stem.low] = tHigh - width;
    } else {
      final center = (ideal(stem.low) + ideal(stem.high)) / 2;
      final start = _roundTo(center - width / 2, offset);
      targets[stem.low] = start;
      targets[stem.high] = start + width;
    }
  }
}

double _roundTo(double v, double offset) =>
    (v - offset + 0.5).floorToDouble() + offset;

/// Snaps every cluster on its own merits.
List<double> _independentTargets(
  List<OutlineStem> stems,
  List<_Run> runs,
  List<double> clusterCoord,
  double k,
  double phase,
) {
  double ideal(int i) => phase + clusterCoord[i] * k;
  final targets = List<double?>.filled(clusterCoord.length, null);
  for (final run in runs) {
    final center = phase + run.center * k;
    run.place(targets, _roundTo(center - run.span / 2, 0));
  }
  final locked = [for (final t in targets) t != null];
  _snapStems(stems, clusterCoord, k, ideal, targets);
  final values = [
    for (var i = 0; i < targets.length; i++)
      targets[i] ?? _roundTo(ideal(i), 0),
  ];
  _refine(values, stems, clusterCoord, k, ideal, locked);
  return values;
}

/// Moves edges a pixel at a time while that lowers the total cost: each
/// edge's distance from its designed position, plus each stem's width
/// error relative to its width.
///
/// Stems are placed one at a time, so the strokes and gaps left between
/// them get whatever space remains. This trades that space back: an
/// adjacent stem can give up a pixel so a stroke does not collapse to one.
void _refine(
  List<double> values,
  List<OutlineStem> stems,
  List<double> clusterCoord,
  double k,
  double Function(int cluster) ideal,
  List<bool> fixed,
) {
  const widthWeight = 4.0;
  final widths = <_Span, double>{
    for (final stem in stems)
      _Span(stem.low, stem.high): _widthOf(stem, clusterCoord, k),
  };
  final touching = <int, List<_Span>>{};
  for (final pair in widths.keys) {
    (touching[pair.low] ??= []).add(pair);
    (touching[pair.high] ??= []).add(pair);
  }
  double cost(int cluster) {
    var sum = (values[cluster] - ideal(cluster)).abs();
    for (final pair in touching[cluster] ?? const <_Span>[]) {
      final want = widths[pair]!;
      final got = values[pair.high] - values[pair.low];
      if (got < 1) return .infinity;
      sum += widthWeight * (got - want).abs() / want;
    }
    return sum;
  }

  for (var pass = 0; pass < 8; pass++) {
    var changed = false;
    for (var i = 0; i < values.length; i++) {
      if (fixed[i] || touching[i] == null) continue;
      final start = values[i];
      final before = cost(i);
      var best = before;
      var bestValue = start;
      for (final step in [-1.0, 1.0]) {
        values[i] = start + step;
        final after = cost(i);
        if (after < best - 1e-9) {
          best = after;
          bestValue = values[i];
        }
      }
      values[i] = bestValue;
      if (bestValue != start) changed = true;
    }
    if (!changed) break;
  }
}

/// For outlines whose edges mirror across the middle of this axis: snaps
/// the far half and mirrors it, so the result stays symmetric. Returns null
/// when no pixel offset of the axis fits.
///
/// The axis lands on a pixel boundary or a pixel center, whichever keeps the
/// half closer to its designed shape.
List<double>? _mirroredTargets(
  Int32List mirror,
  List<OutlineStem> stems,
  List<_Run> runs,
  List<double> clusterCoord,
  double k,
  double phase,
) {
  const tolerance = 2.0;
  final n = clusterCoord.length;
  final axis = (clusterCoord.first + clusterCoord.last) / 2;
  final loose = {
    for (var i = 0; i < n; i++)
      if (mirror[i] == -1) i,
  };

  bool isFar(int i) => mirror[i] != -1 && mirror[i] < i;
  final hasCenterEdge = [for (var i = 0; i < n; i++) mirror[i] == i]
      .any((e) => e);
  final across = [
    for (final stem in stems)
      if (mirror[stem.low] == stem.high) stem,
  ];
  final farStems = [
    for (final stem in stems)
      if (isFar(stem.low) && isFar(stem.high)) stem,
  ];
  double ideal(int i) => (clusterCoord[i] - axis) * k;

  // Offset 0: the axis is on a pixel boundary. 0.5: on a pixel center.
  List<double?>? half(double offset) {
    if (hasCenterEdge && offset != 0) return null;
    final targets = List<double?>.filled(n, null);
    for (var i = 0; i < n; i++) {
      if (mirror[i] == i) targets[i] = 0;
    }
    for (final run in runs) {
      if ((run.center - axis).abs() <= tolerance) {
        // Centered on the axis: its middle lands on the axis.
        final start = -run.span / 2;
        if (((start - offset) % 1).abs() > 1e-9) return null;
        run.place(targets, start, only: isFar);
      } else if (clusterCoord[run.lows.first] > axis) {
        final center = (run.center - axis) * k;
        run.place(targets, _roundTo(center - run.span / 2, offset));
      }
    }
    // A stem across the axis is centered on it.
    for (final stem in across) {
      if (targets[stem.high] != null) continue;
      final width = _widthOf(stem, clusterCoord, k);
      if ((width / 2 - offset) % 1 != 0) continue;
      targets[stem.high] = width / 2;
    }
    _snapStems(farStems, clusterCoord, k, ideal, targets, offset: offset);
    var previous = 0.0;
    var previousKey = axis;
    for (var i = 0; i < n; i++) {
      if (!isFar(i)) continue;
      var t = targets[i] ?? _roundTo(ideal(i), offset);
      final first = previousKey == axis;
      final gap = (clusterCoord[i] - previousKey) * k * (first ? 2 : 1);
      final minimum = first
          ? (gap >= 0.75 ? 0.5 : 0.0)
          : previous + (gap >= 0.75 ? 1 : 0);
      if (t < minimum) t = (minimum - offset).ceilToDouble() + offset;
      targets[i] = t;
      previous = t;
      previousKey = clusterCoord[i];
    }
    return targets;
  }

  double error(List<double?> targets) {
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      if (isFar(i)) sum += (targets[i]! - ideal(i)).abs();
    }
    // A stem across the axis that this offset cannot center at its width.
    for (final stem in across) {
      final width = _widthOf(stem, clusterCoord, k);
      sum += (2 * targets[stem.high]! - width).abs();
    }
    return sum;
  }

  final center = phase + axis * k;
  List<double?>? best;
  var bestOffset = 0.0;
  var bestScore = double.infinity;
  for (final offset in [0.0, 0.5]) {
    final targets = half(offset);
    if (targets == null) continue;
    final axisTarget = _roundTo(center, offset);
    // Shape error first; the whole-icon shift breaks ties.
    final score = error(targets) + 1e-3 * (axisTarget - center).abs();
    if (score < bestScore) {
      best = targets;
      bestOffset = offset;
      bestScore = score;
    }
  }
  if (best == null) return null;
  final axisTarget = _roundTo(center, bestOffset);
  final values = [
    for (var i = 0; i < n; i++)
      if (mirror[i] == -1)
        double.nan
      else if (mirror[i] == i)
        axisTarget
      else if (isFar(i))
        axisTarget + best[i]!
      else
        axisTarget - best[mirror[i]]!,
  ];
  if (loose.isNotEmpty) _placeLoose(values, loose, stems, clusterCoord, k);
  return values;
}

/// Places [loose] clusters, unset (NaN) in [values], in proportion between
/// the placed clusters around them. A stem with both edges loose keeps its
/// pixel width.
void _placeLoose(
  List<double> values,
  Set<int> loose,
  List<OutlineStem> stems,
  List<double> clusterCoord,
  double k,
) {
  double between(int i) {
    var lo = i - 1, hi = i + 1;
    while (loose.contains(lo)) {
      lo--;
    }
    while (loose.contains(hi)) {
      hi++;
    }
    final t =
        (clusterCoord[i] - clusterCoord[lo]) /
        (clusterCoord[hi] - clusterCoord[lo]);
    return values[lo] + t * (values[hi] - values[lo]);
  }

  final ideal = {for (final i in loose) i: between(i)};
  for (final stem in stems) {
    final a = stem.low, b = stem.high;
    if (!loose.contains(a) || !loose.contains(b)) continue;
    if (!values[a].isNaN || !values[b].isNaN) continue;
    final width = _widthOf(stem, clusterCoord, k);
    final start = _roundTo((ideal[a]! + ideal[b]!) / 2 - width / 2, 0);
    values[a] = start;
    values[b] = start + width;
  }
  for (final i in loose) {
    if (values[i].isNaN) values[i] = _roundTo(ideal[i]!, 0);
  }
}

/// Three or more stems of one pixel width, evenly spaced in the design.
/// They keep even spacing in pixels.
class _Run {
  const _Run(this.lows, this.highs, this.width, this.pitch, this.center);

  /// Cluster indices of each stem's low and high edge, in order.
  final List<int> lows, highs;

  /// Stem width and stem-to-stem distance, in device pixels.
  final double width, pitch;

  /// Designed middle of the run, in font units.
  final double center;

  double get span => (lows.length - 1) * pitch + width;

  /// Puts the run's first edge at [start]. Skips clusters already placed
  /// and, with [only], clusters it rejects.
  void place(
    List<double?> targets,
    double start, {
    bool Function(int cluster)? only,
  }) {
    for (var j = 0; j < lows.length; j++) {
      void put(int cluster, double at) {
        if (targets[cluster] == null && (only?.call(cluster) ?? true)) {
          targets[cluster] = at;
        }
      }

      put(lows[j], start + j * pitch);
      put(highs[j], start + j * pitch + width);
    }
  }
}

/// Finds [_Run]s among [stems].
List<_Run> _evenRuns(
  List<OutlineStem> stems,
  List<double> clusterCoord,
  double k,
) {
  final cc = clusterCoord;
  final counter = stems.isNotEmpty && stems.first.counter;
  // What each stem covers along the axis. Members of a run must match:
  // repeats of one shape, not unrelated strokes that happen to be evenly
  // spaced.
  final extents = <_Span, Set<_Span>>{};
  for (final stem in stems) {
    (extents[_Span(stem.low, stem.high)] ??= {}).add(
      _Span(stem.extentStart, stem.extentEnd),
    );
  }
  final pairs = extents.keys.toList()..sort((a, b) => a.low.compareTo(b.low));
  bool sameShape(_Span a, _Span b) {
    final ea = extents[a]!, eb = extents[b]!;
    return ea.length == eb.length && ea.containsAll(eb);
  }

  double widthOf(_Span p) =>
      _stemPixels(cc[p.low], cc[p.high], k, counter: counter);
  final runs = <_Run>[];
  var i = 0;
  while (i < pairs.length) {
    final width = widthOf(pairs[i]);
    var j = i + 1;
    while (j < pairs.length) {
      final previous = pairs[j - 1], next = pairs[j];
      if (cc[next.low] <= cc[previous.high]) break;
      if (widthOf(next) != width) break;
      if (!sameShape(pairs[i], next)) break;
      if (j > i + 1) {
        final pitch = cc[pairs[i + 1].low] - cc[pairs[i].low];
        final step = cc[next.low] - cc[previous.low];
        if ((step - pitch).abs() > 2 * kSameEdge) break;
      }
      j++;
    }
    if (j - i < 3) {
      i++;
      continue;
    }
    final first = pairs[i], last = pairs[j - 1];
    final designedPitch = (cc[last.low] - cc[first.low]) / (j - i - 1);
    final gapPixels = (designedPitch - (cc[first.high] - cc[first.low])) * k;
    final pitch = math.max(
      width + (gapPixels >= 0.75 ? 1 : 0),
      (designedPitch * k + 0.5).floorToDouble(),
    );
    runs.add(
      _Run(
        [for (var m = i; m < j; m++) pairs[m].low],
        [for (var m = i; m < j; m++) pairs[m].high],
        width,
        pitch,
        (cc[first.low] + cc[last.high]) / 2,
      ),
    );
    i = j;
  }
  return runs;
}

/// Bounded cache of fitted paths.
///
/// The key rounds the phase to 1/8 device pixel on each axis, and a phase
/// of 1 becomes 0 (ADR 002, D10). The path is fitted at the rounded phase,
/// so it does not depend on which phase missed first. Draw it at the
/// rounded phase, [snapPhase], so its edges land on device pixels.
final class IconPathCache {
  IconPathCache({this.capacity = 512});

  /// Phase steps per device pixel.
  static const phaseSteps = 8;

  /// [phase] rounded to the nearest step, in [0, 1]. The icon moves by at
  /// most 1/16 device pixel. 1 and 0 give the same path.
  static double snapPhase(double phase) =>
      (phase * phaseSteps).roundToDouble() / phaseSteps;

  final int capacity;
  final _paths = <_PathKey, Path>{};

  Path lookup(
    IconOutline outline, {
    required double size,
    required double deviceScale,
    required Offset phase,
    bool flipX = false,
    bool snap = true,
  }) {
    int q(double v) => (v * 64).round();
    int step(double v) => (v * phaseSteps).round() % phaseSteps;
    // An unsnapped path does not depend on the phase.
    final fit = snap && outline.fits;
    final px = fit ? step(phase.dx) : 0, py = fit ? step(phase.dy) : 0;
    final key = _PathKey(
      outline,
      q(size * deviceScale),
      q(deviceScale),
      px,
      py,
      flipX,
      fit,
    );
    final cached = _paths.remove(key);
    if (cached != null) return _paths[key] = cached;
    if (_paths.length >= capacity) _paths.remove(_paths.keys.first);
    return _paths[key] = gridFitIconOutline(
      outline,
      size: size,
      deviceScale: deviceScale,
      phase: Offset(px / phaseSteps, py / phaseSteps),
      flipX: flipX,
      snap: fit,
    );
  }
}

/// Per dot, in order: its center on [axis] (0 x, 1 y) in device pixels,
/// through [map] and then onto a pixel center or corner as [_rowParity]
/// picks.
///
/// When the outline mirrors across [mirror], the mirror line lands on a
/// pixel center or corner, dots on one side are placed, and the other side
/// mirrors them. Placed one by one, mirrored dots could round apart.
List<double> _placeDots(
  List<OutlineDot> dots,
  double k,
  int axis,
  double Function(double) map,
  double? mirror,
) {
  final odd = _rowParity(dots, k, axis);
  double place(double v, bool odd) =>
      odd ? v.floorToDouble() + 0.5 : v.roundToDouble();
  double center(OutlineDot d) =>
      axis == 0 ? (d.left + d.right) / 2 : (d.top + d.bottom) / 2;
  if (mirror == null) {
    return [
      for (var i = 0; i < dots.length; i++) place(map(center(dots[i])), odd[i]),
    ];
  }
  bool onMirror(OutlineDot d) => (center(d) - mirror).abs() <= 2 * kSameEdge;
  // The mirror line, on a pixel center or corner. Edges already snapped
  // usually put it on one; otherwise dots on the line pick.
  var m = map(mirror);
  if (((2 * m) - (2 * m).roundToDouble()).abs() > 1e-6) {
    final onLine = [
      for (var i = 0; i < dots.length; i++)
        if (onMirror(dots[i])) i,
    ];
    m = onLine.isEmpty
        ? (2 * m).roundToDouble() / 2
        : place(m, odd[onLine.first]);
  }
  return [
    for (var i = 0; i < dots.length; i++)
      () {
        final d = dots[i];
        if (onMirror(d)) return m;
        final dist = map(center(d)) - map(mirror);
        final far = place(m + dist.abs(), odd[i]);
        return dist >= 0 ? far : 2 * m - far;
      }(),
  ];
}

/// Per dot: whether its center goes on a pixel center (true) or a pixel
/// corner on [axis] (0 x, 1 y). Dots whose centers line up on this axis form
/// one row and share the choice of the smallest, so the row stays straight.
List<bool> _rowParity(List<OutlineDot> dots, double k, int axis) {
  double center(OutlineDot d) =>
      axis == 0 ? (d.left + d.right) / 2 : (d.top + d.bottom) / 2;
  double width(OutlineDot d) => axis == 0 ? d.right - d.left : d.bottom - d.top;
  final sorted = [for (var i = 0; i < dots.length; i++) i]
    ..sort((a, b) => center(dots[a]).compareTo(center(dots[b])));
  final result = List.filled(dots.length, false);
  var row = <int>[];
  void flush() {
    if (row.isEmpty) return;
    final smallest = row.map((i) => width(dots[i])).reduce(math.min);
    final pixels = math.max(1, (smallest * k - _kDotCenterBias).round());
    for (final i in row) {
      result[i] = pixels.isOdd;
    }
    row = [];
  }

  for (final i in sorted) {
    if (row.isNotEmpty &&
        center(dots[i]) - center(dots[row.last]) > 2 * kSameEdge) {
      flush();
    }
    row.add(i);
  }
  flush();
  return result;
}

/// Where one dot's center moves: from its designed center, in font units,
/// to its target center, in device pixels.
final class const _DotMove(
  final double fromX,
  final double fromY,
  final double toX,
  final double toY,
);

/// Two ints, low then high: a stem's clusters or its extent.
final class const _Span(final int low, final int high) {
  @override
  bool operator ==(Object other) =>
      other is _Span && other.low == low && other.high == high;

  @override
  int get hashCode => Object.hash(low, high);
}

/// The inputs of one [IconPathCache] path, quantized.
final class const _PathKey(
  final IconOutline outline,
  final int size,
  final int scale,
  final int phaseX,
  final int phaseY,
  final bool flipX,
  final bool fit,
) {
  @override
  bool operator ==(Object other) =>
      other is _PathKey &&
      other.outline == outline &&
      other.size == size &&
      other.scale == scale &&
      other.phaseX == phaseX &&
      other.phaseY == phaseY &&
      other.flipX == flipX &&
      other.fit == fit;

  @override
  int get hashCode =>
      Object.hash(outline, size, scale, phaseX, phaseY, flipX, fit);
}
