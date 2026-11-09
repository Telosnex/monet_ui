import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:monet_ui/widgets/ancestor_raster_scale.dart';
import 'package:monet_ui/widgets/icon_glyph_baseline.dart';
import 'package:monet_ui/widgets/monet_perf_debug_switches.dart';
import 'package:monet_ui/widgets/paint_transform_memo.dart';
import 'package:monet_ui/widgets/raster_cache_diagnostics.dart';
import 'package:monet_ui/widgets/snapped_icons/icon_grid_fit.dart';
import 'package:monet_ui/widgets/snapped_icons/icon_outline.dart';
import 'package:monet_ui/widgets/snapped_icons/icon_shadow.dart';

final _cache = IconPathCache();

/// Draws [icon] as a [size] square: from [outline], with straight edges on
/// device pixels, or from the font when [outline] is null.
///
/// Lays out, paints, hit tests and reports intrinsic sizes and baselines the
/// way [Icon] does for its glyph.
class IconBox extends LeafRenderObjectWidget {
  const IconBox({
    super.key,
    required this.icon,
    required this.outline,
    required this.size,
    required this.color,
    this.flipX = false,
    this.shadows,
    this.blendMode,
    this.fontWeight,
    this.fontVariations,
    this.strokeColor,
    this.strokeWidth = 1,
    this.paintStrokeColor,
    this.paintColorListenable,
    this.paintColor,
    this.paintShadows,
    this.paintDrivenByAncestor = false,
  });

  /// See MonetIcon.strokeColor.
  final Color? strokeColor;

  /// The visible outer stroke width in logical pixels.
  final double strokeWidth;
  final Color Function()? paintStrokeColor;

  /// The glyph. Its text baseline is the box's baseline, and the glyph
  /// source draws it.
  final IconData icon;

  /// The icon's outline. Null draws [icon] with the font (ADR 002, D4).
  final IconOutline? outline;

  final double size;
  final Color color;

  /// Mirrors the icon left to right, as [Icon] does for
  /// [IconData.matchTextDirection] icons in right-to-left text.
  final bool flipX;

  /// Drawn under the icon, in order, as text shadows are. A [BoxShadow]
  /// with a [BoxShadow.spreadRadius] also draws a ring that wide around the
  /// icon, blurred as the shadow is, as text does.
  final List<Shadow>? shadows;

  final BlendMode? blendMode;

  /// Font weight and variations of a glyph drawn with the font.
  final FontWeight? fontWeight;
  final List<FontVariation>? fontVariations;

  /// When this notifies, the box repaints with [paintColor] and
  /// [paintShadows], without a rebuild or a relayout (Mod ADR 004).
  final Listenable? paintColorListenable;

  /// The current color. Replaces [color] when set. Called at paint time, so
  /// keep it cheap.
  final Color Function()? paintColor;

  /// The current shadows. Replace [shadows] when set. Called at paint time.
  final List<Shadow> Function()? paintShadows;

  /// An ancestor listens to the paint bus and repaints this box. The box
  /// then neither listens nor is a repaint boundary, so one listener and
  /// one layer serve a whole list tile.
  final bool paintDrivenByAncestor;

  @override
  RenderIconBox createRenderObject(BuildContext context) => .new(
    icon: icon,
    outline: outline,
    iconSize: size,
    color: color,
    flipX: flipX,
    shadows: shadows,
    blendMode: blendMode,
    fontWeight: fontWeight,
    fontVariations: fontVariations,
    mediaPixelRatio: MediaQuery.maybeDevicePixelRatioOf(context),
    paintColorListenable: paintColorListenable,
    paintColor: paintColor,
    paintShadows: paintShadows,
    paintDrivenByAncestor: paintDrivenByAncestor,
    strokeColor: strokeColor,
    strokeWidth: strokeWidth,
    paintStrokeColor: paintStrokeColor,
    rasterScaleSignal: AncestorRasterScaleScope.of(context),
  );

  @override
  void updateRenderObject(BuildContext context, RenderIconBox renderObject) {
    renderObject
      ..icon = icon
      ..outline = outline
      ..iconSize = size
      ..color = color
      ..flipX = flipX
      ..shadows = shadows
      ..blendMode = blendMode
      ..fontWeight = fontWeight
      ..fontVariations = fontVariations
      ..mediaPixelRatio = MediaQuery.maybeDevicePixelRatioOf(context)
      ..paintColorListenable = paintColorListenable
      ..paintDrivenByAncestor = paintDrivenByAncestor
      ..paintColor = paintColor
      ..paintShadows = paintShadows
      ..strokeColor = strokeColor
      ..strokeWidth = strokeWidth
      ..paintStrokeColor = paintStrokeColor
      ..rasterScaleSignal = AncestorRasterScaleScope.of(context);
  }
}

