import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:monet_ui/util/lru_cache.dart';

import 'package:monet_ui/util/deep_json_equals.dart';

// ============================================================================
// Paragraph layout value types
// ============================================================================

/// Everything needed to lay out one paragraph. Immutable-by-contract.
///
/// Not `const` because the cached tinted style (`effectiveStyle`) is a
/// `late final` — computed once on first access and reused across probes,
/// avoiding a `TextStyle.copyWith` call per binary-search iteration.
@immutable
class ParagraphInput {
  ParagraphInput({
    required this.textSpan,
    required this.text,
    required this.style,
    required this.paintColor,
    required this.direction,
    required this.maxLines,
    required this.align,
    required this.textScaler,
    required this.strutStyle,
    required this.placeholderSizes,
    this.inlinePlaceholderDimensions = const [],
    required this.maxWidth,
    required this.softWrap,
  });

  final InlineSpan textSpan;
  final String text;
  final TextStyle style;

  /// The colour to bake into the paragraph. `_Paragrapher` never reads
  /// [style.color] — always this field. This is what lets the tint strategy
  /// pass Impeller's canonical black/white glyph-mask color without
  /// `copyWith`-ing everywhere.
  final Color paintColor;

  final TextDirection direction;
  final int? maxLines;
  final TextAlign align;
  final TextScaler textScaler;
  final StrutStyle? strutStyle;
  final List<Size> placeholderSizes;
  final List<PlaceholderDimensions> inlinePlaceholderDimensions;
  final double maxWidth;
  final bool softWrap;

  /// [style] with [paintColor] baked into `.color`. Cached so binary-search
  /// probes don't re-allocate a TextStyle every iteration.
  late final TextStyle effectiveStyle = style.copyWith(color: paintColor);
  late final InlineSpan effectiveTextSpan = TextSpan(
    style: effectiveStyle,
    children: [textSpan],
  );
  late final String spanMetricSignature = _inlineSpanMetricSignature(textSpan);

  // ignore: avoid-incomplete-copy-with
  ParagraphInput copyWith({
    InlineSpan? textSpan,
    String? text,
    TextStyle? style,
    Color? paintColor,
    int? maxLines,
    double? maxWidth,
  }) {
    return ParagraphInput(
      textSpan: textSpan ?? this.textSpan,
      text: text ?? this.text,
      style: style ?? this.style,
      paintColor: paintColor ?? this.paintColor,
      direction: direction,
      maxLines: maxLines ?? this.maxLines,
      align: align,
      textScaler: textScaler,
      strutStyle: strutStyle,
      placeholderSizes: placeholderSizes,
      inlinePlaceholderDimensions: inlinePlaceholderDimensions,
      maxWidth: maxWidth ?? this.maxWidth,
      softWrap: softWrap,
    );
  }
}

/// The product of a layout pass. Does **not** own [painter] — the
/// owning [Paragrapher] does. A result is valid only until the next
/// layout call on the same painter overwrites its state; `paint()` is the
/// only legitimate consumer and it always runs before any subsequent
/// layout.
class ParagraphResult {
  const ParagraphResult({
    required this.input,
    required this.painter,
    required this.lines,
    required this.placeholderBoxes,
    required this.size,
    required this.didExceedMaxLines,
    required this.didTruncate,
  });

  final ParagraphInput input;
  final TextPainter painter;
  final List<ui.LineMetrics> lines;
  final List<ui.TextBox> placeholderBoxes;
  final Size size;
  final bool didExceedMaxLines;

  /// True iff the text was shortened (binary-search truncation) before
  /// layout. Distinct from [didExceedMaxLines] which describes the painter's
  /// view of its own layout.
  final bool didTruncate;
}

// ============================================================================
// _Paragrapher — instance-owning paragraph layout
// ============================================================================

/// Instance-based paragraph layout engine. Owns two long-lived
/// [TextPainter]s — a primary (whose state is what callers of [layout]
/// observe) and a scratch (used for probes during truncation). Reusing
/// painters across layouts saves a measurable chunk of allocation traffic;
/// creating a fresh `TextPainter` per probe was the dominant cost on
/// truncation-heavy scenarios in the perf harness.
class Paragrapher {
  Paragrapher();

