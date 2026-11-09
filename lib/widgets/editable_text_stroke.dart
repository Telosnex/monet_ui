import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Draws a stroke under the text of the first [RenderEditable] in [child].
///
/// `dart:ui` cannot fill and stroke text in one pass, and [EditableText]
/// paints its text once. This widget uses the public
/// [RenderEditable.painter] hook, which paints under the text inside the
/// same render object. The stroke reads the text, the scroll offset and the
/// layout inputs from the [RenderEditable] on every paint, so it stays on
/// the glyphs while the field scrolls or is edited.
///
/// Paint order inside the field: selection highlight, stroke, text fill.
/// Native text shadows paint with the fill, so they are above the stroke.
/// That is invisible while the stroke and the shadows share one color.
/// Where the platform paints the caret under the text, the stroke leaves out
/// the visible caret's shape, so the caret looks as it does without a stroke.
///
/// The stroke copy of the text has no decorations, so the composing and
/// spell-check underlines are not outlined.
class EditableTextStroke extends SingleChildRenderObjectWidget {
  /// A [strokeColor] of null, or a [strokeWidth] of 0 or less, draws no
  /// stroke.
  const EditableTextStroke({
    super.key,
    required this.strokeColor,
    this.strokeWidth = 1,
    required Widget super.child,
  });

  final Color? strokeColor;

  /// The visible outer stroke's width in logical pixels. Defaults to 1.
  /// The painter doubles it for the centered stroke under the fill.
  final double strokeWidth;

  @override
  RenderEditableTextStroke createRenderObject(BuildContext context) {
    return RenderEditableTextStroke(
      strokeColor: strokeColor,
      strokeWidth: strokeWidth,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderEditableTextStroke renderObject,
  ) {
    renderObject
      ..strokeColor = strokeColor
      ..strokeWidth = strokeWidth;
  }
}

/// Render object for [EditableTextStroke].
///
/// Installs the painter on the [RenderEditable] during layout of this
/// subtree, inside [invokeLayoutCallback], so the field lays out its painter
/// child in the same frame. If a paint finds that the field was replaced
/// without a layout here, it schedules one for the next frame.
class RenderEditableTextStroke extends RenderProxyBox {
  RenderEditableTextStroke({
    required Color? strokeColor,
    required double strokeWidth,
  }) : _painter = EditableTextStrokePainter(
         color: strokeColor,
         width: strokeWidth,
       );

  final EditableTextStrokePainter _painter;
  RenderEditable? _editable;
  bool _relayoutScheduled = false;

  set strokeColor(Color? value) => _painter.color = value;
  set strokeWidth(double value) => _painter.width = value;

  /// The field the stroke is installed on, if any.
  @visibleForTesting
  RenderEditable? get editable {
    return _editable;
  }

  @override
  void performLayout() {
    invokeLayoutCallback<BoxConstraints>((_) => _attachToEditable());
    super.performLayout();
    if (_isInstalled()) return;
    // A field built during this layout, as by a LayoutBuilder, exists only
    // now. Installing the painter marks it for layout, so lay out again.
    var installed = false;
    invokeLayoutCallback<BoxConstraints>((_) {
      installed = _attachToEditable();
    });
    if (installed) super.performLayout();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    // Only for a field this object can take; one with another painter would
    // otherwise schedule a layout on every frame.
    if (_isInstalled()) return;
    final found = _findEditable(this);
    if (found != null && found.painter == null) _scheduleRelayout();
  }

  @override
  void detach() {
    _relayoutScheduled = false;
    super.detach();
  }

  @override
  void dispose() {
    final current = _editable;
    _editable = null;
    // A field that outlives this object, by moving with a GlobalKey, must
    // not keep a disposed painter.
    if (current != null &&
        current.attached &&
        identical(current.painter, _painter)) {
      current.painter = null;
    }
    _painter.dispose();
    super.dispose();
  }

  bool _isInstalled() {
    final current = _editable;
    return current != null &&
        current.attached &&
        identical(current.painter, _painter) &&
        _isDescendant(current);
  }

  /// Returns true if this call installed the painter.
  bool _attachToEditable() {
    if (_isInstalled()) return false;
    final previous = _editable;
    _editable = null;
    // Only a detached field can be changed here; one that moved elsewhere
    // is in another subtree's layout.
    if (previous != null &&
        !previous.attached &&
        identical(previous.painter, _painter)) {
      previous.painter = null;
    }
    final found = _findEditable(this);
    // Leave a painter that someone else set alone.
    if (found == null || (found.painter != null && found.painter != _painter)) {
      return false;
    }
    found.painter = _painter;
    _editable = found;
    return true;
  }

  void _scheduleRelayout() {
    if (_relayoutScheduled) return;
    _relayoutScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_relayoutScheduled || !attached) return;
      _relayoutScheduled = false;
      markNeedsLayout();
    });
  }

  bool _isDescendant(RenderObject object) {
    RenderObject? node = object.parent;
    while (node != null) {
      if (identical(node, this)) return true;
      node = node.parent;
    }
    return false;
  }

  static RenderEditable? _findEditable(RenderObject root) {
    RenderEditable? found;
    void visit(RenderObject child) {
      if (found != null) return;
      if (child is RenderEditable) {
        found = child;
        return;
      }
      child.visitChildren(visit);
    }

    root.visitChildren(visit);
    return found;
  }
}

/// The [RenderEditablePainter] that [EditableTextStroke] installs.
@visibleForTesting
class EditableTextStrokePainter extends RenderEditablePainter {
  EditableTextStrokePainter({required this._color, required this._width});