class RenderIconBox extends RenderBox with RelayoutWhenSystemFontsChangeMixin {
  RenderIconBox({
    required this._icon,
    required this._outline,
    required this._iconSize,
    required this._color,
    required this._flipX,
    required this._shadows,
    required this._blendMode,
    this._fontWeight,
    this._fontVariations,
    required this._mediaPixelRatio,
    this._paintColorListenable,
    this._paintColor,
    this._paintShadows,
    this._paintDrivenByAncestor = false,
    this._strokeColor,
    this._strokeWidth = 1,
    this._paintStrokeColor,
    AncestorRasterScaleSignal? rasterScaleSignal,
  }) : _rasterScaleSignal = rasterScaleSignal ?? .identity;

  /// Paints since start, in debug builds, for tests.
  @visibleForTesting
  static int debugPaintCount = 0;

  /// Whether the last paint snapped the outline to device pixels, for tests.
  @visibleForTesting
  bool? debugLastPaintSnapped;

  IconData _icon;
  set icon(IconData value) {
    if (value == _icon) return;
    _icon = value;
    markNeedsLayout();
  }

  IconOutline? _outline;
  set outline(IconOutline? value) {
    if (identical(value, _outline)) return;
    _outline = value;
    // An outline icon draws no text.
    if (value != null) _glyph.dispose();
    markNeedsPaint();
  }

  FontWeight? _fontWeight;
  set fontWeight(FontWeight? value) {
    if (value == _fontWeight) return;
    _fontWeight = value;
    markNeedsPaint();
  }

  List<FontVariation>? _fontVariations;
  set fontVariations(List<FontVariation>? value) {
    if (listEquals(value, _fontVariations)) return;
    _fontVariations = value;
    markNeedsPaint();
  }

  /// Paragraphs of the glyph source (D4), one per paint pass.
  final _glyph = _GlyphPasses();

  /// This icon's shadow images in [IconShadowCache].
  final _shadowMemo = IconShadowMemo();

  /// Vector blurs in this icon's last paint, in [IconVectorBlurCensus].
  var _vectorBlurs = 0;

  void _reportVectorBlurs(int blurs) {
    IconVectorBlurCensus.update(_vectorBlurs, blurs);
    _vectorBlurs = blurs;
  }

  /// The previous paint, while [MonetPerfDebugSwitches.classifyIconPaints]
  /// is on.
  _PaintRecord? _lastPaint;

  /// What marked this icon for paint since its last paint, for
  /// [MonetPerfDebugSwitches.classifyIconPaints]. Unset when the icon
  /// paints only because the layer it paints into repaints.
  bool _markedByBus = false;
  bool _markedByRasterScale = false;
  bool _markedSelf = false;

  /// The colors of the last paint. A bus tick that resolves the same
  /// colors is skipped: the paint would draw the same pixels.
  _PaintedColors? _paintedColors;

  void _markNeedsPaintForBus() {
    final painted = _paintedColors;
    if (painted != null && MonetPerfDebugSwitches.skipSameColorBusTicks) {
      if (_effectiveColor == painted.color &&
          _effectiveStrokeColor == painted.stroke &&
          listEquals(_effectiveShadows, painted.shadows)) {
        RasterCacheDiagnostics.record(.icon, .iconBusTickSkipped);
        return;
      }
    }
    _markedByBus = true;
    markNeedsPaint();
  }

  void _markNeedsPaintForRasterScale() {
    _markedByRasterScale = true;
    markNeedsPaint();
  }

  @override
  void markNeedsPaint() {
    _markedSelf = true;
    super.markNeedsPaint();
  }

  @override
  void dispose() {
    _glyph.dispose();
    super.dispose();
  }

  double _iconSize;
  set iconSize(double value) {
    if (value == _iconSize) return;
    _iconSize = value;
    markNeedsLayout();
  }

