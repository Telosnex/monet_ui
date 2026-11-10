import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:monet_ui/fonts/font_height_equalizer.g.dart';
import 'package:monet_ui/util/lru_cache.dart';

/// One line of text whose size is the box around its ink, the pixels its
/// glyphs paint, not its line box. Centering it centres the ink.
///
/// For text standing alone in a shape, such as a count in a badge. Fonts
/// leave uneven space beside a glyph (a `1`'s ink is off the centre of its
/// advance) and above or below it, so centering the line box, or even the
/// font's capitals, does not centre what is drawn.
///
/// With [sizeToLineBox], it keeps the size of its line box, as [Text] does,
/// and paints its ink centred in that box. Use it where something else sizes
/// the text by its line box, such as a [FittedBox].
///
/// Each grapheme's ink is measured once per font, by drawing it large and
/// finding its painted pixels. That is async: until it is done, the text is
/// sized by its advance width and the font's cap height.
class InkCenteredText extends LeafRenderObjectWidget {
  const InkCenteredText({
    super.key,
    required this.text,
    this.style,
    this.textScaler,
    this.sizeToLineBox = false,
  });

  final String text;

  /// Size to the line box instead of the ink, and centre the ink in it.
  final bool sizeToLineBox;

  /// Merged over the ambient [DefaultTextStyle].
  final TextStyle? style;

  /// Defaults to the ambient [MediaQuery]'s text scaler.
  final TextScaler? textScaler;

  @override
  RenderInkCenteredText createRenderObject(BuildContext context) => .new(
    text: text,
    style: _style(context),
    textScaler: textScaler ?? MediaQuery.textScalerOf(context),
    textDirection: Directionality.maybeOf(context) ?? .ltr,
    sizeToLineBox: sizeToLineBox,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderInkCenteredText renderObject,
  ) {
    renderObject
      ..text = text
      ..style = _style(context)
      ..textScaler = textScaler ?? MediaQuery.textScalerOf(context)
      ..textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr
      ..sizeToLineBox = sizeToLineBox;
  }

  TextStyle _style(BuildContext context) =>
      DefaultTextStyle.of(context).style.merge(style);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('text', text));
  }
}

class RenderInkCenteredText extends RenderBox {
  RenderInkCenteredText({
    required String text,
    required TextStyle style,
    required TextScaler textScaler,
    required TextDirection textDirection,
    this._sizeToLineBox = false,
  }) : _text = text,
       _style = style,
       _painter = TextPainter(
         text: TextSpan(text: text, style: style),
         textScaler: textScaler,
         textDirection: textDirection,
         maxLines: 1,
       );

  final TextPainter _painter;

  /// The ink box, in the painter's coordinates.
  Rect _ink = .zero;

  bool _sizeToLineBox;
  set sizeToLineBox(bool value) {
    if (_sizeToLineBox == value) return;
    _sizeToLineBox = value;
    markNeedsLayout();
  }

  /// Where the painter's origin is, in this box.
  Offset get _paintOrigin =>
      _sizeToLineBox ? size.center(.zero) - _ink.center : -_ink.topLeft;

  String _text;
  set text(String value) {
    if (_text == value) return;
    _text = value;
    _setSpan();
  }

  TextStyle get style => _style;
  TextStyle _style;
  set style(TextStyle value) {
    if (_style == value) return;
    _style = value;
    _setSpan();
  }

  void _setSpan() {
    final span = TextSpan(text: _text, style: _style);
    final change = span.compareTo(_painter.text!);
    _painter.text = span;
    switch (change) {
      case .identical || .metadata:
        break;
      case .paint:
        markNeedsPaint();
      case .layout:
        markNeedsLayout();
    }
  }

  set textScaler(TextScaler value) {
    if (_painter.textScaler == value) return;
    _painter.textScaler = value;
    markNeedsLayout();
  }

  set textDirection(TextDirection value) {
    if (_painter.textDirection == value) return;
    _painter.textDirection = value;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    GlyphInkCache.instance.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    GlyphInkCache.instance.removeListener(markNeedsLayout);
    super.detach();
  }

  @override
  void dispose() {
    _painter.dispose();
    super.dispose();
  }

  Rect _layoutInk() {
    _painter.layout();
    return GlyphInkCache.instance.inkOf(_painter, _text, _style);
  }

  /// This box's size, with the painter laid out.
  Size _layoutSize() {
    if (_sizeToLineBox) {
      _painter.layout();
      return _painter.size;
    }
    return _layoutInk().size;
  }

