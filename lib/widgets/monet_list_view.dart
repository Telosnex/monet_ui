// rationale: simple and tightly coupled widgets that are used in many places.
// ignore_for_file: prefer-single-widget-per-file, prefer-declaring-const-constructor

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:monet_ui/third_party/flutter/list_view.dart';
import 'package:monet_ui/widgets/padding.dart';

/// A [ListView2] that keeps the scrollbar/viewport at the real screen edge,
/// while constraining and centering the list sliver's cross-axis extent.
///
/// Use [padding] for the in-viewport gutter. It defaults to [ScreenPadding.inset]
/// so narrow screens keep the normal Monet horizontal floor; wide screens then
/// center the underlying sliver at [maxCrossAxisExtent].
class MonetListView extends ListView2 {
  MonetListView({
    super.key,
    super.scrollDirection,
    super.reverse,
    super.controller,
    super.primary,
    super.physics,
    super.shrinkWrap,
    super.padding = ScreenPadding.inset,
    super.itemExtent,
    super.prototypeItem,
    super.listController,
    super.initialScrollPosition,
    super.addAutomaticKeepAlives,
    super.addRepaintBoundaries,
    super.addSemanticIndexes,
    super.scrollCacheExtent,
    super.children,
    super.semanticChildCount,
    super.dragStartBehavior,
    super.keyboardDismissBehavior,
    super.restorationId,
    super.clipBehavior,
    this.maxCrossAxisExtent = ScreenConstrained.maxWidth,
    this.crossAxisAlignment = 0,
  });

  MonetListView.builder({
    super.key,
    super.scrollDirection,
    super.reverse,
    super.controller,
    super.primary,
    super.physics,
    super.shrinkWrap,
    super.padding = ScreenPadding.inset,
    super.itemExtent,
    super.prototypeItem,
    super.listController,
    super.initialScrollPosition,
    required super.itemBuilder,
    super.findChildIndexCallback,
    super.itemCount,
    super.addAutomaticKeepAlives,
    super.addRepaintBoundaries,
    super.addSemanticIndexes,
    super.scrollCacheExtent,
    super.semanticChildCount,
    super.dragStartBehavior,
    super.keyboardDismissBehavior,
    super.restorationId,
    super.clipBehavior,
    this.maxCrossAxisExtent = ScreenConstrained.maxWidth,
    this.crossAxisAlignment = 0,
  }) : super.builder();

  MonetListView.separated({
    super.key,
    super.scrollDirection,
    super.reverse,
    super.controller,
    super.primary,
    super.physics,
    super.shrinkWrap,
    super.padding = ScreenPadding.inset,
    super.listController,
    super.initialScrollPosition,
    required super.itemBuilder,
    super.findChildIndexCallback,
    required super.separatorBuilder,
    required super.itemCount,
    super.addAutomaticKeepAlives,
    super.addRepaintBoundaries,
    super.addSemanticIndexes,
    super.scrollCacheExtent,
    super.dragStartBehavior,
    super.keyboardDismissBehavior,
    super.restorationId,
    super.clipBehavior,
    this.maxCrossAxisExtent = ScreenConstrained.maxWidth,
    this.crossAxisAlignment = 0,
  }) : super.separated();

  const MonetListView.custom({
    super.key,
    super.scrollDirection,
    super.reverse,
    super.controller,
    super.primary,
    super.physics,
    super.shrinkWrap,
    super.padding = ScreenPadding.inset,
    super.itemExtent,
    super.listController,
    super.prototypeItem,
    super.initialScrollPosition,
    required super.childrenDelegate,
    super.scrollCacheExtent,
    super.semanticChildCount,
    super.dragStartBehavior,
    super.keyboardDismissBehavior,
    super.restorationId,
    super.clipBehavior,
    this.maxCrossAxisExtent = ScreenConstrained.maxWidth,
    this.crossAxisAlignment = 0,
  }) : super.custom();

  /// Maximum width/height, depending on scroll direction, for the list sliver.
  ///
  /// Set to null to make [MonetListView] behave like [ListView2] except for the
  /// default [padding].
  final double? maxCrossAxisExtent;

  /// Cross-axis placement of the constrained sliver.
  ///
  /// -1 is leading, 0 is centered, and 1 is trailing.
  final double crossAxisAlignment;