  Color _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    _markNeedsPaintIfColorsChanged();
  }

  bool _flipX;
  set flipX(bool value) {
    if (value == _flipX) return;
    _flipX = value;
    markNeedsPaint();
  }

  List<Shadow>? _shadows;
  set shadows(List<Shadow>? value) {
    if (listEquals(value, _shadows)) return;
    _shadows = value;
    _markNeedsPaintIfColorsChanged();
  }

  Listenable? _paintColorListenable;
  set paintColorListenable(Listenable? value) {
    if (identical(value, _paintColorListenable)) return;
    final wasRepaintBoundary = isRepaintBoundary;
    if (attached && !_paintDrivenByAncestor) {
      _paintColorListenable?.removeListener(_markNeedsPaintForBus);
      value?.addListener(_markNeedsPaintForBus);
    }
    _paintColorListenable = value;
    _boundaryMayHaveChanged(wasRepaintBoundary);
  }

  bool _paintDrivenByAncestor;
  set paintDrivenByAncestor(bool value) {
    if (value == _paintDrivenByAncestor) return;
    final wasRepaintBoundary = isRepaintBoundary;
    if (attached) {
      if (value) {
        _paintColorListenable?.removeListener(_markNeedsPaintForBus);
      } else {
        _paintColorListenable?.addListener(_markNeedsPaintForBus);
      }
    }
    _paintDrivenByAncestor = value;
    _boundaryMayHaveChanged(wasRepaintBoundary);
  }

  void _boundaryMayHaveChanged(bool wasRepaintBoundary) {
    if (wasRepaintBoundary == isRepaintBoundary) return;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  // Widgets pass fresh closures on each build. Repaint only when what they
  // return differs from the last paint.
  Color Function()? _paintColor;
  set paintColor(Color Function()? value) {
    if (identical(value, _paintColor)) return;
    _paintColor = value;
    _markNeedsPaintIfColorsChanged();
  }

  List<Shadow> Function()? _paintShadows;
  set paintShadows(List<Shadow> Function()? value) {
    if (identical(value, _paintShadows)) return;
    _paintShadows = value;
    _markNeedsPaintIfColorsChanged();
  }

  Color? _strokeColor;
  set strokeColor(Color? value) {
    if (value == _strokeColor) return;
    _strokeColor = value;
    _markNeedsPaintIfColorsChanged();
  }

  double _strokeWidth;
  set strokeWidth(double value) {
    if (value == _strokeWidth) return;
    _strokeWidth = value;
    markNeedsPaint();
  }

  Color Function()? _paintStrokeColor;
  set paintStrokeColor(Color Function()? value) {
    if (identical(value, _paintStrokeColor)) return;
    _paintStrokeColor = value;
    _markNeedsPaintIfColorsChanged();
  }

  /// The stroke color, or null when no stroke shows.
  Color? get _effectiveStrokeColor {
    if (_strokeWidth <= 0) return null;
    final color = _paintStrokeColor?.call() ?? _strokeColor;
    return color == null || color.a <= 0 ? null : color;
  }

  Color get _effectiveColor => _paintColor?.call() ?? _color;

  /// Repaints when the colors differ from the last paint.
  ///
  /// Compares with the last paint, not with the colors before the change: a
  /// paint closure reads live state, so it can already return the new color.
  /// For example, a button's hover state changes before the button rebuilds.
  void _markNeedsPaintIfColorsChanged() {
    final painted = _paintedColors;
    if (painted != null &&
        _effectiveColor == painted.color &&
        _effectiveStrokeColor == painted.stroke &&
        listEquals(_effectiveShadows, painted.shadows)) {
      return;
    }
    markNeedsPaint();
  }

  List<Shadow>? get _effectiveShadows => _paintShadows?.call() ?? _shadows;

  /// A box that listens to the paint bus is a repaint boundary, so a tick
  /// repaints only it (ADR 002, D8). An ancestor-driven box is not: the
  /// ancestor's layer repaints it.
  @override
  bool get isRepaintBoundary =>
      _paintColorListenable != null && !_paintDrivenByAncestor;

  /// The scale that ancestors declare (ADR 002, D7). The outline snaps to
  /// device pixels only under this scale.
  AncestorRasterScaleSignal _rasterScaleSignal;
  set rasterScaleSignal(AncestorRasterScaleSignal value) {
    if (identical(value, _rasterScaleSignal)) return;
    if (attached) {
      _rasterScaleSignal.removeListener(_markNeedsPaintForRasterScale);
    }
    _rasterScaleSignal = value;
    if (attached) value.addListener(_markNeedsPaintForRasterScale);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    if (!_paintDrivenByAncestor) {
      _paintColorListenable?.addListener(_markNeedsPaintForBus);
    }
    _rasterScaleSignal.addListener(_markNeedsPaintForRasterScale);
  }

  @override
  void detach() {
    if (!_paintDrivenByAncestor) {
      _paintColorListenable?.removeListener(_markNeedsPaintForBus);
    }
    _rasterScaleSignal.removeListener(_markNeedsPaintForRasterScale);
    _reportVectorBlurs(0);
    _lastPaint = null;
    _paintedColors = null;
    super.detach();
  }

  BlendMode? _blendMode;
  set blendMode(BlendMode? value) {
    if (value == _blendMode) return;
    _blendMode = value;
    markNeedsPaint();
  }

  /// MediaQuery's pixel ratio. Painting uses the view's ratio (ADR 002,
  /// D7), which can differ; a change of this one only triggers a repaint.
  double? _mediaPixelRatio;
  set mediaPixelRatio(double? value) {
    if (value == _mediaPixelRatio) return;
    _mediaPixelRatio = value;
    markNeedsPaint();
  }

  /// Pixel ratio of the view this icon paints into.
  ///
  /// The implicit view can differ: in tests it is the engine's default view,
  /// not `tester.view`, and other windows can have other ratios.
  double get _viewDevicePixelRatio {
    final rootNode = owner?.rootNode;
    if (rootNode is RenderView) return rootNode.configuration.devicePixelRatio;
    return ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1.0;
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(Size.square(_iconSize));

  // Icon's SizedBox reports its size on both axes, whatever the extent.
  @override
  double computeMinIntrinsicWidth(double height) => _iconSize;

  @override
  double computeMaxIntrinsicWidth(double height) => _iconSize;

  @override
  double computeMinIntrinsicHeight(double width) => _iconSize;

  @override
  double computeMaxIntrinsicHeight(double width) => _iconSize;

  /// Where [Icon] puts its glyph's text box in a box of [size]: centered on
  /// an axis with room, at the start of an axis without, clipped to the box.
  Rect _textBox(Size size) {
    double start(double extent) => math.max(0, (extent - _iconSize) / 2);
    return Rect.fromLTWH(
      start(size.width),
      start(size.height),
      math.min(size.width, _iconSize),
      math.min(size.height, _iconSize),
    );
  }

  /// Top-left of the drawn icon square. A flipped glyph mirrors about the
  /// text box's center, so it moves when the box clips it.
  Offset _origin(Size size) {
    final box = _textBox(size);
    return Offset(_flipX ? box.right - _iconSize : box.left, box.top);
  }

  /// Top-left of the drawn icon square.
  @visibleForTesting
  Offset get debugOrigin => _origin(size);

  /// Whether the drawn icon is mirrored.
  @visibleForTesting
  // ignore: match-getter-setter-field-names
  bool get debugFlipX => _flipX;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      _baseline(size, baseline);

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) => _baseline(getDryLayout(constraints), baseline);

  double? _baseline(Size size, TextBaseline baseline) {
    final glyph = _glyphBaseline(_icon, _iconSize, baseline);
    return glyph == null ? null : _textBox(size).top + glyph;
  }

  @override
  bool hitTestSelf(Offset position) => _textBox(size).contains(position);

  @override
  void paint(PaintingContext context, Offset offset) {
    assert(() {
      debugPaintCount++;
      return true;
    }());
    if (_iconSize <= 0) {
      _reportVectorBlurs(0);
      return;
    }
    RasterCacheDiagnostics.record(.icon, .paintCalls);
    // The paint transform, read once per paint.
    final device = DeviceTransform.of(
      this,
      _viewDevicePixelRatio,
      declaredScale: _rasterScaleSignal.effectiveScale,
    );
    assert(() {
      debugLastPaintSnapped = device.snap;
      return true;
    }());
    final color = _effectiveColor;
    final stroke = _effectiveStrokeColor;
    final shadows = _effectiveShadows;
    _paintedColors = _PaintedColors(color, stroke, shadows);
    if (MonetPerfDebugSwitches.classifyIconPaints) {
      _classifyPaint(device, color, stroke, shadows);
    }
    _markedByBus = false;
    _markedByRasterScale = false;
    _markedSelf = false;
    final outline = _outline;
    if (outline == null) {
      _reportVectorBlurs(_paintGlyph(context.canvas, offset, device.scale));
      return;
    }
    final origin = _origin(size);
    final SnappedIconPath(:path, :at) = snappedIconPath(
      device,
      outline,
      size: _iconSize,
      origin: origin,
      flipX: _flipX,
      baseline: outline.fits ? null : iconExactBaseline(_icon, _iconSize),
    );
    final canvas = context.canvas
      ..save()
      ..translate(offset.dx + at.dx, offset.dy + at.dy);
    final blurs = paintIconShadows(
      canvas,
      path,
      shadows ?? const [],
      outline: outline,
      size: _iconSize,
      deviceScale: device.scale,
      flipX: _flipX,
      memo: _shadowMemo,
      cache: device.snap,
    );
    _reportVectorBlurs(blurs);
    // One built-in stroke, as StrokeIcon drew it and MonetRichText does.
    if (stroke != null) {
      canvas.drawPath(
        path,
        Paint()
          ..style = .stroke
          ..strokeWidth = 2 * _strokeWidth
          ..color = stroke,
      );
    }
    canvas
      ..drawPath(
        path,
        Paint()
          ..color = color
          ..blendMode = _blendMode ?? BlendMode.srcOver,
      )
      ..restore();
  }
}

