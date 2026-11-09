import 'package:monet_ui/widgets/monet_icons.dart';
import 'package:pixel_snap_fork/material.dart';
import 'package:monet_ui/widgets/monet_icon.dart';

/// One cached chevron geometry.
class _ChevronGeometry {
  const _ChevronGeometry(this.width, this.height, this.strokeWidth, this.path);

  final double width;
  final double height;
  final double strokeWidth;
  final Path path;

  bool matches(Size size, double stroke) =>
      width == size.width && height == size.height && strokeWidth == stroke;
}

/// Chevron paths, shared across painter instances.
///
/// The path is a pure function of `(size, strokeWidth)`, so it does not belong
/// on a painter at all. It used to live on the instance, which only helps while
/// that instance survives — true for the animated chevron, whose widget never
/// rebuilds, and false for the static one, which any ancestor rebuild
/// recreates. A conversation shows many static chevrons and its list relayouts
/// while streaming, so the path was being rebuilt constantly and
/// `_ChevronPainter.paint` became the hottest function in the app.
///
/// A linear scan, NOT a map. The first version keyed an [LruCache] on a
/// `(Size, double)` record, which allocated the key on every paint, hashed a
/// Size structurally, and then paid three hash lookups because an LRU probe
/// does `containsKey` + `remove` + re-insert to bump MRU. That measured MORE
/// than the three-segment path it was avoiding. Comparing a few doubles costs
/// nothing and allocates nothing.
///
/// Few geometries are ever on screen at once, so a short list stays short.
const _kChevronGeometryLimit = 8;
final List<_ChevronGeometry> _chevronGeometries = [];

Path _chevronPath(Size size, double strokeWidth) {
  for (final geometry in _chevronGeometries) {
    if (geometry.matches(size, strokeWidth)) {
      return geometry.path;
    }
  }

  // Inset by half the stroke width so the stroke stays within visual bounds.
  final inset = strokeWidth / 2;
  // Draw V shape: top-left -> bottom-center -> top-right
  final path = Path()
    ..moveTo(inset, inset)
    ..lineTo(size.width / 2, size.height - inset)
    ..lineTo(size.width - inset, inset);

  if (_chevronGeometries.length >= _kChevronGeometryLimit) {
    _chevronGeometries.removeAt(0);
  }
  _chevronGeometries.add(
    _ChevronGeometry(size.width, size.height, strokeWidth, path),
  );
  return path;
}

/// Number of distinct chevron geometries currently cached.
@visibleForTesting
int get chevronPathCacheLength => _chevronGeometries.length;

/// Empties the shared path cache so a test can observe it filling.
@visibleForTesting
void clearChevronPathCache() => _chevronGeometries.clear();

/// A custom chevron icon that avoids the padding issues of Flutter's Icon widget.
/// Draws a simple "V" shape (chevron pointing down by default).
class ChevronIcon extends StatelessWidget {
  static bool debugUseTraditionalIcon = false;

  /// Base size the proportions are designed for.
  static const double _baseSize = 21.0;

  /// Actual width of chevron at base size.
  static const double _baseWidth = 11.0;

  /// Actual height of chevron at base size.
  static const double _baseHeight = 7.0;

  /// Stroke width at base size.
  static const double _baseStrokeWidth = 2.0;

  final double? size;
  final Color? color;

  /// Reads the colour at paint time. Combined with [repaint], colour
  /// animations (e.g. loading pulses) repaint the chevron directly without
  /// rebuilding any widgets or re-recording ancestor pictures.
  final Color Function()? colorGetter;

  /// Notifies the painter to repaint when [colorGetter]'s result changes.
  final Listenable? repaint;

  const ChevronIcon({super.key, this.size, this.color})
    : colorGetter = null,
      repaint = null;

  /// Chevron whose colour is driven by an animation. Colour ticks flow
  /// straight to the painter via [repaint] — zero widget rebuilds — and the
  /// repaint is confined to the chevron's own layer by a [RepaintBoundary].
  const ChevronIcon.animated({
    super.key,
    this.size,
    required Color Function() this.colorGetter,
    required Listenable this.repaint,
  }) : color = null;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final resolvedSize = size ?? iconTheme.size ?? 24.0;

    if (debugUseTraditionalIcon) {
      return MonetIcon(
        MonetIcons.expandMore,
        size: resolvedSize,
        color: color ?? colorGetter?.call() ?? iconTheme.color ?? Colors.black,
      );
    }

    final scale = resolvedSize / _baseSize;
    final width = _baseWidth * scale;
    final height = _baseHeight * scale;
    final strokeWidth = _baseStrokeWidth * scale;

    final getter = colorGetter;
    if (getter != null) {
      // The boundary keeps per-tick colour repaints inside the chevron's own
      // (tiny) layer, and lets ancestor repaints (e.g. RotationTransition)
      // reuse the cached layer instead of re-recording the path.
      return RepaintBoundary(
        child: CustomPaint(
          size: Size(width, height),
          painter: _ChevronPainter(
            colorGetter: getter,
            strokeWidth: strokeWidth,
            repaint: repaint,
          ),
        ),
      );
    }

    return CustomPaint(
      size: Size(width, height),
      painter: _ChevronPainter(
        color: color ?? iconTheme.color ?? Colors.black,
        strokeWidth: strokeWidth,
      ),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  /// Static colour; used when [colorGetter] is null.
  final Color? color;

  /// Paint-time colour source; takes precedence over [color].
  final Color Function()? colorGetter;

  final double strokeWidth;

  // Reused across paints by this instance. Colour and stroke width are set on
  // every paint, so nothing here outlives a single call.
  final Paint _paint = Paint()
    ..strokeCap = .butt
    ..strokeJoin = .miter
    ..style = .stroke;

  _ChevronPainter({
    this.color,
    this.colorGetter,
    required this.strokeWidth,
    super.repaint,
  }) : assert(
         (color == null) != (colorGetter == null),
         'Provide exactly one of color or colorGetter.',
       );

  @override
  void paint(Canvas canvas, Size size) {
    _paint
      ..color = colorGetter?.call() ?? color!
      ..strokeWidth = strokeWidth;

    canvas.drawPath(_chevronPath(size, strokeWidth), _paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.colorGetter != colorGetter;
  }
}