  // RenderEditable keeps this gap between the text and the caret; it is
  // private there as `_kCaretGap`.
  static const double _caretGap = 1;

  Color? _color;
  Color? get color => _color;
  set color(Color? value) {
    if (value == _color) return;
    _color = value;
    _strokeText = null;
    notifyListeners();
  }

  double _width;
  double get width => _width;
  set width(double value) {
    if (value == _width) return;
    _width = value;
    _strokeText = null;
    notifyListeners();
  }

  final TextPainter _textPainter = TextPainter();
  InlineSpan? _sourceText;
  InlineSpan? _strokeText;

  /// The stroke copy of the field's text from the last paint.
  @visibleForTesting
  InlineSpan? get strokeText {
    return _strokeText;
  }

  @override
  void paint(Canvas canvas, Size size, RenderEditable renderEditable) {
    final color = _color;
    if (color == null || color.a == 0 || _width <= 0) return;
    // An obscured field paints obscuring characters, not this text.
    if (renderEditable.obscureText) return;
    final source = renderEditable.text;
    if (source == null) return;

    if (_strokeText == null || source != _sourceText) {
      _sourceText = source;
      _strokeText = _strokeCopy(source, _strokePaint(color));
    }

    final painter = _textPainter
      ..text = _strokeText
      ..textAlign = renderEditable.textAlign
      ..textDirection = renderEditable.textDirection
      ..textScaler = renderEditable.textScaler
      ..maxLines = renderEditable.maxLines
      ..strutStyle = renderEditable.strutStyle
      ..textWidthBasis = renderEditable.textWidthBasis
      ..textHeightBehavior = renderEditable.textHeightBehavior
      ..locale = renderEditable.locale;

    // Same width rule as RenderEditable._adjustConstraints, so the stroke
    // copy breaks and aligns its lines like the field's own text.
    final constraints = renderEditable.constraints;
    final caretMargin = _caretGap + renderEditable.cursorWidth;
    final availableMaxWidth = (constraints.maxWidth - caretMargin).clamp(
      0.0,
      double.infinity,
    );
    final availableMinWidth = constraints.minWidth < availableMaxWidth
        ? constraints.minWidth
        : availableMaxWidth;
    final isMultiline = renderEditable.maxLines != 1;
    painter.layout(
      minWidth: renderEditable.forceLine
          ? availableMaxWidth
          : availableMinWidth,
      maxWidth: isMultiline ? availableMaxWidth : .infinity,
    );

    // Same as RenderEditable._paintOffset: single-line fields scroll
    // horizontally, multiline fields vertically.
    final pixels = renderEditable.offset.hasPixels
        ? renderEditable.offset.pixels
        : 0.0;
    final paintOffset = isMultiline ? Offset(0, -pixels) : Offset(-pixels, 0);
    final caret = _caretUnderText(renderEditable);
    if (caret == null) {
      painter.paint(canvas, paintOffset);
      return;
    }
    // Everything the stroke can reach, minus the caret. Glyphs may overhang
    // the field a little; a field with more text clips to its bounds.
    final clip = Path()
      ..fillType = .evenOdd
      ..addRect((Offset.zero & size).inflate(64))
      ..addRRect(caret);
    canvas
      ..save()
      ..clipPath(clip);
    painter.paint(canvas, paintOffset);
    canvas.restore();
  }

  /// The visible caret, where the platform paints it under the text.
  ///
  /// Android, Linux and Windows paint the caret before this painter, so the
  /// stroke would cover its edges. The stroke leaves out the caret's shape
  /// instead. Caret blinks repaint this painter too, because the caret is in
  /// the same group of painters.
  static RRect? _caretUnderText(RenderEditable renderEditable) {
    if (renderEditable.paintCursorAboveText) return null;
    if (!renderEditable.showCursor.value) return null;
    final cursorColor = renderEditable.cursorColor;
    if (cursorColor == null || cursorColor.a == 0) return null;
    final selection = renderEditable.selection;
    if (selection == null || !selection.isValid || !selection.isCollapsed) {
      return null;
    }
    final rect = renderEditable.getLocalRectForCaret(selection.extent);
    final radius = renderEditable.cursorRadius;
    return radius == null
        ? RRect.fromRectXY(rect, 0, 0)
        : RRect.fromRectAndRadius(rect, radius);
  }

  Paint _strokePaint(Color color) => .new()
    ..style = .stroke
    ..strokeWidth = 2 * _width
    ..color = color;

  /// Copies [span] with a stroke-only style on every [TextSpan].
  ///
  /// Each span overrides its own style, because the composing span sets its
  /// underline itself instead of inheriting it.
  static InlineSpan _strokeCopy(InlineSpan span, Paint strokePaint) {
    if (span is! TextSpan) return span;
    return TextSpan(
      text: span.text,
      style: (span.style ?? const TextStyle()).copyWith(
        foreground: strokePaint,
        decoration: .none,
        background: Paint()..color = const Color(0x00000000),
        shadows: const [],
      ),
      locale: span.locale,
      spellOut: span.spellOut,
      children: [
        for (final child in span.children ?? const <InlineSpan>[])
          _strokeCopy(child, strokePaint),
      ],
    );
  }

  @override
  bool shouldRepaint(RenderEditablePainter? oldDelegate) {
    if (oldDelegate is! EditableTextStrokePainter) return true;
    return !identical(oldDelegate, this) ||
        oldDelegate._color != _color ||
        oldDelegate._width != _width;
  }

  @override
  void dispose() {
    _textPainter.dispose();
    super.dispose();
  }
}