/// Boundary names, built once per boundary while classifying paints.
final _layerOwnerNames = Expando<String>('layerOwner');

String _describeOwner(RenderObject boundary) {
  final creator = boundary.debugCreator;
  if (creator is! DebugCreator) return '${boundary.runtimeType} (no creator)';
  final names = <String>[];
  creator.element.visitAncestorElements((element) {
    final widget = element.widget;
    final name = widget.runtimeType.toString();
    final composed = widget is StatelessWidget || widget is StatefulWidget;
    if (composed &&
        !name.startsWith('_') &&
        !_kFrameworkWidgets.contains(name)) {
      if (names.isEmpty || names.last != name) names.add(name);
    }
    return names.length < 3;
  });
  final widget = creator.element.widget;
  return '${widget.runtimeType}${_creationLocation(widget)} '
      '< ${names.join(' < ')}';
}

/// `@file.dart:line` where [widget] was created, when the build tracks
/// widget creation (debug builds do), else empty.
String _creationLocation(Widget widget) {
  final properties = InspectorSerializationDelegate(
    service: WidgetInspectorService.instance,
  ).additionalNodeProperties(widget.toDiagnosticsNode());
  final location = properties['creationLocation'];
  if (location is! Map) return '';
  final file = location['file'];
  final line = location['line'];
  if (file is! String) return '';
  return '@${file.split('/').last}:$line';
}