  late final TextPainter _primary = TextPainter(textDirection: .ltr);
  late final TextPainter _scratch = TextPainter(textDirection: .ltr);
  ParagraphResult? _currentResult;

  /// A result is reusable only while this instance still owns that exact
  /// painter state. Intrinsic/probe layouts also use the primary painter and
  /// can overwrite it without replacing the render object's saved result.
  bool isCurrent(ParagraphResult result) => identical(_currentResult, result);

  /// Invalidates the instance-owned paragraphs after dynamic/system font
  /// registration. Shared metric caches are cleared by their process-global
  /// [PaintingBinding.systemFonts] listener below.
  void systemFontsDidChange() {
    _currentResult = null;
    _primary.markNeedsLayout();
    _scratch.markNeedsLayout();
  }

  /// Lay out without enforcing a trailing reservation. Used for intrinsic
  /// sizing, in-place paragraph rebuilds, and (as the initial probe) by
  /// [layoutReservingTail].
  ParagraphResult layout(ParagraphInput input) {
    configure(_primary, input);
    _primary.layout(maxWidth: input.maxWidth);
    return _harvest(input, _primary, didTruncate: false);
  }

  /// Lay out so that the last visible line ends at least [reservedTailWidth]
  /// before `input.maxWidth`. If the full text doesn't satisfy this (or
  /// exceeds `input.maxLines`), truncates the text at a grapheme cluster
  /// boundary and appends [ellipsis]. Guaranteed to terminate; worst case
  /// returns an ellipsis-only layout.
  ///
  /// Algorithm: grapheme-cluster-aware linear probe (±[_kLinearWindow]
  /// around a `getPositionForOffset` seed) with binary-search fallback.
  /// The linear phase converges in 1-3 probes on realistic UI text; the
  /// binary search preserves O(log n) correctness for pathological seeds.
  ///
  /// The search outcome is memoised in a global LRU ([_tailDecisionCache])
  /// keyed by every metrics-relevant input. Render objects are destroyed
  /// and recreated wholesale when tiles scroll out of and back into a
  /// list's cache extent, so without the memo every remount re-ran the
  /// full probe search (1 full layout + ellipsis measure + N probe
  /// layouts + 1 final layout). On a hit we skip straight to a single
  /// layout of the known-final string.
  ParagraphResult layoutReservingTail(
    ParagraphInput input, {
    required double reservedTailWidth,
    required String ellipsis,
  }) {
    // ---- 0. Consult the global decision cache. ---------------------------
    final _TailCacheKey? key = truncationTailDecisionCacheEnabled
        ? _TailCacheKey(input, reservedTailWidth, ellipsis)
        : null;
    if (key != null) {
      final cached = _tailDecisionCache[key];
      if (cached != null) {
        final cutAt = cached.cutAt;
        if (cutAt == null) {
          // Full text fits with tail slack; lay it out once for painting.
          configure(_primary, input);
          _primary.layout(maxWidth: input.maxWidth);
          return _harvest(input, _primary, didTruncate: false);
        }
        return _finaliseTruncated(input, cutAt: cutAt, ellipsis: ellipsis);
      }
    }

    // ---- 1. Try the full text first on the primary painter. --------------
    configure(_primary, input);
    _primary.layout(maxWidth: input.maxWidth);
    if (!_primary.didExceedMaxLines &&
        _fits(_primary, input, reservedTailWidth)) {
      if (key != null) _tailDecisionCache[key] = const _TailDecision(null);
      return _harvest(input, _primary, didTruncate: false);
    }

    // ---- 2. Seed: estimate where the cut should happen. -----------------
    // Use the primary painter's getPositionForOffset to pick a starting
    // point close to the natural overflow location. This converts the
    // binary search into a handful of probes for the common case.
    final breaks = _graphemeClusterBoundaries(input.text);
    assert(breaks.first == 0 && breaks.last == input.text.length);
    final ellipsisWidth = _measureEllipsisWidth(input, ellipsis);
    final targetX = input.maxWidth - reservedTailWidth - ellipsisWidth;
    final seedBreakIdx = _seedBreakIndex(_primary, input, targetX, breaks);

    // ---- 3. Configure the scratch painter once. -------------------------
    // Probes vary only in `.text`; all other properties (style, direction,
    // placeholders, maxWidth, maxLines) stay fixed. Avoid `input.copyWith`
    // per probe — that was allocating a fresh `_ParagraphInput` and
    // (thanks to `late final`) a fresh `TextStyle` each iteration.
    configure(_scratch, input);
    // Precompute the placeholder prefix spans; only the trailing TextSpan's
    // `text` field changes per probe.
    final placeholderSpans = List<InlineSpan>.generate(
      input.placeholderSizes.length,
      (_) => const WidgetSpan(
        alignment: ui.PlaceholderAlignment.middle,
        child: SizedBox.shrink(),
      ),
      growable: false,
    );

    // ---- 4. Linear probe around the seed, fallback to binary search. ----
    //
    // The "does text[0..k] + ellipsis fit with reserved tail slack?"
    // predicate is monotone in k: adding characters never reduces the
    // last-line's width budget. The seed is usually within a handful of
    // grapheme clusters of the true boundary because it came from the
    // painter's own `getPositionForOffset`, so a bounded linear scan
    // converges in 1-3 probes for the common case. Only pathological seeds
    // (narrow widths, very wide glyphs, maxLines > 1 with odd wrapping)
    // fall through to the binary search, which keeps worst-case O(log n)
    // correctness.
    int winningCut = -1;
    final seedFits = _probeFitsFast(
      input,
      breaks[seedBreakIdx],
      ellipsis,
      reservedTailWidth,
      placeholderSpans,
    );

    if (seedFits) {
      winningCut = breaks[seedBreakIdx];
      // Seed fits: extend rightward until we find the first non-fit.
      int idx = seedBreakIdx + 1;
      int stepsLeft = Paragrapher._kLinearWindow;
      while (idx < breaks.length && stepsLeft > 0) {
        if (_probeFitsFast(
          input,
          breaks[idx],
          ellipsis,
          reservedTailWidth,
          placeholderSpans,
        )) {
          winningCut = breaks[idx];
          idx++;
          stepsLeft--;
        } else {
          // Found the boundary cleanly.
          stepsLeft = -1;
          break;
        }
      }
      if (stepsLeft >= 0 && idx < breaks.length) {
        // Ran out of linear budget, boundary is further right. Binary
        // search [idx, breaks.length).
        winningCut = _binarySearchForBoundary(
          input,
          ellipsis,
          reservedTailWidth,
          placeholderSpans,
          breaks,
          lo: idx - 1,
          hi: breaks.length,
          loFitCut: winningCut,
        );
      }
    } else {
      // Seed doesn't fit: contract leftward until we find the first fit.
      int idx = seedBreakIdx - 1;
      int stepsLeft = Paragrapher._kLinearWindow;
      while (idx >= 0 && stepsLeft > 0) {
        if (_probeFitsFast(
          input,
          breaks[idx],
          ellipsis,
          reservedTailWidth,
          placeholderSpans,
        )) {
          winningCut = breaks[idx];
          stepsLeft = -1;
          break;
        }
        idx--;
        stepsLeft--;
      }
      if (winningCut < 0) {
        // Ran out of linear budget without finding a fit. Binary search
        // [0, idx+1) (inclusive). First verify the floor (ellipsis only).
        if (!_probeFitsFast(
          input,
          0,
          ellipsis,
          reservedTailWidth,
          placeholderSpans,
        )) {
          // Degenerate: even the ellipsis overflows. Return it anyway —
          // better a predictable minimum than a blank.
          if (key != null) _tailDecisionCache[key] = const _TailDecision(0);
          return _finaliseTruncated(input, cutAt: 0, ellipsis: ellipsis);
        }
        winningCut = _binarySearchForBoundary(
          input,
          ellipsis,
          reservedTailWidth,
          placeholderSpans,
          breaks,
          lo: 0,
          hi: (idx + 2).clamp(1, breaks.length),
          loFitCut: 0,
        );
      }
    }

    // ---- 5. Apply the winning cut to the primary painter. ---------------
    final cutAt = _trimmedCutAt(input.text, winningCut);
    if (key != null) _tailDecisionCache[key] = _TailDecision(cutAt);
    return _finaliseTruncated(input, cutAt: cutAt, ellipsis: ellipsis);
  }

