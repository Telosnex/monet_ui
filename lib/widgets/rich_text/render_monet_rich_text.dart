// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:monet_ui/fonts/font_height_equalizer.g.dart';
import 'package:monet_ui/fonts/text_metrics.dart';
import 'package:monet_ui/widgets/ancestor_raster_scale.dart';
import 'package:monet_ui/widgets/monet_perf_debug_switches.dart';
import 'package:monet_ui/widgets/paint_transform_memo.dart';
import 'package:monet_ui/widgets/raster_cache_diagnostics.dart';
import 'package:monet_ui/widgets/rich_text/direct_paint_inputs.dart';
import 'package:monet_ui/widgets/rich_text/emoji_detection.dart';
import 'package:monet_ui/widgets/rich_text/emoji_paint_spans.dart';
import 'package:monet_ui/widgets/rich_text/monet_rich_text_selectable.dart';
import 'package:monet_ui/widgets/rich_text/paint_strategy.dart';
import 'package:monet_ui/widgets/rich_text/paragrapher.dart';

class MonetRichTextParentData extends ContainerBoxParentData<RenderBox> {
  bool visible = true;
}

class RenderMonetRichText extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, MonetRichTextParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, MonetRichTextParentData>,
        RelayoutWhenSystemFontsChangeMixin {
  RenderMonetRichText({
    required this._textSpan,
    required this._text,
    required this._textStyle,
    required this._maxLines,
    required this._leadingCount,
    List<WidgetSpan> inlineSpans = const [],
    int endCount = 0,
    required this._textDirection,
    required this._ellipsis,
    this._textAlign = .start,
    this._textScaler = .noScaling,
    this._strutStyle,
    this._softWrap = true,
    this._selectionRegistrar,
    this._selectionColor,
    this._paintColorListenable,
    this._paintColor,
    this._paintShadows,
    double? toneForTextMasking,
    this._paintDrivenByAncestor = false,
    // Public constructor parameters: callers are in different libraries from
    // this split render-object file, so they cannot pass private field names.
    bool preferDirectPaint = false,
    bool centerCapHeight = true,
    Color? strokeColor,
    double strokeWidth = 1,
    Color Function()? paintStrokeColor,
    double Function()? paintStrokeWidth,
    required AncestorRasterScaleSignal ancestorRasterScaleSignal,
  }) : assert(
         toneForTextMasking == null ||
             (toneForTextMasking.isFinite &&
                 toneForTextMasking >= 0 &&
                 toneForTextMasking <= 100),
       ),
       _inlineSpans = inlineSpans,
       _endCount = endCount,
       _toneForTextMasking = toneForTextMasking,
       _preferDirectPaint = preferDirectPaint,
       _strokeColor = strokeColor,
       _strokeWidth = strokeWidth,
       _paintStrokeColor = paintStrokeColor,
       _paintStrokeWidth = paintStrokeWidth,
       _ancestorRasterScaleSignal = ancestorRasterScaleSignal,
       _ancestorRasterScale = ancestorRasterScaleSignal.quantizedScale {
    // The field also has a default so objects created before a hot reload
    // have a value.
    _centerCapHeight = centerCapHeight;
    if (!MonetPerfDebugSwitches.disableCachedRendering &&
        (_paintColor != null ||
            _paintShadows != null ||
            _paintStrokeColor != null)) {
      _preferTintForColorAnimation = true;
    }
    updateSelectionRegistrarSubscription();
  }

  // --------------------------------------------------------------------------
  // Stroke
  // --------------------------------------------------------------------------

  Color? _strokeColor;
  double _strokeWidth;
  Color Function()? _paintStrokeColor;
  double Function()? _paintStrokeWidth;
  Color? _lastAncestorStrokeColor;

  /// The stroke on the glyph edges, drawn between the shadows and the fill,
  /// as `MonetIcon` draws it. Null for none.
  set strokeColor(Color? value) {
    if (_strokeColor == value) return;
    final old = _effectiveStroke();
    _strokeColor = value;
    _handleStrokeChanged(old, signalsAnimation: true);
  }

  set strokeWidth(double value) {
    if (_strokeWidth == value) return;
    final old = _effectiveStroke();
    _strokeWidth = value;
    _handleStrokeChanged(old, signalsAnimation: false);
  }

  /// The current stroke color, read at paint time. Replaces [strokeColor].
  set paintStrokeColor(Color Function()? value) {
    if (identical(_paintStrokeColor, value)) return;
    final old = _effectiveStroke();
    _paintStrokeColor = value;
    _handleStrokeChanged(old, signalsAnimation: value != null);
  }

  /// The current outer stroke width, read at paint time. Replaces
  /// [strokeWidth]. Paint-only; layout never reads it.
  set paintStrokeWidth(double Function()? value) {
    if (identical(_paintStrokeWidth, value)) return;
    final old = _effectiveStroke();
    _paintStrokeWidth = value;
    _handleStrokeChanged(old, signalsAnimation: false);
  }

  TextStroke? _effectiveStroke() {
    final width = _paintStrokeWidth?.call() ?? _strokeWidth;
    if (width <= 0) return null;
    final color = _paintStrokeColor?.call() ?? _strokeColor;
    if (color == null || color.a <= 0) return null;
    return TextStroke(color: color, width: width);
  }

  void _handleStrokeChanged(TextStroke? old, {required bool signalsAnimation}) {
    final next = _effectiveStroke();
    if (next == old) return;
    // A stroke colour that changes through rebuilds is animating, as a
    // colour-only style change is.
    if (signalsAnimation &&
        old != null &&
        next != null &&
        !MonetPerfDebugSwitches.disableCachedRendering &&
        !_preferDirectPaint) {
      _preferTintForColorAnimation = true;
    }
    _replanAfterPaintChange();
  }

  /// Repaints for a paint-only change: reuses the retained masks when the
  /// plan keeps its strategy, else rebuilds the paragraph in place.
  void _replanAfterPaintChange() {
    final plan = _paintPlanFor(_layoutResult?.input.text ?? _text);
    if (_canReuseCachedTintMask(plan)) {
      markNeedsPaint();
    } else {
      _markParagraphStale();
    }
  }

  // --------------------------------------------------------------------------
  // Configuration (widget-owned)
  // --------------------------------------------------------------------------

  InlineSpan _textSpan;
  InlineSpan get textSpan => _textSpan;
  String _text;
  String get text => _text;
  TextStyle _textStyle;
  TextStyle get textStyle => _textStyle;
  int? _maxLines;
  int _leadingCount;
  int get leadingCount => _leadingCount;
  List<WidgetSpan> _inlineSpans;
  int get _trailingStart => _leadingCount + _inlineSpans.length;

  /// Number of end children: the last children, after the trailing ones.
  ///
  /// They sit at the end edge of the box, centred on the last line. Every
  /// line is laid out narrower by their width, so text never runs under
  /// them, and the box fills the width it is given.
  int _endCount;
  int get endCount => _endCount;
  int get _endStart => math.max(_trailingStart, childCount - _endCount);

  set endCount(int value) {
    if (_endCount == value) return;
    _endCount = value;
    _markLayoutStale();
  }

  set inlineSpans(List<WidgetSpan> value) {
    if (listEquals(_inlineSpans, value)) return;
    _inlineSpans = value;
    _markLayoutStale();
  }

  TextDirection _textDirection;
  TextDirection get textDirection => _textDirection;
  String _ellipsis;
  TextAlign _textAlign;
  TextScaler _textScaler;
  StrutStyle? _strutStyle;
  bool _softWrap;
  SelectionRegistrar? _selectionRegistrar;
  Color? _selectionColor;
  Color? get selectionColor => _selectionColor;
  Listenable? _paintColorListenable;
  Color Function()? _paintColor;
  List<Shadow> Function()? _paintShadows;
  double? _toneForTextMasking;

  /// Opaque colour a Linux/Windows glyph mask is recorded in. See
  /// [_settleGlyphMaskTone].
  Color? _glyphMaskTone;
  Color? _pendingGlyphMaskTone;
  bool _paintDrivenByAncestor;
  bool _preferDirectPaint;
  bool _centerCapHeight = false;
  // The widget State/scope owns this signal; this render object only listens.
  AncestorRasterScaleSignal _ancestorRasterScaleSignal;
  double _ancestorRasterScale;
  bool _needsAncestorRasterScaleValidation = true;
  Color? _lastAncestorPaintColor;
  List<Shadow>? _lastAncestorPaintShadows;

  // --------------------------------------------------------------------------
  // Derived / cached state
  // --------------------------------------------------------------------------

  /// Populated by [performLayout] and possibly replaced in-place by
  /// [_rebuildParagraphInPlace] when a paint-only property changes.
  ParagraphResult? _layoutResult;
  ParagraphResult? get layoutResult => _layoutResult;
  _PrecomputedTextLayout? _precomputedTextLayout;

  /// Vertical distance from the box origin to the painted paragraph.
  ///
  /// Set by [performLayout]. Zero unless [_centerCapHeight] moves the text.
  double _paragraphTop = 0;

  /// Horizontal distance from the box origin to the painted paragraph.
  ///
  /// Nonzero only in RTL with end children, which then sit at the left edge.
  double _paragraphLeft = 0;

  /// Last font family looked up in libmonet's cap-height table.
  String? _capHeightFamily;
  double? _capHeightEm;

  /// Where the paragraph is painted inside this box.
  ///
  /// Selection geometry uses paragraph coordinates, so it applies this offset
  /// to its transform.
  Offset get paragraphOffset => .new(_paragraphLeft, _paragraphTop);

  /// Owns the long-lived [TextPainter]s. Reusing painters across layouts
  /// is worth ~2× in perf scenarios with truncation (the binary search
  /// would otherwise allocate a painter per probe). See
  /// `test/perf/monet_rich_text_paint_perf_test.dart`.
  final Paragrapher _paragrapher = Paragrapher();

  /// Lays out for intrinsic measurements, [computeDryLayout] and
  /// [computeDryBaseline]. Separate from [_paragrapher]: paint draws from that
  /// paragrapher's painter, and probes can run after [performLayout] without a
  /// new layout pass.
  Paragrapher? _dryParagrapher;

  PaintStrategy _paintStrategy = DirectPaintStrategy();
  bool _maskEvictionRepaintScheduled = false;

  /// Test-only view of the active paint strategy (kind + cached rasters).
  @visibleForTesting
  PaintStrategy debugPaintStrategy() => _paintStrategy;

  late final MonetRichTextSelectable _selectable = MonetRichTextSelectable(
    this,
  );
  SelectionRegistrar? _registeredSelectionRegistrar;

  /// Static text should paint directly in its final colour. The retained-layer
  /// tint path is a performance optimisation for colour animation, but it also
  /// routes glyphs through a compositor colour-filter layer. That layer can
  /// produce tiny raster differences across Skia/font stacks, which makes
  /// static-text goldens noisy. Flip this only after seeing a colour-only style
  /// update; after that, subsequent colour changes reuse the cached glyphs.
  bool _preferTintForColorAnimation = false;

  _Staleness _dirty = .clean;

  /// Monotonic counter advanced every time [_layoutResult] is replaced.
  /// Tint strategies cache a `ui.Picture`/DPR mask image against this; the
  /// next paint rebuilds those cached foreground assets when the counter
  /// advances.
  int _generation = 0;

  // --------------------------------------------------------------------------
  // Setters
  // --------------------------------------------------------------------------

  set textSpan(InlineSpan value) {
    if (_textSpan == value) return;
    _textSpan = value;
    _markLayoutStale();
  }

  set text(String value) {
    if (_text == value) return;
    _text = value;
    markNeedsSemanticsUpdate();
    _markLayoutStale();
  }

  /// Atomically installs widget text and keeps the update paint-only when the
  /// newly shaped paragraph has exactly the previous geometry.
  ///
  /// A clock digit still needs shaping, but if line metrics, placeholders, and
  /// size are unchanged there is no reason to relayout ModContent, its
  /// viewport, the Space tile, and the complete grid. Geometry changes retain
  /// the normal [markNeedsLayout] path with no approximation.
  void updateText({required InlineSpan textSpan, required String text}) {
    if (_textSpan == textSpan && _text == text) return;
    _textSpan = textSpan;
    _text = text;
    markNeedsSemanticsUpdate();

    if (_inlineSpans.isNotEmpty) {
      _markLayoutStale();
      return;
    }
    final previous = _layoutResult;
    if (previous == null || _dirty != .clean || debugNeedsLayout) {
      _markLayoutStale();
      return;
    }

    double trailingWidth = 0;
    RenderBox? child = firstChild;
    var index = 0;
    while (child != null) {
      if (!child.hasSize) {
        _markLayoutStale();
        return;
      }
      if (index >= _trailingStart && index < _endStart) {
        trailingWidth += child.size.width;
      }
      child = childAfter(child);
      index++;
    }

    final paintPlan = _paintPlanFor(text);
    final input = previous.input.copyWith(
      textSpan: textSpan,
      text: text,
      style: paintPlan.layoutStyle,
      paintColor: paintPlan.kind == .direct
          ? _effectivePaintColor()
          : _effectiveGlyphMaskColor(),
    );
    final next = _layoutParagraph(_paragrapher, input, trailingWidth);
    if (!sameParagraphGeometry(previous, next)) {
      _markLayoutStale();
      // performLayout can reuse this exact shaping result. The speculative
      // comparison therefore never turns a geometry-changing update into two
      // paragraph layouts; any later metric/constraint change invalidates it.
      _precomputedTextLayout = _PrecomputedTextLayout(
        requestedInput: input,
        result: next,
        trailingWidth: trailingWidth,
        ellipsis: _ellipsis,
      );
      return;
    }

    _replaceLayoutResult(next);
    _maybeSwapStrategy(paintPlan.kind);
    _dirty = .clean;
    markNeedsPaint();
  }

  // rationale: handled by _classifyStyleChange rather than ==
  // ignore: check-for-equals-in-render-object-setters
  set textStyle(TextStyle value) {
    RasterCacheDiagnostics.record(.text, .textStyleCalls);
    final kind = _classifyStyleChange(_textStyle, value);
    if (kind == .none) {
      RasterCacheDiagnostics.record(.text, .textStyleUnchanged);
      return;
    }
    final previousStyle = _textStyle;
    _textStyle = value;
    switch (kind) {
      case .metrics:
        _markLayoutStale();
      case .colorOnly:
        // A colour-only style update is the signal that this render object is
        // actually animating colour. Static text stays on the direct paint path
        // because the composited colour-filter path can produce tiny,
        // platform-dependent glyph-edge differences in goldens.
        if (!MonetPerfDebugSwitches.disableCachedRendering &&
            !_preferDirectPaint) {
          _preferTintForColorAnimation = true;
        }
        // In cached tint modes the colour lives in the paint-time ColorFilter.
        // The paragraph, foreground picture, and DPR mask image remain valid
        // while Impeller's foreground tone stays on the same side of 0.5 luma;
        // crossing that threshold remasks once. This must cover both plain tint
        // text and layered shadow+tint text.
        // Hovering no-background list tiles changes only foreground colour while
        // keeping the shadow underlay shape stable; regenerating every title and
        // subtitle mask during scroll-over-hover was the raster bottleneck.
        final plan = _paintPlanFor(_layoutResult?.input.text ?? _text);
        if (_canReuseCachedTintMask(plan)) {
          RasterCacheDiagnostics.record(.text, .textStyleMaskReused);
          markNeedsPaint();
        } else {
          // Direct mode bakes colour into the paragraph. Strategy transitions
          // also need an in-place paragraph rebuild, but still no relayout.
          _markParagraphStale();
        }
      case .paintOnly:
        // In layered mode shadows are a separate, paint-time mask. Updating
        // their RGB/shape through the widget must be as cheap as a bus tick,
        // not a fresh foreground paragraph + both raster images at settle.
        // Decoration/foreground/background changes still rebuild coverage.
        if (_nonColourPaintFieldsEqual(
          previousStyle,
          value,
          ignoreShadows: true,
        )) {
          // Shadows that change through rebuilds are animating, as a
          // colour-only change is. Without this, each such rebuild
          // reshaped the paragraph with its shadows baked in.
          if (!MonetPerfDebugSwitches.disableCachedRendering &&
              !_preferDirectPaint) {
            _preferTintForColorAnimation = true;
          }
          final plan = _paintPlanFor(_layoutResult?.input.text ?? _text);
          if (_canReuseCachedTintMask(plan)) {
            RasterCacheDiagnostics.record(.text, .textStyleMaskReused);
            // Count the newly avoided invalidation decision, not an image or
            // a promised later rebuild (several setters may coalesce).
            if (_dirty == .clean) {
              RasterCacheDiagnostics.record(.text, .textStyleShadowReuse);
            }
            markNeedsPaint();
            break;
          }
        }
        _markParagraphStale();
      case .none:
        break;
    }
  }

  set maxLines(int? value) {
    if (_maxLines == value) return;
    _maxLines = value;
    _markLayoutStale();
  }

  set leadingCount(int value) {
    if (_leadingCount == value) return;
    _leadingCount = value;
    _markLayoutStale();
  }

  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    _markLayoutStale();
  }

  set ellipsis(String value) {
    if (_ellipsis == value) return;
    _ellipsis = value;
    _markLayoutStale();
  }

  set textAlign(TextAlign value) {
    if (_textAlign == value) return;
    _textAlign = value;
    _markLayoutStale();
  }

  set textScaler(TextScaler value) {
    if (_textScaler == value) return;
    _textScaler = value;
    _markLayoutStale();
  }

  set strutStyle(StrutStyle? value) {
    if (_strutStyle == value) return;
    _strutStyle = value;
    _markLayoutStale();
  }

  set softWrap(bool value) {
    if (_softWrap == value) return;
    _softWrap = value;
    _markLayoutStale();
  }

  set selectionRegistrar(SelectionRegistrar? value) {
    if (_selectionRegistrar == value) return;
    _selectionRegistrar = value;
    updateSelectionRegistrarSubscription();
  }

  set selectionColor(Color? value) {
    if (_selectionColor == value) return;
    _selectionColor = value;
    if (_selectable.value.hasSelection) {
      markNeedsPaint();
    }
  }

  set paintColorListenable(Listenable? value) {
    if (identical(_paintColorListenable, value)) return;
    final wasRepaintBoundary = isRepaintBoundary;
    if (attached && !_paintDrivenByAncestor) {
      _paintColorListenable?.removeListener(_handlePaintColorChanged);
    }
    _paintColorListenable = value;
    if (attached && !_paintDrivenByAncestor) {
      _paintColorListenable?.addListener(_handlePaintColorChanged);
    }
    if (wasRepaintBoundary != isRepaintBoundary) {
      markNeedsCompositingBitsUpdate();
      markNeedsPaint();
    }
    _handlePaintColorChanged();
  }

  set paintDrivenByAncestor(bool value) {
    if (_paintDrivenByAncestor == value) return;
    final wasRepaintBoundary = isRepaintBoundary;
    if (attached) {
      if (value) {
        _paintColorListenable?.removeListener(_handlePaintColorChanged);
      } else {
        _paintColorListenable?.addListener(_handlePaintColorChanged);
      }
    }
    _paintDrivenByAncestor = value;
    _lastAncestorPaintColor = null;
    _lastAncestorStrokeColor = null;
    _lastAncestorPaintShadows = null;
    if (wasRepaintBoundary != isRepaintBoundary) {
      markNeedsCompositingBitsUpdate();
    }
    markNeedsPaint();
  }

  set preferDirectPaint(bool value) {
    if (_preferDirectPaint == value) return;
    RasterCacheDiagnostics.record(.text, .paintPolicyChanged);
    _preferDirectPaint = value;
    if (value) {
      _preferTintForColorAnimation = false;
    }
    _markParagraphStale();
  }

  set centerCapHeight(bool value) {
    if (_centerCapHeight == value) return;
    _centerCapHeight = value;
    // The shift changes the reported baseline, so parents must lay out again.
    _markLayoutStale();
  }

  set ancestorRasterScaleSignal(AncestorRasterScaleSignal value) {
    if (identical(_ancestorRasterScaleSignal, value)) return;
    if (attached && !_ancestorRasterScaleSignal.isIdentity) {
      _ancestorRasterScaleSignal.removeListener(
        _handleAncestorRasterScaleChanged,
      );
    }
    _ancestorRasterScaleSignal = value;
    _needsAncestorRasterScaleValidation = true;
    if (attached && !value.isIdentity) {
      value.addListener(_handleAncestorRasterScaleChanged);
    }
    _handleAncestorRasterScaleChanged();
  }

  void _handleAncestorRasterScaleChanged() {
    final nextScale = _ancestorRasterScaleSignal.quantizedScale;
    if (_ancestorRasterScale == nextScale) return;
    _ancestorRasterScale = nextScale;
    _needsAncestorRasterScaleValidation = true;
    if (_paintStrategy.kind != .direct) {
      _paintStrategy.invalidateRasterImages();
      markNeedsPaint();
    }
  }

  set paintColor(Color Function()? value) {
    if (identical(_paintColor, value)) return;
    // Widgets supply a fresh closure on every rebuild. Compare what the old
    // and new closures produce so closure churn does not re-run paint planning
    // when the effective colour is unchanged.
    final oldEffective = _effectivePaintColor();
    _paintColor = value;
    if (value != null && !MonetPerfDebugSwitches.disableCachedRendering) {
      _preferTintForColorAnimation = true;
    }
    if (_effectivePaintColor() == oldEffective) return;
    _handlePaintColorChanged();
  }

  set paintShadows(List<Shadow> Function()? value) {
    if (identical(_paintShadows, value)) return;
    // Shadow builders commonly return memoized, identical lists. Keep the
    // elementwise fallback for callers that construct equivalent fresh lists.
    final oldEffective = _effectiveShadows();
    _paintShadows = value;
    if (value != null && !MonetPerfDebugSwitches.disableCachedRendering) {
      _preferTintForColorAnimation = true;
    }
    if (_shadowListsEqual(_effectiveShadows(), oldEffective)) return;
    _handlePaintColorChanged();
  }

  set toneForTextMasking(double? value) {
    assert(
      value == null || (value.isFinite && value >= 0 && value <= 100),
      'toneForTextMasking must be between 0 and 100.',
    );
    if (_toneForTextMasking == value) return;
    final oldMaskColor = _effectiveGlyphMaskColor();
    _toneForTextMasking = value;
    if (_paintStrategy.kind != .direct &&
        oldMaskColor != _effectiveGlyphMaskColor()) {
      _markParagraphStale();
    }
  }

  void _handlePaintColorChanged() {
    if (_paintColor == null &&
        _paintShadows == null &&
        _paintStrokeColor == null &&
        _paintStrokeWidth == null) {
      return;
    }
    // This is the core paint-bus fast path. A MonetPaintColors tick should not
    // call setState or mark layout dirty. It either repaints a retained tinted
    // paragraph, or rebuilds the paragraph in-place with identical geometry when
    // shadows/paint fields changed. See Mod ADR 004.
    if (!MonetPerfDebugSwitches.disableCachedRendering) {
      _preferTintForColorAnimation = true;
    }
    final plan = _paintPlanFor(_layoutResult?.input.text ?? _text);
    if (_canReuseCachedTintMask(plan)) {
      markNeedsPaint();
    } else {
      _markParagraphStale();
    }
  }

  Color _effectivePaintColor() =>
      _paintColor?.call() ?? _textStyle.color ?? _kBlack;

  Color _effectiveGlyphMaskColor() => _impellerCorrectsTextGamma
      ? (_glyphMaskTone ?? _effectivePaintColor().withValues(alpha: 1))
      : _glyphMaskColorFor(
          _effectivePaintColor(),
          toneForTextMasking: _toneForTextMasking,
        );

  /// Keeps a Linux/Windows glyph mask recorded in the text's settled colour.
  ///
  /// Impeller on Linux and Windows boosts glyph coverage by the luma of the
  /// text colour (`impeller/entity/contents/text_contents.cc`). A mask
  /// recorded in another colour has thinner or thicker glyphs than the same
  /// text painted directly. Direct paints record the resting colour, so a
  /// mask created by a colour animation starts at the resting luma. When the
  /// colour then settles at another luma for two paints in a row, the mask
  /// is recorded again. Mid-animation frames reuse the old mask.
  void _settleGlyphMaskTone() {
    if (!_impellerCorrectsTextGamma) return;
    final current = _effectivePaintColor().withValues(alpha: 1);
    if (_paintStrategy.kind == .direct) {
      if (_dirty == .clean) {
        _glyphMaskTone = current;
        _pendingGlyphMaskTone = null;
        return;
      }
      // A stale paragraph may be about to become a mask. Its colour is
      // already an animation frame, so the mask keeps the last resting
      // colour, and this paint counts as the first at the new colour.
      if (_glyphMaskTone != null && _luma(_glyphMaskTone!) != _luma(current)) {
        _pendingGlyphMaskTone = current;
        _scheduleEvictionRepaint();
      }
      return;
    }
    final baked = _glyphMaskTone;
    if (baked == null || _luma(baked) == _luma(current)) {
      _glyphMaskTone ??= current;
      _pendingGlyphMaskTone = null;
      return;
    }
    final pending = _pendingGlyphMaskTone;
    if (pending != null && _luma(pending) == _luma(current)) {
      _glyphMaskTone = current;
      _pendingGlyphMaskTone = null;
      if (_dirty.index < _Staleness.paragraphStale.index) {
        _dirty = .paragraphStale;
      }
      return;
    }
    _pendingGlyphMaskTone = current;
    _scheduleEvictionRepaint();
  }

  List<Shadow> _effectiveShadows() =>
      _paintShadows?.call() ?? _textStyle.shadows ?? const [];

  TextStyle _effectiveTextStyle() {
    final shadows = _paintShadows?.call();
    if (shadows == null || identical(shadows, _textStyle.shadows)) {
      return _textStyle;
    }
    return _textStyle.copyWith(shadows: shadows);
  }

  PaintPlan _paintPlanFor(String text) {
    // Resolve the shadow closure once. Calling `_effectiveShadows` and then
    // `_effectiveTextStyle` used to invoke it twice per plan and create a new
    // TextStyle even when a memoized list was already installed on the style.
    final paintShadows = _paintShadows?.call();
    final shadows = paintShadows ?? _textStyle.shadows ?? const [];
    final style =
        paintShadows == null || identical(paintShadows, _textStyle.shadows)
        ? _textStyle
        : _textStyle.copyWith(shadows: paintShadows);
    final styleWithoutShadows = shadows.isEmpty
        ? style
        : style.copyWith(shadows: const []);
    final stroke = _effectiveStroke();
    // A span with its own colours cannot be painted as one tint. It still
    // takes the same path below, so stroked text keeps its shadows out of
    // the fill style.
    final canTintSpan = _spanCanUseSingleTint(_textSpan);
    if (stroke != null) {
      // Shadows paint under the stroke, so no plan bakes them into the fill.
      // The layered underlay holds shadows and stroke in one tint.
      final layered =
          canTintSpan &&
          !_preferDirectPaint &&
          !MonetPerfDebugSwitches.disableCachedRendering &&
          _preferTintForColorAnimation &&
          strokeSharesUnderlayTint(shadows, stroke) &&
          _canTintWith(text, styleWithoutShadows);
      return PaintPlan(
        kind: layered ? .layeredShadowTint : .direct,
        layoutStyle: styleWithoutShadows,
      );
    }
    if (!canTintSpan ||
        _preferDirectPaint ||
        MonetPerfDebugSwitches.disableCachedRendering) {
      return PaintPlan(kind: .direct, layoutStyle: style);
    }
    if (MonetPerfDebugSwitches.enableSplitEmojiTextTint &&
        _preferTintForColorAnimation &&
        textHasColorEmoji(text) &&
        isUnstyledTextSpan(_textSpan) &&
        (style.decoration == null || style.decoration == .none) &&
        _canTintWith(text, styleWithoutShadows, allowEmoji: true) &&
        emojiPaintSpansFor(text).supported &&
        shadows.isEmpty) {
      return PaintPlan(kind: .emojiTint, layoutStyle: styleWithoutShadows);
    }
    final PaintStrategyKind kind =
        _preferTintForColorAnimation &&
            shadows.isNotEmpty &&
            _canTintWith(text, styleWithoutShadows)
        ? .layeredShadowTint
        : (_shouldUseTintWith(text, style) ? .tint : .direct);
    return PaintPlan(
      kind: kind,
      layoutStyle: kind == .layeredShadowTint ? styleWithoutShadows : style,
    );
  }

  void _refreshAncestorDrivenPaintIfNeeded() {
    if (!_paintDrivenByAncestor) return;
    if (_paintColor == null &&
        _paintShadows == null &&
        _paintStrokeColor == null) {
      return;
    }

    final color = _effectivePaintColor();
    final shadows = _paintShadows?.call();
    final strokeColor = _paintStrokeColor?.call();
    final changed =
        color != _lastAncestorPaintColor ||
        strokeColor != _lastAncestorStrokeColor ||
        !_shadowListsEqual(shadows, _lastAncestorPaintShadows);
    if (!changed) return;

    _lastAncestorPaintColor = color;
    _lastAncestorStrokeColor = strokeColor;
    _lastAncestorPaintShadows = shadows;
    if (!MonetPerfDebugSwitches.disableCachedRendering) {
      _preferTintForColorAnimation = true;
    }
    final plan = _paintPlanFor(_layoutResult?.input.text ?? _text);
    if (!_canReuseCachedTintMask(plan)) {
      if (_dirty.index < _Staleness.paragraphStale.index) {
        _dirty = .paragraphStale;
      }
    }
  }

  /// Whether a color tick can keep the current single cached mask.
  ///
  /// Impeller rasterizes different macOS glyph coverage for dark/light mask
  /// tones. Without an override, crossing the foreground threshold remasks
  /// once; a stable [toneForTextMasking] keeps one mask across those ticks.
  bool _canReuseCachedTintMask(PaintPlan plan) {
    if (plan.kind == .direct || _paintStrategy.kind != plan.kind) return false;
    final layout = _layoutResult;
    return layout != null &&
        layout.input.paintColor == _effectiveGlyphMaskColor();
  }

  bool _shadowListsEqual(List<Shadow>? a, List<Shadow>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final left = a[i];
      final right = b[i];
      if (left.color != right.color ||
          left.offset != right.offset ||
          left.blurRadius != right.blurRadius ||
          spreadOf(left) != spreadOf(right)) {
        return false;
      }
    }
    return true;
  }

  void _markLayoutStale() {
    _precomputedTextLayout = null;
    _dirty = .layoutStale;
    markNeedsLayout();
  }

  void _markParagraphStale() {
    if (_dirty.index < _Staleness.paragraphStale.index) {
      _dirty = .paragraphStale;
    }
    markNeedsPaint();
  }

  @override
  void systemFontsDidChange() {
    _paragrapher.systemFontsDidChange();
    _dryParagrapher?.systemFontsDidChange();
    _paintStrategy.systemFontsDidChange();
    // Font bytes/coverage can change with identical semantic paragraph inputs.
    // Force remasking even if the subsequent layout reports equal geometry.
    _generation++;
    RasterCacheDiagnostics.record(.text, .systemFontsChanged);
    _dirty = .layoutStale;
    super.systemFontsDidChange();
  }

  // Visible for selectable, marked as testing so callers have signal that it's
  // not expected to be used.
  @visibleForTesting
  void updateSelectionRegistrarSubscription() {
    final registered = _registeredSelectionRegistrar;
    final next = _selectionRegistrar;
    final hasContent = _selectable.value.hasContent;

    if (registered != null && (registered != next || !hasContent)) {
      registered.remove(_selectable);
      _registeredSelectionRegistrar = null;
      markNeedsCompositingBitsUpdate();
    }

    if (_registeredSelectionRegistrar == null && next != null && hasContent) {
      next.add(_selectable);
      _registeredSelectionRegistrar = next;
      markNeedsCompositingBitsUpdate();
    }
  }

  void _removeSelectionRegistrarSubscription() {
    final registered = _registeredSelectionRegistrar;
    if (registered == null) return;
    registered.remove(_selectable);
    _registeredSelectionRegistrar = null;
    markNeedsCompositingBitsUpdate();
  }

  // --------------------------------------------------------------------------
  // RenderBox boilerplate
  // --------------------------------------------------------------------------

  /// Leaf-driven paint-bus text is isolated. Ancestor-driven text intentionally
  /// is not: one parent repaint boundary/listener repaints a dense composite
  /// such as a list tile, avoiding one layer/listener per text leaf.
  @override
  bool get isRepaintBoundary =>
      _paintColorListenable != null && !_paintDrivenByAncestor;

  /// Selection may need compositing; paint tint strategies draw inline via
  /// DPR-aware mask images and no longer push retained color-filter layers.
  @override
  bool get alwaysNeedsCompositing => _registeredSelectionRegistrar != null;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    if (!_paintDrivenByAncestor) {
      _paintColorListenable?.addListener(_handlePaintColorChanged);
    }
    if (!_ancestorRasterScaleSignal.isIdentity) {
      _ancestorRasterScaleSignal.addListener(_handleAncestorRasterScaleChanged);
    }
    _handleAncestorRasterScaleChanged();
  }

  @override
  void detach() {
    if (!_paintDrivenByAncestor) {
      _paintColorListenable?.removeListener(_handlePaintColorChanged);
    }
    if (!_ancestorRasterScaleSignal.isIdentity) {
      _ancestorRasterScaleSignal.removeListener(
        _handleAncestorRasterScaleChanged,
      );
    }
    super.detach();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! MonetRichTextParentData) {
      child.parentData = MonetRichTextParentData();
    }
  }

  // --------------------------------------------------------------------------
  // Intrinsic dimensions
  // --------------------------------------------------------------------------

  @override
  double computeMinIntrinsicWidth(double height) =>
      computeMaxIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) {
    final paragrapher = _dryParagrapher ??= Paragrapher();
    final leadingSizes = _collectChildIntrinsicSizes();
    double trailingWidth = 0;
    RenderBox? child = firstChild;
    int i = 0;
    while (child != null) {
      if (i >= _trailingStart) {
        trailingWidth += child.getMaxIntrinsicWidth(.infinity);
      }
      child = childAfter(child);
      i++;
    }
    final result = paragrapher.layout(
      _buildInput(
        textSpan: _textSpan,
        text: _text,
        placeholderSizes: leadingSizes,
        inlineDimensions: _intrinsicInlineDimensions(),
        maxWidth: .infinity,
        paintColor: _paintColorForProbe(),
      ),
    );
    // Ceil: paragraph widths are fractional, and callers (IntrinsicWidth)
    // feed this back as a *tight* layout width. Re-laying the paragraph at
    // exactly its measured fractional width can wrap the last word due to
    // floating-point error, which then ellipsizes text at its maxLines budget.
    final width = (result.size.width + trailingWidth).ceilToDouble();
    return width;
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) {
    final paragrapher = _dryParagrapher ??= Paragrapher();
    final leadingSizes = _collectChildIntrinsicSizes();
    double trailingMaxHeight = 0;
    double endWidth = 0;
    RenderBox? child = firstChild;
    int i = 0;
    while (child != null) {
      if (i >= _trailingStart) {
        final cw = child.getMaxIntrinsicWidth(.infinity);
        trailingMaxHeight = math.max(
          trailingMaxHeight,
          child.getMaxIntrinsicHeight(cw),
        );
        if (i >= _endStart) endWidth += cw;
      }
      child = childAfter(child);
      i++;
    }
    final effectiveWidth = width.isFinite
        ? math.max(0.0, width - endWidth)
        : double.infinity;
    final result = paragrapher.layout(
      _buildInput(
        textSpan: _textSpan,
        text: _text,
        placeholderSizes: leadingSizes,
        inlineDimensions: _intrinsicInlineDimensions(),
        maxWidth: effectiveWidth,
        paintColor: _paintColorForProbe(),
      ),
    );
    double totalHeight = 0;
    for (final line in result.lines) {
      totalHeight += line.height;
    }
    // Tall trailing children pushing the last line up.
    if (result.lines.isNotEmpty &&
        trailingMaxHeight > result.lines.last.height) {
      totalHeight += trailingMaxHeight - result.lines.last.height;
    }
    // Tall leading children pushing the first line up.
    if (result.lines.isNotEmpty && leadingSizes.isNotEmpty) {
      final firstLineH = result.lines.first.height;
      for (final s in leadingSizes) {
        if (s.height > firstLineH) {
          totalHeight = math.max(
            totalHeight,
            totalHeight + s.height - firstLineH,
          );
        }
      }
    }
    // Layout adds this above and below the text to fit the cap-height
    // centring shift (_arrange). Without it, IntrinsicHeight parents
    // overflow by twice the pad.
    final pad = _snapToPixels(
      math.max(
        0,
        _capHeightShiftFor(result).abs() - _capHeightShiftSlackFor(result),
      ),
      _viewDevicePixelRatio,
    );
    return totalHeight + 2 * pad;
  }

  List<Size> _collectChildIntrinsicSizes() {
    final sizes = <Size>[];
    RenderBox? child = firstChild;
    int i = 0;
    while (child != null && i < _leadingCount) {
      final w = child.getMaxIntrinsicWidth(.infinity);
      final h = child.getMaxIntrinsicHeight(w);
      sizes.add(Size(w, h));
      child = childAfter(child);
      i++;
    }
    return sizes;
  }

  PlaceholderDimensions _inlineDimension(
    WidgetSpan span,
    Size size,
    RenderBox child, {
    BoxConstraints? dryConstraints,
  }) {
    final baseline = span.baseline;
    return PlaceholderDimensions(
      size: size,
      alignment: span.alignment,
      baseline: baseline,
      baselineOffset:
          span.alignment == ui.PlaceholderAlignment.baseline && baseline != null
          ? (dryConstraints == null
                ? child.getDistanceToBaseline(baseline)
                : child.getDryBaseline(dryConstraints, baseline))
          : null,
    );
  }

  List<PlaceholderDimensions> _intrinsicInlineDimensions() {
    final dimensions = <PlaceholderDimensions>[];
    var index = 0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if (index >= _leadingCount && index < _trailingStart) {
        final width = child.getMaxIntrinsicWidth(.infinity);
        final constraints = BoxConstraints(maxWidth: width);
        final size = child.getDryLayout(constraints);
        dimensions.add(
          _inlineDimension(
            _inlineSpans[index - _leadingCount],
            size,
            child,
            dryConstraints: constraints,
          ),
        );
      }
      index++;
    }
    return dimensions;
  }

  /// A reasonable colour for intrinsic-sizing. Intrinsics don't paint; this
  /// value feeds `_buildInput` but never reaches a real canvas.
  Color _paintColorForProbe() => _effectivePaintColor();

  // --------------------------------------------------------------------------
  // Layout
  // --------------------------------------------------------------------------

  /// Lays out [input] with [trailingWidth] reserved on its last line.
  ///
  /// Text past `maxLines` is truncated with the ellipsis even without
  /// trailing children. A plain layout would drop it silently at a line
  /// break, so a one-line label too wide for its box showed only its first
  /// word. `layoutReservingTail` returns early when the text fits.
  ParagraphResult _layoutParagraph(
    Paragrapher paragrapher,
    ParagraphInput input,
    double trailingWidth,
  ) {
    if (trailingWidth <= 0 && input.maxLines == null) {
      return paragrapher.layout(input);
    }
    return paragrapher.layoutReservingTail(
      input,
      reservedTailWidth: math.max(0.0, trailingWidth),
      ellipsis: _ellipsis,
    );
  }

  @override
  void performLayout() {
    final maxWidth = constraints.maxWidth;

    // ---- 1. Lay out every child. ------------------------------------------
    final leadingSizes = <Size>[];
    final inlineDimensions = <PlaceholderDimensions>[];
    double trailingWidth = 0;
    double endWidth = 0;

    RenderBox? child = firstChild;
    int i = 0;
    while (child != null) {
      child.layout(
        BoxConstraints.loose(Size(maxWidth, .infinity)),
        parentUsesSize: true,
      );
      if (i < _leadingCount) {
        leadingSizes.add(child.size);
      } else if (i < _trailingStart) {
        final span = _inlineSpans[i - _leadingCount];
        inlineDimensions.add(_inlineDimension(span, child.size, child));
      } else if (i < _endStart) {
        trailingWidth += child.size.width;
      } else {
        endWidth += child.size.width;
      }
      child = childAfter(child);
      i++;
    }

    // ---- 2. Choose tint vs direct WITHOUT a probe layout. ------------------
    // Static text paints directly in its final colour. The retained-layer tint
    // path is enabled only after a colour-only style update proves this render
    // object is in a colour-animation scenario.
    final paintPlan = _paintPlanFor(_text);
    final useTint = paintPlan.kind != .direct;
    final effectivePaintColor = _effectivePaintColor();
    final paintColor = useTint
        ? _effectiveGlyphMaskColor()
        : effectivePaintColor;

    final input = _buildInput(
      textSpan: _textSpan,
      text: _text,
      placeholderSizes: leadingSizes,
      inlineDimensions: inlineDimensions,
      // Every line stops short of the end children.
      maxWidth: math.max(0.0, maxWidth - endWidth),
      paintColor: paintColor,
      styleOverride: paintPlan.layoutStyle,
    );

    // ---- 3. Single authoritative layout. -----------------------------------
    final precomputed = _precomputedTextLayout;
    _precomputedTextLayout = null;
    final ParagraphResult layoutResult;
    if (precomputed != null &&
        precomputed.trailingWidth == trailingWidth &&
        precomputed.ellipsis == _ellipsis &&
        _sameParagraphInput(precomputed.requestedInput, input)) {
      layoutResult = precomputed.result;
    } else {
      layoutResult = _layoutParagraph(_paragrapher, input, trailingWidth);
    }

    // Set before publishing the result: selection reads the paragraph offset.
    final arrangement = _arrange(
      layoutResult: layoutResult,
      childSizes: [
        for (var c = firstChild; c != null; c = childAfter(c)) c.size,
      ],
      previousOffsets: [
        for (var c = firstChild; c != null; c = childAfter(c))
          (c.parentData! as MonetRichTextParentData).offset,
      ],
    );
    _paragraphTop = arrangement.paragraphTop;
    _paragraphLeft = arrangement.paragraphLeft;
    _replaceLayoutResult(layoutResult);

    // ---- 4. Decide / swap paint strategy. ---------------------------------
    _maybeSwapStrategy(paintPlan.kind);

    // ---- 5. Position children and size. -----------------------------------
    child = firstChild;
    i = 0;
    while (child != null) {
      final data = child.parentData! as MonetRichTextParentData;
      data.offset = arrangement.offsets[i];
      data.visible =
          i < _leadingCount ||
          i >= _trailingStart ||
          i < layoutResult.placeholderBoxes.length;
      child = childAfter(child);
      i++;
    }
    size = arrangement.size;
    // Layout is complete even for empty text, which has no lines. Leaving
    // it stale made paint assert after a system font change.
    _dirty = .clean;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _dryLayout(constraints).arrangement.size;

  @override
  double computeDryBaseline(BoxConstraints constraints, TextBaseline baseline) {
    final _DryLayout(:result, :arrangement) = _dryLayout(constraints);
    final distance = result.painter.computeDistanceToActualBaseline(baseline);
    return distance + arrangement.paragraphTop;
  }

  /// Lays out the paragraph and arranges children as [performLayout] would,
  /// without changing this render object's state.
  ///
  _DryLayout _dryLayout(BoxConstraints constraints) {
    final maxWidth = constraints.maxWidth;
    final childConstraints = BoxConstraints.loose(Size(maxWidth, .infinity));
    final childSizes = <Size>[];
    final inlineDimensions = <PlaceholderDimensions>[];
    final previousOffsets = <Offset>[];
    for (var c = firstChild; c != null; c = childAfter(c)) {
      final size = c.getDryLayout(childConstraints);
      final index = childSizes.length;
      if (index >= _leadingCount && index < _trailingStart) {
        inlineDimensions.add(
          _inlineDimension(
            _inlineSpans[index - _leadingCount],
            size,
            c,
            dryConstraints: childConstraints,
          ),
        );
      }
      childSizes.add(size);
      previousOffsets.add((c.parentData! as MonetRichTextParentData).offset);
    }
    final leadingSizes = childSizes.take(_leadingCount).toList();
    final endStart = math.max(_trailingStart, childSizes.length - _endCount);
    var trailingWidth = 0.0;
    var endWidth = 0.0;
    for (var index = _trailingStart; index < childSizes.length; index++) {
      if (index < endStart) {
        trailingWidth += childSizes[index].width;
      } else {
        endWidth += childSizes[index].width;
      }
    }
    final paintPlan = _paintPlanFor(_text);
    final input = _buildInput(
      textSpan: _textSpan,
      text: _text,
      placeholderSizes: leadingSizes,
      inlineDimensions: inlineDimensions,
      maxWidth: math.max(0.0, maxWidth - endWidth),
      paintColor: _paintColorForProbe(),
      styleOverride: paintPlan.layoutStyle,
    );
    final paragrapher = _dryParagrapher ??= Paragrapher();
    final result = _layoutParagraph(paragrapher, input, trailingWidth);
    final arrangement = _arrange(
      layoutResult: result,
      childSizes: childSizes,
      previousOffsets: previousOffsets,
      constraints: constraints,
    );
    return _DryLayout(result: result, arrangement: arrangement);
  }

  /// Child offsets, size and paragraph position for [layoutResult].
  ///
  /// [childSizes] and [previousOffsets] list every child in order. A leading
  /// child without a placeholder box, for example one cut by truncation,
  /// keeps its previous offset.
  ///
  /// The cap-height shift moves only the paragraph. Up to
  /// [_kCapHeightShiftSlackEm], the line box's own space above accents and
  /// below descenders takes the shift. A larger shift grows the box by the
  /// excess, at the top and at the bottom. Growing both sides keeps the box
  /// centred on the capitals, so a parent that centres this box still lines it
  /// up with its other children.
  _Arrangement _arrange({
    required ParagraphResult layoutResult,
    required List<Size> childSizes,
    required List<Offset> previousOffsets,
    BoxConstraints? constraints,
  }) {
    final constraints_ = constraints ?? this.constraints;
    final devicePixelRatio = _viewDevicePixelRatio;
    final exactShift = _capHeightShiftFor(layoutResult);
    final capHeightShift = _snapToPixels(exactShift, devicePixelRatio);
    // Children follow the text's rounding before they are rounded. Rounding
    // each one separately could move them a whole device pixel apart.
    final shiftRoundingError = capHeightShift - exactShift;
    final pad = _snapToPixels(
      math.max(0, exactShift.abs() - _capHeightShiftSlackFor(layoutResult)),
      devicePixelRatio,
    );
    double childY(double centredY) =>
        pad + _snapToPixels(centredY + shiftRoundingError, devicePixelRatio);

    final offsets = List.of(previousOffsets);
    final leadingCount = math.min(_leadingCount, childSizes.length);
    final trailingStart = math.min(_trailingStart, childSizes.length);
    final endStart = math.max(trailingStart, childSizes.length - _endCount);
    final trailingSizes = childSizes.sublist(trailingStart, endStart);
    final endSizes = childSizes.sublist(endStart);
    var trailingWidth = 0.0;
    var trailingMaxHeight = 0.0;
    for (final size in trailingSizes) {
      trailingWidth += size.width;
      trailingMaxHeight = math.max(trailingMaxHeight, size.height);
    }

    // Leading children.
    final metrics = layoutResult.lines;
    final placeholderBoxes = layoutResult.placeholderBoxes;
    final firstLineH = metrics.isNotEmpty ? metrics.first.height : 0.0;
    double leadingCentredY(double height) => (firstLineH - height) / 2;
    for (var i = 0; i < leadingCount && i < placeholderBoxes.length; i++) {
      // Use TextPainter's x for text-flow correctness, override y to
      // centre on the first line (TextPainter's middle alignment excludes
      // leading which produces a slightly wrong baseline offset). Snap y,
      // so a child such as a 17.5 icon in an 18-pixel line at 2x sits on
      // the same device pixel rows as the text. Icons fit their edges to
      // the pixels at their own position (ADR 002, D7).
      offsets[i] = Offset(
        placeholderBoxes[i].left,
        childY(leadingCentredY(childSizes[i].height)),
      );
    }

    // Inline widgets use the paragraph's placeholder alignment and baseline.
    // Do not center or snap them independently of the paragraph.
    for (
      var i = leadingCount;
      i < trailingStart && i < placeholderBoxes.length;
      i++
    ) {
      final box = placeholderBoxes[i];
      offsets[i] = Offset(box.left, pad + box.top + capHeightShift);
    }

    // Trailing children (BiDi-aware).
    if (metrics.isEmpty) {
      var x = 0.0;
      var maxHeight = 0.0;
      for (var j = trailingStart; j < childSizes.length; j++) {
        offsets[j] = Offset(x, 0);
        x += childSizes[j].width;
        maxHeight = math.max(maxHeight, childSizes[j].height);
      }
      return _Arrangement(
        offsets: offsets,
        size: constraints_.constrain(Size(x, maxHeight)),
        paragraphTop: pad + capHeightShift,
        paragraphLeft: 0,
      );
    }

    final lastLine = metrics.last;
    final lastLineTop = _sumHeightsExceptLast(metrics);
    // Trailing and end children are centred on the last line: on its
    // capitals when wrapped text has them measured, else on its box. One
    // line: the cap-height shift already centres the capitals in the box.
    final lastLineCapCentre = _lastLineCapCentre(layoutResult, lastLineTop);
    double lastLineChildY(double height) => childY(
      lastLineCapCentre == null
          ? lastLineTop + (lastLine.height - height) / 2
          // childY adds the shift's rounding error, not the shift: add it.
          : exactShift + lastLineCapCentre - height / 2,
    );
    // In RTL the text's logical end is its visual left edge; trailing
    // widgets sit to the left of the last glyph and are still laid out
    // left to right from there.
    var tx = _textDirection == .rtl
        ? lastLine.left - trailingWidth
        : lastLine.left + lastLine.width;
    for (var j = 0; j < trailingSizes.length; j++) {
      final size = trailingSizes[j];
      offsets[trailingStart + j] = Offset(tx, lastLineChildY(size.height));
      tx += size.width;
    }

    // Size.
    var contentWidth = 0.0;
    for (final line in metrics) {
      contentWidth = math.max(contentWidth, line.left + line.width);
    }
    if (_textDirection == .rtl) {
      // Content extends from the (possibly negative) trailing X to the right
      // edge of the widest line.
      contentWidth = math.max(contentWidth, lastLine.left);
    } else {
      contentWidth = math.max(
        contentWidth,
        lastLine.left + lastLine.width + trailingWidth,
      );
    }
    var totalHeight = pad + lastLineTop + lastLine.height;
    // Child offsets may exceed computed text height (tall leading/trailing).
    // End children are placed below, after this.
    for (var i = 0; i < endStart; i++) {
      if (i >= leadingCount &&
          i < trailingStart &&
          i >= placeholderBoxes.length) {
        continue; // A truncated inline widget contributes no visible height.
      }
      totalHeight = math.max(totalHeight, offsets[i].dy + childSizes[i].height);
    }
    if (endSizes.isEmpty) {
      return _Arrangement(
        offsets: offsets,
        size: constraints_.constrain(Size(contentWidth, totalHeight + pad)),
        paragraphTop: pad + capHeightShift,
        paragraphLeft: 0,
      );
    }

    // End children: at the end edge, centred on the last line, like the
    // trailing ones. The paragraph was laid out narrower by their width.
    var endWidth = 0.0;
    for (final size in endSizes) {
      endWidth += size.width;
    }
    final boxWidth = constraints_.maxWidth.isFinite
        ? constraints_.maxWidth
        : contentWidth + endWidth;
    final isRtl = _textDirection == .rtl;
    // In RTL the end edge is the left: everything else moves right.
    final paragraphLeft = isRtl ? endWidth : 0.0;
    if (paragraphLeft != 0) {
      for (var i = 0; i < endStart; i++) {
        offsets[i] = offsets[i].translate(paragraphLeft, 0);
      }
    }
    var ex = isRtl ? 0.0 : boxWidth - endWidth;
    var endTop = double.infinity;
    for (var j = 0; j < endSizes.length; j++) {
      final size = endSizes[j];
      final y = lastLineChildY(size.height);
      offsets[endStart + j] = Offset(ex, y);
      ex += size.width;
      endTop = math.min(endTop, y);
    }
    // An end child taller than a one-line paragraph would start above the
    // box. Move everything down by that much instead.
    final topInset = math.max(0.0, -endTop);
    if (topInset > 0) {
      for (var i = 0; i < offsets.length; i++) {
        offsets[i] = offsets[i].translate(0, topInset);
      }
    }
    for (var j = 0; j < endSizes.length; j++) {
      totalHeight = math.max(
        totalHeight,
        offsets[endStart + j].dy + endSizes[j].height - topInset,
      );
    }
    return _Arrangement(
      offsets: offsets,
      size: constraints_.constrain(
        Size(boxWidth, totalHeight + pad + topInset),
      ),
      paragraphTop: pad + capHeightShift + topInset,
      paragraphLeft: paragraphLeft,
    );
  }

  /// Distance to move the paragraph down so the text is centred in its box.
  ///
  /// The capitals are centred in the first line box.
  ///
  /// Children are centred on the line box, and the line box spans the font's
  /// ascent and descent. Fonts whose capitals do not sit in the middle of that
  /// span, such as caps-only fonts with empty descender space, otherwise look
  /// misaligned next to centred icons. Every line moves by the same amount, so
  /// wrapped text keeps its line spacing.
  ///
  /// The cap height comes from libmonet's offline glyph measurements. The
  /// baseline and line height come from this layout, so platform differences
  /// in ascent and descent are included.
  ///
  /// Returns zero when the font has no usable cap height ([_capHeightFor]).
  double _capHeightShiftFor(ParagraphResult result) {
    if (!_centerCapHeight || result.lines.isEmpty) return 0;
    final line = result.lines.first;
    final capHeight = _capHeightFor(result, line);
    if (capHeight == null) return 0;
    // Unsnapped: performLayout snaps it together with the children.
    return capHeightCentringShift(
      ascent: line.unscaledAscent,
      lineHeight: line.height,
      baseline: _paintedBaseline(
        result.painter.computeDistanceToActualBaseline(.alphabetic),
      ),
      capHeight: capHeight,
    );
  }

  /// The cap height of [result]'s font, in logical pixels. Null when the
  /// font has no measured cap height, or the measurement exceeds [line]'s
  /// ascent: it is then not a cap band, for example in fonts that draw guide
  /// lines.
  double? _capHeightFor(ParagraphResult result, ui.LineMetrics line) {
    final capHeightEm = _capHeightEmFor(result.input.style.fontFamily);
    if (capHeightEm == null) return null;
    final capHeight = capHeightEm * _fontSizeOf(result);
    if (capHeight <= 0 || capHeight > line.unscaledAscent) return null;
    return capHeight;
  }

  /// The baseline the glyphs of a line are painted on, from [baseline]: the
  /// line's alphabetic baseline, both from the same top.
  ///
  /// Use it, not LineMetrics.baseline. SkParagraph reports
  /// LineMetrics.baseline as the rounded line height minus the descent. It
  /// paints each line's glyphs at its alphabetic baseline rounded to a whole
  /// logical pixel, from the line's top (TextLine::buildTextBlob). The two
  /// can differ by more than half a logical pixel.
  static double _paintedBaseline(double baseline) =>
      (baseline + 0.5).floorToDouble();

  /// [result]'s font size, after text scaling.
  static double _fontSizeOf(ParagraphResult result) => result.input.textScaler
      .scale(result.input.style.fontSize ?? kDefaultFontSize);

  /// Centre of the last line's capitals, from the paragraph top, before the
  /// cap-height shift. Null for one line, or when [_capHeightShiftFor] does
  /// not centre capitals.
  ///
  /// The cap-height shift centres the first line's capitals in the first
  /// line box. Later lines have other heights, for example when an icon makes
  /// the first line taller, so their capitals are off the centre of their
  /// boxes. Children beside the last line follow its capitals instead.
  double? _lastLineCapCentre(ParagraphResult result, double lastLineTop) {
    if (!_centerCapHeight || result.lines.length < 2) return null;
    final line = result.lines.last;
    final capHeight = _capHeightFor(result, line);
    if (capHeight == null) return null;
    return lastLineTop + _paintedBaseline(line.ascent) - capHeight / 2;
  }

  /// [_kCapHeightShiftSlackEm] at the paragraph's font size.
  static double _capHeightShiftSlackFor(ParagraphResult result) =>
      _kCapHeightShiftSlackEm * _fontSizeOf(result);

  /// Rounds [logical] to whole physical pixels, so glyphs are not resampled
  /// at a fractional offset.
  static double _snapToPixels(double logical, double devicePixelRatio) =>
      (logical * devicePixelRatio).roundToDouble() / devicePixelRatio;

  /// Pixel ratio of the view this text is painted into.
  ///
  /// The implicit view can differ: in tests it is the engine's default view,
  /// not `tester.view`, and other windows can have other ratios.
  double get _viewDevicePixelRatio {
    final rootNode = owner?.rootNode;
    if (rootNode is RenderView) return rootNode.configuration.devicePixelRatio;
    return ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1.0;
  }

  double? _capHeightEmFor(String? fontFamily) {
    // Normalizing a family name allocates; families rarely change.
    if (fontFamily != _capHeightFamily) {
      _capHeightFamily = fontFamily;
      _capHeightEm = rasterCapHeightEmForFontFamily(fontFamily);
    }
    return _capHeightEm;
  }

  // --------------------------------------------------------------------------
  // Paragraph input construction
  // --------------------------------------------------------------------------

  ParagraphInput _buildInput({
    required InlineSpan textSpan,
    required String text,
    required List<Size> placeholderSizes,
    List<PlaceholderDimensions> inlineDimensions = const [],
    required double maxWidth,
    required Color paintColor,
    TextStyle? styleOverride,
  }) {
    // An empty visible string with inline placeholders still needs a real
    // text line to reserve the usual line height + baseline. A zero-width
    // space produces no glyph but gives the paragraph something to measure
    // against.
    final effectiveText = (text.isEmpty && placeholderSizes.isNotEmpty)
        ? '\u200B'
        : text;
    final effectiveStyle = styleOverride ?? _effectiveTextStyle();
    return ParagraphInput(
      textSpan: effectiveText == text
          ? textSpan
          : TextSpan(text: effectiveText),
      text: effectiveText,
      style: effectiveStyle,
      paintColor: paintColor,
      direction: _textDirection,
      maxLines: _softWrap ? _maxLines : 1,
      align: _textAlign,
      textScaler: _textScaler,
      strutStyle: _strutStyle,
      // Intentionally not `List.unmodifiable` — _ParagraphInput is
      // documented as immutable-by-contract, and the defensive copy was
      // measurable in profiling (called once per probe).
      placeholderSizes: placeholderSizes,
      inlinePlaceholderDimensions: inlineDimensions,
      // No wrapping still needs the available width for single-line
      // truncation and trailing-child reservation. maxLines above prevents
      // additional lines; an unbounded width would make every title fit.
      maxWidth: maxWidth,
      softWrap: _softWrap,
    );
  }

  // --------------------------------------------------------------------------
  // In-place paragraph rebuild (paint-only style change)
  // --------------------------------------------------------------------------

  void _rebuildParagraphInPlace() {
    RasterCacheDiagnostics.record(.text, .paragraphRebuildCalls);
    final old = _layoutResult;
    if (old == null) return;

    // Decide what strategy would suit the *new* style. Because the change
    // was paint-only (metrics equal), the existing geometry is preserved;
    // we only need the new style/colour to flow into a rebuilt Paragraph.
    final paintPlan = _paintPlanFor(old.input.text);
    final useTint = paintPlan.kind != .direct;
    final effectivePaintColor = _effectivePaintColor();
    final paintColor = useTint
        ? _effectiveGlyphMaskColor()
        : effectivePaintColor;

    final input = old.input.copyWith(
      style: paintPlan.layoutStyle,
      paintColor: paintColor,
    );
    final sameInput = _sameParagraphInput(old.input, input);
    if (sameInput) {
      RasterCacheDiagnostics.record(.text, .paragraphSameInput);
    }
    final sameNativePaint =
        !sameInput &&
        MonetPerfDebugSwitches.reuseDirectTextPaint &&
        paintPlan.kind == .direct &&
        _paintStrategy.kind == .direct &&
        sameNativeDirectParagraphPaint(old.input, input);
    if ((sameInput || sameNativePaint) &&
        _paintStrategy.kind == paintPlan.kind &&
        _paragrapher.isCurrent(old) &&
        input.style.foreground == null &&
        input.style.background == null) {
      // A shared bus can notify even when this label's roles did not change.
      // In particular, emoji must stay on the direct path, but direct does
      // not mean "reshape on every notification". Don't skip real strategy
      // transitions or reuse a painter overwritten by an intrinsic probe.
      // Mutable custom Paint objects cannot be validated by style equality.
      RasterCacheDiagnostics.record(.text, .paragraphRebuildSkipped);
      if (sameNativePaint) {
        RasterCacheDiagnostics.record(.text, .paragraphNativePaintReused);
      }
      _dirty = .clean;
      return;
    }
    _recordParagraphRebuild(old.input, input, paintPlan.kind);
    final newResult = _paragrapher.layout(input);
    _replaceLayoutResult(newResult);
    _maybeSwapStrategy(paintPlan.kind);
    _dirty = .clean;
  }

  void _recordParagraphRebuild(
    ParagraphInput previous,
    ParagraphInput next,
    PaintStrategyKind kind,
  ) {
    // Exactly one category per actual rebuild. Extra counters below are
    // overlapping flags, not additional rebuilds. Never record labels/spans.
    final RasterCacheEvent category;
    if (kind != .direct) {
      category = .paragraphCached;
    } else if (_preferDirectPaint ||
        MonetPerfDebugSwitches.disableCachedRendering) {
      category = .paragraphDirectForced;
    } else if (textHasColorEmoji(next.text)) {
      category = .paragraphDirectEmoji;
      // Presence of shadows does not tell us which paint input changed.
      // Keep these categories exclusive, and count only actual rebuilds.
      final fillChanged =
          previous.paintColor.toARGB32() != next.paintColor.toARGB32();
      final shadowChanged = !nativeParagraphShadowsEqual(
        previous.style.shadows,
        next.style.shadows,
      );
      final RasterCacheEvent rebuild;
      if (fillChanged) {
        rebuild = shadowChanged
            ? .emojiFillAndShadowChanged
            : .emojiFillOnlyChanged;
      } else {
        rebuild = shadowChanged ? .emojiShadowOnlyChanged : .emojiOtherRebuild;
      }
      RasterCacheDiagnostics.record(.text, rebuild);
      if (next.style.shadows?.isNotEmpty ?? false) {
        RasterCacheDiagnostics.record(.text, .paragraphEmojiWithShadows);
      }
    } else if (next.text.length > _kMaxTintCharCount) {
      category = .paragraphDirectLongText;
    } else if (!_canTintWith(next.text, next.style)) {
      category = .paragraphDirectStyle;
    } else {
      category = .paragraphDirectOther;
    }
    RasterCacheDiagnostics.record(.text, category);
    if (_paintStrategy.kind != kind) {
      RasterCacheDiagnostics.record(.text, .paragraphStrategyTransition);
    } else if (kind != .direct && previous.paintColor != next.paintColor) {
      RasterCacheDiagnostics.record(.text, .paragraphMaskToneChanged);
    }
  }

  bool _shouldUseTintWith(String text, TextStyle style) =>
      _preferTintForColorAnimation && _canTintWith(text, style);

  void _replaceLayoutResult(ParagraphResult next) {
    RasterCacheDiagnostics.record(.text, .layoutResultCalls);
    // ParagraphResult no longer owns its painter — `_paragrapher` does —
    // so there's nothing to dispose on the old result. The new result may
    // point at the same painter instance as the old; that's expected and
    // fine because the painter's state was overwritten in place.
    final old = _layoutResult;
    final sameInput = old != null && _sameParagraphInput(old.input, next.input);
    RasterCacheDiagnostics.record(
      .text,
      sameInput ? .layoutInputUnchanged : .layoutInputChanged,
    );
    // Reparenting/ancestor layout can run this with precisely the same
    // paragraph. Layout completion is NOT a new glyph generation. Keep the
    // recorded pictures and images when inputs AND resolved geometry agree.
    // Text/tone/style/constraints/font coverage changes still invalidate.
    final sameCoverage =
        old != null && sameInput && sameParagraphGeometry(old, next);
    if (sameCoverage) {
      RasterCacheDiagnostics.record(.text, .layoutCoverageReused);
      if (old.input.style != next.input.style) {
        // The previous raw-style comparison would have rejected this coverage.
        RasterCacheDiagnostics.record(.text, .layoutSnapshotColorReuse);
      }
    }
    _layoutResult = next;
    if (!sameCoverage) _generation++;
    _selectable.didChangeParagraphLayout();
    updateSelectionRegistrarSubscription();
  }

  void _maybeSwapStrategy(PaintStrategyKind kind) {
    if (_paintStrategy.kind == kind) return;
    RasterCacheDiagnostics.record(.text, .strategyChanged);
    _paintStrategy.dispose();
    _paintStrategy = switch (kind) {
      .direct => DirectPaintStrategy(),
      .tint => TintPaintStrategy(
        onRasterEvicted: _scheduleEvictionRepaint,
        onRequestRepaint: _scheduleEvictionRepaint,
      ),
      .emojiTint => EmojiTintPaintStrategy(
        onRasterEvicted: _scheduleEvictionRepaint,
        onRequestRepaint: _scheduleEvictionRepaint,
      ),
      .layeredShadowTint => LayeredShadowTintPaintStrategy(
        onRasterEvicted: _scheduleEvictionRepaint,
        onRequestRepaint: _scheduleEvictionRepaint,
      ),
    };
    // `alwaysNeedsCompositing` changed; let the framework re-evaluate.
    markNeedsCompositingBitsUpdate();
  }

  /// Discarding the Dart image handle is not enough: a retained display list
  /// can still reference its texture. Repaint the owning boundary/subtree so
  /// LRU and memory-pressure eviction actually release that final reference.
  /// A microtask is required because admission can evict another render object
  /// while the pipeline is in `flushPaint`, where `markNeedsPaint` is illegal.
  void _scheduleEvictionRepaint() {
    if (_maskEvictionRepaintScheduled) return;
    _maskEvictionRepaintScheduled = true;
    scheduleMicrotask(() {
      _maskEvictionRepaintScheduled = false;
      if (attached) markNeedsPaint();
    });
  }

  // --------------------------------------------------------------------------
  // Paint
  // --------------------------------------------------------------------------

  @override
  void paint(PaintingContext context, Offset offset) {
    RasterCacheDiagnostics.record(.text, .paintCalls);
    _refreshAncestorDrivenPaintIfNeeded();

    _settleGlyphMaskTone();
    // Lazily rebuild the paragraph if a paint-only setter dirtied it.
    if (_dirty == .paragraphStale) {
      _rebuildParagraphInPlace();
    }
    assert(
      _dirty == .clean,
      'paint() reached with dirty=$_dirty; a setter marked layoutStale '
      'without triggering markNeedsLayout (or performLayout failed to clear).',
    );

    final layout = _layoutResult;
    if (layout != null) {
      if (_paintStrategy.kind != .direct &&
          _needsAncestorRasterScaleValidation) {
        debugValidateDeclaredAncestorRasterScale(this, _ancestorRasterScale);
        _needsAncestorRasterScaleValidation = false;
      }
      final textOffset = offset + paragraphOffset;
      _selectable.paint(context, textOffset);
      _paintStrategy.paint(
        context,
        textOffset,
        layout,
        _generation,
        _effectivePaintColor(),
        _effectiveShadows(),
        _paintStrategy.kind == .direct
            ? _viewDevicePixelRatio * _directShadowScale()
            : _viewDevicePixelRatio * _ancestorRasterScale,
        _paintStrategy.kind == .direct
            ? null
            : _deviceOriginOf(paragraphOffset),
        stroke: _effectiveStroke(),
      );
    }

    _paintChildren(context, offset);
  }

  double _directShadowScale() {
    if (!_effectiveShadows().any((shadow) => shadow.blurRadius > 0)) return 1;
    // Direct dates can scale after ink measurement without a raster scope.
    // This query is only for native device-space shadow sigma, not cache size.
    final scale = paintTransformForPlacement(
      this,
      declaredScale: _ancestorRasterScale,
    ).getMaxScaleOnAxis();
    return scale.isFinite && scale > 0 ? scale : 1;
  }

  void _paintChildren(PaintingContext context, Offset offset) {
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final data = child.parentData! as MonetRichTextParentData;
      if (data.visible) context.paintChild(child, offset + data.offset);
    }
  }

  /// [local] in physical pixels of the view, when this object's paint
  /// transform is a pure translation. Null otherwise: under scale, rotation,
  /// or an ancestor raster scale a cached mask is resampled anyway.
  ///
  /// The transform is read at paint time. A repaint boundary above that later
  /// moves without repainting this object leaves the value stale until the
  /// next paint.
  Offset? _deviceOriginOf(Offset local) {
    if (_ancestorRasterScale != 1) return null;
    final m = paintTransformForPlacement(this).storage;
    final translationOnly =
        m[0] == 1 &&
        m[5] == 1 &&
        m[10] == 1 &&
        m[15] == 1 &&
        m[1] == 0 &&
        m[2] == 0 &&
        m[3] == 0 &&
        m[4] == 0 &&
        m[6] == 0 &&
        m[7] == 0;
    if (!translationOnly) return null;
    return (Offset(m[12], m[13]) + local) * _viewDevicePixelRatio;
  }

  /// The live foreground, including paint-only palette animation.
  @visibleForTesting
  Color get debugEffectivePaintColor => _effectivePaintColor();

  /// Replays text to a golden canvas without submitting cached glyph images.
  ///
  /// Called after normal painting has refreshed the paragraph. A supplied
  /// [textCanvas] can block the paragraph while retaining its live foreground;
  /// selection and inline children still use the supplied painting context.
  @visibleForTesting
  void debugPaintUncached(
    PaintingContext context,
    Offset offset, {
    Canvas? textCanvas,
  }) {
    final layout = _layoutResult;
    if (layout != null) {
      final textOffset = offset + paragraphOffset;
      _selectable.paint(context, textOffset);
      layout.painter.paint(textCanvas ?? context.canvas, textOffset);
    }
    _paintChildren(context, offset);
  }

  // --------------------------------------------------------------------------
  // Hit testing
  // --------------------------------------------------------------------------

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    RenderBox? child = lastChild;
    while (child != null) {
      final pd = child.parentData! as MonetRichTextParentData;
      if (pd.visible &&
          result.addWithPaintOffset(
            offset: pd.offset,
            position: position,
            hitTest: (BoxHitTestResult result, Offset transformed) {
              return child!.hitTest(result, position: transformed);
            },
          )) {
        return true;
      }
      child = childBefore(child);
    }
    return false;
  }

  @override
  bool hitTestSelf(Offset position) => true;

  // --------------------------------------------------------------------------
  // Baseline
  // --------------------------------------------------------------------------

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    assert(!debugNeedsLayout);
    final distance = _layoutResult?.painter.computeDistanceToActualBaseline(
      baseline,
    );
    return distance == null ? null : distance + _paragraphTop;
  }

  // --------------------------------------------------------------------------
  // Semantics
  // --------------------------------------------------------------------------

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final data = child.parentData! as MonetRichTextParentData;
      if (data.visible) visitor(child);
    }
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..label = _text.replaceAll('\uFFFC', '')
      ..textDirection = _textDirection;
  }

  // --------------------------------------------------------------------------
  // Debug
  // --------------------------------------------------------------------------

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('text', _text))
      ..add(IntProperty('leadingCount', _leadingCount))
      ..add(IntProperty('endCount', _endCount, defaultValue: 0))
      ..add(IntProperty('maxLines', _maxLines, defaultValue: null))
      ..add(StringProperty('ellipsis', _ellipsis))
      ..add(EnumProperty<TextAlign>('textAlign', _textAlign))
      ..add(EnumProperty<TextDirection>('textDirection', _textDirection))
      ..add(FlagProperty('softWrap', value: _softWrap, ifFalse: 'no wrap'))
      ..add(DiagnosticsProperty<PaintStrategy>('paintStrategy', _paintStrategy))
      ..add(
        FlagProperty(
          'paintColorListenable',
          value: _paintColorListenable != null,
          ifTrue: 'paint-listening repaint boundary',
        ),
      )
      ..add(
        FlagProperty(
          'paintShadows',
          value: _paintShadows != null,
          ifTrue: 'dynamic paint shadows',
        ),
      )
      ..add(
        DoubleProperty(
          'toneForTextMasking',
          _toneForTextMasking,
          defaultValue: null,
        ),
      )
      ..add(
        FlagProperty(
          'centerCapHeight',
          value: _centerCapHeight,
          ifFalse: 'cap height not centred',
        ),
      )
      ..add(DoubleProperty('paragraphTop', _paragraphTop, defaultValue: 0))
      ..add(
        FlagProperty(
          'didTruncate',
          value: _layoutResult?.didTruncate ?? false,
          ifTrue: 'truncated',
        ),
      );
  }

  // --------------------------------------------------------------------------
  // Lifecycle
  // --------------------------------------------------------------------------

  @override
  void dispose() {
    _paintColorListenable?.removeListener(_handlePaintColorChanged);
    if (!_ancestorRasterScaleSignal.isIdentity) {
      _ancestorRasterScaleSignal.removeListener(
        _handleAncestorRasterScaleChanged,
      );
    }
    _removeSelectionRegistrarSubscription();
    _selectable.dispose();
    _paintStrategy.dispose();
    _paragrapher.dispose();
    _dryParagrapher?.dispose();
    _precomputedTextLayout = null;
    _layoutResult = null;
    super.dispose();
  }
}

