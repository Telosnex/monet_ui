import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:loggy/loggy.dart';
import 'package:monet_ui/util/blur_radius.dart';
import 'package:monet_ui/widgets/monet_perf_debug_switches.dart';
import 'package:monet_ui/widgets/raster_cache_diagnostics.dart';
import 'package:monet_ui/widgets/raster_mask_image_budget.dart';
import 'package:monet_ui/widgets/rich_text/direct_paint_inputs.dart';
import 'package:monet_ui/widgets/rich_text/emoji_paint_spans.dart';
import 'package:monet_ui/widgets/rich_text/paragrapher.dart';

enum PaintStrategyKind { direct, tint, layeredShadowTint, emojiTint }

class PaintPlan {
  final PaintStrategyKind kind;
  final TextStyle layoutStyle;

  const PaintPlan({required this.kind, required this.layoutStyle});
}

// ============================================================================
// Process-wide raster-mask image accounting
// ============================================================================

/// Text masks retain their own registry, independent of button shadows.
final _textMaskImageBudget = RasterMaskImageBudget(
  debugLabel: 'CachedTextImageBudget',
  maxBytes: RasterMaskImageCacheConfig.maxBytes,
  maxImageBytes: RasterMaskImageCacheConfig.maxImageBytes,
);

typedef TextMaskImageCacheStats = RasterMaskImageCacheStats;

TextMaskImageCacheStats get textMaskImageCacheStats =>
    _textMaskImageBudget.stats;

void clearTextMaskImageCache() => _textMaskImageBudget.clear();

@visibleForTesting
void debugConfigureTextMaskImageCache({
  required int maxBytes,
  required int maxImageBytes,
}) => _textMaskImageBudget.debugConfigure(
  maxBytes: maxBytes,
  maxImageBytes: maxImageBytes,
);

@visibleForTesting
void debugResetTextMaskImageCache() => _textMaskImageBudget.debugReset();

class _TextMaskAdmissionDenial {
  _TextMaskAdmissionDenial(
    this.requestSignature,
    this.requestedBytes,
    this.reason, {
    this.allowIdleRetry = true,
  }) : revision = _textMaskImageBudget.availabilityRevision;

  final int requestSignature;
  // Nullable only for denial objects retained across addition of these fields
  // by hot reload. Re-probe legacy denials once to establish their reason.
  final int? requestedBytes;
  final RasterMaskRejection? reason;
  final int revision;
  final bool allowIdleRetry;

  bool stillApplies(int signature) {
    if (requestedBytes == null ||
        reason == null ||
        requestSignature != signature ||
        revision != _textMaskImageBudget.availabilityRevision) {
      return false;
    }
    return !allowIdleRetry ||
        reason != .visibleSet ||
        !_textMaskImageBudget.canRetryAfterIdleFrame(requestedBytes!);
  }
}

// ============================================================================
// BoxShadow.spreadRadius support
// ============================================================================
//
// `TextStyle.shadows` has no spread primitive: the engine draws a
// `BoxShadow` entry as a plain blurred glyph shadow and silently drops its
// `spreadRadius` (monet ADR-003 D3). Both strategies that see shadows emulate
// the spread by drawing the paragraph's own glyphs once more with a stroke
// `foreground` Paint under the fill: width = 2 × spread puts a solid ring
// `spread` px outside the glyph edge, blurred by the shadow's own sigma.
//
// Accepted approximations:
//  - the blur sees only the ring, not a fully dilated solid — slightly
//    sharper skirt, exact alpha at the edge where protection lives;
//  - the engine's spreadless blur of the same entry still paints (it's baked
//    into the paragraph); same RGB, so the overlap only darkens the skirt a
//    little — errs on the protective side.

double spreadOf(Shadow s) => s is BoxShadow ? s.spreadRadius : 0.0;

bool _hasSpread(List<Shadow> shadows) {
  for (final s in shadows) {
    if (spreadOf(s) > 0 && s.color.a > 0) return true;
  }
  return false;
}

/// Underlay style for one spread entry: glyphs stroked instead of filled, in
/// [color], blurred by the shadow's sigma. `TextStyle.copyWith` drops `color`
/// when `foreground` is set, so this flows through
/// `ParagraphInput.effectiveStyle` unchanged; metrics fields are untouched,
/// so the underlay lays out byte-identical geometry.
TextStyle _spreadStrokeStyle(TextStyle base, Shadow shadow, Color color) {
  final paint = Paint()
    ..style = .stroke
    ..strokeWidth = 2 * spreadOf(shadow)
    ..strokeJoin = .round
    ..color = color;
  if (shadow.blurRadius > 0) {
    paint.maskFilter = MaskFilter.blur(.normal, shadow.blurSigma);
  }
  return base.copyWith(shadows: const [], foreground: paint);
}

/// Paints every spread entry of [shadows] as a stroke pass on [canvas],
/// reusing [painter]. With [asMask] false, strokes carry real shadow colors
/// (direct path); with true, white at each shadow's alpha (tint path), for
/// the paint-time srcIn tint.
void _paintSpreadStrokes(
  Canvas canvas,
  TextPainter painter,
  ParagraphResult layout,
  List<Shadow> shadows, {
  required bool asMask,
}) {
  for (final s in shadows) {
    if (spreadOf(s) <= 0 || s.color.a <= 0) continue;
    final color = asMask
        ? Color.from(alpha: s.color.a, red: 1, green: 1, blue: 1)
        : s.color;
    final input = layout.input.copyWith(
      style: _spreadStrokeStyle(layout.input.style, s, color),
    );
    Paragrapher.configure(painter, input);
    painter.layout(maxWidth: input.maxWidth);
    painter.paint(canvas, s.offset);
  }
}

/// A stroke on the glyph edges, drawn after the shadows and before the fill,
/// as `MonetIcon` draws it.
@immutable
class TextStroke {
  const TextStroke({required this.color, required this.width});

  final Color color;

  /// The visible outer stroke width in logical pixels.
  final double width;

  /// Whether [other] covers the same pixels, at any RGB.
  bool sameShape(TextStroke? other) =>
      other != null && other.width == width && other.color.a == color.a;

  @override
  bool operator ==(Object other) =>
      other is TextStroke && other.color == color && other.width == width;

  @override
  int get hashCode => Object.hash(color, width);
}

/// Paints [stroke] on the paragraph's glyphs, with [shadows] under it when
/// [withShadows]. With [asMask], the stroke and shadows are white at their
/// alphas, for the paint-time srcIn tint.
void _paintStrokePass(
  Canvas canvas,
  TextPainter painter,
  ParagraphResult layout,
  TextStroke stroke,
  List<Shadow> shadows, {
  required bool asMask,
  required bool withShadows,
  double shadowScale = 1,
}) {
  final color = asMask
      ? Color.from(alpha: stroke.color.a, red: 1, green: 1, blue: 1)
      : stroke.color;
  final input = layout.input.copyWith(
    style: layout.input.style.copyWith(
      shadows: withShadows
          ? textShadowsAtScale(
              asMask ? _shadowMaskShadows(shadows) : shadows,
              shadowScale,
            )
          : const [],
      foreground: Paint()
        ..style = .stroke
        ..strokeWidth = 2 * stroke.width
        ..color = color,
    ),
  );
  Paragrapher.configure(painter, input);
  painter.layout(maxWidth: input.maxWidth);
  painter.paint(canvas, .zero);
}

abstract class PaintStrategy with Diagnosticable {
  PaintStrategyKind get kind;

