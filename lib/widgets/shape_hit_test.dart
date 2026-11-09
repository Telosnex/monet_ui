import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Hit geometry for a separately painted shape. Children (e.g. a corner menu)
/// get first refusal, just as with RenderDecoratedBox; only background hits
/// use the shape. Retain one local path instead of resolving/caching a border
/// path on every mouse hit test. Shadows remain paint-only.
class ShapeHitTest extends SingleChildRenderObjectWidget {
  const ShapeHitTest({super.key, required this.shape, required super.child});

  final ShapeBorder shape;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderShapeHitTest(
    shape: shape,
    textDirection: Directionality.maybeOf(context),
  );

  @override
  void updateRenderObject(BuildContext context, RenderProxyBox renderObject) {
    (renderObject as _RenderShapeHitTest)
      ..shape = shape
      ..textDirection = Directionality.maybeOf(context);
  }
}

class _RenderShapeHitTest extends RenderProxyBox {
  _RenderShapeHitTest({required this.shape, required this.textDirection});

  ShapeBorder shape;
  TextDirection? textDirection;
  ShapeBorder? _pathShape;
  TextDirection? _pathDirection;
  Size? _pathSize;
  Path? _path;

  @override
  bool hitTestSelf(Offset position) {
    if (_path == null ||
        _pathShape != shape ||
        _pathDirection != textDirection ||
        _pathSize != size) {
      _path = shape.getOuterPath(
        Offset.zero & size,
        textDirection: textDirection,
      );
      _pathShape = shape;
      _pathDirection = textDirection;
      _pathSize = size;
    }
    return _path!.contains(position);
  }
}