  @override
  double computeMinIntrinsicWidth(double height) => _layoutSize().width;

  @override
  double computeMaxIntrinsicWidth(double height) => _layoutSize().width;

  @override
  double computeMinIntrinsicHeight(double width) => _layoutSize().height;

  @override
  double computeMaxIntrinsicHeight(double width) => _layoutSize().height;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_layoutSize());

  @override
  void performLayout() {
    _ink = _layoutInk();
    size = constraints.constrain(_sizeToLineBox ? _painter.size : _ink.size);
  }

  @override
  double computeDistanceToActualBaseline(TextBaseline baseline) =>
      _painter.computeDistanceToActualBaseline(baseline) + _paintOrigin.dy;

  @override
  void paint(PaintingContext context, Offset offset) {
    _painter.paint(context.canvas, offset + _paintOrigin);
  }
}

/// A grapheme's ink, in ems: how far it reaches inside its advance from each
/// side, and above and below the baseline.
@immutable
class GlyphInk {
  const GlyphInk({
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  });

  /// From the advance's left edge to the ink. Negative overhangs.
  final double left;

  /// From the ink to the advance's right edge. Negative overhangs.
  final double right;

  /// Above the baseline.
  final double top;

  /// Below the baseline, positive downwards.
  final double bottom;
}

/// Measured [GlyphInk] for each font and grapheme. Notifies when a
/// measurement finishes, or when fonts change and measurements are redone.
class GlyphInkCache extends ChangeNotifier {
  GlyphInkCache._() : _measureGlyph = measureGlyphInk {
    PaintingBinding.instance.systemFonts.addListener(_fontsChanged);
  }

  /// Creates an isolated cache with an injectable raster measurement.
  @visibleForTesting
  GlyphInkCache.forTesting({
    required Future<GlyphInk?> Function(
      TextStyle style,
      String grapheme, {
      required double fontSize,
    })
    measure,
  }) : _measureGlyph = measure;

  final Future<GlyphInk?> Function(
    TextStyle style,
    String grapheme, {
    required double fontSize,
  })
  _measureGlyph;

  static final instance = GlyphInkCache._();

  /// Size glyphs are drawn at to measure them. Ink scales with the font
  /// size, so one size serves all.
  static const _measureSize = 128.0;

  /// A null record means measurement is unavailable; a record with null ink
  /// means the grapheme paints nothing. Both are cached to avoid retry loops.
  final _ink = LruCache<(TextStyle, String), ({GlyphInk? ink})?>(capacity: 512);
  final _pending = <(TextStyle, String)>{};

  /// Increments when fonts change, so measurements of old fonts are dropped.
  int _generation = 0;
  bool _reportedReadbackFailure = false;

  /// Whether every measurement started has finished.
  @visibleForTesting
  bool get isIdle => _pending.isEmpty;

  void _fontsChanged() {
    _generation++;
    _ink.clear();
    _pending.clear();
    notifyListeners();
  }