  /// Binary search in `breaks[lo..hi)` for the largest fitting cut. `lo`
  /// is assumed to fit (at [loFitCut]); `hi` is the open upper bound (may
  /// be past the last non-fit).
  int _binarySearchForBoundary(
    ParagraphInput input,
    String ellipsis,
    double reservedTailWidth,
    List<InlineSpan> placeholderSpans,
    List<int> breaks, {
    required int lo,
    required int hi,
    required int loFitCut,
  }) {
    int winningCut = loFitCut;
    while (lo + 1 < hi) {
      final mid = (lo + hi) ~/ 2;
      if (_probeFitsFast(
        input,
        breaks[mid],
        ellipsis,
        reservedTailWidth,
        placeholderSpans,
      )) {
        lo = mid;
        winningCut = breaks[mid];
      } else {
        hi = mid;
      }
    }
    return winningCut;
  }

  // --------- implementation details -----------------------------------------

  /// Configure [target] for [input] without laying out. Safe to call many
  /// times on the same painter; each call replaces the previous span and
  /// placeholder dimensions.
  static void configure(TextPainter target, ParagraphInput input) {
    target
      ..text = _buildSpan(input)
      ..textDirection = input.direction
      ..textAlign = input.align
      ..textScaler = input.textScaler
      ..maxLines = input.maxLines
      ..strutStyle = input.strutStyle
      ..textWidthBasis = .longestLine
      ..setPlaceholderDimensions([
        for (final s in input.placeholderSizes)
          PlaceholderDimensions(
            size: s,
            alignment: ui.PlaceholderAlignment.middle,
          ),
        ...input.inlinePlaceholderDimensions.take(
          _placeholderCount(input.textSpan),
        ),
      ]);
  }

