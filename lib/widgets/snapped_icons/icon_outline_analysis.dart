/// Icon outlines and the analysis that grid fitting needs from them.
///
/// The analysis depends only on the outline, so the outline generator
/// stores it with the outline (ADR 002, D9). At run time, the fit in
/// `icon_grid_fit.dart` only spaces stroke runs, places edges and dots on
/// pixels, and builds the path.
///
/// Plain Dart, without `dart:ui`, so the generator can run it.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Units per em of Material icon outlines.
const kIconOutlineEm = 512;

/// Commands in an [IconOutline].
abstract final class OutlineVerb {
  static const move = 0;
  static const line = 1;
  static const cubic = 2;
  static const close = 3;
}

/// A glyph outline in font units, y down, placed in the em square (0, 0) to
/// ([em], [em]) as [Icon] places the glyph in its square.
final class IconOutline {
  IconOutline(
    this.verbs,
    this.points, {
    this.em = kIconOutlineEm,
    this.fits = true,
    this._leftToRight,
    this._rightToLeft,
  });

  /// Units per em of [points].
  final int em;

  /// Whether the outline is drawn on the 24-unit Material grid, so grid
  /// fitting applies. Other outlines draw unfitted (ADR 002, NG3).
  final bool fits;

  /// [OutlineVerb] values.
  final Uint8List verbs;

  /// x, y pairs: one point per move or line, three per cubic.
  final Int16List points;

  IconOutlineAnalysis? _leftToRight;
  IconOutlineAnalysis? _rightToLeft;

  /// The analysis of this outline, mirrored left to right when [flipX].
  ///
  /// Stored analyses come from the outline data. Others are computed on
  /// first use.
  IconOutlineAnalysis analysis({required bool flipX}) => flipX
      ? _rightToLeft ??= analyzeIconOutline(this, flipX: true)
      : _leftToRight ??= analyzeIconOutline(this, flipX: false);
}

/// What grid fitting needs from an outline in one text direction.
final class IconOutlineAnalysis {
  const IconOutlineAnalysis({
    required this.x,
    required this.y,
    required this.dots,
  });

  /// Vertical edges, placed on the x axis.
  final AxisAnalysis x;

  /// Horizontal edges, placed on the y axis.
  final AxisAnalysis y;

  /// Solid round dots, moved as one piece each, in contour order.
  final List<OutlineDot> dots;
}

/// What grid fitting needs from an outline on one axis.
final class AxisAnalysis {
  AxisAnalysis({
    required this.mirrorAxis,
    required this.clusterSums,
    required this.clusterCounts,
    required this.stems,
    required this.mirror,
  }) : clusters = Float64List.fromList([
         for (var i = 0; i < clusterSums.length; i++)
           clusterSums[i] / clusterCounts[i],
       ]);

  /// The line the whole outline mirrors across, in font units, or null.
  final double? mirrorAxis;

  /// Per cluster, the sum of its edge coordinates. Each is a multiple of
  /// 1/512 font unit, so the sums and [clusters] are exact.
  final Float64List clusterSums;

  /// Per cluster, its number of edges.
  final Uint16List clusterCounts;

  /// Coordinates of edge clusters, ascending. Each is the mean of the edges
  /// that are one designed edge.
  final Float64List clusters;

  /// Strokes and gaps between facing edges, in fit priority order.
  final List<OutlineStem> stems;

  /// Per cluster, the cluster it mirrors to across the middle of the
  /// clusters, or -1 for a cluster with an edge that has no partner. Null
  /// when the edges do not mirror well enough to fit one half and mirror it.
  final Int32List? mirror;
}

/// A stroke of ink between clusters [low] and [high], or with [counter], a
/// gap of white between them.
final class OutlineStem {
  const OutlineStem(
    this.low,
    this.high, {
    required this.counter,
    required this.extentStart,
    required this.extentEnd,
  });

  final int low, high;
  final bool counter;

  /// Where the two edges overlap along the axis, in half grid units.
  /// Stems in an even run must cover the same extents.
  final int extentStart, extentEnd;
}

