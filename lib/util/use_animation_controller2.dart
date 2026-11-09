// Lazy, forked replacement for flutter_hooks' useAnimationController.
//
// Why a fork at all: flutter_hooks' _TickerProviderHookState.createTicker
// builds `debugLabel: 'created by $context'` UNCONDITIONALLY (flutter_hooks
// 0.21.3+1, lib/src/animation.dart). `$context` is Element.toString(), which
// renders widget diagnostics — and it runs in every build mode, unlike
// Flutter's own TickerProviderStateMixin, which guards its label with
// kDebugMode. A CPU profile of merely scrolling a static conversation
// (test-results/dart_devtools_2026-06-12_09_21_36.946.json) showed 3.5% of
// UI-thread self time in createTicker alone.
//
// Why lazy: a follow-up profile with the label fixed
// (test-results/dart_devtools_2026-06-12_09_43_19.712.json) still attributed
// ~2.9% of UI-thread time to AnimationController/Ticker lifecycle (creation,
// TickerMode wiring, Ticker's debug-only StackTrace.current capture,
// disposal) for controllers that NEVER ticked: expand arrows, borders and
// expandables allocate a controller per conversation-tile mount, but during
// a plain scroll nothing animates.
//
// So useAnimationController2 registers a cheap hook slot and defers
// AnimationController + Ticker construction until the first call that
// actually needs to animate. forward()/reverse()/animateTo() calls that
// would be no-ops (already at the target value, the common case on mount)
// do not construct anything.

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_hooks/flutter_hooks.dart';

/// Lazily-constructed stand-in for [AnimationController].
///
/// Extends [ProxyAnimation], so it can be used anywhere an
/// [Animation<double>] is expected ([AnimatedBuilder], [CurvedAnimation],
/// `drive`, transitions). Until the real controller exists, it proxies a
/// constant value; once something forces creation, existing listeners are
/// transparently re-attached to the real controller.
class LazyAnimationController extends ProxyAnimation {
  LazyAnimationController({
    required this._vsync,
    this._duration,
    this._reverseDuration,
    this.debugLabel,
    double initialValue = 0,
    this.lowerBound = 0,
    this.upperBound = 1,
    this.animationBehavior = AnimationBehavior.normal,
  }) : _staticValue = initialValue,
       super(_StaticAnimation(initialValue, lowerBound, upperBound));

  final TickerProvider _vsync;
  final String? debugLabel;
  final double lowerBound;
  final double upperBound;
  final AnimationBehavior animationBehavior;

  Duration? _duration;
  Duration? _reverseDuration;
  final double _staticValue;
  AnimationController? _controller;
  bool _disposed = false;

  Duration? get duration => _duration;
  set duration(Duration? value) {
    _duration = value;
    _controller?.duration = value;
  }

  Duration? get reverseDuration => _reverseDuration;
  set reverseDuration(Duration? value) {
    _reverseDuration = value;
    _controller?.reverseDuration = value;
  }

  /// Whether the real [AnimationController] has been constructed.
  bool get isCreated => _controller != null;

  /// The real controller, constructing it (and its [Ticker]) on first access.
  AnimationController get controller {
    assert(!_disposed, 'LazyAnimationController used after dispose');
    var controller = _controller;
    if (controller == null) {
      controller = AnimationController(
        vsync: _vsync,
        duration: _duration,
        reverseDuration: _reverseDuration,
        debugLabel: debugLabel,
        value: _staticValue,
        lowerBound: lowerBound,
        upperBound: upperBound,
        animationBehavior: animationBehavior,
      );
      _controller = controller;
      // ProxyAnimation transfers any already-attached listeners.
      parent = controller;
    }
    return controller;
  }

  @override
  double get value => _controller?.value ?? _staticValue;

  set value(double newValue) {
    if (_controller == null && newValue == _staticValue) {
      // Already showing this value; a real controller would only re-notify
      // listeners with an identical value.
      return;
    }
    controller.value = newValue;
  }

  @override
  bool get isAnimating => _controller?.isAnimating ?? false;

  TickerFuture forward({double? from}) {
    if (_controller == null && from == null && _staticValue == upperBound) {
      // Already at the target; the real controller would complete
      // synchronously without ever ticking. Don't construct it.
      return TickerFuture.complete();
    }
    return controller.forward(from: from);
  }

  TickerFuture reverse({double? from}) {
    if (_controller == null && from == null && _staticValue == lowerBound) {
      return TickerFuture.complete();
    }
    return controller.reverse(from: from);
  }

  TickerFuture animateTo(
    double target, {
    Duration? duration,
    Curve curve = Curves.linear,
  }) {
    if (_controller == null && target == _staticValue) {
      return TickerFuture.complete();
    }
    return controller.animateTo(target, duration: duration, curve: curve);
  }

  TickerFuture repeat({
    double? min,
    double? max,
    bool reverse = false,
    Duration? period,
  }) {
    return controller.repeat(
      min: min,
      max: max,
      reverse: reverse,
      period: period,
    );
  }

  void reset() {
    if (_controller == null && _staticValue == lowerBound) {
      return;
    }
    // Route through the real controller so listeners are notified of the
    // value change, exactly like AnimationController.reset().
    controller.reset();
  }

  void stop({bool canceled = true}) {
    _controller?.stop(canceled: canceled);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // Detach listeners before disposing the real controller.
    parent = null;
    _controller?.dispose();
    _controller = null;
  }
}