  /// Fast probe fit check. Reuses [_scratch], mutating only `.text` to
  /// avoid an `input.copyWith` per iteration (which otherwise allocates
  /// both a `_ParagraphInput` and a `TextStyle`).
  bool _probeFitsFast(
    ParagraphInput base,
    int cutAt,
    String ellipsis,
    double reservedTailWidth,
    List<InlineSpan> placeholderSpans,
  ) {
    final trimmedCutAt = _trimmedCutAt(base.text, cutAt);
    final probeText = _truncatedText(base.text, trimmedCutAt, ellipsis);
    final probeTextSpan = _truncateInlineSpan(
      base.textSpan,
      cutAt: trimmedCutAt,
      ellipsis: ellipsis,
    );
    _scratch.text = TextSpan(
      children: [
        ...placeholderSpans,
        if (probeText.isNotEmpty)
          TextSpan(style: base.effectiveStyle, children: [probeTextSpan]),
      ],
    );
    _scratch.setPlaceholderDimensions([
      for (final size in base.placeholderSizes)
        PlaceholderDimensions(
          size: size,
          alignment: ui.PlaceholderAlignment.middle,
        ),
      ...base.inlinePlaceholderDimensions.take(
        _placeholderCount(probeTextSpan),
      ),
    ]);
    _scratch.layout(maxWidth: base.maxWidth);
    return !_scratch.didExceedMaxLines &&
        _fits(_scratch, base, reservedTailWidth);
  }

  /// Lay out the winning cut on the primary painter and harvest a result.
  /// Used for both the truncated-text finalisation and the degenerate
  /// ellipsis-only fallback path.
  ParagraphResult _finaliseTruncated(
    ParagraphInput base, {
    required int cutAt,
    required String ellipsis,
  }) {
    final finalText = _truncatedText(base.text, cutAt, ellipsis);
    final finalInput = base.copyWith(
      textSpan: _truncateInlineSpan(
        base.textSpan,
        cutAt: cutAt,
        ellipsis: ellipsis,
      ),
      text: finalText,
    );
    configure(_primary, finalInput);
    _primary.layout(maxWidth: finalInput.maxWidth);
    return _harvest(finalInput, _primary, didTruncate: true);
  }

  /// Cheap fit check. For single-line text, `painter.width` is the last
  /// line's width — no need to cross into Skia for `computeLineMetrics`
  /// (which dominated the V2 profile at ~10% inclusive). For multi-line
  /// we fall back to the precise line metrics.
  static bool _fits(
    TextPainter painter,
    ParagraphInput input,
    double reservedTailWidth,
  ) {
    if (input.maxLines == 1) {
      return input.maxWidth - painter.width >= reservedTailWidth - 0.5;
    }
    final metrics = painter.computeLineMetrics();
    if (metrics.isEmpty) return input.maxWidth >= reservedTailWidth;
    final last = metrics.last;
    return input.maxWidth - (last.left + last.width) >= reservedTailWidth - 0.5;
  }