/// A solid round dot: its contour and its bounds, control points included,
/// in font units.
final class OutlineDot {
  const OutlineDot(this.contour, this.left, this.top, this.right, this.bottom);

  final int contour;
  final double left, top, right, bottom;
}

/// Font units per Material grid unit: icons are drawn on a 24-unit grid.
const kIconGridUnit = kIconOutlineEm / 24;

/// Coordinates closer than this are one edge. The font rounds the 24-unit
/// grid to 512 units, so one designed edge can land on neighbouring values.
const kSameEdge = 2.0;

/// Straight segments shorter than this are not edges.
const _kMinEdgeLength = 0.75 * kIconGridUnit;

/// Ink between two facing edges at most this far apart is a stroke.
const _kMaxStemWidth = 4.5 * kIconGridUnit;

/// Round dots up to this wide are moved as one piece.
const _kMaxDotSize = 4 * kIconGridUnit;

/// Most clusters without a mirror partner that a mirrored fit places
/// between the others.
const _kMaxLooseClusters = 2;

/// Analyzes [outline], mirrored left to right when [flipX]. The outline
/// must be on the Material grid ([IconOutline.fits]).
IconOutlineAnalysis analyzeIconOutline(
  IconOutline outline, {
  required bool flipX,
}) {
  if (!outline.fits || outline.em != kIconOutlineEm) {
    throw ArgumentError('Only Material grid outlines have an analysis');
  }
  final pointCount = outline.points.length ~/ 2;
  final xs = List<double>.filled(pointCount, 0);
  final ys = List<double>.filled(pointCount, 0);
  for (var i = 0; i < pointCount; i++) {
    final x = outline.points[2 * i].toDouble();
    xs[i] = flipX ? kIconOutlineEm - x : x;
    ys[i] = outline.points[2 * i + 1].toDouble();
  }
  final contours = _contours(outline, xs, ys);
  final ink = _InkTest(contours, xs, ys);
  final dots = <OutlineDot>[];
  for (var ci = 0; ci < contours.length; ci++) {
    final c = contours[ci];
    if (_isRoundDot(c, xs, ys, ink)) {
      final b = _bounds(c, xs, ys);
      dots.add(OutlineDot(ci, b[0], b[1], b[2], b[3]));
    }
  }
  final exclude = {for (final dot in dots) dot.contour};
  AxisAnalysis axis({required bool horizontalEdges}) => _analyzeAxis(
    contours,
    ink,
    xs,
    ys,
    horizontalEdges: horizontalEdges,
    shapeAxis: ink.mirrorAxis(vertical: horizontalEdges),
    exclude: exclude,
  );
  return IconOutlineAnalysis(
    x: axis(horizontalEdges: false),
    y: axis(horizontalEdges: true),
    dots: dots,
  );
}

/// One contour as on-curve point indices plus, per segment, whether it is a
/// cubic and the indices of its control points.
class _Contour {
  final onCurve = <int>[];

  /// For segment i, from onCurve[i] to onCurve[i + 1] (wrapping): the index
  /// of its first control point, or null for a line. The second control
  /// point follows the first.
  final controls = <int?>[];
}

List<_Contour> _contours(
  IconOutline outline,
  List<double> xs,
  List<double> ys,
) {
  final result = <_Contour>[];
  _Contour? current;
  var p = 0;
  void finish() {
    final c = current;
    if (c == null || c.onCurve.length < 2) return;
    // The implicit closing segment back to the start is a line.
    final first = c.onCurve.first, last = c.onCurve.last;
    if (xs[first] == xs[last] && ys[first] == ys[last]) {
      c.onCurve.removeLast();
    } else {
      c.controls.add(null);
    }
    result.add(c);
  }

  for (final verb in outline.verbs) {
    switch (verb) {
      case OutlineVerb.move:
        finish();
        current = _Contour()..onCurve.add(p);
        p++;
      case OutlineVerb.line:
        current!
          ..controls.add(null)
          ..onCurve.add(p);
        p++;
      case OutlineVerb.cubic:
        current!
          ..controls.add(p)
          ..onCurve.add(p + 2);
        p += 3;
      case OutlineVerb.close:
        finish();
        current = null;
    }
  }
  finish();
  return result;
}

