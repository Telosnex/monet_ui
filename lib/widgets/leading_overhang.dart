import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:pixel_snap_fork/widgets.dart';

/// Lets the first [overhang] logical pixels of [child] extend past the left
/// edge of this widget's box.
///
/// Use it for a background around an icon, such as the hover fill of a
/// pill. The parent then places the icon itself, not its background, and
/// never needs to know the size of the background.
///
/// [child] is laid out [overhang] wider than this widget and painted
/// [overhang] to the left. Taps and hovers on the overhang reach [child]
/// if the ancestors' boxes contain it: give the parent at least [overhang]
/// of left padding.
class LeadingOverhang extends SingleChildRenderObjectWidget {
  const LeadingOverhang({
    super.key,
    required this.overhang,
    required Widget super.child,
  }) : assert(overhang >= 0);

  final double overhang;

  @override
  RenderLeadingOverhang createRenderObject(BuildContext context) =>
      .new(overhang);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLeadingOverhang renderObject,
  ) {
    renderObject.overhang = overhang;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('overhang', overhang));
  }
}

/// The render object of [LeadingOverhang].
class RenderLeadingOverhang extends RenderShiftedBox {
  RenderLeadingOverhang(this._overhang, [RenderBox? child]) : super(child);

  double get overhang => _overhang;
  double _overhang;
  set overhang(double value) {
    if (value == _overhang) return;
    _overhang = value;
    markNeedsLayout();
  }

  BoxConstraints _childConstraints(BoxConstraints constraints) => .new(
    minWidth: constraints.minWidth + overhang,
    maxWidth: constraints.maxWidth + overhang,
    minHeight: constraints.minHeight,
    maxHeight: constraints.maxHeight,
  );

  Size _sizeFor(BoxConstraints constraints, Size childSize) =>
      constraints.constrain(
        Size(math.max(0, childSize.width - overhang), childSize.height),
      );

  @override
  double computeMinIntrinsicWidth(double height) =>
      math.max(0, (child?.getMinIntrinsicWidth(height) ?? 0) - overhang);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      math.max(0, (child?.getMaxIntrinsicWidth(height) ?? 0) - overhang);

  @override
  double computeMinIntrinsicHeight(double width) =>
      child?.getMinIntrinsicHeight(width + overhang) ?? 0;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      child?.getMaxIntrinsicHeight(width + overhang) ?? 0;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    return _sizeFor(
      constraints,
      child.getDryLayout(_childConstraints(constraints)),
    );
  }

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) => child?.getDryBaseline(_childConstraints(constraints), baseline);

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_childConstraints(constraints), parentUsesSize: true);
    (child.parentData! as BoxParentData).offset = Offset(-overhang, 0);
    size = _sizeFor(constraints, child.size);
  }

  /// Tests the whole child, including the overhang, which is outside [size].
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (hitTestChildren(result, position: position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }

  @override
  Rect get paintBounds =>
      Offset(-overhang, 0) & Size(size.width + overhang, size.height);
}