  /// [rasterPixelRatio] is the physical pixels per logical pixel that cached
  /// mask images are rasterized at. The render object computes it as the
  /// pixel ratio of the view it paints into × the quantized ancestor paint
  /// scale, so paint-time upscaling ancestors (e.g. `ScaleUpLayout` on the
  /// Mod screen) don't stretch a lower-resolution bitmap. A mask rasterized
  /// at another view's ratio is resampled when drawn, which blurs it and
  /// moves its visible centre. [DirectPaintStrategy] ignores it.
  ///
  /// [deviceTextOrigin] is [offset] in physical pixels of the view, or null
  /// when the paint transform is not a pure translation. Cached masks bake
  /// its sub-pixel phase in so they land on whole device pixels. A mask drawn
  /// at a fractional device position is resampled, which blurs its glyphs.
  ///
  /// With [stroke], [layout] is laid out without shadows: shadows paint
  /// under the stroke, and the stroke under the fill.
  void paint(
    PaintingContext context,
    Offset offset,
    ParagraphResult layout,
    int generation,
    Color effectiveColor,
    List<Shadow> shadows,
    double rasterPixelRatio,
    Offset? deviceTextOrigin, {
    TextStroke? stroke,
  });

  /// Drops only resolution-dependent raster images.
  ///
  /// Paragraph layout and recorded vector pictures remain valid.
  void invalidateRasterImages();

  /// The render object also advances its paragraph generation. Private
  /// painters/caches may need explicit invalidation even with equal inputs.
  void systemFontsDidChange() => invalidateRasterImages();

  void dispose();
}

/// Bakes `effectiveColor` into the paragraph at layout time and draws it
/// directly. Used when tinting would be lossy (colour emoji, `foreground`
/// Paint, `background` Paint) or too memory-hungry.
class DirectPaintStrategy extends PaintStrategy {
  ui.Picture? _logicalShadowPicture;
  TextPainter? _logicalShadowPainter;
  int _logicalShadowGeneration = -1;
  double _logicalShadowScale = 0;
  double _strokeShadowScale = 0;

  /// Spread entries can't be baked into the paragraph; they're recorded once
  /// as stroke passes and replayed under the main painter. A vector picture:
  /// no raster to invalidate, safe for the static-text golden path.
  ui.Picture? _spreadPicture;
  int _spreadGeneration = -1;
  List<Shadow>? _spreadShadows;
  ParagraphInput? _spreadInput;
  TextPainter? _spreadPainter;

  /// The stroke and the shadows under it, recorded once per generation,
  /// stroke and shadow list.
  ui.Picture? _strokePicture;
  int _strokeGeneration = -1;
  TextStroke? _stroke;
  List<Shadow>? _strokeShadows;

  @override
  PaintStrategyKind get kind => .direct;

  @override
  void paint(
    PaintingContext context,
    Offset offset,
    ParagraphResult layout,
    int generation,
    Color effectiveColor,
    List<Shadow> shadows,
    double rasterPixelRatio,
    Offset? deviceTextOrigin, {
    TextStroke? stroke,
  }) {
    if (_hasSpread(shadows)) {
      _ensureSpreadPicture(layout, generation, shadows);
      final picture = _spreadPicture;
      if (picture != null) {
        final canvas = context.canvas
          ..save()
          ..translate(offset.dx, offset.dy);
        canvas.drawPicture(picture);
        canvas.restore();
      }
    }
    if (stroke != null) {
      _ensureStrokePicture(
        layout,
        generation,
        shadows,
        stroke,
        rasterPixelRatio,
      );
      context.canvas
        ..save()
        ..translate(offset.dx, offset.dy)
        ..drawPicture(_strokePicture!)
        ..restore();
    }
    if (stroke == null && shadows.any((shadow) => shadow.blurRadius > 0)) {
      // Record native shadows with a scale-adjusted sigma. Keep the fill,
      // native emoji and rich spans on the engine's ordinary paragraph path.
      if (_logicalShadowPicture == null ||
          _logicalShadowGeneration != generation ||
          _logicalShadowScale != rasterPixelRatio) {
        _logicalShadowPicture?.dispose();
        final painter = _logicalShadowPainter ??= TextPainter(
          textDirection: .ltr,
        );
        final input = layout.input.copyWith(
          style: layout.input.style.copyWith(
            shadows: textShadowsAtScale(shadows, rasterPixelRatio),
          ),
        );
        Paragrapher.configure(painter, input);
        painter.layout(maxWidth: input.maxWidth);
        final recorder = ui.PictureRecorder();
        painter.paint(Canvas(recorder), .zero);
        _logicalShadowPicture = recorder.endRecording();
        _logicalShadowGeneration = generation;
        _logicalShadowScale = rasterPixelRatio;
      }
      context.canvas
        ..save()
        ..translate(offset.dx, offset.dy)
        ..drawPicture(_logicalShadowPicture!)
        ..restore();
    } else {
      layout.painter.paint(context.canvas, offset);
    }
  }

  void _ensureStrokePicture(
    ParagraphResult layout,
    int generation,
    List<Shadow> shadows,
    TextStroke stroke,
    double shadowScale,
  ) {
    if (_strokePicture != null &&
        _strokeGeneration == generation &&
        _strokeShadowScale == shadowScale &&
        _stroke == stroke &&
        _sameShadowColors(shadows, _strokeShadows!)) {
      return;
    }
    _strokePicture?.dispose();
    final painter = _spreadPainter ??= TextPainter(textDirection: .ltr);
    final recorder = ui.PictureRecorder();
    _paintStrokePass(
      Canvas(recorder),
      painter,
      layout,
      stroke,
      shadows,
      asMask: false,
      withShadows: true,
      shadowScale: shadowScale,
    );
    _strokeShadowScale = shadowScale;
    _strokePicture = recorder.endRecording();
    _strokeGeneration = generation;
    _stroke = stroke;
    _strokeShadows = List.unmodifiable(shadows);
  }

  void _ensureSpreadPicture(
    ParagraphResult layout,
    int generation,
    List<Shadow> shadows,
  ) {
    // This picture contains ONLY spread strokes. Rebuilding the foreground
    // paragraph is not evidence that these strokes changed. Keep real native
    // emoji colors and drawing order; no masks, tinting or extra surfaces.
    final sameGeneration = _spreadGeneration == generation;
    if (_spreadPicture != null &&
        _sameSpreadStrokes(shadows, _spreadShadows!) &&
        (sameGeneration ||
            (MonetPerfDebugSwitches.reuseDirectTextPaint &&
                _spreadInput != null &&
                sameDirectSpreadBase(_spreadInput!, layout.input)))) {
      RasterCacheDiagnostics.record(.text, .directSpreadReused);
      if (!sameGeneration) {
        RasterCacheDiagnostics.record(.text, .directSpreadPaintReuse);
        _spreadGeneration = generation;
      }
      return;
    }
    _spreadPicture?.dispose();
    final painter = _spreadPainter ??= TextPainter(textDirection: .ltr);
    final recorder = ui.PictureRecorder();
    _paintSpreadStrokes(
      Canvas(recorder),
      painter,
      layout,
      shadows,
      asMask: false,
    );
    _spreadPicture = recorder.endRecording();
    _spreadGeneration = generation;
    _spreadInput = layout.input;
    _spreadShadows = List.unmodifiable(shadows.where(_isSpreadStroke));
    RasterCacheDiagnostics.record(.text, .directSpreadBuilt);
  }

