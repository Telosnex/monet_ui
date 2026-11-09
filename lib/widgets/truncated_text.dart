// ignore_for_file: prefer-single-widget-per-file

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// A widget that truncates text in the middle and adds an ellipsis when it overflows.
///
/// This is useful when you want to show the beginning and end of a text but have
/// limited space, such as for filenames or URLs.
class MiddleEllipsisText extends StatelessWidget {
  /// The text to display and potentially truncate.
  final String text;

  /// Optional text style to apply to the text.
  final TextStyle? style;

  /// The ellipsis string to use for indicating truncation. Defaults to '...'.
  final String ellipsis;

  const MiddleEllipsisText({
    super.key,
    required this.text,
    this.style,
    this.ellipsis = '...',
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final direction = Directionality.of(context);
        final effectiveStyle = style == null || style!.inherit
            ? DefaultTextStyle.of(context).style.merge(style)
            : style!;
        final scaler = MediaQuery.textScalerOf(context);
        final truncatedText = _truncatedText(
          constraints.maxWidth,
          direction,
          effectiveStyle,
          scaler,
        );

        return Text(
          truncatedText,
          style: effectiveStyle,
          textScaler: scaler,
          maxLines: 1,
          softWrap: false,
          overflow: .clip,
        );
      },
    );
  }

  String _truncatedText(
    double maxWidth,
    TextDirection direction,
    TextStyle effectiveStyle,
    TextScaler scaler,
  ) {
    // Lay out once for the full text.
    final fullPainter = TextPainter(
      text: TextSpan(text: text, style: effectiveStyle),
      maxLines: 1,
      textDirection: direction,
      textScaler: scaler,
    )..layout(minWidth: 0, maxWidth: .infinity);

    try {
      if (fullPainter.width <= maxWidth) {
        return text;
      }

      // Measure the ellipsis once.
      final ellipsisPainter = TextPainter(
        text: TextSpan(text: ellipsis, style: effectiveStyle),
        maxLines: 1,
        textDirection: direction,
        textScaler: scaler,
      )..layout(minWidth: 0, maxWidth: .infinity);

      try {
        final ellipsisWidth = ellipsisPainter.width;
        final availableWidth = maxWidth - ellipsisWidth;

        if (availableWidth <= 0) {
          return ellipsis;
        }

        final half = availableWidth / 2.0;

        // Use the existing layout to map widths to text positions.
        int leftEnd = fullPainter.getPositionForOffset(Offset(half, 0)).offset;
        final totalWidth = fullPainter.width;
        final rightStartX = math.max(0.0, totalWidth - half);
        int rightStart = fullPainter
            .getPositionForOffset(Offset(rightStartX, 0))
            .offset;

        // Make sure the measured substring widths are <= their targets.
        double leftWidth = _selectionWidth(fullPainter, 0, leftEnd, direction);
        while (leftEnd > 0 && leftWidth > half) {
          final prev = fullPainter.getOffsetBefore(leftEnd);
          if (prev == null) break;
          leftEnd = prev;
          leftWidth = _selectionWidth(fullPainter, 0, leftEnd, direction);
        }

        double rightWidth = _selectionWidth(
          fullPainter,
          rightStart,
          text.length,
          direction,
        );
        while (rightStart < text.length && rightWidth > half) {
          final next = fullPainter.getOffsetAfter(rightStart);
          if (next == null) break;
          rightStart = next;
          rightWidth = _selectionWidth(
            fullPainter,
            rightStart,
            text.length,
            direction,
          );
        }

        // Ensure we don't overlap.
        if (leftEnd <= 0 && rightStart >= text.length) {
          return ellipsis;
        }
        if (leftEnd >= rightStart) {
          // Not enough space for both sides, show whichever has more width.
          if (leftWidth >= rightWidth && leftEnd > 0) {
            return '${text.substring(0, leftEnd)}$ellipsis';
          } else if (rightStart < text.length) {
            return '$ellipsis${text.substring(rightStart)}';
          } else {
            return ellipsis;
          }
        }

        final startText = leftEnd > 0 ? text.substring(0, leftEnd) : '';
        final endText = rightStart < text.length
            ? text.substring(rightStart)
            : '';

        return '$startText$ellipsis$endText';
      } finally {
        ellipsisPainter.dispose();
      }
    } finally {
      fullPainter.dispose();
    }
  }
}

/// A widget that truncates text at the beginning and adds an ellipsis when it overflows.
///
/// This is useful when you want to show the end of a text but have limited space,
/// such as for long paths or file names where the end is more important.
class LeadingEllipsisText extends StatelessWidget {
  /// The text to display and potentially truncate.
  final String text;

  /// Optional text style to apply to the text.
  final TextStyle? style;

  /// The ellipsis string to use for indicating truncation. Defaults to '...'.
  final String ellipsis;

