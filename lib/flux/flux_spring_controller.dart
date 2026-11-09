import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'package:monet_ui/flux/flux_animation.dart';
import 'package:monet_ui/flux/sim.dart';
import 'package:monet_ui/flux/spring.dart';

/// A retargetable, simulation-driven spring for bounded double values.
///
/// Unlike a [CurvedAnimation], this controller has no artificial duration.
/// Calling [animateTo] while it is moving starts a new spring from the current
/// value and instantaneous velocity, so reversals do not jerk or restart from
/// rest.
class FluxSpringController extends FluxAnimation<double>
    with
        AnimationLocalStatusListenersMixin,
        AnimationLocalListenersMixin,
        AnimationEagerListenerMixin {
  FluxSpringController({
    required TickerProvider vsync,
    double value = 0,
    this.lowerBound = 0,
    this.upperBound = 1,
    this.spring = FluxSpring.snappy,
  }) : assert(lowerBound <= value && value <= upperBound),
       _value = value,
       _target = value,
       _status = value == lowerBound
           ? .dismissed
           : value == upperBound
           ? .completed
           : .forward {
    _ticker = vsync.createTicker(_tick);
  }

  final double lowerBound;
  final double upperBound;
  final SpringDescription spring;
  late final Ticker _ticker;

  SimDouble? _simulation;
  double _value;
  double _velocity = 0;
  double _target;
  AnimationStatus _status;

  @override
  double get value => _value;

  @override
  double get velocity => _velocity;

  double get target => _target;

  @override
  bool get isAnimating => _ticker.isActive;

  @override
  AnimationStatus get status => _status;

  /// Springs from the current state to [target].
  ///
  /// A running spring is retargeted with its current velocity. The returned
  /// future completes when this particular ticker run stops; callers should
  /// still inspect [status] because a later retarget may have interrupted it.
  TickerFuture animateTo(double target) {
    assert(lowerBound <= target && target <= upperBound);
    if (!_ticker.isActive && target == _value) {
      _target = target;
      _velocity = 0;
      _setStatus(_settledStatus(target));
      return TickerFuture.complete();
    }

    if (_ticker.isActive) _ticker.stop();
    _target = target;
    _simulation = springSimDouble(
      start: _value,
      end: target,
      velocity: _velocity,
      spring: spring,
    );
    _setStatus(target >= _value ? .forward : .reverse);
    return _ticker.start();
  }

  /// Stops motion and places the controller exactly at [value].
  void jumpTo(double value) {
    assert(lowerBound <= value && value <= upperBound);
    if (_ticker.isActive) _ticker.stop();
    _simulation = null;
    _value = value;
    _target = value;
    _velocity = 0;
    notifyListeners();
    _setStatus(_settledStatus(value));
  }

  AnimationStatus _settledStatus(double value) {
    return value <= lowerBound ? .dismissed : .completed;
  }

  void _setStatus(AnimationStatus value) {
    if (_status == value) return;
    _status = value;
    notifyStatusListeners(value);
  }

  void _tick(Duration elapsed) {
    final simulation = _simulation;
    if (simulation == null) return;
    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    if (simulation.isDone(seconds)) {
      _value = _target;
      _velocity = 0;
      _ticker.stop();
      notifyListeners();
      _setStatus(_settledStatus(_target));
      return;
    }
    _value = simulation.value(seconds);
    _velocity = simulation.velocity(seconds);
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