  @override
  void systemFontsDidChange() {
    _spreadPicture?.dispose();
    _spreadPicture = null;
    _spreadInput = null;
    _strokePicture?.dispose();
    _strokePicture = null;
    _spreadPainter?.markNeedsLayout();
    _logicalShadowPicture?.dispose();
    _logicalShadowPicture = null;
    _logicalShadowPainter?.markNeedsLayout();
  }

  @override
  void invalidateRasterImages() {
    assert(kind == .direct, 'Direct paint owns no raster images.');
  }

  @override
  void dispose() {
    _spreadPicture?.dispose();
    _spreadPicture = null;
    _strokePicture?.dispose();
    _strokePicture = null;
    _spreadPainter?.dispose();
    _spreadPainter = null;
    _spreadInput = null;
    _spreadShadows = null;
    _strokeShadows = null;
    _logicalShadowPicture?.dispose();
    _logicalShadowPicture = null;
    _logicalShadowPainter?.dispose();
    _logicalShadowPainter = null;
  }
}

bool _sameShadowColors(List<Shadow> a, List<Shadow> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].color != b[i].color ||
        a[i].offset != b[i].offset ||
        a[i].blurRadius != b[i].blurRadius ||
        spreadOf(a[i]) != spreadOf(b[i])) {
      return false;
    }
  }
  return true;
}

bool _isSpreadStroke(Shadow shadow) =>
    spreadOf(shadow) > 0 && shadow.color.a > 0;

bool _sameSpreadStrokes(List<Shadow> shadows, List<Shadow> strokes) {
  var index = 0;
  for (final shadow in shadows) {
    if (!_isSpreadStroke(shadow)) continue;
    if (index == strokes.length) return false;
    final previous = strokes[index++];
    // This is a float-colored Paint, NOT ParagraphBuilder's ARGB32 color.
    if (shadow.color != previous.color ||
        shadow.offset != previous.offset ||
        shadow.blurRadius != previous.blurRadius ||
        spreadOf(shadow) != spreadOf(previous)) {
      return false;
    }
  }
  return index == strokes.length;
}

/// Memory-safe fallback when a tint mask is not admitted by the byte budget.
///
/// This repeats paragraph layout while under pressure, but unlike a saveLayer
/// fallback it cannot allocate another full-size offscreen surface and bypass
/// the very limit that rejected the retained image.
void _paintDirectFallback(
  Canvas canvas,
  Offset offset,
  ParagraphResult layout,
  Color effectiveColor,
  List<Shadow> shadows,
  TextPainter painter, {
  TextStroke? stroke,
  double shadowScale = 1,
}) {
  // Cache misses may produce NO images and still shape/draw every frame.
  // Keep this separate from render-object paragraph rebuilds: its private
  // fallback painter does not flow through _rebuildParagraphInPlace.
  RasterCacheDiagnostics.record(.text, .directFallbackPaints);
  canvas.save();
  try {
    canvas.translate(offset.dx, offset.dy);
    if (_hasSpread(shadows)) {
      _paintSpreadStrokes(canvas, painter, layout, shadows, asMask: false);
    }
    if (stroke != null) {
      _paintStrokePass(
        canvas,
        painter,
        layout,
        stroke,
        shadows,
        asMask: false,
        withShadows: true,
        shadowScale: shadowScale,
      );
    }
    final input = layout.input.copyWith(
      style: layout.input.style.copyWith(
        shadows: stroke == null
            ? textShadowsAtScale(shadows, shadowScale)
            : const [],
      ),
      paintColor: effectiveColor,
    );
    Paragrapher.configure(painter, input);
    painter.layout(maxWidth: input.maxWidth);
    painter.paint(canvas, .zero);
  } finally {
    canvas.restore();
  }
}

/// Records a paragraph laid out in Impeller's canonical black/white glyph tone
/// into a `ui.Picture`, lazily rasterizes that picture to a DPR-aware mask
/// image, and tints the mask inline with `drawImageRect`.
///
/// This removes the per-frame `pushColorFilter` compositing layer from the
/// paint-bus path. Rasterisation is only redone when the paragraph generation
/// or effective raster scale (device pixel ratio × ancestor paint scale)
/// changes. Same-tone colour ticks only swap the tint paint; the render object
/// advances the generation once if Impeller's foreground tone threshold is
/// crossed.
class TintPaintStrategy extends PaintStrategy {
  TintPaintStrategy({this.onRasterEvicted, this.onRequestRepaint});

  final VoidCallback? onRasterEvicted;

  /// Requests one more paint, outside the current paint phase.
  final VoidCallback? onRequestRepaint;
  final _MaskPhase _phase = _MaskPhase();
  ui.Picture? _picture;
  // ignore: dispose-class-fields
  ui.Image? _image;
  _RasterSpec? _imageSpec;
  _TextMaskAdmissionDenial? _admissionDenial;
  double _imageDpr = 0;
  int _pictureGeneration = -1;
  final Object _imageBudgetKey = Object();
  final _TintedImagePaintCache _imagePaint = _TintedImagePaintCache();
  TextPainter? _fallbackPainter;

  /// Test-only view of the cached mask raster, for asserting that ancestor
  /// paint scales are reflected in raster resolution.
  @visibleForTesting
  ui.Image? debugImage() => _image;

  /// Test-only view of the effective raster scale the cached mask was built
  /// at (device pixel ratio × quantized ancestor scale).
  @visibleForTesting
  double debugImageDpr() => _imageDpr;

  @override
  PaintStrategyKind get kind => .tint;

  @override
  void paint(
    PaintingContext context,
    Offset offset,
    ParagraphResult layout,
    int generation,
    Color effectiveColor,
    List<Shadow> shadows,
    double rasterPixelRatio,
    Offset? deviceTextOrigin, {
    TextStroke? stroke,
  }) {
    assert(stroke == null, 'A stroke uses the layered or direct strategy.');
    if (_pictureGeneration != generation) {
      _rebuildPicture(layout, generation);
    }
    final dpr = rasterPixelRatio;
    final bounds = _foregroundRasterBounds(layout.size);
    final phase = _MaskPhaseRequest.at(deviceTextOrigin, bounds.topLeft, dpr);
    if (_image != null &&
        _imageDpr == dpr &&
        _phase.needsRemask(phase, onRequestRepaint)) {
      _dropImage(.rasterPhase);
    }
    final image = _ensureImage(bounds, dpr, phase.quantized);
    if (image == null) {
      _paintDirectFallback(
        context.canvas,
        offset,
        layout,
        effectiveColor,
        shadows,
        _fallbackPainter ??= TextPainter(textDirection: .ltr),
        shadowScale: rasterPixelRatio,
      );
      return;
    }
    _drawTintedImage(
      context.canvas,
      image,
      offset + bounds.topLeft,
      bounds.size,
      dpr,
      effectiveColor,
      _imagePaint,
      phase: _phase.baked,
      shift: _phase.drawShift(phase),
    );
  }

  void _rebuildPicture(ParagraphResult layout, int generation) {
    _picture?.dispose();
    _dropImage(.generation);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    layout.painter.paint(canvas, .zero);
    _picture = recorder.endRecording();
    _pictureGeneration = generation;
  }