/// Classifies how [a] and [b] differ so the render object can pick the
/// minimal pipeline action. Lives in one place so that upstream additions
/// to [TextStyle] only need to be reconsidered here.
///
/// Hot path: the hover-animation case drives this at 60+ calls per second,
/// so we avoid `TextStyle.copyWith` entirely. Instead, directly check
/// whether all non-colour paint fields are equal; if so and colour
/// differs, it's `colorOnly`. Profiling with 60-frame hover animations
/// showed the earlier `copyWith`-based version allocating a TextStyle per
/// frame, ~1.3% of total self time.
_StyleChangeKind _classifyStyleChange(TextStyle a, TextStyle b) {
  if (identical(a, b) || a == b) return .none;
  if (!metricsEqual(a, b)) return .metrics;
  if (!_nonColourPaintFieldsEqual(a, b)) return .paintOnly;
  return a.color == b.color ? .none : .colorOnly;
}

enum _StyleChangeKind {
  /// `a == b`, or differs only in fields `_Paragrapher` does not read.
  none,

  /// Only [TextStyle.color] differs. In tint mode no paragraph rebuild is
  /// needed.
  colorOnly,

  /// A paint-affecting field differs (shadows, decoration, foreground,
  /// background, etc.) but metrics are equal. The paragraph must be
  /// rebuilt, but geometry is preserved — no relayout.
  paintOnly,