class _Edge {
  _Edge(this.c, this.ink, this.lo, this.hi);

  /// Coordinate across the edge, in font units.
  final double c;

  /// +1 when ink lies at greater coordinates, -1 when at smaller ones.
  final int ink;

  /// Extent along the edge.
  final double lo, hi;

  late int cluster;
}

/// Finds the edges of one axis, clusters them, pairs them into stems, and
/// matches clusters across the middle.
///
/// [horizontalEdges] selects y: edges are horizontal segments. Otherwise x.
AxisAnalysis _analyzeAxis(
  List<_Contour> contours,
  _InkTest inkTest,
  List<double> xs,
  List<double> ys, {
  required bool horizontalEdges,
  required double? shapeAxis,
  required Set<int> exclude,
}) {
  // Across the edge (the snapped axis) and along it.
  final across = horizontalEdges ? ys : xs;
  final along = horizontalEdges ? xs : ys;

  // Which side of an edge is inked, by sampling just either side of it.
  // Contours in one glyph can wind either way, so a single orientation per
  // glyph is not enough. Edges with ink on both sides or neither are not
  // edges: they are inside overlapping contours.
  const probe = 3.0;
  int? inkSide(double acrossAt, double alongAt) {
    bool inked(double c) =>
        horizontalEdges ? inkTest.inked(alongAt, c) : inkTest.inked(c, alongAt);
    final above = inked(acrossAt + probe), below = inked(acrossAt - probe);
    if (above == below) return null;
    return above ? 1 : -1;
  }

  final edges = <_Edge>[];
  for (var ci = 0; ci < contours.length; ci++) {
    final contour = contours[ci];
    if (exclude.contains(ci)) continue;
    final n = contour.onCurve.length;
    for (var i = 0; i < n; i++) {
      final b = contour.onCurve[(i + 1) % n];
      final control = contour.controls[i];
      if (control == null) {
        final a = contour.onCurve[i];
        final dAlong = along[b] - along[a];
        final c = (across[a] + across[b]) / 2;
        final ink =
            (across[b] - across[a]).abs() <= 1 &&
                dAlong.abs() >= _kMinEdgeLength
            ? inkSide(c, (along[a] + along[b]) / 2)
            : null;
        if (ink != null) {
          edges.add(
            _Edge(
              c,
              ink,
              math.min(along[a], along[b]),
              math.max(along[a], along[b]),
            ),
          );
        }
      }
      // Round extremum at b: both neighbouring curve handles flat on this
      // axis, on opposite sides of b.
      final next = contour.controls[(i + 1) % n];
      if (control != null && next != null) {
        final inHandle = control + 1, outHandle = next;
        final flatIn = (across[inHandle] - across[b]).abs() <= 1;
        final flatOut = (across[outHandle] - across[b]).abs() <= 1;
        final dAlong = along[outHandle] - along[inHandle];
        final ink =
            flatIn &&
                flatOut &&
                (along[b] - along[inHandle]).sign ==
                    (along[outHandle] - along[b]).sign &&
                dAlong != 0
            ? inkSide(across[b], along[b])
            : null;
        if (ink != null) {
          edges.add(
            _Edge(
              across[b],
              ink,
              math.min(along[inHandle], along[outHandle]),
              math.max(along[inHandle], along[outHandle]),
            ),
          );
        }
      }
    }
  }
  if (edges.isEmpty) {
    return AxisAnalysis(
      mirrorAxis: shapeAxis,
      clusterSums: Float64List(0),
      clusterCounts: Uint16List(0),
      stems: const [],
      mirror: null,
    );
  }

  // The outline is symmetric but its edges may not be: the font can draw
  // one side with a point at the extremum and the other side without.
  // Give such edges their missing mirror partner.
  if (shapeAxis != null) {
    const tolerance = 2.0;
    final missing = <_Edge>[
      for (final e in edges)
        if (!edges.any(
          (f) =>
              f.ink == -e.ink &&
              (e.c + f.c - 2 * shapeAxis).abs() <= tolerance &&
              (e.lo - f.lo).abs() <= tolerance &&
              (e.hi - f.hi).abs() <= tolerance,
        ))
          _Edge(2 * shapeAxis - e.c, -e.ink, e.lo, e.hi),
    ];
    edges.addAll(missing);
  }

  // Cluster coordinates.
  edges.sort((a, b) => a.c.compareTo(b.c));
  final members = <List<double>>[];
  for (final edge in edges) {
    if (members.isEmpty || edge.c - members.last.first > kSameEdge) {
      members.add([edge.c]);
    } else {
      members.last.add(edge.c);
    }
    edge.cluster = members.length - 1;
  }
  final clusterSums = Float64List.fromList([
    for (final m in members) m.reduce((a, b) => a + b),
  ]);
  final clusterCounts = Uint16List.fromList([
    for (final m in members) m.length,
  ]);
  final clusterCoord = [
    for (var i = 0; i < members.length; i++) clusterSums[i] / clusterCounts[i],
  ];
  // Pair facing edges into stems: ink at greater coordinates from `low`,
  // at smaller coordinates from `high`, extents overlapping.
  // Also pair the reverse way: the white gaps between facing ink. Cut-out
  // shapes are drawn with these.
  final stems = <_StemCandidate>[];
  for (final counter in [false, true]) {
    final lowInk = counter ? -1 : 1;
    for (final low in edges) {
      if (low.ink != lowInk) continue;
      _Edge? best;
      for (final high in edges) {
        if (high.ink != -lowInk) continue;
        final width = clusterCoord[high.cluster] - clusterCoord[low.cluster];
        if (width <= kSameEdge || width > _kMaxStemWidth) continue;
        final overlap = math.min(low.hi, high.hi) - math.max(low.lo, high.lo);
        if (overlap <= 0) continue;
        if (best == null || high.c < best.c) best = high;
      }
      if (best != null) {
        final overlap = math.min(low.hi, best.hi) - math.max(low.lo, best.lo);
        stems.add(_StemCandidate(low, best, overlap, counter));
      }
    }
  }
  // Longest first; ink before gaps.
  stems.sort((a, b) {
    final byOverlap = b.overlap.compareTo(a.overlap);
    if (byOverlap != 0) return byOverlap;
    return (a.counter ? 1 : 0) - (b.counter ? 1 : 0);
  });
  int q(double v) => (v / (kIconGridUnit / 2)).round();
  return AxisAnalysis(
    mirrorAxis: shapeAxis,
    clusterSums: clusterSums,
    clusterCounts: clusterCounts,
    stems: [
      for (final _StemCandidate(:low, :high, :counter) in stems)
        OutlineStem(
          low.cluster,
          high.cluster,
          counter: counter,
          extentStart: q(math.max(low.lo, high.lo)),
          extentEnd: q(math.min(low.hi, high.hi)),
        ),
    ],
    mirror: _mirrorMap(edges, clusterCoord),
  );
}