  ui.Image? _ensureImage(Rect bounds, double dpr, Offset phase) {
    final picture = _picture;
    if (picture == null) return null;
    // Colour ticks intentionally do not invalidate this image. It only depends
    // on glyph coverage and the effective raster scale (physical pixel ratio ×
    // ancestor paint scale); the tint is applied per draw.
    if (_image != null && _imageDpr == dpr) {
      RasterCacheDiagnostics.record(.text, .hit);
      _textMaskImageBudget.touch(_imageBudgetKey);
      return _image;
    }
    RasterCacheDiagnostics.record(.text, .miss);
    if (_image != null) _dropImage(.rasterScale);
    final spec = _rasterSpecFor(bounds, dpr, phase);
    if (spec == null) return null;
    final requestSignature = spec.signature;
    final retry = _admissionDenial?.requestSignature == requestSignature;
    if (_admissionDenial?.stillApplies(requestSignature) ?? false) {
      RasterCacheDiagnostics.record(.text, .admissionMemoHit);
      return null;
    }
    if (!_textMaskImageBudget.tryReserveAll([
      RasterMaskImageReservation(
        key: _imageBudgetKey,
        estimatedBytes: spec.estimatedBytes,
        evict: _evictImageFromBudget,
      ),
    ], protectPreviousFrame: retry)) {
      RasterCacheDiagnostics.record(.text, .admissionDenied);
      _admissionDenial = _TextMaskAdmissionDenial(
        requestSignature,
        spec.estimatedBytes,
        _textMaskImageBudget.lastRejection!,
      );
      return null;
    }
    try {
      if (retry) RasterCacheDiagnostics.record(.text, .admissionRecovered);
      _image = _rasterizePictureAtDpr(picture, bounds, dpr, spec, phase);
      _imageSpec = spec;
      _imageDpr = dpr;
      _phase.bake(phase);
      _admissionDenial = null;
    } catch (_) {
      _dropImage(.rasterFailure);
      rethrow;
    }
    return _image;
  }

  void _dropImage(RasterCacheEvent reason) {
    _textMaskImageBudget.release(_imageBudgetKey);
    _evictImage(reason);
    _admissionDenial = null;
  }

  void _evictImage(RasterCacheEvent reason) {
    final image = _image;
    if (image != null) {
      RasterCacheDiagnostics.invalidated(
        .text,
        reason,
        image.width * image.height,
      );
    }
    _image?.dispose();
    _image = null;
    _imageSpec = null;
    _imageDpr = 0;
  }

  void _evictImageFromBudget() {
    final spec = _imageSpec;
    _evictImage(.budgetEviction);
    if (spec != null) {
      _admissionDenial = _TextMaskAdmissionDenial(
        spec.signature,
        spec.estimatedBytes,
        .visibleSet,
        allowIdleRetry: !_textMaskImageBudget.isClearing,
      );
    }
    onRasterEvicted?.call();
  }

  @override
  void invalidateRasterImages() => _dropImage(.rasterScale);

  @override
  void systemFontsDidChange() {
    super.systemFontsDidChange();
    _fallbackPainter?.markNeedsLayout();
  }

  @override
  void dispose() {
    _picture?.dispose();
    _dropImage(.ownerDispose);
    _fallbackPainter?.dispose();
    _fallbackPainter = null;
    _picture = null;
  }
}

/// Records one white/alpha shadow mask and one tone-correct foreground mask.
///
/// Paint-time work is intentionally tiny: draw the cached shadow mask tinted
/// with the current shadow colour, then draw the cached foreground mask tinted
/// with the current foreground colour. Rasterisation is only redone when glyph
/// coverage, shadow alpha/offset/blur, or effective raster scale changes;
/// same-tone paint-bus colour ticks only swap tint paints. Crossing Impeller's
/// foreground tone threshold advances the paragraph generation and remasks
/// once. This keeps wallpaper protection shadows visually in lockstep with
/// foreground text without recreating blurred shadow bitmaps every frame.
class LayeredShadowTintPaintStrategy extends PaintStrategy {
  LayeredShadowTintPaintStrategy({this.onRasterEvicted, this.onRequestRepaint});

  final VoidCallback? onRasterEvicted;

  /// Requests one more paint, outside the current paint phase.
  final VoidCallback? onRequestRepaint;

  /// Phase of the foreground mask. Shadow masks are blurred, so resampling
  /// them is not visible; an underlay with a crisp stroke has its own phase.
  final _MaskPhase _foregroundPhase = _MaskPhase();
  final _MaskPhase _underlayPhase = _MaskPhase();
  ui.Picture? _foregroundPicture;
  // ignore: dispose-class-fields
  ui.Image? _foregroundImage;
  double _foregroundImageDpr = 0;
  ui.Picture? _shadowPicture;
  // ignore: dispose-class-fields
  ui.Image? _shadowImage;
  Offset _shadowImageOffset = .zero;
  Size _shadowImageLogicalSize = .zero;
  double _shadowImageDpr = 0;
  int _foregroundGeneration = -1;
  int _shadowGeneration = -1;
  double _shadowPictureScale = 0;
  List<Shadow>? _shadowImageShadows;

  /// The stroke in the underlay mask. Its RGB matches the shadows' (see
  /// [underlayTintFor]), so one tint serves both.
  TextStroke? _shadowImageStroke;
  int? _admissionSignature;
  int _admissionBytes = 0;
  _TextMaskAdmissionDenial? _admissionDenial;
  final Object _foregroundBudgetKey = Object();
  final Object _shadowBudgetKey = Object();
  final _TintedImagePaintCache _shadowImagePaint = _TintedImagePaintCache();
  final _TintedImagePaintCache _foregroundPaint = _TintedImagePaintCache();
  final TextPainter _shadowPainter = TextPainter(textDirection: .ltr);
  TextPainter? _fallbackPainter;

  /// Test-only view of the single cached foreground mask.
  @visibleForTesting
  ui.Image? debugForegroundImage() => _foregroundImage;

  @override
  PaintStrategyKind get kind => .layeredShadowTint;