  static int _seedBreakIndex(
    TextPainter painter,
    ParagraphInput input,
    double targetX,
    List<int> breaks,
  ) {
    // Single-line fast path: no need for line metrics; the midline is
    // just half the painter's overall height.
    if (input.maxLines == 1) {
      final pos = painter.getPositionForOffset(
        Offset(math.max(0, targetX), painter.height / 2),
      );
      final textOffset = (pos.offset - input.placeholderSizes.length).clamp(
        0,
        input.text.length,
      );
      return _nearestBreak(breaks, textOffset);
    }
    final metrics = painter.computeLineMetrics();
    if (metrics.isEmpty) return breaks.length ~/ 2;
    final effectiveMax = input.maxLines ?? metrics.length;
    final visibleLastIdx = math.min(metrics.length, effectiveMax) - 1;
    final visibleLast = metrics[visibleLastIdx];
    double y = 0;
    for (int i = 0; i < visibleLastIdx; i++) {
      y += metrics[i].height;
    }
    y += visibleLast.height / 2;
    final pos = painter.getPositionForOffset(Offset(math.max(0, targetX), y));
    final textOffset = (pos.offset - input.placeholderSizes.length).clamp(
      0,
      input.text.length,
    );
    return _nearestBreak(breaks, textOffset);
  }

  /// Long-lived painter for ellipsis measurement; avoids a TextPainter
  /// allocation + dispose per truncation search. Single-threaded use only
  /// (all layout happens on the UI thread).
  static final TextPainter _ellipsisPainter = TextPainter(textDirection: .ltr);

  /// Ellipsis width depends only on metrics-relevant style fields, the
  /// scaler, direction, and the ellipsis string itself — not on colour —
  /// so memoise it. The key deliberately omits paint-only fields to keep
  /// hover/colour animations from churning entries.
  static final LruCache<int, double> _ellipsisWidthCache =
      LruCache<int, double>(capacity: 128);

  static double _measureEllipsisWidth(ParagraphInput input, String ellipsis) {
    final style = input.style;
    final cacheKey = Object.hash(
      ellipsis,
      style.fontSize,
      style.fontWeight,
      style.fontStyle,
      style.fontFamily,
      style.letterSpacing,
      style.wordSpacing,
      style.height,
      input.textScaler,
      input.direction,
    );
    final cached = _ellipsisWidthCache[cacheKey];
    if (cached != null) return cached;
    _ellipsisPainter
      ..text = TextSpan(text: ellipsis, style: input.effectiveStyle)
      ..textDirection = input.direction
      ..textScaler = input.textScaler
      ..layout();
    final w = _ellipsisPainter.width;
    _ellipsisWidthCache[cacheKey] = w;
    return w;
  }

  static List<int> _graphemeClusterBoundaries(String text) {
    // Happy-path fast check: if the string is pure ASCII every code unit
    // is its own grapheme cluster. Skip the `characters` machinery.
    bool ascii = true;
    for (int i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) >= 0x80) {
        ascii = false;
        break;
      }
    }
    if (ascii) {
      return List.generate(text.length + 1, (i) => i, growable: false);
    }
    final breaks = [0];
    int offset = 0;
    for (final cluster in text.characters) {
      offset += cluster.length;
      breaks.add(offset);
    }
    return breaks;
  }

  /// Linear-probe window used by [layoutReservingTail] before falling
  /// back to binary search. Profiling showed 4 probes is more than
  /// enough to converge on a good `getPositionForOffset` seed for UI-
  /// chrome text; we only fall into binary search on degenerate inputs.
  static const int _kLinearWindow = 4;

  static int _nearestBreak(List<int> breaks, int target) {
    int lo = 0, hi = breaks.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (breaks[mid] <= target) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  static InlineSpan _buildSpan(ParagraphInput input) {
    final spans = <InlineSpan>[];
    for (int i = 0; i < input.placeholderSizes.length; i++) {
      spans.add(
        const WidgetSpan(
          alignment: ui.PlaceholderAlignment.middle,
          child: SizedBox.shrink(),
        ),
      );
    }
    if (input.text.isNotEmpty) {
      spans.add(input.effectiveTextSpan);
    }
    return TextSpan(children: spans);
  }

  ParagraphResult _harvest(
    ParagraphInput input,
    TextPainter painter, {
    required bool didTruncate,
  }) {
    return _currentResult = ParagraphResult(
      input: input,
      painter: painter,
      lines: painter.computeLineMetrics(),
      placeholderBoxes: painter.inlinePlaceholderBoxes ?? const [],
      size: painter.size,
      didExceedMaxLines: painter.didExceedMaxLines,
      didTruncate: didTruncate,
    );
  }

  void dispose() {
    _currentResult = null;
    _primary.dispose();
    _scratch.dispose();
  }
}