/// Framework widgets that wrap almost everything, skipped in owner names.
const _kFrameworkWidgets = {
  'AnimatedBuilder',
  'Builder',
  'Consumer',
  'Container',
  'DefaultTextStyle',
  'HookBuilder',
  'LayoutBuilder',
  'ListenableBuilder',
  'Material',
  'Semantics',
  'ValueListenableBuilder',
};

extension on RenderIconBox {
  /// Counts this paint as first, moved, recolored or unchanged against the
  /// previous paint ([RasterCacheEvent.iconPaintFirst] and the next four).
  void _classifyPaint(
    DeviceTransform device,
    Color color,
    Color? stroke,
    List<Shadow>? shadows,
  ) {
    final paint = _PaintRecord.of(device, color, stroke, shadows);
    final last = _lastPaint;
    _lastPaint = paint;
    final RasterCacheEvent cause;
    if (last == null) {
      cause = .iconPaintFirst;
    } else {
      final moved = !paint.samePlace(last);
      final recolored = !paint.sameColors(last);
      if (moved) {
        cause = recolored ? .iconPaintMovedRecolored : .iconPaintMoved;
      } else {
        cause = recolored ? .iconPaintRecolored : .iconPaintUnchanged;
      }
    }
    RasterCacheDiagnostics.record(.icon, cause);
    if (cause == .iconPaintUnchanged) {
      final trigger = _unchangedTrigger();
      RasterCacheDiagnostics.record(.icon, trigger);
      if (trigger == .iconUnchangedByLayer) {
        LayerOwnerDiagnostics.record(_layerOwner());
      }
    }
  }

  /// Names the layer this icon paints into: its repaint boundary's widget,
  /// then up to three public app-level widgets above it, nearest first.
  /// Needs debug builds, where render objects know their creator.
  String _layerOwner() {
    RenderObject? boundary = this;
    while (boundary != null && !boundary.isRepaintBoundary) {
      boundary = boundary.parent;
    }
    if (boundary == null) return '(root)';
    return _layerOwnerNames[boundary] ??= _describeOwner(boundary);
  }