  /// The ink box of [text], laid out in [painter] with [style], in the
  /// painter's coordinates. Until each grapheme is measured, an estimate:
  /// the advance width, from the baseline to the cap height.
  Rect inkOf(TextPainter painter, String text, TextStyle style) {
    final fontSize = painter.textScaler.scale(
      style.fontSize ?? kDefaultFontSize,
    );
    final baseline = painter.computeDistanceToActualBaseline(.alphabetic);
    final estimate = _estimate(painter, style, fontSize, baseline);
    final key = _fontKey(style);
    // Letter spacing is added after each glyph, inside its box, but glyphs
    // are measured without it.
    final letterSpacing = style.letterSpacing ?? 0;
    Rect? ink;
    var offset = 0;
    for (final grapheme in text.characters) {
      final start = offset;
      offset += grapheme.length;
      final measured = _lookup(key, grapheme);
      if (measured == null) return estimate;
      final glyph = measured.ink;
      if (glyph == null) continue;
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: offset),
      );
      if (boxes.isEmpty) return estimate;
      final box = boxes.first;
      final rect = Rect.fromLTRB(
        box.left + glyph.left * fontSize,
        baseline - glyph.top * fontSize,
        box.right - letterSpacing - glyph.right * fontSize,
        baseline + glyph.bottom * fontSize,
      );
      ink = ink?.expandToInclude(rect) ?? rect;
    }
    return ink ?? estimate;
  }

  static Rect _estimate(
    TextPainter painter,
    TextStyle style,
    double fontSize,
    double baseline,
  ) {
    final capHeight = rasterCapHeightEmForFontFamily(style.fontFamily);
    return capHeight == null
        ? Offset.zero & painter.size
        : Rect.fromLTRB(
            0,
            baseline - capHeight * fontSize,
            painter.width,
            baseline,
          );
  }

  /// The parts of [style] that change glyph shapes.
  static TextStyle _fontKey(TextStyle style) => .new(
    fontFamily: style.fontFamily,
    fontFamilyFallback: style.fontFamilyFallback,
    fontWeight: style.fontWeight,
    fontStyle: style.fontStyle,
    fontFeatures: style.fontFeatures,
    fontVariations: style.fontVariations,
    locale: style.locale,
  );

  /// The measured ink, in a record so "no ink" differs from "not measured".
  /// Starts a measurement when there is none.
  ({GlyphInk? ink})? _lookup(TextStyle key, String grapheme) {
    final cacheKey = (key, grapheme);
    if (_ink.containsKey(cacheKey)) return _ink[cacheKey];
    if (_pending.add(cacheKey)) unawaited(_measure(cacheKey));
    return null;
  }

  Future<void> _measure((TextStyle, String) cacheKey) async {
    final generation = _generation;
    final (style, grapheme) = cacheKey;
    ({GlyphInk? ink})? result;
    try {
      result = (
        ink: await _measureGlyph(style, grapheme, fontSize: _measureSize),
      );
    } on Object catch (error) {
      // Pixel readback is optional. A missing graphics context must not turn
      // ordinary text into an application error. Keep the estimated ink box.
      if (!_reportedReadbackFailure) {
        _reportedReadbackFailure = true;
        debugPrint(
          'Glyph ink readback unavailable; using estimated bounds: $error',
        );
      }
    }
    if (generation != _generation) return;
    _pending.remove(cacheKey);
    _ink[cacheKey] = result;
    notifyListeners();
  }
}

/// Draws [grapheme] in [style] at [fontSize] and returns its ink in ems, or
/// null if it paints nothing.
@visibleForTesting
Future<GlyphInk?> measureGlyphInk(
  TextStyle style,
  String grapheme, {
  required double fontSize,
}) async {
  final builder = ui.ParagraphBuilder(ui.ParagraphStyle(textDirection: .ltr))
    ..pushStyle(
      style
          .copyWith(
            fontSize: fontSize,
            color: const Color(0xff000000),
            height: 1,
          )
          .getTextStyle(),
    )
    ..addText(grapheme);
  final paragraph = builder.build()
    ..layout(const ui.ParagraphConstraints(width: .infinity));
  final advance = paragraph.maxIntrinsicWidth;
  final baseline = paragraph.alphabeticBaseline;
  // Room for ink beyond the advance and line box: swashes, accents.
  final pad = fontSize;
  final width = (advance + 2 * pad).ceil();
  final height = (paragraph.height + 2 * pad).ceil();
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawParagraph(paragraph, Offset(pad, pad));
  paragraph.dispose();
  final picture = recorder.endRecording();
  final ui.Image image;
  try {
    image = picture.toImageSync(width, height);
  } finally {
    picture.dispose();
  }
  final ByteData? bytes;
  try {
    bytes = await image.toByteData();
  } finally {
    image.dispose();
  }
  if (bytes == null) throw StateError('Glyph pixel readback unavailable.');
  // Coverage, 0 to 1, of each row and column's most covered pixel.
  final rows = Float64List(height);
  final columns = Float64List(width);
  for (var y = 0; y < height; y++) {
    final row = y * width * 4;
    for (var x = 0; x < width; x++) {
      final alpha = bytes.getUint8(row + x * 4 + 3) / 255;
      if (alpha > rows[y]) rows[y] = alpha;
      if (alpha > columns[x]) columns[x] = alpha;
    }
  }
  // Faint antialiasing is not ink; edges are placed by their coverage.
  const threshold = 0.04;
  final top = rows.indexWhere((c) => c > threshold);
  if (top < 0) return null;
  final bottom = rows.lastIndexWhere((c) => c > threshold);
  final left = columns.indexWhere((c) => c > threshold);
  final right = columns.lastIndexWhere((c) => c > threshold);
  // Text is drawn with its baseline on the nearest whole pixel.
  final baselineY = (pad + baseline).roundToDouble();
  return GlyphInk(
    left: (left + 1 - columns[left] - pad) / fontSize,
    right: (pad + advance - (right + columns[right])) / fontSize,
    top: (baselineY - (top + 1 - rows[top])) / fontSize,
    bottom: (bottom + rows[bottom] - baselineY) / fontSize,
  );
}