  @override
  void paint(
    PaintingContext context,
    Offset offset,
    ParagraphResult layout,
    int generation,
    Color effectiveColor,
    List<Shadow> shadows,
    double rasterPixelRatio,
    Offset? deviceTextOrigin, {
    TextStroke? stroke,
  }) {
    if (_foregroundGeneration != generation) {
      _rebuildForegroundPicture(layout, generation);
    }
    final dpr = rasterPixelRatio;
    if (_shadowGeneration != generation ||
        _shadowPictureScale != dpr ||
        !_shadowUnderlayShapeEqual(shadows, _shadowImageShadows) ||
        (stroke == null) != (_shadowImageStroke == null) ||
        (stroke != null && !stroke.sameShape(_shadowImageStroke))) {
      _rebuildShadowPicture(layout, generation, shadows, stroke, dpr);
    }
    final needsUnderlay = shadows.isNotEmpty || stroke != null;

    final foregroundBounds = _foregroundRasterBounds(layout.size);
    final phase = _MaskPhaseRequest.at(
      deviceTextOrigin,
      foregroundBounds.topLeft,
      dpr,
    );
    if (_foregroundImage != null &&
        _foregroundImageDpr == dpr &&
        _foregroundPhase.needsRemask(phase, onRequestRepaint)) {
      _dropImages(.rasterPhase);
    }
    final underlayPhase = stroke == null
        ? _MaskPhaseRequest.unknown
        : _MaskPhaseRequest.at(deviceTextOrigin, _shadowImageOffset, dpr);
    if (_shadowImage != null &&
        _shadowImageDpr == dpr &&
        _underlayPhase.needsRemask(underlayPhase, onRequestRepaint)) {
      _dropImages(.rasterPhase);
    }
    if (!_ensureImages(
      foregroundBounds,
      dpr,
      needsUnderlay,
      phase.quantized,
      underlayPhase.quantized,
    )) {
      _paintDirectFallback(
        context.canvas,
        offset,
        layout,
        effectiveColor,
        shadows,
        _fallbackPainter ??= TextPainter(textDirection: .ltr),
        stroke: stroke,
        shadowScale: rasterPixelRatio,
      );
      return;
    }

    final shadowImage = _shadowImage;
    if (shadowImage != null) {
      if (MonetPerfDebugSwitches.logCachedTextImageRects) {
        final width = _shadowImageLogicalSize.width * dpr;
        final height = _shadowImageLogicalSize.height * dpr;
        final srcRect = Rect.fromLTWH(0, 0, width, height);
        final shadowRect =
            (offset + _shadowImageOffset) & _shadowImageLogicalSize;
        logDebug(
          '[CachedTextImageRects] shadow '
          'image=${shadowImage.width}x${shadowImage.height} '
          'logical=$_shadowImageLogicalSize dpr=$dpr '
          'src=$srcRect dst=$shadowRect offset=$_shadowImageOffset '
          'generation=$generation',
        );
      }
      _drawTintedImage(
        context.canvas,
        shadowImage,
        offset + _shadowImageOffset,
        _shadowImageLogicalSize,
        dpr,
        underlayTintFor(shadows, stroke),
        _shadowImagePaint,
        phase: _underlayPhase.baked,
        shift: _underlayPhase.drawShift(underlayPhase),
      );
    }

    final foregroundImage = _foregroundImage!;
    _drawTintedImage(
      context.canvas,
      foregroundImage,
      offset + foregroundBounds.topLeft,
      foregroundBounds.size,
      dpr,
      effectiveColor,
      _foregroundPaint,
      phase: _foregroundPhase.baked,
      shift: _foregroundPhase.drawShift(phase),
    );
  }

  void _rebuildForegroundPicture(ParagraphResult layout, int generation) {
    _foregroundPicture?.dispose();
    _dropForegroundImage(.generation);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    layout.painter.paint(canvas, .zero);
    _foregroundPicture = recorder.endRecording();
    _foregroundGeneration = generation;
  }