  /// What made an unchanged paint happen. The first mark wins, in this
  /// order: the paint bus, the raster-scale signal, any other mark of this
  /// icon, then the repaint of the layer it paints into.
  RasterCacheEvent _unchangedTrigger() {
    if (_markedByBus) return .iconUnchangedByBus;
    if (_markedByRasterScale) return .iconUnchangedByRasterScale;
    if (_markedSelf) return .iconUnchangedBySelf;
    if (_paintDrivenByAncestor && _paintColorListenable != null) {
      return .iconUnchangedByAncestorLayer;
    }
    return .iconUnchangedByLayer;
  }

  /// Draws [_icon] with the font, where [Icon] draws it. Shadows are text
  /// shadows, as in [Icon], then one ring per spread, as text draws spread.
  ///
  /// The baseline goes where [Icon] intends it, [iconExactBaseline], on a
  /// whole device pixel. [Icon] draws it at the baseline that SkParagraph
  /// rounds to a whole logical pixel, which is up to half a logical pixel
  /// low at fractional sizes. StrokeIcon, which this replaced, made the same
  /// correction.
  /// Paints the glyph source (D4). Returns how many blurred shadows it drew:
  /// text shadows are vector blurs.
  int _paintGlyph(Canvas canvas, Offset offset, double scale) {
    final passes = _glyph;
    final text = String.fromCharCode(_icon.codePoint);
    // What every pass's style shares. A change relays out every pass.
    final style = [
      text,
      _iconSize,
      _icon.fontFamily,
      _icon.fontPackage,
      ...?_icon.fontFamilyFallback,
      _fontWeight,
      ...?_fontVariations,
      size.width,
    ];
    TextPainter pass(
      _GlyphPass pass,
      List<Object> key, {
      Paint Function()? foreground,
      List<Shadow>? shadows,
    }) => pass.update(
      [...style, ...key],
      () => TextSpan(
        text: text,
        style: TextStyle(
          inherit: false,
          foreground: foreground?.call(),
          color: foreground == null ? const Color(0x00000000) : null,
          shadows: shadows,
          fontSize: _iconSize,
          fontFamily: _icon.fontFamily,
          package: _icon.fontPackage,
          fontFamilyFallback: _icon.fontFamilyFallback,
          fontWeight: _fontWeight,
          fontVariations: _fontVariations,
          height: 1,
          leadingDistribution: .even,
        ),
      ),
      size.width,
    );

    final color = _effectiveColor;
    final blendMode = _blendMode ?? .srcOver;
    final fill = pass(
      passes.fill,
      [color, blendMode],
      foreground: () => Paint()
        ..color = color
        ..blendMode = blendMode,
    );
    final box = _textBox(size);
    final intended = box.top + iconExactBaseline(_icon, _iconSize);
    final drawn = (fill.computeDistanceToActualBaseline(.alphabetic) + 0.5)
        .floorToDouble();
    final at =
        offset +
        Offset(
          math.max(0, (size.width - fill.width) / 2),
          ((intended - drawn) * scale).roundToDouble() / scale,
        );
    canvas.save();
    if (_flipX) {
      // Icon mirrors its text about the text box's center.
      final center = offset.dx + box.center.dx;
      canvas
        ..translate(2 * center, 0)
        ..scale(-1, 1);
    }
    final shadows = _effectiveShadows ?? const <Shadow>[];
    var rings = 0;
    var blurs = 0;
    if (shadows.isNotEmpty) {
      pass(passes.shadows, shadows, shadows: shadows).paint(canvas, at);
      for (final shadow in shadows) {
        final blurred = shadow.blurRadius > 0 && shadow.color.a > 0;
        if (blurred) blurs++;
        final spread = shadow is BoxShadow ? shadow.spreadRadius : 0.0;
        if (spread <= 0 || shadow.color.a <= 0) continue;
        if (blurred) blurs++;
        pass(
          passes.ring(rings++),
          [shadow.color, shadow.blurRadius, spread],
          foreground: () => iconShadowPaint(shadow)
            ..style = .stroke
            ..strokeWidth = 2 * spread
            ..strokeJoin = .round,
        ).paint(canvas, at + shadow.offset);
      }
    }
    passes.trimRings(rings);
    if (_effectiveStrokeColor case final stroke?) {
      pass(
        passes.stroke,
        [stroke, _strokeWidth],
        foreground: () => Paint()
          ..style = .stroke
          ..strokeWidth = 2 * _strokeWidth
          ..color = stroke,
      ).paint(canvas, at);
    }
    fill.paint(canvas, at);
    canvas.restore();
    return blurs;
  }
}