  /// A metrics-affecting field differs (font size, family, weight,
  /// letterSpacing, ...). Full relayout required.
  metrics,
}

/// All paint-relevant fields except [TextStyle.color]. Used together with
/// a colour comparison to decide between `colorOnly` and `paintOnly`
/// without the allocation cost of `TextStyle.copyWith`.
bool _nonColourPaintFieldsEqual(
  TextStyle a,
  TextStyle b, {
  bool ignoreShadows = false,
}) {
  return a.backgroundColor == b.backgroundColor &&
      (ignoreShadows || listEquals(a.shadows, b.shadows)) &&
      a.decoration == b.decoration &&
      a.decorationColor == b.decorationColor &&
      a.decorationStyle == b.decorationStyle &&
      a.decorationThickness == b.decorationThickness &&
      a.foreground == b.foreground &&
      a.background == b.background;
}

// ============================================================================
// Tint-safety predicates & constants
// ============================================================================

const Color _kBlack = Color(0xFF000000);
const Color _kWhite = Color(0xFFFFFFFF);

/// Chooses the source color for an alpha-only cached glyph mask.
///
/// Mirrors Flutter engine PR #186074: CoreText glyph coverage depends on the
/// foreground tone, so macOS rasterizes black/white atlas variants at BT.709
/// luma `> 0.5`. The fix stayed off iOS to avoid extra atlas/staging cost where
/// high DPI made the defect less visible. See
/// `impeller/typographer/font_glyph_pair.h` and
/// `impeller/typographer/backends/skia/typographer_context_skia.cc`.
///
/// Linux/Windows instead apply continuous luma correction in
/// `impeller/entity/contents/text_contents.cc` and `shaders/glyph_atlas.frag`.
/// Those platforms record masks in the settled text colour instead; see
/// `_settleGlyphMaskTone`.
/// When [toneForTextMasking] is supplied, it replaces the animated foreground
/// as the tone source. Passing the resting text tone anchors one cached mask
/// while the animated foreground intentionally crosses the threshold, then
/// avoids a mask swap as that foreground returns to rest.
Color _glyphMaskColorFor(Color foreground, {double? toneForTextMasking}) {
  if (kIsWeb || defaultTargetPlatform != .macOS) return _kBlack;
  final luma = toneForTextMasking == null
      ? foreground.r * 0.2126 + foreground.g * 0.7152 + foreground.b * 0.0722
      : toneForTextMasking / 100;
  return luma > 0.5 ? _kWhite : _kBlack;
}