  void _rebuildShadowPicture(
    ParagraphResult layout,
    int generation,
    List<Shadow> shadows,
    TextStroke? stroke,
    double shadowScale,
  ) {
    _shadowPictureScale = shadowScale;
    _shadowPicture?.dispose();
    _shadowPicture = null;
    _dropShadowImage(
      _shadowGeneration == generation ? .shadowShape : .generation,
    );
    _shadowImageOffset = .zero;
    _shadowImageLogicalSize = .zero;
    _shadowGeneration = generation;
    _shadowImageShadows = List.unmodifiable(shadows);
    _shadowImageStroke = stroke;
    if (shadows.isEmpty && stroke == null) return;

    final input = layout.input.copyWith(
      // Rasterize the shadow as an alpha mask, not as a fully-coloured bitmap.
      // The RGB comes from `_shadowTintFor(shadows)` at paint time, matching the
      // foreground mask path and avoiding per-colour re-rasterization.
      style: layout.input.style.copyWith(
        shadows: textShadowsAtScale(_shadowMaskShadows(shadows), shadowScale),
      ),
      paintColor: const Color(0x00000000),
    );
    Paragrapher.configure(_shadowPainter, input);
    _shadowPainter.layout(maxWidth: input.maxWidth);

    var bounds = _shadowRasterBounds(layout.size, shadows);
    if (stroke != null) {
      // The full public width is outside the glyph, plus antialiasing.
      final reach = (stroke.width + 1).ceilToDouble();
      bounds = bounds.expandToInclude(
        _foregroundRasterBounds(layout.size).inflate(reach),
      );
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    _shadowPainter.paint(canvas, .zero);
    // Spread entries ride the same cached mask: white stroke passes at each
    // shadow's alpha, tinted by the shared srcIn filter at draw time. The
    // painter is reused; each configure/layout/paint executes immediately
    // into the recording.
    if (_hasSpread(shadows)) {
      _paintSpreadStrokes(
        canvas,
        _shadowPainter,
        layout,
        shadows,
        asMask: true,
      );
    }
    // Same-colour white layers: the order of their alpha does not matter.
    if (stroke != null) {
      _paintStrokePass(
        canvas,
        _shadowPainter,
        layout,
        stroke,
        shadows,
        asMask: true,
        withShadows: false,
      );
    }
    _shadowPicture = recorder.endRecording();
    _shadowImageOffset = bounds.topLeft;
    _shadowImageLogicalSize = bounds.size;
  }

  bool _ensureImages(
    Rect foregroundBounds,
    double dpr,
    bool needsShadow,
    Offset foregroundPhase,
    Offset underlayPhase,
  ) {
    if (_foregroundImage != null && _foregroundImageDpr != dpr) {
      _dropImages(.rasterScale);
    }
    if (_shadowImage != null && _shadowImageDpr != dpr) {
      _dropImages(.rasterScale);
    }

    final foregroundReady = _foregroundImage != null;
    final shadowReady = !needsShadow || _shadowImage != null;
    if (foregroundReady && shadowReady) {
      RasterCacheDiagnostics.record(.text, .hit, needsShadow ? 2 : 1);
      _textMaskImageBudget.touch(_foregroundBudgetKey);
      if (needsShadow) _textMaskImageBudget.touch(_shadowBudgetKey);
      return true;
    }

    RasterCacheDiagnostics.record(
      .text,
      .miss,
      (foregroundReady ? 0 : 1) + (shadowReady ? 0 : 1),
    );
    final foregroundSpec = _rasterSpecFor(
      foregroundBounds,
      dpr,
      foregroundPhase,
    );
    final shadowBounds = _shadowImageOffset & _shadowImageLogicalSize;
    final shadowSpec = needsShadow
        ? _rasterSpecFor(shadowBounds, dpr, underlayPhase)
        : null;
    final foregroundPicture = _foregroundPicture;
    final shadowPicture = _shadowPicture;
    if (foregroundSpec == null ||
        foregroundPicture == null ||
        (needsShadow && (shadowSpec == null || shadowPicture == null))) {
      _dropImages(.pairRebuild);
      return false;
    }

    final requestSignature = Object.hash(
      foregroundSpec.signature,
      needsShadow ? shadowSpec!.signature : null,
    );
    final retry = _admissionDenial?.requestSignature == requestSignature;
    final denial = _admissionDenial;
    if (denial?.stillApplies(requestSignature) ?? false) {
      // One member may have survived until its partner was evicted. Release it
      // once, then pin the denial to the new availability revision so this
      // visible pair settles on direct fallback instead of cycling allocations.
      _dropImages(.pairRebuild);
      RasterCacheDiagnostics.record(.text, .admissionDenied);
      RasterCacheDiagnostics.record(.text, .admissionMemoHit);
      _admissionDenial = _TextMaskAdmissionDenial(
        requestSignature,
        denial!.requestedBytes,
        denial.reason,
        allowIdleRetry: denial.allowIdleRetry,
      );
      return false;
    }

    // A layered pair is useful only as a pair. Re-reserve and create both
    // atomically if either half was invalidated or evicted.
    _dropImages(.pairRebuild);

    final reservations = [
      RasterMaskImageReservation(
        key: _foregroundBudgetKey,
        estimatedBytes: foregroundSpec.estimatedBytes,
        evict: _evictForegroundImageFromBudget,
      ),
      if (needsShadow)
        RasterMaskImageReservation(
          key: _shadowBudgetKey,
          estimatedBytes: shadowSpec!.estimatedBytes,
          evict: _evictShadowImageFromBudget,
        ),
    ];
    final requestedBytes =
        foregroundSpec.estimatedBytes + (shadowSpec?.estimatedBytes ?? 0);
    if (!_textMaskImageBudget.tryReserveAll(
      reservations,
      protectPreviousFrame: retry,
    )) {
      RasterCacheDiagnostics.record(.text, .admissionDenied);
      _admissionDenial = _TextMaskAdmissionDenial(
        requestSignature,
        requestedBytes,
        _textMaskImageBudget.lastRejection!,
      );
      return false;
    }

    try {
      if (retry) RasterCacheDiagnostics.record(.text, .admissionRecovered);
      _foregroundImage = _rasterizePictureAtDpr(
        foregroundPicture,
        foregroundBounds,
        dpr,
        foregroundSpec,
        foregroundPhase,
      );
      _foregroundImageDpr = dpr;
      _foregroundPhase.bake(foregroundPhase);
      if (needsShadow) {
        _shadowImage = _rasterizePictureAtDpr(
          shadowPicture!,
          shadowBounds,
          dpr,
          shadowSpec!,
          underlayPhase,
        );
        _shadowImageDpr = dpr;
        _underlayPhase.bake(underlayPhase);
      }
      _admissionSignature = requestSignature;
      _admissionBytes = requestedBytes;
      _admissionDenial = null;
    } catch (_) {
      _dropImages(.rasterFailure);
      rethrow;
    }
    return true;
  }

  Rect _shadowRasterBounds(Size size, List<Shadow> shadows) {
    var left = 0.0;
    var top = 0.0;
    var right = size.width;
    var bottom = size.height;
    for (final shadow in shadows) {
      final expansion = shadow.blurSigma * 3 + spreadOf(shadow);
      left = math.min(left, shadow.offset.dx - expansion);
      top = math.min(top, shadow.offset.dy - expansion);
      right = math.max(right, shadow.offset.dx + size.width + expansion);
      bottom = math.max(bottom, shadow.offset.dy + size.height + expansion);
    }
    return Rect.fromLTRB(
      left.floorToDouble(),
      top.floorToDouble(),
      right.ceilToDouble(),
      bottom.ceilToDouble(),
    );
  }

  @override
  void invalidateRasterImages() => _dropImages(.rasterScale);

  @override
  void systemFontsDidChange() {
    super.systemFontsDidChange();
    _shadowPainter.markNeedsLayout();
    _fallbackPainter?.markNeedsLayout();
  }

  void _dropImages(RasterCacheEvent reason) {
    _dropForegroundImage(reason);
    _dropShadowImage(reason);
    _admissionSignature = null;
    _admissionDenial = null;
  }

  void _dropForegroundImage(RasterCacheEvent reason) {
    _textMaskImageBudget.release(_foregroundBudgetKey);
    _evictForegroundImage(reason);
    _admissionSignature = null;
    _admissionDenial = null;
  }

  void _evictForegroundImage(RasterCacheEvent reason) {
    final image = _foregroundImage;
    if (image != null) {
      RasterCacheDiagnostics.invalidated(
        .text,
        reason,
        image.width * image.height,
      );
    }
    _foregroundImage?.dispose();
    _foregroundImage = null;
    _foregroundImageDpr = 0;
  }

  void _evictForegroundImageFromBudget() {
    final requestSignature = _admissionSignature;
    _evictForegroundImage(.budgetEviction);
    if (requestSignature != null) {
      RasterCacheDiagnostics.record(.text, .admissionDenied);
      _admissionDenial = _TextMaskAdmissionDenial(
        requestSignature,
        _admissionBytes,
        .visibleSet,
        allowIdleRetry: !_textMaskImageBudget.isClearing,
      );
    }
    onRasterEvicted?.call();
  }

  void _dropShadowImage(RasterCacheEvent reason) {
    _textMaskImageBudget.release(_shadowBudgetKey);
    _evictShadowImage(reason);
    _admissionSignature = null;
    _admissionDenial = null;
  }

  void _evictShadowImage(RasterCacheEvent reason) {
    final image = _shadowImage;
    if (image != null) {
      RasterCacheDiagnostics.invalidated(
        .text,
        reason,
        image.width * image.height,
      );
    }
    _shadowImage?.dispose();
    _shadowImage = null;
    _shadowImageDpr = 0;
  }

  void _evictShadowImageFromBudget() {
    final requestSignature = _admissionSignature;
    _evictShadowImage(.budgetEviction);
    if (requestSignature != null) {
      RasterCacheDiagnostics.record(.text, .admissionDenied);
      _admissionDenial = _TextMaskAdmissionDenial(
        requestSignature,
        _admissionBytes,
        .visibleSet,
        allowIdleRetry: !_textMaskImageBudget.isClearing,
      );
    }
    onRasterEvicted?.call();
  }

  @override
  void dispose() {
    _foregroundPicture?.dispose();
    _shadowPicture?.dispose();
    _dropImages(.ownerDispose);
    _foregroundPicture = null;
    _shadowPicture = null;
    _shadowImageLogicalSize = .zero;
    _shadowImageStroke = null;
    _shadowPainter.dispose();
    _fallbackPainter?.dispose();
    _fallbackPainter = null;
  }
}

/// Experimental retained ordinary-text mask + untinted native emoji pass.
///
/// No per-glyph positions or substring layouts: both complementary paragraphs
/// keep ALL the original text. Native emoji is never sent through srcIn.
/// Foreground RGB does not reshape either pass. Shadows remain direct: native
/// colour-font spread/shadow rendering differs from an alpha-only shadow mask. Opacity changes
/// rebuild the native pass, since color-glyph alpha is baked by TextPainter.
/// A geometry mismatch or mask budget denial uses the original direct path.
/// Not enabled by default: Unicode presentation cannot guarantee that the
/// actual fallback font supplies colour rather than monochrome emoji glyphs.
class EmojiTintPaintStrategy extends PaintStrategy {
  EmojiTintPaintStrategy({
    VoidCallback? onRasterEvicted,
    VoidCallback? onRequestRepaint,
  }) : _mask = TintPaintStrategy(
         onRasterEvicted: onRasterEvicted,
         onRequestRepaint: onRequestRepaint,
       );

  final TintPaintStrategy _mask;
  TextPainter? _fallbackPainter;

  final Paragrapher _ordinary = Paragrapher();
  final Paragrapher _emoji = Paragrapher();
  ParagraphResult? _ordinaryLayout;
  ParagraphResult? _emojiLayout;
  int _splitGeneration = -1;
  double? _emojiAlpha;
  bool _geometryMatches = false;

  @override
  PaintStrategyKind get kind => .emojiTint;

