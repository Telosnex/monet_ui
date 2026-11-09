// ---------------------------------------------------------------------------
//  PrettyText implementation for Flutter
// ---------------------------------------------------------------------------

import 'dart:math' as math;

import 'package:flutter/rendering.dart'
    show RelayoutWhenSystemFontsChangeMixin, SemanticsConfiguration;

import 'package:material_ui/material_ui.dart';

import 'package:monet_ui/widgets/padding.dart';

/// --------------------------------------------------------------
/// Public API
/// --------------------------------------------------------------
enum PrettyMode { stable, pretty, balance }

class _WordWidthKey {
  final String text;
  final int metrics;
  final TextDirection direction;
  const _WordWidthKey(this.text, this.metrics, this.direction);

  @override
  bool operator ==(Object other) =>
      other is _WordWidthKey &&
      text == other.text &&
      metrics == other.metrics &&
      direction == other.direction;

  @override
  int get hashCode => Object.hash(text, metrics, direction);
}

class _WrappedTextKey {
  final String text;
  final int metrics;
  final TextDirection direction;
  final PrettyMode mode;
  final double maxWidth;
  const _WrappedTextKey(
    this.text,
    this.metrics,
    this.direction,
    this.mode,
    this.maxWidth,
  );

  @override
  bool operator ==(Object other) =>
      other is _WrappedTextKey &&
      text == other.text &&
      metrics == other.metrics &&
      direction == other.direction &&
      mode == other.mode &&
      maxWidth == other.maxWidth;

  @override
  int get hashCode => Object.hash(text, metrics, direction, mode, maxWidth);
}

class _BalancedBreaks {
  final List<int> breaks;
  final double score;
  const _BalancedBreaks(this.breaks, this.score);
}

class PrettyText extends LeafRenderObjectWidget {
  const PrettyText(
    this.data, {
    super.key,
    this.mode = PrettyMode.stable,
    this.textAlign = TextAlign.start,
    this.textDirection,
  });

  final String data;
  final PrettyMode mode;
  final TextAlign textAlign;
  final TextDirection? textDirection;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderPrettyText(
      data: data,
      style: DefaultTextStyle.of(context).style,
      mode: mode,
      textAlign: textAlign,
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: textDirection ?? Directionality.maybeOf(context) ?? .ltr,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderPrettyText renderObject,
  ) {
    renderObject
      ..data = data
      ..style = DefaultTextStyle.of(context).style
      ..mode = mode
      ..textAlign = textAlign
      ..textScaler = MediaQuery.textScalerOf(context)
      ..textDirection =
          textDirection ?? Directionality.maybeOf(context) ?? TextDirection.ltr;
  }
}

// ---------------------------------------------------------------------------
//  PrettyTextV3 - User's proposed ship version for performance testing
// ---------------------------------------------------------------------------