/// Whether Impeller boosts glyph coverage by text luma on this platform.
bool get _impellerCorrectsTextGamma =>
    !kIsWeb &&
    (defaultTargetPlatform == .linux || defaultTargetPlatform == .windows);

/// Rec. 709 luma, as Impeller computes it for text gamma correction.
double _luma(Color c) => c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722;

/// Cheap pre-layout rejection for prose. Physical raster bytes are bounded
/// authoritatively by the process-wide budget in `paint_strategy.dart`; this
/// also avoids recording a vector picture for obviously unsuitable text.
const int _kMaxTintCharCount = 2000;

bool _spanCanUseSingleTint(InlineSpan span) {
  if (span is! TextSpan) return false;
  final style = span.style;
  if (style != null &&
      (style.color != null ||
          style.foreground != null ||
          style.background != null ||
          style.backgroundColor != null ||
          style.decorationColor != null ||
          (style.shadows?.isNotEmpty ?? false))) {
    return false;
  }
  return span.children?.every(_spanCanUseSingleTint) ?? true;
}

bool _canTintWith(String text, TextStyle style, {bool allowEmoji = false}) {
  // Any drawing whose colour is independent of `style.color` would be
  // incorrectly recoloured by `ColorFilter.mode(..., srcIn)`. Exclude
  // these up front so the tint path is only chosen when the effective
  // colour of every painted pixel is derivable from `style.color` alone.
  if (style.foreground != null) return false;
  if (style.background != null) return false;
  if (style.backgroundColor != null) return false;
  // `shadows` each carry their own colour; a red drop shadow under black
  // text would turn blue on a hover-blue tint, which is almost always
  // not what the author meant. Even though V2 only switches to tint after
  // observing colour animation, the tint-safety predicate still has to be
  // conservative.
  if (style.shadows != null && style.shadows!.isNotEmpty) return false;
  // An explicit decoration colour is similarly independent of `style.color`.
  // When `decorationColor` is null the decoration inherits the text colour,
  // which tints correctly.
  if (style.decoration != null &&
      style.decoration != .none &&
      style.decorationColor != null) {
    return false;
  }
  if (text.length > _kMaxTintCharCount) return false;
  if (!allowEmoji && textHasColorEmoji(text)) return false;
  return true;
}

