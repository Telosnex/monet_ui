import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'package:monet_ui/widgets/rich_text/render_monet_rich_text.dart';

class MonetRichTextSelectable extends ChangeNotifier
    with Diagnosticable
    implements Selectable {
  MonetRichTextSelectable(this.paragraph) {
    _selectionGeometry = _getSelectionGeometry();
  }

  final RenderMonetRichText paragraph;

  TextPosition? _selectionStart;
  TextPosition? _selectionEnd;
  LayerLink? _startHandleLayerLink;
  LayerLink? _endHandleLayerLink;
  List<Rect>? _cachedBoundingBoxes;
  Rect? _cachedRect;
  bool _geometryUpdateScheduled = false;
  bool _disposed = false;

  late SelectionGeometry _selectionGeometry;

  @override
  SelectionGeometry get value => _selectionGeometry;

  @override
  int get contentLength => _selectableText.length;

  @override
  Size get size => _rect.size;

  @override
  List<Rect> get boundingBoxes {
    if (_cachedBoundingBoxes != null) return _cachedBoundingBoxes!;
    if (!_hasContent) {
      _cachedBoundingBoxes = const <Rect>[];
      return _cachedBoundingBoxes!;
    }

    final boxes = _boxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: contentLength),
      boxHeightStyle: ui.BoxHeightStyle.max,
    );
    if (boxes.isNotEmpty) {
      _cachedBoundingBoxes = <Rect>[for (final box in boxes) box.toRect()];
    } else {
      final offset = _offsetForPosition(const TextPosition(offset: 0));
      _cachedBoundingBoxes = [
        Rect.fromPoints(offset, offset.translate(0, -_preferredLineHeight)),
      ];
    }
    return _cachedBoundingBoxes!;
  }

  Rect get _rect {
    if (_cachedRect != null) return _cachedRect!;
    if (boundingBoxes.isEmpty) {
      _cachedRect = .zero;
      return _cachedRect!;
    }

    Rect result = boundingBoxes.first;
    for (final rect in boundingBoxes.skip(1)) {
      result = result.expandToInclude(rect);
    }
    _cachedRect = result;
    return result;
  }

  bool get _hasContent => contentLength > 0;

  String get _selectableText {
    final layoutText = paragraph.layoutResult?.input.text;
    if (layoutText == '\u200B' && paragraph.text.isEmpty) return '';
    return layoutText ?? paragraph.text;
  }

  int get _placeholderOffset =>
      paragraph.layoutResult?.input.placeholderSizes.length ??
      paragraph.leadingCount;

  TextPainter? get _painter => paragraph.layoutResult?.painter;

  double get _preferredLineHeight =>
      _painter?.preferredLineHeight ?? paragraph.textStyle.fontSize ?? 0;

  void didChangeParagraphLayout() {
    _cachedBoundingBoxes = null;
    _cachedRect = null;
    final oldStart = _selectionStart;
    final oldEnd = _selectionEnd;
    _clampSelectionToContent();
    if (oldStart != _selectionStart || oldEnd != _selectionEnd) {
      paragraph.markNeedsPaint();
    }
    // A geometry change notifies the selection container, which reads the
    // size of its own render box. During layout that box is usually not the
    // one being laid out, so the read fails the sizeAccessAllowed assertion.
    // Send the update after the frame instead.
    if (SchedulerBinding.instance.schedulerPhase == .persistentCallbacks) {
      _scheduleSelectionGeometryUpdate();
    } else {
      _updateSelectionGeometry();
    }
  }

  void _scheduleSelectionGeometryUpdate() {
    if (_geometryUpdateScheduled) return;
    _geometryUpdateScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _geometryUpdateScheduled = false;
      if (_disposed || !paragraph.attached) return;
      _updateSelectionGeometry();
    }, debugLabel: 'MonetRichTextSelectable.updateSelectionGeometry');
  }

  /// Selection geometry uses paragraph coordinates. The paragraph can be
  /// painted below the box origin, see
  /// [RenderMonetRichText.paragraphOffset].
  @override
  Matrix4 getTransformTo(RenderObject? ancestor) {
    final transform = paragraph.getTransformTo(ancestor);
    final offset = paragraph.paragraphOffset;
    if (offset != .zero) {
      transform.translateByDouble(offset.dx, offset.dy, 0, 1);
    }
    return transform;
  }

  @override
  void pushHandleLayers(LayerLink? startHandle, LayerLink? endHandle) {
    if (!paragraph.attached) {
      assert(
        startHandle == null && endHandle == null,
        'Only cleanup can be called after detach.',
      );
      return;
    }
    if (_startHandleLayerLink != startHandle) {
      _startHandleLayerLink = startHandle;
      paragraph.markNeedsPaint();
    }
    if (_endHandleLayerLink != endHandle) {
      _endHandleLayerLink = endHandle;
      paragraph.markNeedsPaint();
    }
  }

  @override
  SelectedContent? getSelectedContent() {
    if (_selectionStart == null || _selectionEnd == null) return null;
    final start = math.min(_selectionStart!.offset, _selectionEnd!.offset);
    final end = math.max(_selectionStart!.offset, _selectionEnd!.offset);
    return SelectedContent(plainText: _selectableText.substring(start, end));
  }

  @override
  SelectedContentRange? getSelection() {
    if (_selectionStart == null || _selectionEnd == null) return null;
    return SelectedContentRange(
      startOffset: _selectionStart!.offset,
      endOffset: _selectionEnd!.offset,
    );
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    final oldStart = _selectionStart;
    final oldEnd = _selectionEnd;

    final SelectionResult result;
    switch (event.type) {
      case .startEdgeUpdate:
      case .endEdgeUpdate:
        final edgeUpdate = event as SelectionEdgeUpdateEvent;
        final isEnd = event.type == .endEdgeUpdate;
        result = switch (edgeUpdate.granularity) {
          .word => _updateSelectionEdgeByWord(
            edgeUpdate.globalPosition,
            isEnd: isEnd,
          ),
          .paragraph ||
          .document => _updateSelectionEdgeByWholeContent(isEnd: isEnd),
          .character || .line => _updateSelectionEdge(
            edgeUpdate.globalPosition,
            isEnd: isEnd,
          ),
        };
      case .clear:
        result = _handleClearSelection();
      case .selectAll:
        result = _handleSelectAll();
      case .selectWord:
        result = _handleSelectWord(
          (event as SelectWordSelectionEvent).globalPosition,
        );
      case .selectParagraph:
        final selectParagraph = event as SelectParagraphSelectionEvent;
        result = selectParagraph.absorb
            ? _handleSelectAll(absorb: true)
            : _handleSelectParagraph(selectParagraph.globalPosition);
      case .granularlyExtendSelection:
        final granular = event as GranularlyExtendSelectionEvent;
        result = _handleGranularlyExtendSelection(
          forward: granular.forward,
          isEnd: granular.isEnd,
          granularity: granular.granularity,
        );
      case .directionallyExtendSelection:
        final directional = event as DirectionallyExtendSelectionEvent;
        result = _handleDirectionallyExtendSelection(
          isEnd: directional.isEnd,
          direction: directional.direction,
        );
    }

    if (oldStart != _selectionStart || oldEnd != _selectionEnd) {
      _didChangeSelection();
    }
    return result;
  }

  SelectionResult _updateSelectionEdge(
    Offset globalPosition, {
    required bool isEnd,
  }) {
    if (!_hasContent) return .none;
    _setSelectionPosition(null, isEnd: isEnd);
    final localPosition = _globalToLocal(globalPosition);
    final rect = _rect;
    if (rect.isEmpty) {
      return SelectionUtils.getResultBasedOnRect(rect, localPosition);
    }

    final adjustedOffset = SelectionUtils.adjustDragOffset(
      rect,
      localPosition,
      direction: paragraph.textDirection,
    );
    final position = _clampTextPosition(_positionForOffset(adjustedOffset));
    _setSelectionPosition(position, isEnd: isEnd);
    return _resultForPosition(position, localPosition);
  }

  SelectionResult _updateSelectionEdgeByWord(
    Offset globalPosition, {
    required bool isEnd,
  }) {
    if (!_hasContent) return .none;
    _setSelectionPosition(null, isEnd: isEnd);
    final localPosition = _globalToLocal(globalPosition);
    final rect = _rect;
    if (rect.isEmpty) {
      return SelectionUtils.getResultBasedOnRect(rect, localPosition);
    }

    final adjustedOffset = SelectionUtils.adjustDragOffset(
      rect,
      localPosition,
      direction: paragraph.textDirection,
    );
    final position = _clampTextPosition(_positionForOffset(adjustedOffset));
    final boundary = getWordBoundary(position);
    final staticEdge = isEnd ? _selectionStart : _selectionEnd;
    final target = _clampTextPosition(
      _boundaryPositionForDrag(boundary, position, staticEdge),
    );
    _setSelectionPosition(target, isEnd: isEnd);
    return _resultForPosition(target, localPosition);
  }

  SelectionResult _updateSelectionEdgeByWholeContent({required bool isEnd}) {
    if (!_hasContent) return .none;
    final staticEdge = isEnd ? _selectionStart : _selectionEnd;
    final target = staticEdge == null || staticEdge.offset <= contentLength / 2
        ? TextPosition(offset: contentLength)
        : const TextPosition(offset: 0);
    _setSelectionPosition(target, isEnd: isEnd);
    return _resultForOffset(target.offset);
  }

  SelectionResult _handleClearSelection() {
    _selectionStart = null;
    _selectionEnd = null;
    return .none;
  }

  SelectionResult _handleSelectAll({bool absorb = false}) {
    if (!_hasContent) {
      _selectionStart = null;
      _selectionEnd = null;
      return .none;
    }
    _selectionStart = const TextPosition(offset: 0);
    _selectionEnd = TextPosition(offset: contentLength);
    return absorb ? .next : .none;
  }

  SelectionResult _handleSelectWord(Offset globalPosition) {
    if (!_hasContent) return .none;
    final localPosition = _globalToLocal(globalPosition);
    if (!_rect.contains(localPosition)) {
      return SelectionUtils.getResultBasedOnRect(_rect, localPosition);
    }

    final position = _clampTextPosition(_positionForOffset(localPosition));
    // Mirror RenderParagraph's _SelectableFragment._handleSelectWord: a
    // select-word landing inside a non-collapsed existing selection keeps
    // that selection. This is what makes right-click on selected text show
    // the context menu without resetting the selection to the word under
    // the cursor (SelectableRegion._handleRightClickDown on macOS always
    // dispatches a select-word; the preserve-if-inside behavior lives at
    // the selectable level).
    if (_positionIsWithinCurrentSelection(position)) return .end;
    final word = getWordBoundary(position);
    _selectionStart = TextPosition(offset: word.start);
    _selectionEnd = TextPosition(offset: word.end);
    return .end;
  }

  bool _positionIsWithinCurrentSelection(TextPosition position) {
    final start = _selectionStart;
    final end = _selectionEnd;
    if (start == null || end == null) return false;
    final min = math.min(start.offset, end.offset);
    final max = math.max(start.offset, end.offset);
    if (min == max) return false;
    return min <= position.offset && position.offset <= max;
  }

  SelectionResult _handleSelectParagraph(Offset globalPosition) {
    if (!_hasContent) return .none;
    final localPosition = _globalToLocal(globalPosition);
    if (!_rect.contains(localPosition)) {
      return SelectionUtils.getResultBasedOnRect(_rect, localPosition);
    }
    _selectionStart = const TextPosition(offset: 0);
    _selectionEnd = TextPosition(offset: contentLength);
    return .end;
  }

  SelectionResult _handleGranularlyExtendSelection({
    required bool forward,
    required bool isEnd,
    required TextGranularity granularity,
  }) {
    if (!_hasContent) return .none;
    final current = _edgeForExtension(forward: forward, isEnd: isEnd);
    final target = switch (granularity) {
      .character => _nextCharacterBoundary(current, forward: forward),
      .word => _nextWordBoundary(current, forward: forward),
      .line =>
        forward
            ? _getTextPositionBelow(current)
            : _getTextPositionAbove(current),
      .paragraph ||
      .document => TextPosition(offset: forward ? contentLength : 0),
    };
    final clampedTarget = _clampTextPosition(target);
    _setSelectionPosition(clampedTarget, isEnd: isEnd);
    return _resultForOffset(clampedTarget.offset);
  }

  SelectionResult _handleDirectionallyExtendSelection({
    required bool isEnd,
    required SelectionExtendDirection direction,
  }) {
    if (!_hasContent) return .none;
    final current = _edgeForExtension(
      forward: direction != .backward && direction != .previousLine,
      isEnd: isEnd,
    );
    final target = switch (direction) {
      .previousLine => _getTextPositionAbove(current),
      .nextLine => _getTextPositionBelow(current),
      .forward => _nextCharacterBoundary(current, forward: true),
      .backward => _nextCharacterBoundary(current, forward: false),
    };
    final clampedTarget = _clampTextPosition(target);
    _setSelectionPosition(clampedTarget, isEnd: isEnd);
    return _resultForOffset(clampedTarget.offset);
  }

  TextPosition _edgeForExtension({required bool forward, required bool isEnd}) {
    final fallback = TextPosition(offset: forward ? 0 : contentLength);
    final current = (isEnd ? _selectionEnd : _selectionStart) ?? fallback;
    if (_selectionStart == null && _selectionEnd == null) {
      _selectionStart = current;
      _selectionEnd = current;
    }
    return _clampTextPosition(current);
  }

  TextPosition _nextCharacterBoundary(
    TextPosition position, {
    required bool forward,
  }) {
    var offset = 0;
    var previous = 0;
    for (final character in _selectableText.characters) {
      offset += character.length;
      if (forward && offset > position.offset) {
        return TextPosition(offset: offset);
      }
      if (!forward && offset >= position.offset) {
        return TextPosition(offset: previous);
      }
      previous = offset;
    }
    return TextPosition(offset: forward ? contentLength : previous);
  }

  TextPosition _nextWordBoundary(
    TextPosition position, {
    required bool forward,
  }) {
    final boundary = getWordBoundary(position);
    if (forward) {
      if (boundary.end > position.offset) {
        return TextPosition(offset: boundary.end);
      }
      return _nextCharacterBoundary(position, forward: true);
    }
    if (boundary.start < position.offset) {
      return TextPosition(offset: boundary.start);
    }
    return _nextCharacterBoundary(position, forward: false);
  }

  TextPosition _boundaryPositionForDrag(
    TextRange boundary,
    TextPosition position,
    TextPosition? staticEdge,
  ) {
    if (staticEdge != null) {
      return TextPosition(
        offset: position.offset < staticEdge.offset
            ? boundary.start
            : boundary.end,
      );
    }
    final distanceToStart = (position.offset - boundary.start).abs();
    final distanceToEnd = (boundary.end - position.offset).abs();
    return TextPosition(
      offset: distanceToStart <= distanceToEnd ? boundary.start : boundary.end,
    );
  }

  TextRange getWordBoundary(TextPosition position) {
    final painter = _painter;
    if (painter == null) {
      return TextRange(start: position.offset, end: position.offset);
    }
    return _fromPainterRange(
      painter.getWordBoundary(_toPainterPosition(position)),
    );
  }

  TextPosition _getTextPositionAbove(TextPosition position) {
    return _getTextPositionVertical(position, -0.5 * _preferredLineHeight);
  }

  TextPosition _getTextPositionBelow(TextPosition position) {
    return _getTextPositionVertical(position, 1.5 * _preferredLineHeight);
  }

  TextPosition _getTextPositionVertical(
    TextPosition position,
    double verticalOffset,
  ) {
    final painter = _painter;
    if (painter == null) return _clampTextPosition(position);
    final caretOffset = painter.getOffsetForCaret(
      _toPainterPosition(position),
      .zero,
    );
    return _fromPainterPosition(
      painter.getPositionForOffset(caretOffset.translate(0, verticalOffset)),
    );
  }

  Offset _globalToLocal(Offset globalPosition) {
    final transform = getTransformTo(null)..invert();
    return MatrixUtils.transformPoint(transform, globalPosition);
  }

  TextPosition _positionForOffset(Offset offset) {
    final painter = _painter;
    if (painter == null) return const TextPosition(offset: 0);
    return _fromPainterPosition(painter.getPositionForOffset(offset));
  }

  Offset _offsetForPosition(TextPosition position) {
    final painter = _painter;
    if (painter == null) return .zero;
    final painterPosition = _toPainterPosition(position);
    return painter.getOffsetForCaret(painterPosition, .zero) +
        Offset(0, painter.getFullHeightForCaret(painterPosition, .zero));
  }

  List<ui.TextBox> _boxesForSelection(
    TextSelection selection, {
    ui.BoxHeightStyle boxHeightStyle = ui.BoxHeightStyle.tight,
    // ignore: avoid-never-passed-parameters
    ui.BoxWidthStyle boxWidthStyle = ui.BoxWidthStyle.tight,
  }) {
    final painter = _painter;
    if (painter == null || selection.isCollapsed) return const [];
    return painter.getBoxesForSelection(
      _toPainterSelection(selection),
      boxHeightStyle: boxHeightStyle,
      boxWidthStyle: boxWidthStyle,
    );
  }

  TextSelection _toPainterSelection(TextSelection selection) {
    return TextSelection(
      baseOffset: _toPainterOffset(selection.baseOffset),
      extentOffset: _toPainterOffset(selection.extentOffset),
      affinity: selection.affinity,
      isDirectional: selection.isDirectional,
    );
  }

  TextPosition _toPainterPosition(TextPosition position) {
    return TextPosition(
      offset: _toPainterOffset(position.offset),
      affinity: position.affinity,
    );
  }

  int _toPainterOffset(int offset) {
    return _placeholderOffset + _clampOffset(offset);
  }

  TextPosition _fromPainterPosition(TextPosition position) {
    return TextPosition(
      offset: _clampOffset(position.offset - _placeholderOffset),
      affinity: position.affinity,
    );
  }

  TextRange _fromPainterRange(TextRange range) {
    return TextRange(
      start: _clampOffset(range.start - _placeholderOffset),
      end: _clampOffset(range.end - _placeholderOffset),
    );
  }

  TextPosition _clampTextPosition(TextPosition position) {
    return TextPosition(
      offset: _clampOffset(position.offset),
      affinity: position.affinity,
    );
  }

  int _clampOffset(int offset) {
    return math.min(math.max(offset, 0), contentLength);
  }

  void _clampSelectionToContent() {
    if (!_hasContent) {
      _selectionStart = null;
      _selectionEnd = null;
      return;
    }
    final start = _selectionStart;
    if (start != null) _selectionStart = _clampTextPosition(start);
    final end = _selectionEnd;
    if (end != null) _selectionEnd = _clampTextPosition(end);
  }

  SelectionResult _resultForPosition(
    TextPosition position,
    Offset localPosition,
  ) {
    if (position.offset == contentLength) return .next;
    if (position.offset == 0) return .previous;
    return SelectionUtils.getResultBasedOnRect(_rect, localPosition);
  }

  SelectionResult _resultForOffset(int offset) {
    if (offset <= 0) return .previous;
    if (offset >= contentLength) return .next;
    return .end;
  }

  void _setSelectionPosition(TextPosition? position, {required bool isEnd}) {
    if (isEnd) {
      _selectionEnd = position;
    } else {
      _selectionStart = position;
    }
  }

  void _didChangeSelection() {
    paragraph.markNeedsPaint();
    _updateSelectionGeometry();
  }

  void _updateSelectionGeometry() {
    final next = _getSelectionGeometry();
    if (_selectionGeometry == next) return;
    final hadContent = _selectionGeometry.hasContent;
    _selectionGeometry = next;
    if (hadContent != next.hasContent) {
      // ignore: invalid_use_of_visible_for_testing_member
      paragraph.updateSelectionRegistrarSubscription();
    }
    notifyListeners();
  }

  SelectionGeometry _getSelectionGeometry() {
    final hasContent = _hasContent;
    final start = _selectionStart;
    final end = _selectionEnd;
    if (!hasContent || start == null || end == null || _painter == null) {
      return SelectionGeometry(status: .none, hasContent: hasContent);
    }

    final selectionStart = start.offset;
    final selectionEnd = end.offset;
    final isReversed = selectionStart > selectionEnd;
    final startOffset = _offsetForPosition(start);
    final endOffset = selectionStart == selectionEnd
        ? startOffset
        : _offsetForPosition(end);
    final flipHandles = isReversed != (paragraph.textDirection == .rtl);
    final selection = TextSelection(
      baseOffset: selectionStart,
      extentOffset: selectionEnd,
    );
    final selectionRects = <Rect>[
      for (final box in _boxesForSelection(selection)) box.toRect(),
    ];
    final collapsed = selectionStart == selectionEnd;
    final TextSelectionHandleType startHandleType;
    final TextSelectionHandleType endHandleType;
    if (collapsed) {
      startHandleType = .collapsed;
      endHandleType = .collapsed;
    } else if (flipHandles) {
      startHandleType = .right;
      endHandleType = .left;
    } else {
      startHandleType = .left;
      endHandleType = .right;
    }

    return SelectionGeometry(
      startSelectionPoint: SelectionPoint(
        localPosition: startOffset,
        lineHeight: _preferredLineHeight,
        handleType: startHandleType,
      ),
      endSelectionPoint: SelectionPoint(
        localPosition: endOffset,
        lineHeight: _preferredLineHeight,
        handleType: endHandleType,
      ),
      selectionRects: selectionRects,
      status: collapsed ? .collapsed : .uncollapsed,
      hasContent: true,
    );
  }

  void paint(PaintingContext context, Offset offset) {
    if (_selectionStart == null || _selectionEnd == null) return;
    final selectionColor = paragraph.selectionColor;
    if (selectionColor != null) {
      final selection = TextSelection(
        baseOffset: _selectionStart!.offset,
        extentOffset: _selectionEnd!.offset,
      );
      final selectionPaint = Paint()
        ..style = .fill
        ..color = selectionColor;
      for (final box in _boxesForSelection(selection)) {
        context.canvas.drawRect(box.toRect().shift(offset), selectionPaint);
      }
    }

    final startPoint = value.startSelectionPoint;
    if (_startHandleLayerLink != null && startPoint != null) {
      context.pushLayer(
        LeaderLayer(
          link: _startHandleLayerLink!,
          offset: offset + startPoint.localPosition,
        ),
        // ignore: no-empty-block
        (PaintingContext context, Offset offset) {},
        .zero,
      );
    }

    final endPoint = value.endSelectionPoint;
    if (_endHandleLayerLink != null && endPoint != null) {
      context.pushLayer(
        LeaderLayer(
          link: _endHandleLayerLink!,
          offset: offset + endPoint.localPosition,
        ),
        // ignore: no-empty-block
        (PaintingContext context, Offset offset) {},
        .zero,
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _startHandleLayerLink = null;
    _endHandleLayerLink = null;
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('selectableText', _selectableText))
      ..add(DiagnosticsProperty<SelectionGeometry>('value', value));
  }
}
