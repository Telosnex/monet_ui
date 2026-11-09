// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Extracted from packages/flutter/lib/src/widgets/scrollable.dart at
// flutter/flutter@6655482ec06e547f90abf8ae7590466f4415978d (2026-09-20).
// Local changes: public class name, DeferredSelectionOrder mixin, position
// listener removal in dispose, and imports. Keep selection/scroll logic aligned
// with the SDK. The name contains "Scrollable" because cmark-gfm-widget uses
// that marker to flatten infrastructure containers during copy serialization.
// See TelosnexScrollBehavior for the interception contract and upgrade tests.
// Keep upstream syntax to make SDK diffs reviewable.
// ignore_for_file: prefer_initializing_formals, prefer-shorthands-with-enums, prefer-shorthands-with-static-fields, avoid-unnecessary-return
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'package:monet_ui/widgets/deferred_selection_order.dart';

class DeferredScrollableSelectionContainerDelegate
    extends MultiSelectableSelectionContainerDelegate
    with DeferredSelectionOrder {
  DeferredScrollableSelectionContainerDelegate({
    required this.state,
    required ScrollPosition position,
  }) : _position = position,
       _autoScroller = EdgeDraggingAutoScroller(
         state,
         velocityScalar: _kDefaultSelectToScrollVelocityScalar,
       ) {
    _position.addListener(_scheduleLayoutChange);
  }

  // Pointer drag is a single point, it should not have a size.
  static const double _kDefaultDragTargetSize = 0;

  // An eye-balled value for a smooth scrolling speed.
  static const double _kDefaultSelectToScrollVelocityScalar = 30;

  final ScrollableState state;
  final EdgeDraggingAutoScroller _autoScroller;
  bool _scheduledLayoutChange = false;
  Offset? _currentDragStartRelatedToOrigin;
  Offset? _currentDragEndRelatedToOrigin;

  // The scrollable only auto scrolls if the selection starts in the scrollable.
  bool _selectionStartsInScrollable = false;

  ScrollPosition get position => _position;
  ScrollPosition _position;
  set position(ScrollPosition other) {
    if (other == _position) {
      return;
    }
    _position.removeListener(_scheduleLayoutChange);
    _position = other;
    _position.addListener(_scheduleLayoutChange);
  }

  // The layout will only be updated a frame later than position changes.
  // Schedule PostFrameCallback to capture the accurate layout.
  void _scheduleLayoutChange() {
    if (_scheduledLayoutChange) {
      return;
    }
    _scheduledLayoutChange = true;
    SchedulerBinding.instance.addPostFrameCallback((Duration timeStamp) {
      if (!_scheduledLayoutChange) {
        return;
      }
      _scheduledLayoutChange = false;
      layoutDidChange();
    }, debugLabel: 'ScrollableSelectionContainer.layoutDidChange');
  }

  /// Stores the scroll offset when a scrollable receives the last
  /// [SelectionEdgeUpdateEvent].
  ///
  /// The stored scroll offset may be null if a scrollable never receives a
  /// [SelectionEdgeUpdateEvent].
  ///
  /// When a new [SelectionEdgeUpdateEvent] is dispatched to a selectable, this
  /// updater checks the current scroll offset against the one stored in these
  /// records. If the scroll offset is different, it synthesizes an opposite
  /// [SelectionEdgeUpdateEvent] and dispatches the event before dispatching the
  /// new event.
  ///
  /// For example, if a selectable receives an end [SelectionEdgeUpdateEvent]
  /// and its scroll offset in the records is different from the current value,
  /// it synthesizes a start [SelectionEdgeUpdateEvent] and dispatches it before
  /// dispatching the original end [SelectionEdgeUpdateEvent].
  final Map<Selectable, double> _selectableStartEdgeUpdateRecords =
      <Selectable, double>{};
  final Map<Selectable, double> _selectableEndEdgeUpdateRecords =
      <Selectable, double>{};

  @override
  void didChangeSelectables() {
    final Set<Selectable> selectableSet = selectables.toSet();
    _selectableStartEdgeUpdateRecords.removeWhere(
      (Selectable key, double value) => !selectableSet.contains(key),
    );
    _selectableEndEdgeUpdateRecords.removeWhere(
      (Selectable key, double value) => !selectableSet.contains(key),
    );
    super.didChangeSelectables();
  }

  @override
  SelectionResult handleClearSelection(ClearSelectionEvent event) {
    _selectableStartEdgeUpdateRecords.clear();
    _selectableEndEdgeUpdateRecords.clear();
    _currentDragStartRelatedToOrigin = null;
    _currentDragEndRelatedToOrigin = null;
    _selectionStartsInScrollable = false;
    return super.handleClearSelection(event);
  }

  @override
  SelectionResult handleSelectionEdgeUpdate(SelectionEdgeUpdateEvent event) {
    if (_currentDragEndRelatedToOrigin == null &&
        _currentDragStartRelatedToOrigin == null) {
      assert(!_selectionStartsInScrollable);
      _selectionStartsInScrollable = _globalPositionInScrollable(
        event.globalPosition,
      );
    }
    final Offset deltaToOrigin = _getDeltaToScrollOrigin(state);
    if (event.type == SelectionEventType.endEdgeUpdate) {
      _currentDragEndRelatedToOrigin = _inferPositionRelatedToOrigin(
        event.globalPosition,
      );
      final Offset endOffset = _currentDragEndRelatedToOrigin!.translate(
        -deltaToOrigin.dx,
        -deltaToOrigin.dy,
      );
      event = SelectionEdgeUpdateEvent.forEnd(
        globalPosition: endOffset,
        granularity: event.granularity,
      );
    } else {
      _currentDragStartRelatedToOrigin = _inferPositionRelatedToOrigin(
        event.globalPosition,
      );
      final Offset startOffset = _currentDragStartRelatedToOrigin!.translate(
        -deltaToOrigin.dx,
        -deltaToOrigin.dy,
      );
      event = SelectionEdgeUpdateEvent.forStart(
        globalPosition: startOffset,
        granularity: event.granularity,
      );
    }
    final SelectionResult result = super.handleSelectionEdgeUpdate(event);

    // Result may be pending if one of the selectable child is also a scrollable.
    // In that case, the parent scrollable needs to wait for the child to finish
    // scrolling.
    if (result == SelectionResult.pending) {
      _autoScroller.stopAutoScroll();
      return result;
    }
    if (_selectionStartsInScrollable) {
      _autoScroller.startAutoScrollIfNecessary(_dragTargetFromEvent(event));
      if (_autoScroller.scrolling) {
        return SelectionResult.pending;
      }
    }
    return result;
  }

  Offset _inferPositionRelatedToOrigin(Offset globalPosition) {
    final box = state.context.findRenderObject()! as RenderBox;
    final Offset localPosition = box.globalToLocal(globalPosition);
    if (!_selectionStartsInScrollable) {
      // If the selection starts outside of the scrollable, selecting across the
      // scrollable boundary will act as selecting the entire content in the
      // scrollable. This logic move the offset to the 0.0 or infinity to cover
      // the entire content if the input position is outside of the scrollable.
      if (localPosition.dy < 0 || localPosition.dx < 0) {
        return box.localToGlobal(Offset.zero);
      }
      if (localPosition.dy > box.size.height ||
          localPosition.dx > box.size.width) {
        return Offset.infinite;
      }
    }
    final Offset deltaToOrigin = _getDeltaToScrollOrigin(state);
    return box.localToGlobal(
      localPosition.translate(deltaToOrigin.dx, deltaToOrigin.dy),
    );
  }

  /// Infers the [_currentDragStartRelatedToOrigin] and
  /// [_currentDragEndRelatedToOrigin] from the geometry.
  ///
  /// This method is called after a select word and select all event where the
  /// selection is triggered by none drag events. The
  /// [_currentDragStartRelatedToOrigin] and [_currentDragEndRelatedToOrigin]
  /// are essential to handle future [SelectionEdgeUpdateEvent]s.
  void _updateDragLocationsFromGeometries({
    bool forceUpdateStart = true,
    bool forceUpdateEnd = true,
  }) {
    final Offset deltaToOrigin = _getDeltaToScrollOrigin(state);
    final box = state.context.findRenderObject()! as RenderBox;
    final Matrix4 transform = box.getTransformTo(null);
    if (currentSelectionStartIndex != -1 &&
        (_currentDragStartRelatedToOrigin == null || forceUpdateStart)) {
      final SelectionGeometry geometry =
          selectables[currentSelectionStartIndex].value;
      assert(geometry.hasSelection);
      final SelectionPoint start = geometry.startSelectionPoint!;
      final Matrix4 childTransform = selectables[currentSelectionStartIndex]
          .getTransformTo(box);
      final Offset localDragStart = MatrixUtils.transformPoint(
        childTransform,
        start.localPosition + Offset(0, -start.lineHeight / 2),
      );
      _currentDragStartRelatedToOrigin = MatrixUtils.transformPoint(
        transform,
        localDragStart + deltaToOrigin,
      );
    }
    if (currentSelectionEndIndex != -1 &&
        (_currentDragEndRelatedToOrigin == null || forceUpdateEnd)) {
      final SelectionGeometry geometry =
          selectables[currentSelectionEndIndex].value;
      assert(geometry.hasSelection);
      final SelectionPoint end = geometry.endSelectionPoint!;
      final Matrix4 childTransform = selectables[currentSelectionEndIndex]
          .getTransformTo(box);
      final Offset localDragEnd = MatrixUtils.transformPoint(
        childTransform,
        end.localPosition + Offset(0, -end.lineHeight / 2),
      );
      _currentDragEndRelatedToOrigin = MatrixUtils.transformPoint(
        transform,
        localDragEnd + deltaToOrigin,
      );
    }
  }

  @override
  SelectionResult handleSelectAll(SelectAllSelectionEvent event) {
    assert(!_selectionStartsInScrollable);
    final SelectionResult result = super.handleSelectAll(event);
    assert(
      (currentSelectionStartIndex == -1) == (currentSelectionEndIndex == -1),
    );
    if (currentSelectionStartIndex != -1) {
      _updateDragLocationsFromGeometries();
    }
    return result;
  }

  @override
  SelectionResult handleSelectWord(SelectWordSelectionEvent event) {
    _selectionStartsInScrollable = _globalPositionInScrollable(
      event.globalPosition,
    );
    final SelectionResult result = super.handleSelectWord(event);
    _updateDragLocationsFromGeometries();
    return result;
  }

  @override
  SelectionResult handleGranularlyExtendSelection(
    GranularlyExtendSelectionEvent event,
  ) {
    final SelectionResult result = super.handleGranularlyExtendSelection(event);
    // The selection geometry may not have the accurate offset for the edges
    // that are outside of the viewport whose transform may not be valid. Only
    // the edge this event is updating is sure to be accurate.
    _updateDragLocationsFromGeometries(
      forceUpdateStart: !event.isEnd,
      forceUpdateEnd: event.isEnd,
    );
    if (_selectionStartsInScrollable) {
      _jumpToEdge(event.isEnd);
    }
    return result;
  }

  @override
  SelectionResult handleDirectionallyExtendSelection(
    DirectionallyExtendSelectionEvent event,
  ) {
    final SelectionResult result = super.handleDirectionallyExtendSelection(
      event,
    );
    // The selection geometry may not have the accurate offset for the edges
    // that are outside of the viewport whose transform may not be valid. Only
    // the edge this event is updating is sure to be accurate.
    _updateDragLocationsFromGeometries(
      forceUpdateStart: !event.isEnd,
      forceUpdateEnd: event.isEnd,
    );
    if (_selectionStartsInScrollable) {
      _jumpToEdge(event.isEnd);
    }
    return result;
  }

  void _jumpToEdge(bool isExtent) {
    final Selectable selectable;
    final double? lineHeight;
    final SelectionPoint? edge;
    if (isExtent) {
      selectable = selectables[currentSelectionEndIndex];
      edge = selectable.value.endSelectionPoint;
      lineHeight = selectable.value.endSelectionPoint!.lineHeight;
    } else {
      selectable = selectables[currentSelectionStartIndex];
      edge = selectable.value.startSelectionPoint;
      lineHeight = selectable.value.startSelectionPoint?.lineHeight;
    }
    if (lineHeight == null || edge == null) {
      return;
    }
    final scrollableBox = state.context.findRenderObject()! as RenderBox;
    final Matrix4 transform = selectable.getTransformTo(scrollableBox);
    final Offset edgeOffsetInScrollableCoordinates = MatrixUtils.transformPoint(
      transform,
      edge.localPosition,
    );
    final scrollableRect = Rect.fromLTRB(
      0,
      0,
      scrollableBox.size.width,
      scrollableBox.size.height,
    );
    switch (state.axisDirection) {
      case AxisDirection.up:
        final double edgeBottom = edgeOffsetInScrollableCoordinates.dy;
        final double edgeTop =
            edgeOffsetInScrollableCoordinates.dy - lineHeight;
        if (edgeBottom >= scrollableRect.bottom &&
            edgeTop <= scrollableRect.top) {
          return;
        }
        if (edgeBottom > scrollableRect.bottom) {
          position.jumpTo(position.pixels + scrollableRect.bottom - edgeBottom);
          return;
        }
        if (edgeTop < scrollableRect.top) {
          position.jumpTo(position.pixels + scrollableRect.top - edgeTop);
        }
        return;
      case AxisDirection.right:
        final double edge = edgeOffsetInScrollableCoordinates.dx;
        if (edge >= scrollableRect.right && edge <= scrollableRect.left) {
          return;
        }
        if (edge > scrollableRect.right) {
          position.jumpTo(position.pixels + edge - scrollableRect.right);
          return;
        }
        if (edge < scrollableRect.left) {
          position.jumpTo(position.pixels + edge - scrollableRect.left);
        }
        return;
      case AxisDirection.down:
        final double edgeBottom = edgeOffsetInScrollableCoordinates.dy;
        final double edgeTop =
            edgeOffsetInScrollableCoordinates.dy - lineHeight;
        if (edgeBottom >= scrollableRect.bottom &&
            edgeTop <= scrollableRect.top) {
          return;
        }
        if (edgeBottom > scrollableRect.bottom) {
          position.jumpTo(position.pixels + edgeBottom - scrollableRect.bottom);
          return;
        }
        if (edgeTop < scrollableRect.top) {
          position.jumpTo(position.pixels + edgeTop - scrollableRect.top);
        }
        return;
      case AxisDirection.left:
        final double edge = edgeOffsetInScrollableCoordinates.dx;
        if (edge >= scrollableRect.right && edge <= scrollableRect.left) {
          return;
        }
        if (edge > scrollableRect.right) {
          position.jumpTo(position.pixels + scrollableRect.right - edge);
          return;
        }
        if (edge < scrollableRect.left) {
          position.jumpTo(position.pixels + scrollableRect.left - edge);
        }
        return;
    }
  }

  bool _globalPositionInScrollable(Offset globalPosition) {
    final box = state.context.findRenderObject()! as RenderBox;
    final Offset localPosition = box.globalToLocal(globalPosition);
    final rect = Rect.fromLTWH(0, 0, box.size.width, box.size.height);
    return rect.contains(localPosition);
  }

  Rect _dragTargetFromEvent(SelectionEdgeUpdateEvent event) {
    return Rect.fromCenter(
      center: event.globalPosition,
      width: _kDefaultDragTargetSize,
      height: _kDefaultDragTargetSize,
    );
  }

  @override
  SelectionResult dispatchSelectionEventToChild(
    Selectable selectable,
    SelectionEvent event,
  ) {
    switch (event.type) {
      case SelectionEventType.startEdgeUpdate:
        _selectableStartEdgeUpdateRecords[selectable] = state.position.pixels;
        ensureChildUpdated(selectable);
      case SelectionEventType.endEdgeUpdate:
        _selectableEndEdgeUpdateRecords[selectable] = state.position.pixels;
        ensureChildUpdated(selectable);
      case SelectionEventType.granularlyExtendSelection:
      case SelectionEventType.directionallyExtendSelection:
        ensureChildUpdated(selectable);
        _selectableStartEdgeUpdateRecords[selectable] = state.position.pixels;
        _selectableEndEdgeUpdateRecords[selectable] = state.position.pixels;
      case SelectionEventType.clear:
        _selectableEndEdgeUpdateRecords.remove(selectable);
        _selectableStartEdgeUpdateRecords.remove(selectable);
      case SelectionEventType.selectAll:
      case SelectionEventType.selectWord:
      case SelectionEventType.selectParagraph:
        _selectableEndEdgeUpdateRecords[selectable] = state.position.pixels;
        _selectableStartEdgeUpdateRecords[selectable] = state.position.pixels;
    }
    return super.dispatchSelectionEventToChild(selectable, event);
  }

  @override
  void ensureChildUpdated(Selectable selectable) {
    final double newRecord = state.position.pixels;
    final double? previousStartRecord =
        _selectableStartEdgeUpdateRecords[selectable];
    if (_currentDragStartRelatedToOrigin != null &&
        (previousStartRecord == null ||
            (newRecord - previousStartRecord).abs() >
                precisionErrorTolerance)) {
      // Make sure the selectable has up to date events.
      final Offset deltaToOrigin = _getDeltaToScrollOrigin(state);
      final Offset startOffset = _currentDragStartRelatedToOrigin!.translate(
        -deltaToOrigin.dx,
        -deltaToOrigin.dy,
      );
      selectable.dispatchSelectionEvent(
        SelectionEdgeUpdateEvent.forStart(globalPosition: startOffset),
      );
      // Make sure we track that we have synthesized a start event for this selectable,
      // so we don't synthesize events unnecessarily.
      _selectableStartEdgeUpdateRecords[selectable] = state.position.pixels;
    }
    final double? previousEndRecord =
        _selectableEndEdgeUpdateRecords[selectable];
    if (_currentDragEndRelatedToOrigin != null &&
        (previousEndRecord == null ||
            (newRecord - previousEndRecord).abs() > precisionErrorTolerance)) {
      // Make sure the selectable has up to date events.
      final Offset deltaToOrigin = _getDeltaToScrollOrigin(state);
      final Offset endOffset = _currentDragEndRelatedToOrigin!.translate(
        -deltaToOrigin.dx,
        -deltaToOrigin.dy,
      );
      selectable.dispatchSelectionEvent(
        SelectionEdgeUpdateEvent.forEnd(globalPosition: endOffset),
      );
      // Make sure we track that we have synthesized an end event for this selectable,
      // so we don't synthesize events unnecessarily.
      _selectableEndEdgeUpdateRecords[selectable] = state.position.pixels;
    }
  }

  @override
  void dispose() {
    // Unlike the SDK handler, this delegate owns its position listener.
    _position.removeListener(_scheduleLayoutChange);
    _selectableStartEdgeUpdateRecords.clear();
    _selectableEndEdgeUpdateRecords.clear();
    _scheduledLayoutChange = false;
    _autoScroller.stopAutoScroll();
    super.dispose();
  }
}

Offset _getDeltaToScrollOrigin(ScrollableState scrollableState) {
  return switch (scrollableState.axisDirection) {
    AxisDirection.up => Offset(0, -scrollableState.position.pixels),
    AxisDirection.down => Offset(0, scrollableState.position.pixels),
    AxisDirection.left => Offset(-scrollableState.position.pixels, 0),
    AxisDirection.right => Offset(scrollableState.position.pixels, 0),
  };
}
