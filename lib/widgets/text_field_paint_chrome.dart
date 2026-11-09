import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'package:material_ui/material_ui.dart';

/// Colors a paint-bus-driven text field needs per tick.
class TextFieldPaintColors {
  const TextFieldPaintColors({
    required this.content,
    required this.cursor,
    required this.border,
    required this.focusedBorder,
    required this.fill,
  });

  /// Input text + hint text color.
  final Color content;
  final Color cursor;
  final Color border;
  final Color focusedBorder;

  /// Shape fill behind the field (the decoration's own fillColor must be
  /// transparent in paint-driven mode).
  final Color fill;
}

/// Paint-bus chrome for a [TextField]: delivers all animated colors at
/// paint/render time so wallpaper theme motion causes ZERO widget rebuilds.
///
/// Forked from the TextField color path rather than the widget: TextField,
/// InputDecorator and EditableText all deliver colors through constructors,
/// so with stock plumbing every color tick rebuilds the entire field and —
/// worse — restarts InputDecorator's 167ms border tween at the bus rate.
/// Instead:
///
///  * The themed border is painted here, over the child, with the current
///    palette + focus state. The child's own InputDecoration must use
///    transparent borders of matching widths (see TFID paintDrivenChrome).
///  * Input text, hint text and cursor are recolored at the RENDER level:
///    [RenderEditable.text], [RenderEditable.cursorColor] and
///    [RenderParagraph.text] are public mutable properties, and
///    [TextSpan.compareTo] reports color-only changes as
///    [RenderComparison.paint], so recoloring is a paint-only update with no
///    relayout and no element rebuilds.
///
/// The widget layer should build with the CURRENT palette value (via a
/// non-subscribing read); any natural rebuild then agrees with what this
/// render object last applied. After the bus settles, the last tick leaves
/// the settled colors in place.
///
/// [resolveColors] is called from paint/tick contexts and must not read
/// inherited widgets.
class TextFieldPaintChrome extends SingleChildRenderObjectWidget {
  const TextFieldPaintChrome({
    super.key,
    required this.repaint,
    required this.focusNode,
    required this.resolveColors,
    required super.child,
  });

  final Listenable repaint;
  final FocusNode focusNode;
  final TextFieldPaintColors Function() resolveColors;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderTextFieldPaintChrome(
        repaint,
        focusNode,
        resolveColors,
        Theme.of(context).inputDecorationTheme.border ??
            const OutlineInputBorder(),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderTextFieldPaintChrome renderObject,
  ) {
    renderObject
      ..repaint = repaint
      ..focusNode = focusNode
      ..resolveColors = resolveColors
      ..border =
          Theme.of(context).inputDecorationTheme.border ??
          const OutlineInputBorder();
  }
}

class RenderTextFieldPaintChrome extends RenderProxyBox {
  RenderTextFieldPaintChrome(
    this._repaint,
    this._focusNode,
    this.resolveColors,
    this._border,
  );

  TextFieldPaintColors Function() resolveColors;

  InputBorder _border;
  set border(InputBorder value) {
    if (_border == value) return;
    _border = value;
    markNeedsPaint();
  }

  Listenable _repaint;
  set repaint(Listenable value) {
    if (identical(_repaint, value)) return;
    if (attached) _repaint.removeListener(_onTick);
    _repaint = value;
    if (attached) _repaint.addListener(_onTick);
    markNeedsPaint();
  }

  FocusNode _focusNode;
  set focusNode(FocusNode value) {
    if (identical(_focusNode, value)) return;
    if (attached) _focusNode.removeListener(_onFocusChange);
    _focusNode = value;
    if (attached) _focusNode.addListener(_onFocusChange);
    markNeedsPaint();
  }

  /// Last content color applied to descendants; skips the subtree walk while
  /// the bus ticks but colors are stable (i.e. most of the time).
  Color? _appliedContent;
  Color? _appliedCursor;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _repaint.addListener(_onTick);
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void detach() {
    _repaint.removeListener(_onTick);
    _focusNode.removeListener(_onFocusChange);
    super.detach();
  }