/// For edges that mirror across the middle of their clusters: per cluster,
/// its mirror cluster, or -1 for a loose cluster, one with an edge that has
/// no partner. Null when the edges do not mirror: an outermost cluster is
/// loose, more than [_kMaxLooseClusters] are, or the pairs disagree.
Int32List? _mirrorMap(List<_Edge> edges, List<double> clusterCoord) {
  const tolerance = 2.0;
  final n = clusterCoord.length;
  final axis = (clusterCoord.first + clusterCoord.last) / 2;
  final matches = <_Edge, _Edge>{};
  for (final e in edges) {
    for (final f in edges) {
      if (f.ink == -e.ink &&
          (e.c + f.c - 2 * axis).abs() <= tolerance &&
          (e.lo - f.lo).abs() <= tolerance &&
          (e.hi - f.hi).abs() <= tolerance) {
        matches[e] = f;
        break;
      }
    }
  }
  // Clusters with an edge that has no mirror partner, such as a crossbar
  // drawn slightly off center. A few inner ones are placed afterwards,
  // between the mirrored edges around them.
  final loose = {
    for (final e in edges)
      if (!matches.containsKey(e)) e.cluster,
  };
  if (loose.contains(0) || loose.contains(n - 1)) return null;
  if (loose.length > _kMaxLooseClusters) return null;
  final mirror = Int32List(n)..fillRange(0, n, -1);
  for (final MapEntry(key: e, value: match) in matches.entries) {
    if (loose.contains(e.cluster)) continue;
    if (loose.contains(match.cluster)) return null;
    final previous = mirror[e.cluster];
    if (previous != -1 && previous != match.cluster) return null;
    mirror[e.cluster] = match.cluster;
  }
  for (var i = 0; i < n; i++) {
    if (loose.contains(i)) continue;
    if (mirror[mirror[i]] != i) return null;
  }
  return mirror;
}