/// The colors of one paint, so a bus tick with the same colors can skip.
final class const _PaintedColors(
  final Color color,
  final Color? stroke,
  final List<Shadow>? shadows,
);

/// A snapped icon path, and where to draw it.
final class const SnappedIconPath(final Path path, final Offset at);

/// What one icon paint drew with: where on the device, and in which colors.
final class _PaintRecord {
  const _PaintRecord(this.place, this.color, this.stroke, this.shadows);

  factory _PaintRecord.of(
    DeviceTransform device,
    Color color,
    Color? stroke,
    List<Shadow>? shadows,
  ) {
    final m = device.transform.storage;
    return .new(
      [m[0], m[1], m[4], m[5], m[12], m[13], device.devicePixelRatio],
      color,
      stroke,
      shadows,
    );
  }

  /// The 2D part of the paint transform, and the view's pixel ratio.
  final List<double> place;
  final Color color;
  final Color? stroke;
  final List<Shadow>? shadows;

  bool samePlace(_PaintRecord other) => listEquals(place, other.place);

  bool sameColors(_PaintRecord other) =>
      color == other.color &&
      stroke == other.stroke &&
      listEquals(shadows, other.shadows);
}

/// One paint pass of the glyph source: a [TextPainter] whose paragraph is
/// rebuilt only when the pass's inputs change.
///
/// [TextPainter] rebuilds its paragraph on any paint-only change of its
/// span, and a [Paint] equals only itself. One painter shared by every pass
/// rebuilt a paragraph per pass per paint.
final class _GlyphPass {
  final painter = TextPainter(textDirection: .ltr);
  List<Object?>? _key;

  TextPainter update(
    List<Object?> key,
    TextSpan Function() span,
    double maxWidth,
  ) {
    if (!listEquals(key, _key)) {
      painter.text = span();
      _key = key;
    }
    // Lays out only when the span's layout or the width changed.
    painter.layout(maxWidth: maxWidth);
    return painter;
  }

  void dispose() => painter.dispose();
}

/// The glyph source's passes: shadows, one ring per spread, the stroke, and
/// the fill.
final class _GlyphPasses {
  _GlyphPass? _fill, _shadows, _stroke;
  final _rings = <_GlyphPass>[];

  _GlyphPass get fill => _fill ??= .new();
  _GlyphPass get shadows => _shadows ??= .new();
  _GlyphPass get stroke => _stroke ??= .new();

  _GlyphPass ring(int i) {
    while (_rings.length <= i) {
      _rings.add(_GlyphPass());
    }
    return _rings[i];
  }

  /// Frees ring passes from [count] on.
  void trimRings(int count) {
    while (_rings.length > count) {
      _rings.removeLast().dispose();
    }
  }

  void dispose() {
    _fill?.dispose();
    _shadows?.dispose();
    _stroke?.dispose();
    _fill = null;
    _shadows = null;
    _stroke = null;
    for (final ring in _rings) {
      ring.dispose();
    }
    _rings.clear();
  }
}

/// Where a render box paints on the device, from one walk of its paint
/// transform.
final class DeviceTransform {
  const DeviceTransform._(
    this.transform,
    this.devicePixelRatio,
    this.axisAligned,
    this.scale,
    this.snap,
  );

  /// [box]'s transform to the view, read once. [devicePixelRatio] is the
  /// view's ratio. [declaredScale] is the scale that ancestors declare with
  /// an AncestorRasterScaleScope.
  ///
  /// Call it from [box]'s paint. [MonetPerfDebugSwitches.paintPlacement]
  /// picks how the transform is found ([paintTransformForPlacement]).
  factory DeviceTransform.of(
    RenderBox box,
    double devicePixelRatio, {
    double declaredScale = 1,
  }) {
    final transform = paintTransformForPlacement(
      box,
      declaredScale: declaredScale,
    );
    final m = transform.storage;
    final scale = m[0];
    final axisAligned =
        m[1].abs() < 1e-9 &&
        m[4].abs() < 1e-9 &&
        scale > 0 &&
        (m[5] - scale).abs() < 1e-9;
    return DeviceTransform._(
      transform,
      devicePixelRatio,
      axisAligned,
      (axisAligned ? scale : 1) * devicePixelRatio,
      axisAligned && (scale - declaredScale).abs() <= 1e-3 * declaredScale,
    );
  }