/// Cap-height shift, in em, that the line box absorbs without growing.
///
/// A font's ascent and descent usually leave space above its accents and
/// below its descenders. Growing the box for every shift would make most
/// labels a device pixel taller on each side.
const _kCapHeightShiftSlackEm = 0.1;

/// Child offsets, size and paragraph position of one layout.
final class const _Arrangement({
  required final List<Offset> offsets,
  required final Size size,
  required final double paragraphTop,
  required final double paragraphLeft,
});

/// A dry layout's paragraph and arrangement.
final class const _DryLayout({
  required final ParagraphResult result,
  required final _Arrangement arrangement,
});

final class _PrecomputedTextLayout {
  const _PrecomputedTextLayout({
    required this.requestedInput,
    required this.result,
    required this.trailingWidth,
    required this.ellipsis,
  });

  final ParagraphInput requestedInput;
  final ParagraphResult result;
  final double trailingWidth;
  final String ellipsis;
}

bool _sameParagraphInput(ParagraphInput a, ParagraphInput b) =>
    a.textSpan == b.textSpan &&
    a.text == b.text &&
    // ParagraphInput overrides style.color with paintColor. Comparing the
    // unused snapshot color invalidates tint masks during unrelated relayouts.
    a.effectiveStyle == b.effectiveStyle &&
    a.paintColor == b.paintColor &&
    a.direction == b.direction &&
    a.maxLines == b.maxLines &&
    a.align == b.align &&
    a.textScaler == b.textScaler &&
    a.strutStyle == b.strutStyle &&
    listEquals(a.placeholderSizes, b.placeholderSizes) &&
    listEquals(a.inlinePlaceholderDimensions, b.inlinePlaceholderDimensions) &&
    a.maxWidth == b.maxWidth &&
    a.softWrap == b.softWrap;

double _sumHeightsExceptLast(List<ui.LineMetrics> metrics) {
  double top = 0;
  for (int j = 0; j < metrics.length - 1; j++) {
    top += metrics[j].height;
  }
  return top;
}

enum _Staleness {
  clean,

  /// A paint-affecting (not metrics-affecting) property changed. The next
  /// [RenderMonetRichText.paint] call rebuilds the paragraph in place
  /// using the same geometry and new style; no relayout cascades.
  paragraphStale,

  /// A metrics-affecting or structural property changed; `markNeedsLayout`
  /// has fired and the next pipeline tick will `performLayout`.
  layoutStale,
}