/// Whether a point is inked under the nonzero fill rule.
class _InkTest {
  _InkTest(List<_Contour> contours, List<double> xs, List<double> ys) {
    for (final contour in contours) {
      final poly = <double>[];
      final n = contour.onCurve.length;
      for (var i = 0; i < n; i++) {
        final a = contour.onCurve[i];
        poly.addAll([xs[a], ys[a]]);
        final control = contour.controls[i];
        if (control == null) continue;
        final b = contour.onCurve[(i + 1) % n];
        final c1 = control, c2 = control + 1;
        const steps = 8;
        for (var s = 1; s < steps; s++) {
          final t = s / steps, u = 1 - t;
          double at(List<double> v) =>
              u * u * u * v[a] +
              3 * u * u * t * v[c1] +
              3 * u * t * t * v[c2] +
              t * t * t * v[b];
          poly.addAll([at(xs), at(ys)]);
        }
      }
      _polygons.add(poly);
    }
  }

  final _polygons = <List<double>>[];

  /// The coordinate of the line the outline mirrors across, or null when it
  /// does not. [vertical] selects a top/bottom mirror (across y).
  ///
  /// Every outline point, mirrored, must lie within a fifth of a grid unit
  /// of the outline. The font draws some symmetric shapes with different
  /// points on each side, so the points themselves need not pair up.
  double? mirrorAxis({required bool vertical}) {
    final o = vertical ? 1 : 0;
    var lo = double.infinity, hi = -double.infinity;
    for (final poly in _polygons) {
      for (var i = o; i < poly.length; i += 2) {
        lo = math.min(lo, poly[i]);
        hi = math.max(hi, poly[i]);
      }
    }
    if (lo > hi) return null;
    final axis = (lo + hi) / 2;
    const tolerance = kIconGridUnit / 5;
    // Points along every segment, not only its ends: two different
    // outlines can share all their corners.
    const spacing = kIconGridUnit / 2;
    for (final poly in _polygons) {
      final n = poly.length ~/ 2;
      for (var i = 0; i < n; i++) {
        final j = (i + 1) % n;
        final x0 = poly[2 * i], y0 = poly[2 * i + 1];
        final dx = poly[2 * j] - x0, dy = poly[2 * j + 1] - y0;
        final steps = math.max(
          1,
          (math.sqrt(dx * dx + dy * dy) / spacing).ceil(),
        );
        for (var s = 0; s < steps; s++) {
          final px = x0 + s / steps * dx, py = y0 + s / steps * dy;
          final x = vertical ? px : 2 * axis - px;
          final y = vertical ? 2 * axis - py : py;
          if (_distanceToOutline(x, y) > tolerance) return null;
        }
      }
    }
    return axis;
  }