  @override
  Widget buildChildLayout(BuildContext context) {
    final maxCrossAxisExtent = this.maxCrossAxisExtent;
    final sliver = super.buildChildLayout(context);
    if (maxCrossAxisExtent == null) return sliver;

    return _SliverCrossAxisConstrained(
      maxCrossAxisExtent: ScreenConstrained.platformWidthOf(
        context,
        maxCrossAxisExtent,
      ),
      alignment: crossAxisAlignment,
      sliver: sliver,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(
        DoubleProperty(
          'maxCrossAxisExtent',
          maxCrossAxisExtent,
          defaultValue: ScreenConstrained.maxWidth,
        ),
      )
      ..add(
        DoubleProperty(
          'crossAxisAlignment',
          crossAxisAlignment,
          defaultValue: 0,
        ),
      );
  }
}

class _SliverCrossAxisConstrained extends SingleChildRenderObjectWidget {
  const _SliverCrossAxisConstrained({
    required this.maxCrossAxisExtent,
    required this.alignment,
    required Widget sliver,
  }) : super(child: sliver);

  final double maxCrossAxisExtent;
  final double alignment;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderSliverCrossAxisConstrained(
      maxCrossAxisExtent: maxCrossAxisExtent,
      alignment: alignment,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderSliverCrossAxisConstrained renderObject,
  ) {
    renderObject
      ..maxCrossAxisExtent = maxCrossAxisExtent
      ..alignment = alignment;
  }
}

class _SliverCrossAxisPositionedParentData extends SliverPhysicalParentData {
  late double crossAxisPosition;
}

class _RenderSliverCrossAxisConstrained extends RenderSliver
    with RenderObjectWithChildMixin<RenderSliver> {
  _RenderSliverCrossAxisConstrained({
    required this._maxCrossAxisExtent,
    required this._alignment,
  });

  double get maxCrossAxisExtent => _maxCrossAxisExtent;
  double _maxCrossAxisExtent;
  set maxCrossAxisExtent(double value) {
    assert(value > 0);
    if (_maxCrossAxisExtent == value) return;
    _maxCrossAxisExtent = value;
    markNeedsLayout();
  }

  double get alignment => _alignment;
  double _alignment;
  set alignment(double value) {
    assert(value >= -1.0 && value <= 1.0);
    if (_alignment == value) return;
    _alignment = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! _SliverCrossAxisPositionedParentData) {
      child.parentData = _SliverCrossAxisPositionedParentData();
    }
  }

  @override
  @nonVirtual
  void performLayout() {
    final crossAxisExtent = math.min(
      constraints.crossAxisExtent,
      maxCrossAxisExtent,
    );
    final crossAxisPosition =
        (alignment + 1) * ((constraints.crossAxisExtent - crossAxisExtent) / 2);

    child!.layout(
      constraints.copyWith(crossAxisExtent: crossAxisExtent),
      parentUsesSize: true,
    );
    geometry = child!.geometry;
    if (geometry!.scrollOffsetCorrection != null) return;

    final childParentData =
        child!.parentData as _SliverCrossAxisPositionedParentData;
    childParentData.crossAxisPosition = crossAxisPosition;
    childParentData.paintOffset = switch (constraints.axis) {
      .vertical => Offset(crossAxisPosition, 0),
      .horizontal => Offset(0, crossAxisPosition),
    };
  }

  @override
  bool hitTestChildren(
    SliverHitTestResult result, {
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) {
    final child = this.child;
    if (child == null) return false;

    final childParentData =
        child.parentData as _SliverCrossAxisPositionedParentData;
    return result.addWithAxisOffset(
      paintOffset: childParentData.paintOffset,
      mainAxisOffset: 0,
      crossAxisOffset: childCrossAxisPosition(child),
      mainAxisPosition: mainAxisPosition,
      crossAxisPosition: crossAxisPosition,
      hitTest: child.hitTest,
    );
  }

  @override
  double childCrossAxisPosition(RenderSliver child) {
    final childParentData =
        child.parentData as _SliverCrossAxisPositionedParentData;
    return childParentData.crossAxisPosition;
  }

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {
    assert(child == this.child);
    final childParentData = child.parentData as SliverPhysicalParentData;
    childParentData.applyPaintTransform(transform);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null || !child.geometry!.visible) return;

    final childParentData = child.parentData as SliverPhysicalParentData;
    context.paintChild(child, offset + childParentData.paintOffset);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DoubleProperty('maxCrossAxisExtent', maxCrossAxisExtent))
      ..add(DoubleProperty('alignment', alignment));
  }
}
