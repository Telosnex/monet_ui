import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/monet_theme_data.dart';
import 'package:monet_ui/util/color_deprecated.dart';
import 'package:pixel_snap_fork/material.dart';

/// A custom slider implementation that follows Monet design principles.
/// This implementation is lightweight and doesn't rely on the Material slider.
class MonetSlider extends StatefulWidget {
  static const kDefaultTrackHeight = MonetThemeData.touchSize;

  /// The current value of the slider.
  final double value;

  /// The minimum value the slider can have.
  final double min;

  /// The maximum value the slider can have.
  final double max;

  /// Called before an interaction changes the value (including tap/hold).
  final ValueChanged<double>? onChangeStart;

  /// Called when a pointer, keyboard, or accessibility action changes the value.
  final ValueChanged<double>? onChanged;

  /// Called after an interaction, or deferred cleanup on disable/unmount.
  final ValueChanged<double>? onChangeEnd;

  /// The icon to show in the thumb.
  final IconData? thumbIcon;

  /// A letter to show in the thumb (alternative to icon).
  final String? thumbLetter;

  /// A text style for the thumb letter.
  final TextStyle? thumbLetterStyle;

  /// Whether the slider is enabled.
  final bool enabled;

  /// The height of the track.
  final double trackHeight;

  /// The color of the active portion of the track.
  final Color? activeTrackColor;

  /// The color of the inactive portion of the track.
  final Color? inactiveTrackColor;

  /// The color of the border around the track.
  final Color? borderColor;

  /// The color of the icon or letter in the thumb.
  final Color? thumbContentColor;

  /// Creates a MonetSlider widget.
  const MonetSlider({
    super.key,
    required this.value,
    this.min = 0.0,
    this.max = 1.0,
    this.onChangeStart,
    this.onChanged,
    this.onChangeEnd,
    this.thumbIcon,
    this.thumbLetter,
    this.thumbLetterStyle,
    this.enabled = true,
    this.trackHeight = kDefaultTrackHeight,
    this.activeTrackColor,
    this.inactiveTrackColor,
    this.borderColor,
    this.thumbContentColor,
  }) : assert(min < max),
       assert(value >= min && value <= max),
       assert(
         thumbIcon == null || thumbLetter == null,
         'Cannot provide both thumbIcon and thumbLetter',
       );

  @override
  State<MonetSlider> createState() => _MonetSliderState();
}

class _MonetSliderState extends State<MonetSlider> {
  final FocusNode _focusNode = FocusNode();
  bool _dragging = false;
  double? _acceptedDragValue;
  int? _interactionPointer;
  ValueChanged<double>? _endInteractionCallback;
  ValueChanged<double>? _settleEndValue;

  void _beginInteraction(PointerDownEvent event) {
    if (!widget.enabled || _interactionPointer != null) return;
    _settleEndValue = null;
    _focusNode.requestFocus();
    _interactionPointer = event.pointer;
    _endInteractionCallback = widget.onChangeEnd;
    widget.onChangeStart?.call(_currentValue);
  }

  void _endInteraction(PointerEvent event) {
    if (_interactionPointer != event.pointer) return;
    _interactionPointer = null;
    final end = _endInteractionCallback;
    _endInteractionCallback = null;
    // Allow the final onChanged's parent rebuild to accept/quantize the value,
    // even when release occurs before the next frame.
    var endValue = _currentValue;
    void settle(double value) => endValue = value;
    _settleEndValue = settle;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_settleEndValue == settle) _settleEndValue = null;
      end?.call(endValue);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _abandonInteraction() {
    if (_interactionPointer == null) return;
    _interactionPointer = null;
    _dragging = false;
    _currentValue = _acceptedDragValue ?? _currentValue;
    _acceptedDragValue = null;
    final end = _endInteractionCallback;
    _endInteractionCallback = null;
    final value = _currentValue;
    // Removing/disabling a slider may happen during another widget's build.
    if (end != null) scheduleMicrotask(() => end(value));
  }

  @override
  void dispose() {
    _abandonInteraction();
    _focusNode.dispose();
    super.dispose();
  }

  late double _currentValue;

  double get trackHeight {
    return math.sqrt(MonetTheme.of(context).scale) * widget.trackHeight;
  }

  @override
  void initState() {
    super.initState();
    _currentValue = widget.value;
  }