  double _distanceToOutline(double x, double y) {
    var best = double.infinity;
    for (final poly in _polygons) {
      final n = poly.length ~/ 2;
      for (var i = 0; i < n; i++) {
        final x0 = poly[2 * i], y0 = poly[2 * i + 1];
        final j = (i + 1) % n;
        final dx = poly[2 * j] - x0, dy = poly[2 * j + 1] - y0;
        final len2 = dx * dx + dy * dy;
        final t = len2 == 0
            ? 0.0
            : (((x - x0) * dx + (y - y0) * dy) / len2).clamp(0.0, 1.0);
        final ex = x0 + t * dx - x, ey = y0 + t * dy - y;
        best = math.min(best, ex * ex + ey * ey);
      }
    }
    return math.sqrt(best);
  }

  bool inked(double x, double y) {
    var winding = 0;
    for (final poly in _polygons) {
      final n = poly.length ~/ 2;
      for (var i = 0; i < n; i++) {
        final x0 = poly[2 * i], y0 = poly[2 * i + 1];
        final j = (i + 1) % n;
        final x1 = poly[2 * j], y1 = poly[2 * j + 1];
        final cross = (x1 - x0) * (y - y0) - (x - x0) * (y1 - y0);
        if (y0 <= y && y < y1 && cross > 0) winding++;
        if (y1 <= y && y < y0 && cross < 0) winding--;
      }
    }
    return winding != 0;
  }
}

/// Whether [c] is a solid round dot at most [_kMaxDotSize] across: curves
/// only, about as tall as wide, inked at its center.
bool _isRoundDot(_Contour c, List<double> xs, List<double> ys, _InkTest ink) {
  if (c.controls.any((e) => e == null)) return false;
  final b = _bounds(c, xs, ys);
  final w = b[2] - b[0], h = b[3] - b[1];
  // The font rounds the 24-unit grid to 512 units, so a 4-unit dot can
  // measure slightly over.
  if (math.max(w, h) > _kMaxDotSize + kSameEdge) return false;
  if ((w - h).abs() > 0.25 * math.max(w, h)) return false;
  return ink.inked((b[0] + b[2]) / 2, (b[1] + b[3]) / 2);
}

/// Bounds of a curves-only contour, control points included: left, top,
/// right, bottom.
List<double> _bounds(_Contour c, List<double> xs, List<double> ys) {
  var x0 = double.infinity, y0 = double.infinity;
  var x1 = -double.infinity, y1 = -double.infinity;
  for (var i = 0; i < c.onCurve.length; i++) {
    final c1 = c.controls[i]!;
    for (final p in [c.onCurve[i], c1, c1 + 1]) {
      x0 = math.min(x0, xs[p]);
      x1 = math.max(x1, xs[p]);
      y0 = math.min(y0, ys[p]);
      y1 = math.max(y1, ys[p]);
    }
  }
  return [x0, y0, x1, y1];
}

// Encoding. See ADR 002 §5 and its 2026-10-09 addendum.

/// Writes [analysis] to [out]. Throws when a value would not decode
/// exactly.
void writeIconOutlineAnalysis(BytesBuilder out, IconOutlineAnalysis analysis) {
  for (final axis in [analysis.x, analysis.y]) {
    _writeAxis(out, axis);
  }
  writeVarint(out, analysis.dots.length);
  for (final dot in analysis.dots) {
    writeVarint(out, dot.contour);
    for (final v in [dot.left, dot.top, dot.right, dot.bottom]) {
      writeVarint(out, _zigzag(_exactInt(v, 1)));
    }
  }
}

void _writeAxis(BytesBuilder out, AxisAnalysis axis) {
  final mirrorAxis = axis.mirrorAxis;
  if (mirrorAxis == null) {
    writeVarint(out, 0);
  } else {
    writeVarint(out, 1);
    writeZigzag(out, _exactInt(mirrorAxis, 1024));
  }
  final n = axis.clusters.length;
  writeVarint(out, n);
  var previous = 0;
  for (var i = 0; i < n; i++) {
    final sum = _exactInt(axis.clusterSums[i], 512);
    writeVarint(out, _zigzag(sum - previous));
    writeVarint(out, axis.clusterCounts[i]);
    previous = sum;
  }
  writeVarint(out, axis.stems.length);
  for (final stem in axis.stems) {
    writeVarint(out, stem.low);
    writeVarint(out, (stem.high - stem.low) * 2 + (stem.counter ? 1 : 0));
    writeVarint(out, _zigzag(stem.extentStart));
    writeVarint(out, _zigzag(stem.extentEnd - stem.extentStart));
  }
  final mirror = axis.mirror;
  if (mirror == null) {
    writeVarint(out, 0);
  } else {
    writeVarint(out, 1);
    for (final m in mirror) {
      writeVarint(out, m + 1);
    }
  }
}