  /// Logical pixels to the view, without the view's pixel ratio.
  final Matrix4 transform;

  /// The view's device pixels per logical pixel.
  final double devicePixelRatio;

  /// Whether the transform is a translation and a uniform positive scale.
  final bool axisAligned;

  /// Device pixels per logical pixel: the view's ratio times the
  /// transform's scale when [axisAligned], else the view's ratio.
  final double scale;

  /// Whether to snap to device pixels: the transform is [axisAligned] and
  /// its scale is the declared one (ADR 002, D7).
  ///
  /// A picture can be reused at another scale without a repaint, as under a
  /// ScaleTransition. An outline snapped at the first scale is then wrong
  /// at the next, and one snapped near 0x is all whole-pixel strokes. A
  /// plain outline scales cleanly, so only a declared scale snaps.
  final bool snap;

  /// [point], in the box's coordinates, in device pixels.
  Offset toDevice(Offset point) =>
      MatrixUtils.transformPoint(transform, point) * devicePixelRatio;
}

/// Baselines of icon glyphs as [Icon] lays them out, by glyph and size.
final _glyphBaselines = <_GlyphBaselineKey, double?>{};

/// A glyph, its size, and a baseline kind.
final class const _GlyphBaselineKey(
  final IconData icon,
  final double size,
  final TextBaseline baseline,
) {
  @override
  bool operator ==(Object other) =>
      other is _GlyphBaselineKey &&
      other.icon == icon &&
      other.size == size &&
      other.baseline == baseline;

  @override
  int get hashCode => Object.hash(icon, size, baseline);
}

double? _glyphBaseline(IconData icon, double size, TextBaseline baseline) {
  final key = _GlyphBaselineKey(icon, size, baseline);
  if (_glyphBaselines.containsKey(key)) return _glyphBaselines[key];
  if (_glyphBaselines.length >= 256) _glyphBaselines.clear();
  final painter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      // The parts of Icon's text style that affect layout.
      style: TextStyle(
        inherit: false,
        fontSize: size,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontFamilyFallback: icon.fontFamilyFallback,
        height: 1,
        leadingDistribution: .even,
      ),
    ),
    textDirection: .ltr,
  )..layout();
  final result = painter.computeDistanceToActualBaseline(baseline);
  painter.dispose();
  return _glyphBaselines[key] = result;
}

/// [outline] as a path for a [size] square whose top-left corner is at
/// [origin] in [box]'s coordinates, with straight edges on device pixels,
/// and where to draw it.
///
/// [device] is the painting box's transform, read during its paint.
/// Snapping needs [DeviceTransform.snap]; otherwise the path is the plain
/// outline. The path is in the square's coordinates, (0, 0) to (size, size).
/// Draw it at the returned offset: [origin], moved by at most 1/16 device
/// pixel to the phase that the path was fitted at.
///
/// An outline that does not [IconOutline.fits] is not fitted. With
/// [baseline], its distance from the square's top to the glyph baseline,
/// the square moves by at most half a device pixel so that the baseline
/// lands on a device pixel, as the glyph source puts it.
SnappedIconPath snappedIconPath(
  DeviceTransform device,
  IconOutline outline, {
  required double size,
  Offset origin = .zero,
  bool flipX = false,
  double? baseline,
}) {
  final snap = device.snap;
  final deviceOrigin = device.toDevice(origin);
  double frac(double v) => v - v.floorToDouble();
  final deviceScale = device.scale;
  final phase = Offset(frac(deviceOrigin.dx), frac(deviceOrigin.dy));
  final path = _cache.lookup(
    outline,
    size: size,
    deviceScale: deviceScale,
    phase: phase,
    flipX: flipX,
    snap: snap,
  );
  if (!snap) return SnappedIconPath(path, origin);
  if (!outline.fits) {
    if (baseline == null) return SnappedIconPath(path, origin);
    final y = deviceOrigin.dy + baseline * deviceScale;
    return SnappedIconPath(
      path,
      origin.translate(0, (y.roundToDouble() - y) / deviceScale),
    );
  }
  final shift = Offset(
    IconPathCache.snapPhase(phase.dx) - phase.dx,
    IconPathCache.snapPhase(phase.dy) - phase.dy,
  );
  return SnappedIconPath(path, origin + shift / deviceScale);
}