  @override
  void didUpdateWidget(MonetSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _abandonInteraction();
    if (_dragging) {
      // Retain even unchanged values: a parent may reject or quantize an
      // interaction back to its previous controlled value.
      _acceptedDragValue = widget.value;
    } else if (oldWidget.value != widget.value || _settleEndValue != null) {
      // Only update the internal value if we're not currently dragging
      // This prevents conflicts between gesture updates and parent widget updates
      _currentValue = widget.value;
      _settleEndValue?.call(_currentValue);
    }
  }

  void _handleDragStart(DragStartDetails details) {
    if (!widget.enabled) return;

    _dragging = true;
    // Calculate the new position and update the value
    _updateAndNotify(details.localPosition);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_dragging || !widget.enabled) return;

    _updateAndNotify(details.localPosition);
  }

  void _updateAndNotify(Offset position) {
    final double previousValue = _currentValue;
    _updateValueFromPosition(position);

    // Only notify if the value actually changed
    if (previousValue != _currentValue) {
      widget.onChanged?.call(_currentValue);
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!_dragging || !widget.enabled) return;

    _finishDrag();
  }

  void _finishDrag() {
    _dragging = false;
    final accepted = _acceptedDragValue;
    _acceptedDragValue = null;
    if (accepted != null && accepted != _currentValue) {
      setState(() => _currentValue = accepted);
    }
    _settleEndValue?.call(_currentValue);
  }

  void _handleTapDown(TapDownDetails details) {
    if (!widget.enabled) return;

    // Set dragging to true to prevent value override from parent
    _dragging = true;
    _updateAndNotify(details.localPosition);

    // Reset dragging state after tap is complete
    _finishDrag();
  }

  void _updateValueFromPosition(Offset position) {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    // Get the thumb radius (half of track height)
    final double r = trackHeight / 2;

    // Geometry must mirror _MonetSliderPainter.
    final double trackLen = box.size.width; // full painted track
    if (trackLen <= 0) return;

    final double innerLen =
        trackLen - (r * 2); // range the thumb centre travels
    if (innerLen <= 0) return;

    // Clamp pointer so the thumb stays fully inside the track when value=1.0
    final double x = position.dx.clamp(r, trackLen - r);

    // Inverse mapping of
    //   thumbCenterX = r + innerLen * v  ⇒  v = (thumbCenterX - r) / innerLen
    final double valueFraction = ((x - r) / innerLen).clamp(0.0, 1.0);

    final double newValue =
        widget.min + valueFraction * (widget.max - widget.min);

    final double roundedValue = _roundToNearestFraction(newValue, 1000);

    if (_currentValue != roundedValue) {
      setState(() {
        _currentValue = roundedValue;
      });
    }
  }

  // Rounds a value to the nearest 1/precision
  // This helps avoid microscopic value changes that cause jitter
  double _roundToNearestFraction(double value, int precision) {
    return (value * precision).round() / precision;
  }

  double _adjustedValue(bool increase) {
    final step = (widget.max - widget.min) / 20;
    return (_currentValue + (increase ? step : -step)).clamp(
      widget.min,
      widget.max,
    );
  }

  void _adjustTo(double value) {
    // An accessible adjustment is one complete interaction. Do not mix it
    // into a pointer session, whose end callback belongs to pointer-up.
    if (!widget.enabled || _interactionPointer != null) return;
    final nextValue = value.clamp(widget.min, widget.max);
    if (nextValue == _currentValue) return;

    final end = widget.onChangeEnd;
    widget.onChangeStart?.call(_currentValue);
    setState(() => _currentValue = nextValue);
    try {
      widget.onChanged?.call(nextValue);
    } finally {
      end?.call(nextValue);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.enabled ||
        _interactionPointer != null ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return .ignored;
    }

    final key = event.logicalKey;
    if (key == .arrowRight || key == .arrowUp) {
      _adjustTo(_adjustedValue(true));
    } else if (key == .arrowLeft || key == .arrowDown) {
      _adjustTo(_adjustedValue(false));
    } else if (key == .home) {
      _adjustTo(widget.min);
    } else if (key == .end) {
      _adjustTo(widget.max);
    } else {
      return .ignored;
    }
    return .handled;
  }

  String _semanticValue(double value) {
    // Keep spoken values readable without binary floating-point noise, while
    // retaining useful precision even for sliders with very small ranges.
    final text = value.toStringAsPrecision(6);
    if (!text.contains('.') || text.contains('e')) return text;
    return text
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final MonetTheme monet = MonetTheme.of(context);

    // Determine colors from theme if not provided
    final activeTrackColor = widget.activeTrackColor ?? monet.primary.color;
    final inactiveTrackColor =
        widget.inactiveTrackColor ?? monet.primary.background;
    final borderColor = widget.borderColor ?? monet.primary.colorBorder;
    final thumbContentColor =
        widget.thumbContentColor ?? monet.primary.colorIcon;

    final double normalizedValue =
        (_currentValue - widget.min) / (widget.max - widget.min);

    // Apply opacity if not enabled
    final double opacity = widget.enabled ? 1.0 : 0.6;

    final canIncrease = widget.enabled && _currentValue < widget.max;
    final canDecrease = widget.enabled && _currentValue > widget.min;

    return Focus(
      focusNode: _focusNode,
      canRequestFocus: widget.enabled,
      includeSemantics: false,
      // ignore: avoid-empty-setstate, no-empty-block
      onFocusChange: (_) => setState(() {}),
      onKeyEvent: _handleKeyEvent,
      child: Semantics(
        slider: true,
        enabled: widget.enabled,
        focusable: widget.enabled,
        focused: _focusNode.hasFocus,
        value: _semanticValue(_currentValue),
        increasedValue: canIncrease
            ? _semanticValue(_adjustedValue(true))
            : null,
        decreasedValue: canDecrease
            ? _semanticValue(_adjustedValue(false))
            : null,
        onIncrease: canIncrease ? () => _adjustTo(_adjustedValue(true)) : null,
        onDecrease: canDecrease ? () => _adjustTo(_adjustedValue(false)) : null,
        child: MouseRegion(
          cursor: widget.enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: Listener(
            onPointerDown: _beginInteraction,
            onPointerUp: _endInteraction,
            onPointerCancel: (event) {
              _finishDrag();
              _endInteraction(event);
            },
            child: GestureDetector(
              excludeFromSemantics: true,
              onHorizontalDragStart: _handleDragStart,
              onHorizontalDragUpdate: _handleDragUpdate,
              onHorizontalDragEnd: _handleDragEnd,
              onHorizontalDragCancel: _finishDrag,
              onTapDown: _handleTapDown,
              behavior: .opaque, // Improves touch response
              child: SizedBox(
                height: trackHeight,
                child: CustomPaint(
                  painter: _MonetSliderPainter(
                    value: normalizedValue,
                    trackHeight: trackHeight,
                    activeTrackColor: activeTrackColor.withOpacityNeue(opacity),
                    inactiveTrackColor: inactiveTrackColor.withOpacityNeue(
                      opacity,
                    ),
                    borderColor:
                        (_focusNode.hasFocus ? activeTrackColor : borderColor)
                            .withOpacityNeue(opacity),
                    thumbIcon: widget.thumbIcon,
                    thumbLetter: widget.thumbLetter,
                    thumbLetterStyle: widget.thumbLetterStyle,
                    thumbContentColor: thumbContentColor.withOpacityNeue(
                      opacity,
                    ),
                  ),
                  size: .infinite,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MonetSliderPainter extends CustomPainter {
  final double value;
  final double trackHeight;
  final Color activeTrackColor;
  final Color inactiveTrackColor;
  final Color borderColor;
  final IconData? thumbIcon;
  final String? thumbLetter;
  final TextStyle? thumbLetterStyle;
  final Color thumbContentColor;

  // Cached paint objects to avoid recreation on every paint
  late final Paint _inactiveTrackPaint;
  late final Paint _activeTrackPaint;
  late final Paint _borderPaint;
  late final Paint _blurPaint;

  _MonetSliderPainter({
    required this.value,
    required this.trackHeight,
    required this.activeTrackColor,
    required this.inactiveTrackColor,
    required this.borderColor,
    this.thumbIcon,
    this.thumbLetter,
    this.thumbLetterStyle,
    required this.thumbContentColor,
  }) {
    // Initialize paints once in the constructor
    _inactiveTrackPaint = Paint()..color = inactiveTrackColor;
    _activeTrackPaint = Paint()..color = activeTrackColor;

    _borderPaint = Paint()
      ..color = borderColor
      ..style = .stroke
      ..strokeWidth = 1.0;

    _blurPaint = Paint()
      ..color = borderColor
      // Without fill, the shadow is displayed on the inside of the track,
      // even with BlurStyle.outer.
      ..style = .fill
      ..strokeWidth = 1.0
      ..maskFilter = const MaskFilter.blur(.outer, 2.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = trackHeight / 2;
    final double borderWidth = 1.0;

    // Center the track vertically
    final double trackY = size.height / 2;

    // Track layout
    final double trackStart = 0;
    final double trackEnd = size.width;
    final double trackLength = trackEnd - trackStart;

    // Background track
    final Rect trackRect = Rect.fromLTRB(
      trackStart,
      trackY - radius,
      trackEnd,
      trackY + radius,
    );

    final RRect trackRRect = RRect.fromRectAndRadius(
      trackRect,
      .circular(radius),
    );

    // Draw background track
    canvas.drawRRect(trackRRect, _inactiveTrackPaint);

    // Compute inner usable length so the thumb circle stays fully inside
    // the track. Inner length excludes a radius on both ends.
    final double innerLen = trackLength - (radius * 2);

    // Thumb centre travels from `trackStart + radius`  ..  `trackEnd - radius`.
    final double thumbCenterX = trackStart + radius + (innerLen * value);

    // The active track visually extends to the *trailing edge* of the thumb
    // (centre + radius) so it appears to connect seamlessly.
    final double activeRight = thumbCenterX + radius;

    final Rect activeRect = Rect.fromLTRB(
      trackStart,
      trackY - radius,
      activeRight,
      trackY + radius,
    );

    final RRect activeRRect = RRect.fromRectAndCorners(
      activeRect,
      topLeft: .circular(radius),
      bottomLeft: .circular(radius),
      topRight: .circular(radius),
      bottomRight: .circular(radius),
    );

    canvas.drawRRect(activeRRect, _activeTrackPaint);

    // Draw border on background track (deflated to keep stroke inside pixels)
    final RRect trackBorderRRect = trackRRect.deflate(borderWidth / 2);
    canvas.drawRRect(trackBorderRRect, _borderPaint);

    // Blur for background track border
    canvas.drawRRect(trackBorderRRect, _blurPaint);

    // Draw border only on right semi-circle of thumb to avoid left overlap
    final double thumbX = thumbCenterX;
    final Offset thumbCenter = Offset(thumbX, trackY);

    const double arcStartAngle = -math.pi / 2; // top center moving clockwise
    const double arcSweepAngle = math.pi; // right half circle
    canvas.drawArc(
      Rect.fromCircle(center: thumbCenter, radius: radius - borderWidth / 2),
      arcStartAngle,
      arcSweepAngle,
      false,
      _borderPaint,
    );

    // Draw icon or letter if provided
    if (thumbIcon != null || thumbLetter != null) {
      // Calculate position for icon/letter - always centered in the thumb area
      // The thumb is the rounded end of the active track
      final double thumbX = thumbCenterX;

      final Offset thumbCenter = Offset(thumbX, trackY);

      final double contentSize = radius * 1.2;
      final ui.ParagraphBuilder builder;

      if (thumbIcon != null) {
        // Draw icon
        builder =
            ui.ParagraphBuilder(
                ui.ParagraphStyle(
                  fontFamily: thumbIcon!.fontFamily,
                  fontSize: contentSize,
                ),
              )
              ..pushStyle(
                ui.TextStyle(color: thumbContentColor, fontSize: contentSize),
              )
              ..addText(String.fromCharCode(thumbIcon!.codePoint));
      } else {
        // Draw letter
        final TextStyle effectiveTextStyle =
            thumbLetterStyle ??
            const TextStyle(color: Colors.white, fontSize: 12);

        builder =
            ui.ParagraphBuilder(
                ui.ParagraphStyle(
                  fontFamily: effectiveTextStyle.fontFamily,
                  fontSize: contentSize,
                ),
              )
              ..pushStyle(
                ui.TextStyle(
                  color: thumbContentColor,
                  fontSize: contentSize,
                  fontWeight: effectiveTextStyle.fontWeight,
                ),
              )
              ..addText(thumbLetter!);
      }

      final ui.Paragraph paragraph = builder.build()
        ..layout(ui.ParagraphConstraints(width: contentSize * 2));

      final double contentHeight = paragraph.height;
      final double contentWidth = paragraph.minIntrinsicWidth;

      canvas.drawParagraph(
        paragraph,
        Offset(
          thumbCenter.dx - contentWidth / 2,
          thumbCenter.dy - contentHeight / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_MonetSliderPainter oldPainter) {
    return oldPainter.value != value ||
        oldPainter.trackHeight != trackHeight ||
        oldPainter.activeTrackColor != activeTrackColor ||
        oldPainter.inactiveTrackColor != inactiveTrackColor ||
        oldPainter.borderColor != borderColor ||
        oldPainter.thumbIcon != thumbIcon ||
        oldPainter.thumbLetter != thumbLetter ||
        oldPainter.thumbContentColor != thumbContentColor;
  }
}