String _inlineSpanMetricSignature(InlineSpan span) {
  final buffer = StringBuffer();
  _writeInlineSpanMetricSignature(buffer, span);
  return buffer.toString();
}

void _writeInlineSpanMetricSignature(StringBuffer buffer, InlineSpan span) {
  switch (span) {
    case TextSpan():
      buffer
        ..write('T(')
        ..write(span.text ?? '')
        ..write('|');
      _writeTextStyleMetricSignature(buffer, span.style);
      buffer.write(')[');
      final children = span.children;
      if (children != null) {
        for (final child in children) {
          _writeInlineSpanMetricSignature(buffer, child);
        }
      }
      buffer.write(']');
    case PlaceholderSpan():
      buffer
        ..write('P(')
        ..write(span.alignment)
        ..write('|')
        ..write(span.baseline)
        ..write('|');
      _writeTextStyleMetricSignature(buffer, span.style);
      buffer.write(')');
    default:
      buffer.write(span.toPlainText(includeSemanticsLabels: false));
  }
}

void _writeTextStyleMetricSignature(StringBuffer buffer, TextStyle? style) {
  buffer
    ..write(style?.fontSize)
    ..write('|')
    ..write(style?.fontWeight)
    ..write('|')
    ..write(style?.fontStyle)
    ..write('|')
    ..write(style?.fontFamily)
    ..write('|')
    ..write(style?.fontFamilyFallback)
    ..write('|')
    ..write(style?.letterSpacing)
    ..write('|')
    ..write(style?.wordSpacing)
    ..write('|')
    ..write(style?.height)
    ..write('|')
    ..write(style?.leadingDistribution)
    ..write('|')
    ..write(style?.textBaseline)
    ..write('|')
    ..write(style?.fontFeatures)
    ..write('|')
    ..write(style?.fontVariations)
    ..write('|')
    ..write(style?.locale);
}

int _trimmedCutAt(String text, int cutAt) {
  var end = cutAt.clamp(0, text.length);
  while (end > 0 && text.substring(end - 1, end).trim().isEmpty) {
    end--;
  }
  return end;
}

String _truncatedText(String text, int cutAt, String ellipsis) {
  final prefix = cutAt <= 0 ? '' : text.substring(0, cutAt);
  return '$prefix$ellipsis';
}

InlineSpan _truncateInlineSpan(
  InlineSpan span, {
  required int cutAt,
  required String ellipsis,
}) {
  final prefix = _InlineSpanPrefixBuilder(cutAt).build(span);
  return TextSpan(
    children: [
      ?prefix,
      TextSpan(text: ellipsis),
    ],
  );
}

class _InlineSpanPrefixBuilder {
  _InlineSpanPrefixBuilder(this.remaining);

  int remaining;

  InlineSpan? build(InlineSpan span) {
    if (remaining <= 0) return null;
    return _visit(span);
  }

  InlineSpan? _visit(InlineSpan span) {
    if (remaining <= 0) return null;
    switch (span) {
      case TextSpan():
        return _visitTextSpan(span);
      case PlaceholderSpan():
        remaining--;
        return span;
      default:
        return null;
    }
  }