class RenderPrettyText extends RenderBox
    with RelayoutWhenSystemFontsChangeMixin {
  RenderPrettyText({
    required this._data,
    required this._style,
    required this._mode,
    required this._textAlign,
    required this._textDirection,
    this._textScaler = TextScaler.noScaling,
  });

  String _data;
  set data(String v) {
    if (v == _data) return;
    _data = v;
    _wrapDirty = true;
    _paragraphDirty = true;
    markNeedsSemanticsUpdate();
    markNeedsLayout();
  }

  TextStyle _style;
  set style(TextStyle v) {
    if (v == _style) return;

    if (_sameTextMetrics(v, _style)) {
      _style = v;
      _tp.text = TextSpan(text: _laidOutText, style: _style);
      markNeedsPaint();
      return;
    }

    _style = v;
    _localWordWidthCache.clear();
    _wrapDirty = true;
    _paragraphDirty = true;
    markNeedsLayout();
  }

  PrettyMode _mode;
  set mode(PrettyMode v) {
    if (v == _mode) return;
    _mode = v;
    _wrapDirty = true;
    _paragraphDirty = true;
    markNeedsLayout();
  }

  TextAlign _textAlign;
  set textAlign(TextAlign v) {
    if (v == _textAlign) return;
    _textAlign = v;
    _paragraphDirty = true;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection v) {
    if (v == _textDirection) return;
    _textDirection = v;
    _localWordWidthCache.clear();
    _wrapDirty = true;
    _paragraphDirty = true;
    markNeedsSemanticsUpdate();
    markNeedsLayout();
  }

  final TextPainter _tp = TextPainter();
  final TextPainter _measureTp = TextPainter(maxLines: 1);

  TextScaler _textScaler;
  set textScaler(TextScaler value) {
    if (value == _textScaler) return;
    _textScaler = value;
    _localWordWidthCache.clear();
    _wrapDirty = true;
    _paragraphDirty = true;
    markNeedsLayout();
  }

  bool _wrapDirty = true;
  bool _paragraphDirty = true;

  late String _laidOutText;
  late Size _paragraphSize;
  bool _didOverflowHeight = false;
  double _laidOutTextWidth = -1;

  final Map<String, double> _localWordWidthCache = <String, double>{};

  static final Map<_WordWidthKey, double> _wordWidthCache =
      _createWordWidthCache();
  static const _maxWordCacheSize = 4000;

  static final Map<_WrappedTextKey, String> _wrappedTextCache = {};
  static const _maxWrappedCacheSize = 512;

  static Map<_WordWidthKey, double> _createWordWidthCache() {
    final cache = <_WordWidthKey, double>{};
    PaintingBinding.instance.systemFonts.addListener(_clearSharedFontCaches);
    return cache;
  }

  static void _clearSharedFontCaches() {
    _wordWidthCache.clear();
    _wrappedTextCache.clear();
  }

  @override
  void systemFontsDidChange() {
    _tp.markNeedsLayout();
    _measureTp.markNeedsLayout();
    _localWordWidthCache.clear();
    _wrapDirty = true;
    _paragraphDirty = true;
    super.systemFontsDidChange();
  }

  int get _metricsKey => Object.hash(
    _textScaler,
    _style.fontFamily,
    _style.fontSize,
    _style.fontWeight,
    _style.fontStyle,
    _style.letterSpacing,
    _style.wordSpacing,
    _style.height,
    _style.textBaseline,
    _style.locale,
    _style.leadingDistribution,
  );

  bool _sameTextMetrics(TextStyle a, TextStyle b) {
    return a.fontFamily == b.fontFamily &&
        a.fontSize == b.fontSize &&
        a.fontWeight == b.fontWeight &&
        a.fontStyle == b.fontStyle &&
        a.letterSpacing == b.letterSpacing &&
        a.wordSpacing == b.wordSpacing &&
        a.height == b.height &&
        a.textBaseline == b.textBaseline &&
        a.locale == b.locale &&
        a.leadingDistribution == b.leadingDistribution;
  }

  @visibleForTesting
  // ignore: match-getter-setter-field-names
  String get debugLaidOutText => _laidOutText;

  @visibleForTesting
  // ignore: match-getter-setter-field-names
  bool get debugDidOverflowHeight => _didOverflowHeight;

  @visibleForTesting
  double debugMeasureCached(String text) => _measureCached(text);

  @visibleForTesting
  String debugPrettyWrap(String text, double maxWidth) =>
      _prettyWrap(text, maxWidth);

  @visibleForTesting
  String debugBalanceWrap(String text, double maxWidth) =>
      _balanceWrap(text, maxWidth);

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..label = _data
      ..textDirection = _textDirection;
  }

  @override
  void performLayout() {
    final double maxWidth = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : .infinity;

    final bool widthChanged = _laidOutTextWidth != maxWidth;

    if (_wrapDirty || widthChanged) {
      _laidOutText = _computeWrappedText(maxWidth);
      _laidOutTextWidth = maxWidth;
      _wrapDirty = false;
      _paragraphDirty = true;
    }

    if (_paragraphDirty) {
      _tp
        ..text = TextSpan(text: _laidOutText, style: _style)
        ..textScaler = _textScaler
        ..textAlign = _textAlign
        ..textDirection = _textDirection
        ..layout(maxWidth: maxWidth);
      _paragraphSize = _tp.size;
      _paragraphDirty = false;
    }

    size = constraints.constrain(_paragraphSize);
    _didOverflowHeight = _paragraphSize.height > size.height + 4;
  }

  @override
  void dispose() {
    _tp.dispose();
    _measureTp.dispose();
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final rect = offset & size;

    if (!_didOverflowHeight) {
      // Match RenderParagraph: glyph ink is allowed to extend fractionally
      // outside its logical line box when the paragraph itself fits. Clipping
      // to [size] here cuts off font outlines that reach the font descent.
      _tp.paint(canvas, offset);
      return;
    }

    final fadeHeight = math.min(VerticalPadding.amount * 3, size.height * 0.5);
    if (fadeHeight <= 0) {
      canvas.save();
      canvas.clipRect(rect);
      _tp.paint(canvas, offset);
      canvas.restore();
      return;
    }

    canvas.saveLayer(rect, Paint());
    canvas.clipRect(rect);
    _tp.paint(canvas, offset);

    final fadeRect = Rect.fromLTWH(
      rect.left,
      rect.bottom - fadeHeight,
      rect.width,
      fadeHeight,
    );

    final fadePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, Colors.transparent],
      ).createShader(fadeRect)
      ..blendMode = .dstIn;

    canvas.drawRect(fadeRect, fadePaint);
    canvas.restore();
  }

  String _computeWrappedText(double maxWidth) {
    if (_mode == .stable ||
        maxWidth.isInfinite ||
        _data.isEmpty ||
        _data.contains('\n')) {
      return _data;
    }

    final key = _WrappedTextKey(
      _data,
      _metricsKey,
      _textDirection,
      _mode,
      maxWidth,
    );
    final cached = _wrappedTextCache[key];
    if (cached != null) return cached;

    final result = switch (_mode) {
      .stable => _data,
      .pretty => _prettyWrap(_data, maxWidth),
      .balance => _balanceWrap(_data, maxWidth),
    };

    if (_wrappedTextCache.length >= _maxWrappedCacheSize) {
      _wrappedTextCache.clear();
    }
    _wrappedTextCache[key] = result;
    return result;
  }

  double _measureCached(String s) {
    final local = _localWordWidthCache[s];
    if (local != null) return local;

    final key = _WordWidthKey(s, _metricsKey, _textDirection);
    final cached = _wordWidthCache[key];
    if (cached != null) {
      _localWordWidthCache[s] = cached;
      return cached;
    }

    _measureTp
      ..text = TextSpan(text: s, style: _style)
      ..textScaler = _textScaler
      ..textDirection = _textDirection
      ..layout();

    final width = _measureTp.width;
    _localWordWidthCache[s] = width;
    if (_wordWidthCache.length >= _maxWordCacheSize) _wordWidthCache.clear();
    _wordWidthCache[key] = width;
    return width;
  }

  List<String> _splitWords(String text) {
    return text
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList(growable: false);
  }

  List<double> _buildPrefixSums(List<double> wordWidths) {
    final prefix = List<double>.filled(wordWidths.length + 1, 0);
    for (int i = 0; i < wordWidths.length; i++) {
      prefix[i + 1] = prefix[i] + wordWidths[i];
    }
    return prefix;
  }

  double _lineWidth(
    List<double> prefix,
    int start,
    int end,
    double spaceWidth,
  ) {
    final wordCount = end - start;
    if (wordCount <= 0) return 0;
    return prefix[end] - prefix[start] + spaceWidth * (wordCount - 1);
  }

  List<int> _greedyBreaks(
    List<double> prefix,
    int n,
    double spaceWidth,
    double maxWidth,
  ) {
    final breaks = <int>[];
    int start = 0;

    while (start < n) {
      int end = start + 1;
      while (end <= n &&
          _lineWidth(prefix, start, end, spaceWidth) <= maxWidth) {
        end++;
      }

      final next = end == start + 1 ? end : end - 1;
      breaks.add(next);
      start = next;
    }

    return breaks;
  }

  String _joinWords(List<String> words, List<int> breaks) {
    final result = StringBuffer();
    int start = 0;

    for (final end in breaks) {
      if (result.length > 0) result.write('\n');
      result.writeAll(words.getRange(start, end), ' ');
      start = end;
    }

    return result.toString();
  }

  String _prettyWrap(String text, double maxWidth) {
    final words = _splitWords(text);
    final n = words.length;
    if (n <= 1) return text;

    final wordWidths = List.generate(
      n,
      (i) => _measureCached(words[i]),
      growable: false,
    );
    final spaceWidth = _measureCached(' ');
    final prefix = _buildPrefixSums(wordWidths);

    if (_lineWidth(prefix, 0, n, spaceWidth) <= maxWidth) {
      return text;
    }

    const penaltyShortLast = 3000.0;

    final costs = List.filled(n + 1, double.infinity);
    final breaks = List.filled(n + 1, -1);
    costs[0] = 0;

    for (int i = 0; i < n; i++) {
      if (!costs[i].isFinite) continue;

      for (int j = i + 1; j <= n; j++) {
        final lineW = _lineWidth(prefix, i, j, spaceWidth);

        if (lineW > maxWidth && j > i + 1) break;

        final isLastLine = j == n;
        final slack = maxWidth - lineW;
        double badness = slack >= 0 ? slack * slack * 0.1 : -slack * 1000.0;

        if (isLastLine && slack > maxWidth * 0.5) {
          badness += penaltyShortLast;
        }

        final newCost = costs[i] + badness;
        if (newCost < costs[j]) {
          costs[j] = newCost;
          breaks[j] = i;
        }

        if (lineW > maxWidth) break;
      }
    }

    if (!costs[n].isFinite) {
      return _joinWords(words, _greedyBreaks(prefix, n, spaceWidth, maxWidth));
    }

    final reversedBreaks = <int>[];
    for (int end = n; end > 0; end = breaks[end]) {
      reversedBreaks.add(end);
    }

    return _joinWords(words, reversedBreaks.reversed.toList(growable: false));
  }

  _BalancedBreaks? _solveBalancedBreaks(
    List<double> prefix,
    int n,
    double spaceWidth,
    double maxWidth,
    int lines,
  ) {
    final target = _lineWidth(prefix, 0, n, spaceWidth) / lines;

    final costs = List.generate(
      lines + 1,
      (_) => List.filled(n + 1, double.infinity),
      growable: false,
    );
    final prev = List.generate(
      lines + 1,
      (_) => List.filled(n + 1, -1),
      growable: false,
    );

    costs[0][0] = 0;

    for (int line = 1; line <= lines; line++) {
      for (int end = line; end <= n; end++) {
        for (int start = end - 1; start >= line - 1; start--) {
          final prevCost = costs[line - 1][start];
          if (!prevCost.isFinite) continue;

          final width = _lineWidth(prefix, start, end, spaceWidth);
          if (width > maxWidth && start != end - 1) break;

          final diff = width - target;
          final cost = prevCost + diff * diff;

          if (cost < costs[line][end]) {
            costs[line][end] = cost;
            prev[line][end] = start;
          }

          if (width > maxWidth) break;
        }
      }
    }

    if (!costs[lines][n].isFinite) return null;

    final breaks = List.filled(lines, 0);
    int end = n;
    for (int line = lines; line >= 1; line--) {
      breaks[line - 1] = end;
      end = prev[line][end];
    }

    return _BalancedBreaks(breaks, costs[lines][n] / lines);
  }

  String _balanceWrap(String text, double maxWidth) {
    final words = _splitWords(text);
    final n = words.length;
    if (n <= 1) return text;

    final wordWidths = List.generate(
      n,
      (i) => _measureCached(words[i]),
      growable: false,
    );
    final spaceWidth = _measureCached(' ');
    final prefix = _buildPrefixSums(wordWidths);

    if (_lineWidth(prefix, 0, n, spaceWidth) <= maxWidth) {
      return text;
    }

    final greedy = _greedyBreaks(prefix, n, spaceWidth, maxWidth);
    if (greedy.length > 4) {
      return _prettyWrap(text, maxWidth);
    }

    double bestScore = .infinity;
    List<int>? bestBreaks;

    for (int lines = 2; lines <= math.min(4, n); lines++) {
      final solution = _solveBalancedBreaks(
        prefix,
        n,
        spaceWidth,
        maxWidth,
        lines,
      );
      if (solution == null) continue;

      // ignore: move-variable-closer-to-its-usage
      final breaks = solution.breaks;
      final score = solution.score;

      if (score < bestScore) {
        bestScore = score;
        bestBreaks = breaks;
      }
    }

    return bestBreaks == null
        ? _prettyWrap(text, maxWidth)
        : _joinWords(words, bestBreaks);
  }
}