/// Reads an analysis written by [writeIconOutlineAnalysis].
IconOutlineAnalysis readIconOutlineAnalysis(OutlineDataReader reader) {
  final x = _readAxis(reader);
  final y = _readAxis(reader);
  final dots = [
    for (var i = reader.varint(); i > 0; i--)
      OutlineDot(
        reader.varint(),
        reader.zigzag().toDouble(),
        reader.zigzag().toDouble(),
        reader.zigzag().toDouble(),
        reader.zigzag().toDouble(),
      ),
  ];
  return IconOutlineAnalysis(x: x, y: y, dots: dots);
}

AxisAnalysis _readAxis(OutlineDataReader reader) {
  final mirrorAxis = reader.varint() == 0 ? null : reader.zigzag() / 1024;
  final n = reader.varint();
  final sums = Float64List(n);
  final counts = Uint16List(n);
  var sum = 0;
  for (var i = 0; i < n; i++) {
    sum += reader.zigzag();
    sums[i] = sum / 512;
    counts[i] = reader.varint();
  }
  final stems = <OutlineStem>[];
  for (var i = reader.varint(); i > 0; i--) {
    final low = reader.varint();
    final span = reader.varint();
    final start = reader.zigzag();
    stems.add(
      OutlineStem(
        low,
        low + span ~/ 2,
        counter: span.isOdd,
        extentStart: start,
        extentEnd: start + reader.zigzag(),
      ),
    );
  }
  Int32List? mirror;
  if (reader.varint() == 1) {
    mirror = Int32List(n);
    for (var i = 0; i < n; i++) {
      mirror[i] = reader.varint() - 1;
    }
  }
  return AxisAnalysis(
    mirrorAxis: mirrorAxis,
    clusterSums: sums,
    clusterCounts: counts,
    stems: stems,
    mirror: mirror,
  );
}

/// [v] times [scale] as an integer. Throws when that is not exact.
int _exactInt(double v, int scale) {
  final scaled = v * scale;
  final rounded = scaled.round();
  if (rounded != scaled) {
    throw FormatException('$v is not a multiple of 1/$scale');
  }
  return rounded;
}

int _zigzag(int v) => v >= 0 ? v * 2 : -v * 2 - 1;

/// Writes [value], at least 0, as a little-endian base-128 varint.
void writeVarint(BytesBuilder out, int value) {
  var v = value;
  while (v >= 0x80) {
    out.addByte((v & 0x7f) | 0x80);
    v >>= 7;
  }
  out.addByte(v);
}

/// Writes [value] as a zigzag varint.
void writeZigzag(BytesBuilder out, int value) =>
    writeVarint(out, _zigzag(value));

/// Reads the varints of the outline data.
final class OutlineDataReader {
  OutlineDataReader(this.bytes, [this.offset = 0]);

  final Uint8List bytes;
  int offset;

  int varint() {
    var value = 0;
    var shift = 0;
    while (true) {
      final byte = bytes[offset++];
      value |= (byte & 0x7f) << shift;
      if (byte < 0x80) return value;
      shift += 7;
    }
  }

  int zigzag() {
    final v = varint();
    return v.isEven ? v ~/ 2 : -(v + 1) ~/ 2;
  }
}

/// A low edge paired with its facing high edge, how far they overlap, and
/// whether the pair is a white gap ([counter]) rather than ink.
final class const _StemCandidate(
  final _Edge low,
  final _Edge high,
  final double overlap,
  final bool counter,
);
