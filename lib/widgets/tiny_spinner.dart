import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/rendering.dart' show PipelineOwner;
import 'package:flutter/scheduler.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/palette.dart';
import 'package:monet_ui/widgets/icon_size.dart';
import 'package:pixel_snap_fork/material.dart';

class TinySpinner extends StatelessWidget {
  /// Widget states of the surface the spinner sits on, for example the
  /// `statesController` of an enclosing `MonetButton`. When set, the
  /// spinner uses the hovered and splashed colors of its palette for those
  /// states. The color is resolved at paint time; state changes do not
  /// rebuild this widget.
  final ValueListenable<Set<WidgetState>>? states;

  const TinySpinner({super.key, this.states});

  @override
  Widget build(BuildContext context) {
    final double size =
        iconSizeForTextStyleOrNull(Theme.of(context).textTheme.bodySmall) ?? 12;
    return SizedBox(
      height: size,
      width: size,
      child: _TinySpinnerArc(
        palette: MonetTheme.of(context).tertiary,
        states: states,
        strokeWidth: 2, // Don't scale.
      ),
    );
  }
}

// ignore: prefer-single-widget-per-file
class _TinySpinnerArc extends LeafRenderObjectWidget {
  final Palette palette;
  final ValueListenable<Set<WidgetState>>? states;
  final double strokeWidth;

  const _TinySpinnerArc({
    required this.palette,
    required this.states,
    required this.strokeWidth,
  });

  @override
  RenderTinySpinner createRenderObject(BuildContext context) {
    return RenderTinySpinner(
      palette: palette,
      states: states,
      strokeWidth: strokeWidth,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderTinySpinner renderObject,
  ) {
    renderObject
      ..palette = palette
      ..states = states
      ..strokeWidth = strokeWidth;
  }
}

/// Paints a rotating arc at about 30 fps, and only while it is painted.
///
/// There is no ticker. Each paint starts a one-shot timer, and the timer
/// marks this render object as needing paint, which schedules the next
/// frame. When an ancestor stops painting the spinner (scrolled out of the
/// viewport, in a list's cache area, `Offstage`, a covered route), flushPaint
/// skips it, no timer starts, and frames stop after one more frame. When an
/// ancestor paints it again, it is still marked as needing paint, so the
/// rotation resumes on its own.
///
/// Each frame moves the arc end about 1 px at this size, so a 60 or 120 Hz
/// ticker would mostly produce frames that look the same.
///
/// The angle comes from the frame timestamp, which follows `timeDilation`
/// and the fake clock of widget tests.
@visibleForTesting
class RenderTinySpinner extends RenderBox {
  /// Time for one full turn.
  static const period = Duration(milliseconds: 900);

  /// Delay from a paint to the next repaint request. The frame then waits
  /// for the next vsync, so 25 ms gives every 2nd frame at 60 Hz and every
  /// 3rd or 4th frame at 120 Hz.
  static const repaintDelay = Duration(milliseconds: 25);

  static const _sweep = math.pi * 1.4;

  RenderTinySpinner({
    required this._palette,
    required this._states,
    required this._strokeWidth,
  });

  final Paint _paint = Paint()
    ..style = .stroke
    ..strokeCap = .round;
  Timer? _repaintTimer;
  Duration _lastFrameTimeStamp = .zero;

  Palette get palette => _palette;
  Palette _palette;
  set palette(Palette value) {
    if (identical(value, _palette)) return;
    _palette = value;
    markNeedsPaint();
  }

  ValueListenable<Set<WidgetState>>? get states => _states;
  ValueListenable<Set<WidgetState>>? _states;
  set states(ValueListenable<Set<WidgetState>>? value) {
    if (value == _states) return;
    if (attached) _states?.removeListener(markNeedsPaint);
    _states = value;
    if (attached) _states?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  double get strokeWidth => _strokeWidth;
  double _strokeWidth;
  set strokeWidth(double value) {
    if (value == _strokeWidth) return;
    _strokeWidth = value;
    markNeedsPaint();
  }

  /// Whether a repaint request is pending. For tests.
  @visibleForTesting
  bool get hasPendingRepaint => _repaintTimer != null;

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    return constraints.smallest;
  }

  // Same as the CustomPaint this replaced: the spinner's area counts as a
  // hit, so ancestors with deferToChild hit testing still receive taps on it.
  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _states?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _states?.removeListener(markNeedsPaint);
    _repaintTimer?.cancel();
    _repaintTimer = null;
    super.detach();
  }

  void _onRepaintTimer() {
    _repaintTimer = null;
    markNeedsPaint();
  }

  /// Same state precedence as libmonet's `widgetPropertyByState`, which the
  /// enclosing button's `backgroundButtonStyle` uses for its surface.
  Color _colorFor(Set<WidgetState> states) {
    if (states.contains(WidgetState.pressed) ||
        states.contains(WidgetState.dragged)) {
      return palette.backgroundSplashedFill;
    }
    if (states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.focused) ||
        states.contains(WidgetState.selected)) {
      return palette.backgroundHoveredFill;
    }
    return palette.fill;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // The frame timestamp is only set during a frame. A paint outside one,
    // for example by a test's `paints` matcher, keeps the last angle.
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase != .idle) {
      _lastFrameTimeStamp = scheduler.currentFrameTimeStamp;
    }
    final elapsed = _lastFrameTimeStamp;
    final turn =
        (elapsed.inMicroseconds % period.inMicroseconds) /
        period.inMicroseconds;

    _paint
      ..color = _colorFor(states?.value ?? const {})
      ..strokeWidth = strokeWidth;
    final diameter = math.min(size.width, size.height);
    final radius = math.max(0.0, (diameter - strokeWidth) / 2);
    context.canvas.drawArc(
      Rect.fromCircle(center: offset + size.center(.zero), radius: radius),
      turn * math.pi * 2 - math.pi / 2,
      _sweep,
      false,
      _paint,
    );

    _repaintTimer ??= Timer(repaintDelay, _onRepaintTimer);
  }
}