/// Constant-value [Animation] used as the proxy parent before the real
/// controller exists. Reports the same status a fresh [AnimationController]
/// at [value] would (see AnimationController._internalSetValue).
class _StaticAnimation extends Animation<double> {
  const _StaticAnimation(this.value, this._lowerBound, this._upperBound);

  @override
  final double value;
  final double _lowerBound;
  final double _upperBound;

  @override
  // ignore: no-empty-block
  void addListener(VoidCallback listener) {}
  @override
  // ignore: no-empty-block
  void removeListener(VoidCallback listener) {}
  @override
  // ignore: no-empty-block
  void addStatusListener(AnimationStatusListener listener) {}
  @override
  // ignore: no-empty-block
  void removeStatusListener(AnimationStatusListener listener) {}

  @override
  AnimationStatus get status {
    if (value == _lowerBound) return .dismissed;
    if (value == _upperBound) return .completed;
    return .forward;
  }
}

/// Drop-in replacement for flutter_hooks' useAnimationController that only
/// constructs the [AnimationController] (and its [Ticker]) when something
/// actually animates.
///
/// Returns a [LazyAnimationController], which is an [Animation<double>] and
/// supports the common controller surface (forward/reverse/animateTo/repeat/
/// reset/stop/value/isAnimating). Access `.controller` for anything else.
LazyAnimationController useAnimationController2({
  Duration? duration,
  Duration? reverseDuration,
  String? debugLabel,
  double initialValue = 0,
  double lowerBound = 0,
  double upperBound = 1,
  TickerProvider? vsync,
  AnimationBehavior animationBehavior = .normal,
  List<Object?>? keys,
}) {
  return use(
    _LazyAnimationControllerHook(
      duration: duration,
      reverseDuration: reverseDuration,
      debugLabel: debugLabel,
      initialValue: initialValue,
      lowerBound: lowerBound,
      upperBound: upperBound,
      vsync: vsync,
      animationBehavior: animationBehavior,
      keys: keys,
    ),
  );
}

class _LazyAnimationControllerHook extends Hook<LazyAnimationController> {
  const _LazyAnimationControllerHook({
    required this.duration,
    required this.reverseDuration,
    required this.debugLabel,
    required this.initialValue,
    required this.lowerBound,
    required this.upperBound,
    required this.vsync,
    required this.animationBehavior,
    super.keys,
  });

  final Duration? duration;
  final Duration? reverseDuration;
  final String? debugLabel;
  final double initialValue;
  final double lowerBound;
  final double upperBound;
  final TickerProvider? vsync;
  final AnimationBehavior animationBehavior;

  @override
  _LazyAnimationControllerHookState createState() => .new();
}

class _LazyAnimationControllerHookState
    extends HookState<LazyAnimationController, _LazyAnimationControllerHook>
    implements TickerProvider {
  late final LazyAnimationController _animationController =
      LazyAnimationController(
        vsync: hook.vsync ?? this,
        duration: hook.duration,
        reverseDuration: hook.reverseDuration,
        debugLabel: hook.debugLabel,
        initialValue: hook.initialValue,
        lowerBound: hook.lowerBound,
        upperBound: hook.upperBound,
        animationBehavior: hook.animationBehavior,
      );

  // Owned and disposed by the AnimationController created from this
  // provider, mirroring flutter_hooks' useSingleTickerProvider.
  // ignore: dispose-class-fields
  Ticker? _ticker;
  ValueListenable<bool>? _tickerModeNotifier;

  @override
  Ticker createTicker(TickerCallback onTick) {
    assert(
      _ticker == null,
      'useAnimationController2 created a second Ticker. '
      'This should be impossible: the hook owns a single controller.',
    );
    // Upstream difference: constant label instead of 'created by $context'
    // (Element.toString() per ticker creation, in all build modes).
    _ticker = Ticker(
      onTick,
      debugLabel: kDebugMode ? 'created by useAnimationController2' : null,
    );
    _updateTickerModeNotifier();
    _updateTicker();
    return _ticker!;
  }

  @override
  void didUpdateHook(_LazyAnimationControllerHook oldHook) {
    super.didUpdateHook(oldHook);
    if (hook.duration != oldHook.duration) {
      _animationController.duration = hook.duration;
    }
    if (hook.reverseDuration != oldHook.reverseDuration) {
      _animationController.reverseDuration = hook.reverseDuration;
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _tickerModeNotifier?.removeListener(_updateTicker);
    _tickerModeNotifier = null;
    super.dispose();
  }

  @override
  LazyAnimationController build(BuildContext context) {
    // Only maintain TickerMode wiring once a ticker actually exists;
    // this is the entire point of the lazy variant.
    if (_ticker != null) {
      _updateTickerModeNotifier();
      _updateTicker();
    }
    return _animationController;
  }

  void _updateTicker() {
    if (_ticker != null) {
      _ticker!.muted = !_tickerModeNotifier!.value;
    }
  }

  void _updateTickerModeNotifier() {
    // Upstream flutter_hooks still uses the deprecated API; match it so the
    // fork stays behaviorally identical.
    // ignore: deprecated_member_use
    final newNotifier = TickerMode.getNotifier(context);
    if (newNotifier == _tickerModeNotifier) {
      return;
    }
    _tickerModeNotifier?.removeListener(_updateTicker);
    newNotifier.addListener(_updateTicker);
    _tickerModeNotifier = newNotifier;
  }

  @override
  String get debugLabel => 'useAnimationController2';

  @override
  bool get debugSkipValue => true;
}