  @override
  void paint(
    PaintingContext context,
    Offset offset,
    ParagraphResult layout,
    int generation,
    Color effectiveColor,
    List<Shadow> shadows,
    double rasterPixelRatio,
    Offset? deviceTextOrigin, {
    TextStroke? stroke,
  }) {
    assert(stroke == null, 'A stroke uses the layered or direct strategy.');
    RasterCacheDiagnostics.record(.text, .emojiSplitPaints);
    if (_splitGeneration != generation) {
      final spans = emojiPaintSpansFor(layout.input.text);
      _ordinaryLayout = _ordinary.layout(
        layout.input.copyWith(textSpan: spans.ordinary),
      );
      _emojiLayout = _emoji.layout(
        layout.input.copyWith(
          textSpan: spans.emoji,
          paintColor: const Color(0xffffffff)
              .withValues(alpha: effectiveColor.a),
        ),
      );
      _splitGeneration = generation;
      _emojiAlpha = effectiveColor.a;
      _geometryMatches =
          sameParagraphGeometry(layout, _ordinaryLayout!) &&
          sameParagraphGeometry(layout, _emojiLayout!);
      RasterCacheDiagnostics.record(.text, .emojiSplitBuilds);
    } else if (_emojiAlpha != effectiveColor.a) {
      _emojiLayout = _emoji.layout(
        _emojiLayout!.input.copyWith(
          paintColor: const Color(0xffffffff)
              .withValues(alpha: effectiveColor.a),
        ),
      );
      _emojiAlpha = effectiveColor.a;
      RasterCacheDiagnostics.record(.text, .emojiAlphaBuilds);
    } else {
      RasterCacheDiagnostics.record(.text, .emojiSplitReused);
    }
    if (!_geometryMatches) {
      RasterCacheDiagnostics.record(.text, .emojiGeometryFallbacks);
      _paintDirectFallback(
        context.canvas,
        offset,
        layout,
        effectiveColor,
        shadows,
        _fallbackPainter ??= TextPainter(textDirection: .ltr),
        shadowScale: rasterPixelRatio,
      );
      return;
    }
    // Even budget fallback is complementary: TintPaintStrategy paints only
    // ordinary text (emoji spans are transparent), then we paint emoji once.
    _mask.paint(
      context,
      offset,
      _ordinaryLayout!,
      generation,
      effectiveColor,
      const [],
      rasterPixelRatio,
      deviceTextOrigin,
    );
    _emojiLayout!.painter.paint(context.canvas, offset);
  }

  @override
  void invalidateRasterImages() => _mask.invalidateRasterImages();

  @override
  void systemFontsDidChange() {
    _mask.systemFontsDidChange();
    _ordinary.systemFontsDidChange();
    _emoji.systemFontsDidChange();
    _fallbackPainter?.markNeedsLayout();
  }

  @override
  void dispose() {
    _ordinary.dispose();
    _emoji.dispose();
    _ordinaryLayout = null;
    _emojiLayout = null;
    _mask.dispose();
    _fallbackPainter?.dispose();
    _fallbackPainter = null;
  }
}

const _kForegroundRasterBleed = 1.0;

Rect _foregroundRasterBounds(Size size) => .fromLTRB(
  -_kForegroundRasterBleed,
  -_kForegroundRasterBleed,
  size.width + _kForegroundRasterBleed,
  size.height + _kForegroundRasterBleed,
);

class _RasterSpec {
  const _RasterSpec({
    required this.width,
    required this.height,
    required this.estimatedBytes,
  });

  final int width;
  final int height;
  final int estimatedBytes;

  int get signature => Object.hash(width, height);
}

_RasterSpec? _rasterSpecFor(Rect bounds, double dpr, [Offset phase = .zero]) {
  if (!bounds.isFinite || !dpr.isFinite || dpr <= 0) return null;
  final scaledWidth = bounds.width * dpr + phase.dx;
  final scaledHeight = bounds.height * dpr + phase.dy;
  if (!scaledWidth.isFinite || !scaledHeight.isFinite) return null;
  final width = math.max(1, scaledWidth.ceil());
  final height = math.max(1, scaledHeight.ceil());
  final estimatedBytes = estimateRasterMaskImageBytes(width, height);
  return _RasterSpec(
    width: width,
    height: height,
    estimatedBytes: estimatedBytes,
  );
}

/// Converts a logical-space glyph picture into a physical-pixel mask.
///
/// The cached picture is recorded in logical coordinates; scaling the temporary
/// raster canvas by [dpr] (device pixel ratio × ancestor paint scale) before
/// `toImageSync` gives the mask enough pixels to be drawn back into [bounds]
/// without the softening we saw from 1x masks on high DPI displays — or from
/// DPR-only masks under upscaling ancestors like the Mod screen's
/// `ScaleUpLayout`.
///
/// [bounds] includes a small bleed around the paragraph's logical size.
/// TextPainter itself does not clip glyph ink to that size: outlines touching
/// an ascent/descent edge can contribute antialiasing beyond it. Rasterizing
/// only the logical box made cached text lose those edge pixels even though
/// the equivalent direct paragraph retained them.
///
/// [phase] is the sub-pixel device offset the mask will be drawn at. Glyphs
/// are rasterized at that offset, and the image itself is drawn on whole
/// device pixels; see [_MaskPhase].
ui.Image _rasterizePictureAtDpr(
  ui.Picture picture,
  Rect bounds,
  double dpr,
  _RasterSpec spec, [
  Offset phase = .zero,
]) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..translate(phase.dx, phase.dy)
    ..scale(dpr, dpr)
    ..translate(-bounds.left, -bounds.top);
  canvas.drawPicture(picture);
  final scaledPicture = recorder.endRecording();
  try {
    final image = scaledPicture.toImageSync(spec.width, spec.height);
    RasterCacheDiagnostics.record(.text, .created);
    RasterCacheDiagnostics.record(
      .text,
      .createdPixels,
      spec.width * spec.height,
    );
    return image;
  } finally {
    scaledPicture.dispose();
  }
}

List<Shadow> _shadowMaskShadows(List<Shadow> shadows) {
  return [
    for (final shadow in shadows)
      Shadow(
        // Preserve the original shadow alpha in the cached mask. RGB is
        // deliberately white so `_drawTintedImage(..., srcIn)` can replace it
        // with the current paint-bus shadow colour at draw time.
        color: Color.from(alpha: shadow.color.a, red: 1, green: 1, blue: 1),
        offset: shadow.offset,
        blurRadius: shadow.blurRadius,
      ),
  ];
}

/// The RGB of the layered underlay: the shadows', or the stroke's when no
/// shadow shows.
Color underlayTintFor(List<Shadow> shadows, TextStroke? stroke) {
  final tint = _shadowTintFor(shadows);
  if (tint.a > 0 || stroke == null) return tint;
  return stroke.color.withValues(alpha: 1);
}

/// Whether [stroke] can share the layered underlay's single tint.
bool strokeSharesUnderlayTint(List<Shadow> shadows, TextStroke stroke) {
  final tint = _shadowTintFor(shadows);
  return tint.a == 0 || tint == stroke.color.withValues(alpha: 1);
}

Color _shadowTintFor(List<Shadow> shadows) {
  // This layered strategy is designed for protection shadows, whose entries
  // share one base RGB and differ only by shape/count. Alpha lives in the mask
  // (`_shadowMaskShadows`), so tint with the first non-transparent RGB at full
  // opacity. If a caller supplies genuinely multi-colour shadows, this remains
  // a sensible best-effort fallback; such styles should use direct painting if
  // exact per-shadow RGB is required.
  for (final shadow in shadows) {
    if (shadow.color.a > 0) {
      return shadow.color.withValues(alpha: 1);
    }
  }
  return const Color(0x00000000);
}

