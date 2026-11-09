// Flutter Hooks integration for Flux animations.
//
// These hooks manage the lifecycle of FluxAnimation objects — creating them,
// disposing them, and rebuilding the widget when they tick.

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_hooks/flutter_hooks.dart';

import 'package:monet_ui/flux/flux_animation.dart';
import 'package:monet_ui/flux/spring.dart';

/// Creates a [SimAnimationController] that springs from [start] to [end].
///
/// The spring auto-starts and auto-disposes. Returns a [FluxAnimation<double>]
/// that rebuilds the widget on every tick.
///
/// Restarts whenever [start], [end], or [spring] change.
///
/// Usage:
/// ```dart
/// final anim = useFluxSpring(
///   start: isExpanded ? 0.0 : 1.0,
///   end: isExpanded ? 1.0 : 0.0,
///   spring: FluxSpring.snappy,
/// );
/// // anim.value is 0.0 → 1.0 (with overshoot if underdamped)
/// // anim.velocity is the current velocity in units/sec
/// ```
FluxAnimation<double> useFluxSpring({
  required double start,
  required double end,
  double velocity = 0.0,
  SpringDescription spring = FluxSpring.snappy,
}) {
  return use(
    _FluxSpringHook(start: start, end: end, velocity: velocity, spring: spring),
  );
}

class _FluxSpringHook extends Hook<FluxAnimation<double>> {
  const _FluxSpringHook({
    required this.start,
    required this.end,
    required this.velocity,
    required this.spring,
  });

  final double start;
  final double end;
  final double velocity;
  final SpringDescription spring;

  @override
  _FluxSpringHookState createState() => .new();
}

class _FluxSpringHookState
    extends HookState<FluxAnimation<double>, _FluxSpringHook>
    implements TickerProvider {
  late SimAnimationController<double> _controller;
  // ignore: dispose-class-fields
  Ticker? _ticker;
  ValueListenable<TickerModeData>? _tickerModeNotifier;

  @override
  Ticker createTicker(TickerCallback onTick) {
    assert(
      _ticker == null,
      'useFluxSpring attempted to create multiple Tickers.',
    );
    _ticker = Ticker(onTick, debugLabel: 'created by useFluxSpring');
    _updateTickerModeNotifier();
    _updateTicker();
    return _ticker!;
  }

  void _updateTickerModeNotifier() {
    final newNotifier = TickerMode.getValuesNotifier(context);
    if (newNotifier == _tickerModeNotifier) return;
    _tickerModeNotifier?.removeListener(_updateTicker);
    _tickerModeNotifier = newNotifier;
    _tickerModeNotifier?.addListener(_updateTicker);
  }

  void _updateTicker() {
    if (_ticker != null) {
      _ticker!.muted = !(_tickerModeNotifier?.value.enabled ?? true);
    }
  }

  @override
  void initHook() {
    super.initHook();
    _createController();
    _controller.start();
  }

  @override
  void didUpdateHook(_FluxSpringHook oldHook) {
    if (oldHook.start != hook.start ||
        oldHook.end != hook.end ||
        oldHook.spring != hook.spring) {
      // Pick up from current velocity for seamless transition.
      final currentVelocity = _controller.velocity;
      _controller.dispose();
      _ticker = null;
      _createController(velocity: currentVelocity);
      _controller.start();
    }
  }

  void _createController({double? velocity}) {
    final sim = springSimDouble(
      start: hook.start,
      end: hook.end,
      velocity: velocity ?? hook.velocity,
      spring: hook.spring,
    );
    _controller = SimAnimationController<double>(vsync: this, sim: sim);
    _controller.addListener(_markNeedsBuild);
  }

  void _markNeedsBuild() {
    // ignore: no-empty-block
    setState(() {});
  }

  @override
  FluxAnimation<double> build(BuildContext context) => _controller;

  @override
  void dispose() {
    _tickerModeNotifier?.removeListener(_updateTicker);
    _tickerModeNotifier = null;
    _controller.removeListener(_markNeedsBuild);
    _controller.dispose();
  }

  @override
  String get debugLabel => 'useFluxSpring';
}

/// Creates a [ManualAnimation] for drag-to-spring patterns.
///
/// During a drag: call `animation.update(value: ..., velocity: ...)`
/// When released: call `animation.done()` — the builder creates a spring
/// that picks up from the gesture's velocity.
///
/// Usage:
/// ```dart
/// final drag = useFluxManual<double>(
///   initialValue: 0.0,
///   initialVelocity: 0.0,
///   builder: (value, velocity) => SimAnimationController(
///     vsync: this,
///     sim: springSimDouble(start: value, end: 0.0, velocity: velocity),
///   )..start(),
/// );
///
/// GestureDetector(
///   onPanUpdate: (d) => drag.update(value: d.localPosition.dy, velocity: ...),
///   onPanEnd: (_) => drag.done(),
/// )
/// ```
ManualAnimation<T> useFluxManual<T>({
  required T initialValue,
  required T initialVelocity,
  FluxAnimationInit<T>? builder,
}) {
  return use(
    _FluxManualHook<T>(
      initialValue: initialValue,
      initialVelocity: initialVelocity,
      builder: builder,
    ),
  );
}

class _FluxManualHook<T> extends Hook<ManualAnimation<T>> {
  const _FluxManualHook({
    required this.initialValue,
    required this.initialVelocity,
    this.builder,
  });

  final T initialValue;
  final T initialVelocity;
  final FluxAnimationInit<T>? builder;

  @override
  _FluxManualHookState<T> createState() => .new();
}

class _FluxManualHookState<T>
    extends HookState<ManualAnimation<T>, _FluxManualHook<T>> {
  late ManualAnimation<T> _animation;

  @override
  void initHook() {
    super.initHook();
    _animation = ManualAnimation<T>(
      value: hook.initialValue,
      velocity: hook.initialVelocity,
      builder: hook.builder,
    );
    _animation.addListener(_markNeedsBuild);
  }

  void _markNeedsBuild() {
    // ignore: no-empty-block
    setState(() {});
  }

  @override
  ManualAnimation<T> build(BuildContext context) => _animation;

  @override
  void dispose() {
    _animation.removeListener(_markNeedsBuild);
    // ManualAnimation doesn't own a ticker, so nothing else to dispose.
  }

  @override
  String get debugLabel => 'useFluxManual';
}
