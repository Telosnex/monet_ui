// A Curve adapter that lets implicit animations (AnimatedContainer, etc.)
// use spring dynamics without restructuring to explicit AnimationController.
//
// Yes, it's ironic — the whole point of Flux is that springs aren't curves
// (they don't have a fixed duration). But Flutter's implicit animation widgets
// require a Curve, and this adapter is the pragmatic bridge. It simulates the
// spring for a fixed number of frames and maps t ∈ [0,1] into the result.
//
// Use this for Tier 3 animations (AnimatedContainer, AnimatedSize, etc.)
// where the widget structure change isn't worth the spring benefit.
// For Tier 1 (gesture → spring), use the real FluxAnimation classes.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:monet_ui/flux/rk4_spring.dart';
import 'package:monet_ui/flux/spring.dart';

/// A [Curve] backed by a spring simulation.
///
/// Maps t ∈ [0, 1] to the spring's position at time t * [settleTime].
/// The spring runs from 0.0 → 1.0 with zero initial velocity.
///
/// [settleTime] is auto-computed from the spring parameters if not provided:
/// it's the time at which the spring is within 0.1% of the target.
///
/// Usage:
/// ```dart
/// AnimatedContainer(
///   duration: const Duration(milliseconds: 500),
///   curve: FluxCurve(spring: FluxSpring.snappy),
///   // ...
/// )
/// ```
class FluxCurve extends Curve {
  FluxCurve({
    SpringDescription spring = FluxSpring.gentle,
    RK4SpringDescription? rk4,
    double? settleTime,
    this.debugLabel,
    // Can be used at runtime; flagged so there's a warning to remove it after
    // debugging and before checking in.
    @visibleForTesting this.debugLogs = false,
  }) : _rk4Desc =
           rk4 ??
           RK4SpringDescription(
             tension: spring.stiffness,
             friction: spring.damping,
           ),
       _settleTime =
           settleTime ??
           _computeSettleTimeRK4(
             rk4 ??
                 RK4SpringDescription(
                   tension: spring.stiffness,
                   friction: spring.damping,
                 ),
           ) {
    assert(() {
      if (debugLogs) {
        debugPrint(
          '[FluxCurve${debugLabel == null ? '' : ' $debugLabel'}] '
          'settle=${(_settleTime * 1000).toStringAsFixed(0)}ms '
          'rk4=$_rk4Desc',
        );
      }
      return true;
    }());
  }

  final RK4SpringDescription _rk4Desc;
  final double _settleTime;
  final String? debugLabel;
  final bool debugLogs;

  /// The spring settle time in seconds, used to map [transformInternal].
  double get settleTime => _settleTime;

  /// The spring's natural duration — the wall-clock time it needs to settle.
  ///
  /// Use this as the `duration` parameter for implicit animation widgets:
  /// ```dart
  /// final curve = FluxCurve(spring: FluxSpring.gentle);
  /// AnimatedContainer(
  ///   duration: curve.duration,
  ///   curve: curve,
  /// )
  /// ```
  ///
  /// Without this, the animation controller picks an arbitrary duration
  /// and the spring shape gets time-compressed or stretched. The spring
  /// overshoot might happen at 60ms wall time — invisible.
  Duration get duration => .new(milliseconds: (_settleTime * 1000).round());

  @override
  double transformInternal(double t) {
    // Map t ∈ [0, 1] to simulation time.
    // Use the RK4 spring with soft onset, not the analytical solution.
    final spring = RK4Spring(initValue: 0.0, desc: _rk4Desc);
    spring.target = 1.0;
    spring.elapseTime(t * _settleTime);
    return spring.value;
  }

  /// Compute the time at which the RK4 spring settles within tolerance.
  static double _computeSettleTimeRK4(RK4SpringDescription desc) {
    final spring = RK4Spring(initValue: 0.0, desc: desc);
    spring.target = 1.0;
    const tolerance = 0.001;
    const maxTime = 5.0;
    const dt = 1.0 / 60.0;
    double t = 0.0;
    while (t < maxTime) {
      spring.elapseTime(dt);
      t += dt;
      if ((spring.value - 1.0).abs() < tolerance &&
          spring.velocity.abs() < tolerance) {
        return math.max(t, 0.1);
      }
    }
    return maxTime;
  }
}