  const LeadingEllipsisText({
    super.key,
    required this.text,
    this.style,
    this.ellipsis = '...',
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final direction = Directionality.of(context);
        final effectiveStyle = style == null || style!.inherit
            ? DefaultTextStyle.of(context).style.merge(style)
            : style!;
        final scaler = MediaQuery.textScalerOf(context);
        final truncatedText = _truncatedText(
          constraints.maxWidth,
          direction,
          effectiveStyle,
          scaler,
        );

        return Text(
          truncatedText,
          style: effectiveStyle,
          textScaler: scaler,
          maxLines: 1,
          softWrap: false,
          overflow: .clip,
        );
      },
    );
  }

  String _truncatedText(
    double maxWidth,
    TextDirection direction,
    TextStyle effectiveStyle,
    TextScaler scaler,
  ) {
    // Lay out once for the full text.
    final fullPainter = TextPainter(
      text: TextSpan(text: text, style: effectiveStyle),
      maxLines: 1,
      textDirection: direction,
      textScaler: scaler,
    )..layout(minWidth: 0, maxWidth: .infinity);

    try {
      if (fullPainter.width <= maxWidth) {
        return text;
      }

      // Measure the ellipsis once.
      final ellipsisPainter = TextPainter(
        text: TextSpan(text: ellipsis, style: effectiveStyle),
        maxLines: 1,
        textDirection: direction,
        textScaler: scaler,
      )..layout(minWidth: 0, maxWidth: .infinity);

      try {
        final availableWidth = maxWidth - ellipsisPainter.width;
        if (availableWidth <= 0) {
          return ellipsis;
        }

        // Choose the start index so that [start..end] fits in availableWidth.
        final startX = math.max(0.0, fullPainter.width - availableWidth);
        int startIndex = fullPainter
            .getPositionForOffset(Offset(startX, 0))
            .offset;

        double width = _selectionWidth(
          fullPainter,
          startIndex,
          text.length,
          direction,
        );
        while (startIndex < text.length && width > availableWidth) {
          final next = fullPainter.getOffsetAfter(startIndex);
          if (next == null) break;
          startIndex = next;
          width = _selectionWidth(
            fullPainter,
            startIndex,
            text.length,
            direction,
          );
        }

        if (startIndex >= text.length) {
          return ellipsis;
        }

        final visibleText = text.substring(startIndex);

        return '$ellipsis$visibleText';
      } finally {
        ellipsisPainter.dispose();
      }
    } finally {
      fullPainter.dispose();
    }
  }
}

/// A widget that truncates text at the end and adds an ellipsis when it overflows.
///
/// This is a more customizable version of Flutter's built-in Text widget with
/// TextOverflow.ellipsis, with more precise control over the truncation.
class TrailingEllipsisText extends StatelessWidget {
  /// The text to display and potentially truncate.
  final String text;

  /// Optional text style to apply to the text.
  final TextStyle? style;

  /// The ellipsis string to use for indicating truncation. Defaults to '...'.
  final String ellipsis;

  const TrailingEllipsisText({
    super.key,
    required this.text,
    this.style,
    this.ellipsis = '...',
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final direction = Directionality.of(context);
        final effectiveStyle = style == null || style!.inherit
            ? DefaultTextStyle.of(context).style.merge(style)
            : style!;
        final scaler = MediaQuery.textScalerOf(context);
        final truncatedText = _truncatedText(
          constraints.maxWidth,
          direction,
          effectiveStyle,
          scaler,
        );

        return Text(
          truncatedText,
          style: effectiveStyle,
          textScaler: scaler,
          maxLines: 1,
          softWrap: false,
          overflow: .clip,
        );
      },
    );
  }

  String _truncatedText(
    double maxWidth,
    TextDirection direction,
    TextStyle effectiveStyle,
    TextScaler scaler,
  ) {
    // Lay out once for the full text.
    final fullPainter = TextPainter(
      text: TextSpan(text: text, style: effectiveStyle),
      maxLines: 1,
      textDirection: direction,
      textScaler: scaler,
    )..layout(minWidth: 0, maxWidth: .infinity);

    try {
      if (fullPainter.width <= maxWidth) {
        return text;
      }

      // Measure the ellipsis once.
      final ellipsisPainter = TextPainter(
        text: TextSpan(text: ellipsis, style: effectiveStyle),
        maxLines: 1,
        textDirection: direction,
        textScaler: scaler,
      )..layout(minWidth: 0, maxWidth: .infinity);

      try {
        final availableWidth = maxWidth - ellipsisPainter.width;
        if (availableWidth <= 0) {
          return ellipsis;
        }

        // Choose the end index so that [0..end] fits in availableWidth.
        int endIndex = fullPainter
            .getPositionForOffset(Offset(availableWidth, 0))
            .offset;
        double width = _selectionWidth(fullPainter, 0, endIndex, direction);
        while (endIndex > 0 && width > availableWidth) {
          final prev = fullPainter.getOffsetBefore(endIndex);
          if (prev == null) break;
          endIndex = prev;
          width = _selectionWidth(fullPainter, 0, endIndex, direction);
        }

        if (endIndex <= 0) {
          return ellipsis;
        }

        final visibleText = text.substring(0, endIndex);

        return '$visibleText$ellipsis';
      } finally {
        ellipsisPainter.dispose();
      }
    } finally {
      fullPainter.dispose();
    }
  }
}

// Helper: compute width of a selection from an already-laid-out TextPainter.
double _selectionWidth(
  TextPainter painter,
  int start,
  int end,
  TextDirection _,
) {
  if (end <= start) return 0.0;
  final boxes = painter.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: end),
  );
  if (boxes.isEmpty) return 0.0;
  // For single-line LTR, the union width is right-most minus left-most.
  double minLeft = .infinity;
  double maxRight = -double.infinity;
  for (final b in boxes) {
    minLeft = math.min(minLeft, b.left);
    maxRight = math.max(maxRight, b.right);
  }
  final width = math.max(0.0, maxRight - minLeft);
  return width;
}