  InlineSpan? _visitTextSpan(TextSpan span) {
    String? text;
    final sourceText = span.text;
    if (sourceText != null && sourceText.isNotEmpty && remaining > 0) {
      final take = math.min(remaining, sourceText.length);
      text = sourceText.substring(0, take);
      remaining -= take;
      if (take < sourceText.length) {
        return _copyTextSpan(span, text: text, children: null);
      }
    }

    final copiedChildren = <InlineSpan>[];
    final sourceChildren = span.children;
    if (sourceChildren != null && remaining > 0) {
      for (final child in sourceChildren) {
        final copiedChild = _visit(child);
        if (copiedChild != null) copiedChildren.add(copiedChild);
        if (remaining <= 0) break;
      }
    }

    if ((text == null || text.isEmpty) && copiedChildren.isEmpty) return null;
    return _copyTextSpan(
      span,
      text: text,
      children: copiedChildren.isEmpty ? null : copiedChildren,
    );
  }

  TextSpan _copyTextSpan(
    TextSpan span, {
    required String? text,
    required List<InlineSpan>? children,
  }) {
    return TextSpan(
      text: text,
      children: children,
      style: span.style,
      recognizer: span.recognizer,
      mouseCursor: span.mouseCursor,
      onEnter: span.onEnter,
      onExit: span.onExit,
      semanticsLabel: span.semanticsLabel,
      semanticsIdentifier: span.semanticsIdentifier,
      locale: span.locale,
      spellOut: span.spellOut,
    );
  }
}

// ============================================================================
// Tail-decision cache
// ============================================================================

/// Test/escape hatch for the global truncation decision cache.
@visibleForTesting
bool truncationTailDecisionCacheEnabled = true;

/// Clears the global truncation decision cache. Exposed for tests (e.g.
/// goldens that load fonts mid-suite) and debugging.
@visibleForTesting
void debugClearTruncationTailDecisionCache() => _tailDecisionCache.clear();

/// Creates the same detached key used by the global decision cache.
@visibleForTesting
Object debugTruncationTailCacheKey(
  ParagraphInput input, {
  double reservedTailWidth = 20,
  String ellipsis = '…',
}) => _TailCacheKey(input, reservedTailWidth, ellipsis);

/// The outcome of one [Paragrapher.layoutReservingTail] search.
///
/// [cutAt] is `null` when the full text fits with the required tail slack,
/// otherwise it is the already-trimmed UTF-16 text offset where the rich span
/// should be cut before appending the ellipsis.
class _TailDecision {
  const _TailDecision(this.cutAt);
  final int? cutAt;
}

/// Key covering every input that can change the truncation decision:
/// the text, available width, reserved tail width, ellipsis, line limits,
/// direction/alignment/scaler/strut, placeholder sizes, and the
/// metrics-relevant fields of the style. Paint-only fields (colour,
/// shadows, decorations) are deliberately excluded — they cannot move a
/// line break, and including them would make hover/colour animations
/// churn the cache.
class _TailCacheKey {
  _TailCacheKey(ParagraphInput input, double reservedTailWidth, String ellipsis)
    : _scaler = WeakReference(input.textScaler),
      _scalerHash = input.textScaler.hashCode,
      _values = [
        input.text,
        input.spanMetricSignature,
        input.maxWidth,
        reservedTailWidth,
        ellipsis,
        input.maxLines,
        input.direction,
        input.align,
        input.softWrap,
        _styleMetricValues(input.style),
        _strutMetricValues(input.strutStyle),
        [
          for (final size in input.placeholderSizes) [size.width, size.height],
        ],
        [
          for (final d in input.inlinePlaceholderDimensions)
            [
              d.size.width,
              d.size.height,
              d.alignment,
              d.baseline,
              d.baselineOffset,
            ],
        ],
      ];

  // Never retain ParagraphInput: spans can own callbacks/widgets, and Flutter's
  // debug Size subclasses own render objects. Snapshot only metric values.
  final List<Object?> _values;

  // TextScaler is extensible; a custom scaler can own arbitrary app state.
  // Preserve its equality semantics without keeping it alive. If collected,
  // this entry simply misses until normal LRU eviction. The hash stays stable.
  final WeakReference<TextScaler> _scaler;
  final int _scalerHash;
  late final int _hashCode = Object.hash(_scalerHash, deepJsonHash(_values));

  @override
  int get hashCode => _hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! _TailCacheKey) return false;
    if (_hashCode != other._hashCode) return false;
    final scaler = _scaler.target;
    return scaler != null &&
        scaler == other._scaler.target &&
        deepJsonEquals(_values, other._values);
  }
}