  void _onFocusChange() {
    if (attached) markNeedsPaint();
  }

  void _onTick() {
    if (!attached) return;
    final colors = resolveColors();
    if (colors.content != _appliedContent || colors.cursor != _appliedCursor) {
      _recolorDescendants(colors);
    }
    markNeedsPaint();
  }

  /// The chrome is NOT the only writer of these spans: the widget layer
  /// (InputDecorator internals, EditableText, the selectable hint) rebuilds
  /// on its own schedule and resets span colors to build-snapshot values —
  /// proven to happen between a tick's recolor and the same frame's paint,
  /// and (fatally) on the final frame of a glide, after which no tick ever
  /// repairs it because [_appliedContent] believes the work is done.
  ///
  /// So: verify at paint time (read-only walk — legal during paint) and, on
  /// mismatch, repair in a post-frame callback (mutation — legal there).
  /// Converges in one frame at rest; during pathological per-frame rebuilds
  /// the colors trail by a single frame, which is imperceptible.
  bool _repairScheduled = false;

  void _verifyAppliedColors(TextFieldPaintColors colors) {
    if (_repairScheduled) return;
    bool differs(Color? onScreen, Color expected) =>
        onScreen != null && onScreen != expected;
    var mismatch = false;
    void visit(RenderObject node) {
      if (mismatch) return;
      if (node is RenderEditable) {
        final span = node.text;
        mismatch =
            differs(span?.style?.color, colors.content) ||
            differs(node.cursorColor, colors.cursor);
        return;
      }
      if (node is RenderParagraph) {
        final span = node.text;
        mismatch =
            span is TextSpan && differs(span.style?.color, colors.content);
        return;
      }
      node.visitChildren(visit);
    }

    visitChildren(visit);
    if (!mismatch) return;
    _repairScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _repairScheduled = false;
      if (!attached) return;
      _recolorDescendants(resolveColors());
      markNeedsPaint();
    });
  }

  /// Recolors input text (RenderEditable), hint text (RenderParagraph) and
  /// the cursor. Color-only span updates are RenderComparison.paint: no
  /// relayout, no rebuild.
  void _recolorDescendants(TextFieldPaintColors colors) {
    _appliedContent = colors.content;
    _appliedCursor = colors.cursor;
    void visit(RenderObject node) {
      if (node is RenderEditable) {
        node.cursorColor = colors.cursor;
        final span = node.text;
        if (span != null) {
          node.text = _recolored(span, colors.content);
        }
        return; // Nothing color-bearing below a RenderEditable.
      }
      if (node is RenderParagraph) {
        node.text = _recolored(node.text, colors.content);
        return;
      }
      node.visitChildren(visit);
    }

    visitChildren(visit);
  }

  static InlineSpan _recolored(InlineSpan span, Color color) {
    if (span is! TextSpan) return span;
    return TextSpan(
      text: span.text,
      children: span.children == null
          ? null
          : [for (final child in span.children!) _recolored(child, color)],
      style: (span.style ?? const TextStyle()).copyWith(color: color),
      recognizer: span.recognizer,
      mouseCursor: span.mouseCursor,
      onEnter: span.onEnter,
      onExit: span.onExit,
      semanticsLabel: span.semanticsLabel,
      locale: span.locale,
      spellOut: span.spellOut,
    );
  }

  final Paint _fillPaint = Paint()..isAntiAlias = true;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) {
      super.paint(context, offset);
      return;
    }
    final colors = resolveColors();
    _verifyAppliedColors(colors);
    final focused = _focusNode.hasFocus;
    final rect = offset & size;
    final border = _border.copyWith(
      borderSide: BorderSide(
        width: focused ? 2 : 1,
        color: focused ? colors.focusedBorder : colors.border,
      ),
    );
    // Fill under the child (InputDecorator's own fill is transparent in
    // paint-driven mode), border over it.
    if (colors.fill.a > 0) {
      _fillPaint.color = colors.fill;
      context.canvas.drawPath(border.getOuterPath(rect), _fillPaint);
    }
    super.paint(context, offset);
    border.paint(context.canvas, rect);
  }
}
