import 'package:monet_ui/widgets/scroll_edge_fade.dart';
import 'package:pixel_snap_fork/material.dart';

/// A one-line [TextField] that is as wide as its text and shrinks its font,
/// in whole points, to fit the available width.
///
/// The font starts at [style]'s size clamped to [minFontSize] and
/// [maxFontSize]. If the text does not fit at [minFontSize], the field takes
/// the full width and scrolls, fading the edges that have text past them.
/// The width includes room for the caret after the text, and is never less
/// than [minWidth].
class AutoSizeTitleField extends StatefulWidget {
  const AutoSizeTitleField({
    required this.controller,
    required this.style,
    required this.minFontSize,
    required this.maxFontSize,
    required this.cursorColor,
    this.decoration = const InputDecoration(),
    this.textAlign = TextAlign.start,
    this.minWidth = 0,
    this.fadeWidth = 16,
    super.key,
  }) : assert(0 < minFontSize && minFontSize <= maxFontSize);

  final TextEditingController controller;

  /// The text style. Its font size, or 14 if it has none, is the size to use
  /// when the text fits.
  final TextStyle style;
  final double minFontSize;
  final double maxFontSize;
  final Color cursorColor;
  final InputDecoration decoration;
  final TextAlign textAlign;
  final double minWidth;
  final double fadeWidth;

  @override
  State<AutoSizeTitleField> createState() => _AutoSizeTitleFieldState();
}

class _AutoSizeTitleFieldState extends State<AutoSizeTitleField> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(AutoSizeTitleField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _scrollController.dispose();
    super.dispose();
  }

  var _lastText = '';

  void _onTextChanged() {
    // Selection and composing changes also notify; only text sizes the field.
    if (widget.controller.text == _lastText) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    _lastText = widget.controller.text;
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final padding = widget.decoration.contentPadding?.horizontal ?? 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = _fit(context, style, constraints.maxWidth - padding);
        return SizedBox(
          width: (fit.width + padding).clamp(widget.minWidth, double.infinity),
          child: Align(
            alignment: _alignment(widget.textAlign),
            child: ScrollEdgeFade(
              controller: _scrollController,
              leading: widget.fadeWidth,
              trailing: widget.fadeWidth,
              child: TextField(
                controller: widget.controller,
                scrollController: _scrollController,
                style: style.copyWith(fontSize: fit.fontSize),
                cursorColor: widget.cursorColor,
                decoration: widget.decoration,
                textAlign: widget.textAlign,
              ),
            ),
          ),
        );
      },
    );
  }

  /// The largest whole font size from the starting size down to
  /// [AutoSizeTitleField.minFontSize] at which the text fits [available],
  /// and the text's width at that size.
  _Fit _fit(BuildContext context, TextStyle style, double available) {
    final text = widget.controller.text;
    final painter = TextPainter(
      // A trailing space keeps room for the caret after the text.
      text: TextSpan(text: text.isEmpty ? '' : '$text ', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    try {
      double widthAt(double size) {
        painter.text = TextSpan(
          text: (painter.text! as TextSpan).text,
          style: style.copyWith(fontSize: size),
        );
        painter.layout();
        return painter.width;
      }

      final start = (style.fontSize ?? 14).clamp(
        widget.minFontSize,
        widget.maxFontSize,
      );
      final startWidth = widthAt(start);
      if (startWidth <= available) return _Fit(start, startWidth);

      // Binary search over whole sizes for the largest that fits.
      var low = widget.minFontSize.ceil();
      var high = start.ceil() - 1;
      var best = widget.minFontSize;
      while (low <= high) {
        final mid = (low + high) ~/ 2;
        if (widthAt(mid.toDouble()) <= available) {
          best = mid.toDouble();
          low = mid + 1;
        } else {
          high = mid - 1;
        }
      }
      return _Fit(best, widthAt(best));
    } finally {
      painter.dispose();
    }
  }
}

Alignment _alignment(TextAlign align) => switch (align) {
  .start || .left => Alignment.centerLeft,
  .end || .right => Alignment.centerRight,
  .center || .justify => Alignment.center,
};

/// A font size and the text's width at that size.
final class _Fit {
  const _Fit(this.fontSize, this.width);
  final double fontSize;
  final double width;
}