List<Object?> _styleMetricValues(TextStyle style) => [
  style.fontSize,
  style.fontWeight,
  style.fontStyle,
  style.fontFamily,
  style.fontFamilyFallback?.toList(growable: false),
  style.letterSpacing,
  style.wordSpacing,
  style.height,
  style.leadingDistribution,
  style.textBaseline,
  style.fontFeatures == null
      ? null
      : [
          for (final feature in style.fontFeatures!)
            [feature.feature, feature.value],
        ],
  style.fontVariations == null
      ? null
      : [
          for (final variation in style.fontVariations!)
            [variation.axis, variation.value],
        ],
  style.locale?.toLanguageTag(),
];

List<Object?>? _strutMetricValues(StrutStyle? strut) => strut == null
    ? null
    : [
        strut.fontFamily,
        strut.fontFamilyFallback?.toList(growable: false),
        strut.fontSize,
        strut.fontWeight,
        strut.fontStyle,
        strut.height,
        strut.leading,
        strut.forceStrutHeight,
        if (strut.height != null) strut.leadingDistribution,
      ];

/// Global LRU of truncation decisions, shared across all
/// [RenderMonetRichText] instances. Conversation tiles are unmounted
/// and remounted wholesale as they cross a scroll view's cache extent; the
/// decision (which is a pure function of the key) survives here so a
/// remount costs one paragraph layout instead of a full probe search.
///
/// Invalidated when system/dynamic fonts load, since glyph metrics — and
/// therefore the correct cut point — may change.
void _clearSharedParagraphFontCaches() {
  _tailDecisionCache.clear();
  Paragrapher._ellipsisWidthCache.clear();
  Paragrapher._ellipsisPainter.markNeedsLayout();
}

final LruCache<_TailCacheKey, _TailDecision> _tailDecisionCache = () {
  final cache = LruCache<_TailCacheKey, _TailDecision>(capacity: 1024);
  PaintingBinding.instance.systemFonts.addListener(
    _clearSharedParagraphFontCaches,
  );
  return cache;
}();

bool metricsEqual(TextStyle a, TextStyle b) {
  return a.fontSize == b.fontSize &&
      a.fontWeight == b.fontWeight &&
      a.fontStyle == b.fontStyle &&
      a.fontFamily == b.fontFamily &&
      listEquals(a.fontFamilyFallback, b.fontFamilyFallback) &&
      a.letterSpacing == b.letterSpacing &&
      a.wordSpacing == b.wordSpacing &&
      a.height == b.height &&
      a.leadingDistribution == b.leadingDistribution &&
      a.textBaseline == b.textBaseline &&
      listEquals(a.fontFeatures, b.fontFeatures) &&
      listEquals(a.fontVariations, b.fontVariations) &&
      a.locale == b.locale;
}

/// Exact resolved geometry comparison for retained paint assets.
bool sameParagraphGeometry(ParagraphResult a, ParagraphResult b) {
  if (a.size != b.size ||
      a.lines.length != b.lines.length ||
      a.placeholderBoxes.length != b.placeholderBoxes.length) {
    return false;
  }
  for (var index = 0; index < a.lines.length; index++) {
    final left = a.lines[index];
    final right = b.lines[index];
    if (left.hardBreak != right.hardBreak ||
        left.ascent != right.ascent ||
        left.descent != right.descent ||
        left.unscaledAscent != right.unscaledAscent ||
        left.height != right.height ||
        left.width != right.width ||
        left.left != right.left ||
        left.baseline != right.baseline ||
        left.lineNumber != right.lineNumber) {
      return false;
    }
  }
  for (var index = 0; index < a.placeholderBoxes.length; index++) {
    final left = a.placeholderBoxes[index];
    final right = b.placeholderBoxes[index];
    if (left.left != right.left ||
        left.top != right.top ||
        left.right != right.right ||
        left.bottom != right.bottom ||
        left.direction != right.direction) {
      return false;
    }
  }
  return true;
}

int _placeholderCount(InlineSpan span) => switch (span) {
  PlaceholderSpan() => 1,
  TextSpan() => (span.children ?? const <InlineSpan>[]).fold(
    0,
    (count, child) => count + _placeholderCount(child),
  ),
  _ => 0,
};