void _drawTintedImage(
  Canvas canvas,
  ui.Image image,
  Offset offset,
  Size logicalSize,
  double dpr,
  Color tint,
  _TintedImagePaintCache paintCache, {
  Offset phase = .zero,
  Offset shift = .zero,
}) {
  // `srcIn` treats the mask's alpha as coverage and replaces RGB with the
  // current paint-bus colour. This is the inline equivalent of the old retained
  // ColorFilterLayer, but avoids adding one compositor layer per text element.
  //
  // The image dimensions are integer `ceil(logicalSize * dpr)` values because
  // `toImageSync` requires integer pixels. Draw only the exact logical coverage
  // rect from that image; using the full ceiled image subtly rescales/shrinks
  // glyphs whenever `logicalSize * dpr` is fractional. Filtering keeps scaled
  // space-card previews from sampling the cached masks as chunky pixels.
  //
  // [phase] is the device-pixel offset baked into the image, so its source
  // and destination grow by that amount. [shift] moves the image back by the
  // exact sub-pixel phase of [offset]: the image then starts on a whole device
  // pixel and is sampled 1:1, while its glyphs land at [offset].
  final paint = paintCache.paintFor(tint);
  final srcRect = paintCache.sourceRectFor(logicalSize, dpr, phase);
  final dstRect = Rect.fromLTWH(
    offset.dx - shift.dx / dpr,
    offset.dy - shift.dy / dpr,
    srcRect.width / dpr,
    srcRect.height / dpr,
  );
  if (MonetPerfDebugSwitches.logCachedTextImageRects) {
    logDebug(
      '[CachedTextImageRects] foreground '
      'image=${image.width}x${image.height} '
      'logical=$logicalSize dpr=$dpr '
      'src=$srcRect dst=$dstRect offset=$offset',
    );
  }
  canvas.drawImageRect(image, srcRect, dstRect, paint);
}

class _TintedImagePaintCache {
  Size? _sourceLogicalSize;
  double _sourceDpr = 0;
  Offset _sourcePhase = .zero;
  Rect? _sourceRect;

  Paint paintFor(Color tint) => _sharedTintPaintPool.paintFor(tint);

  Rect sourceRectFor(Size logicalSize, double dpr, Offset phase) {
    final cached = _sourceRect;
    if (cached != null &&
        _sourceLogicalSize == logicalSize &&
        _sourceDpr == dpr &&
        _sourcePhase == phase) {
      return cached;
    }
    _sourceLogicalSize = logicalSize;
    _sourceDpr = dpr;
    _sourcePhase = phase;
    return _sourceRect = Rect.fromLTWH(
      0,
      0,
      logicalSize.width * dpr + phase.dx,
      logicalSize.height * dpr + phase.dy,
    );
  }
}

/// Sub-pixel phases are quantized to this many steps per device pixel.
///
/// Quantizing keeps float noise from causing remasks. The largest glyph
/// position error is half a step: 1/128 of a device pixel.
const _kMaskPhaseSteps = 64;

/// Where one cached mask should be drawn, split into the phase a mask is
/// rasterized with and the exact phase used to draw it.
@immutable
final class _MaskPhaseRequest {
  const _MaskPhaseRequest(this.quantized, this.exact);

  /// No known device position: phase zero, drawn as before.
  static const unknown = _MaskPhaseRequest(.zero, .zero);

  /// [deviceTextOrigin] plus the mask's logical [topLeft], in device pixels.
  factory _MaskPhaseRequest.at(
    Offset? deviceTextOrigin,
    Offset topLeft,
    double dpr,
  ) {
    if (deviceTextOrigin == null) return unknown;
    final origin = deviceTextOrigin + topLeft * dpr;
    final x = _axis(origin.dx), y = _axis(origin.dy);
    if (!x.quantized.isFinite || !y.quantized.isFinite) return unknown;
    return _MaskPhaseRequest(
      Offset(x.quantized, y.quantized),
      Offset(x.exact, y.exact),
    );
  }

  /// Phase baked into a newly rasterized mask. Always in `[0, 1)`.
  final Offset quantized;

  /// Exact phase, kept within half a step of [quantized]. A phase that rounds
  /// up to 1 becomes 0, and its exact value becomes slightly negative.
  final Offset exact;

  static _AxisPhase _axis(double v) {
    final exact = v - v.floorToDouble();
    final quantized =
        (exact * _kMaskPhaseSteps).roundToDouble() / _kMaskPhaseSteps;
    return quantized >= 1
        ? _AxisPhase(0.0, exact - 1)
        : _AxisPhase(quantized, exact);
  }
}

/// Tracks the sub-pixel phase of one cached mask.
///
/// The first mask uses the current phase. When the text later moves to a
/// new phase, the mask is rebuilt only after two paints in a row at that
/// phase. Until then the old mask is drawn at the correct position, but
/// resampled. A scroll at fractional offsets changes the phase every frame,
/// so rebuilding immediately would rasterize every tinted text per frame.
/// One extra paint is requested so a settled text still gets its sharp mask.
final class _MaskPhase {
  /// Phase baked into the current mask image.
  Offset baked = .zero;
  Offset? _pending;

  void bake(Offset phase) {
    baked = phase;
    _pending = null;
  }

  /// Whether the current mask should be rebuilt for [request].
  bool needsRemask(_MaskPhaseRequest request, VoidCallback? requestRepaint) {
    final phase = request.quantized;
    if (phase == baked) {
      _pending = null;
      return false;
    }
    if (phase == _pending || requestRepaint == null) return true;
    _pending = phase;
    requestRepaint();
    return false;
  }

  /// How far to move the mask back so its glyphs land on [request].
  Offset drawShift(_MaskPhaseRequest request) =>
      request.quantized == baked ? request.exact : baked;
}

/// Small process-wide pool of immutable-by-convention tint paints.
///
/// A palette tick commonly repaints dozens of text render objects with the
/// same colour. Giving every `_TintedImagePaintCache` its own mutable [Paint]
/// created one Dart and native [ColorFilter] per text per tick. Canvas draw
/// calls consume a Paint synchronously, so equal tints can safely share one
/// preconfigured Paint without changing the recorded display list.
///
/// Search newest-first: adjacent text normally shares a tint, while layered
/// shadow text alternates between only two. Eight entries cover those paint
/// channels without retaining an unbounded animation-colour history.
final _sharedTintPaintPool = _TintPaintPool();

final class _TintPaintPool {
  static const _capacity = 8;
  final _entries = <_TintPaint>[];

  Paint paintFor(Color tint) {
    for (var index = _entries.length - 1; index >= 0; index--) {
      final entry = _entries[index];
      if (entry.tint == tint) return entry.paint;
    }
    final paint = Paint()
      ..filterQuality = ui.FilterQuality.low
      ..colorFilter = ColorFilter.mode(tint, .srcIn);
    if (_entries.length == _capacity) _entries.removeAt(0);
    _entries.add(_TintPaint(tint, paint));
    return paint;
  }
}

bool _shadowUnderlayShapeEqual(List<Shadow> a, List<Shadow>? b) {
  if (identical(a, b)) return true;
  if (b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final left = a[i];
    final right = b[i];
    // The cached shadow image is a white/alpha mask; RGB is applied at paint
    // time. Rebuild only when coverage can change: alpha, offset, blur, or list
    // shape. This is the shadow equivalent of the foreground tint cache.
    if (left.color.a != right.color.a ||
        left.offset != right.offset ||
        left.blurRadius != right.blurRadius ||
        spreadOf(left) != spreadOf(right)) {
      return false;
    }
  }
  return true;
}

/// The quantized and exact phase on one axis.
final class const _AxisPhase(final double quantized, final double exact);

/// A shared paint and the tint it draws with.
final class const _TintPaint(final Color tint, final Paint paint);
