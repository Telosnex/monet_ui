import 'dart:async';

import 'package:clock/clock.dart';
import 'package:loggy/loggy.dart';

/// Coalesces repeated publish requests so work runs at most once per [interval].
///
/// If multiple publishes arrive while a publish is in flight or during the
/// throttle window, only the latest pending callback is retained.
class ThrottledPublisher with UiLoggy {
  final Duration interval;
  Timer? _timer;
  DateTime? _lastPublishTime;
  bool _isPending = false;
  bool _isExecuting = false;
  bool _isDisposed = false;
  Future<void>? _inFlight;
  FutureOr<void> Function()? _pendingPublish;

  ThrottledPublisher({this.interval = const Duration(milliseconds: 500)});

  /// The callback currently executing, if any.
  Future<void>? get inFlight => _inFlight;

  /// Current time, via [Clock] so tests can override it with [FakeAsync].
  DateTime _now() => clock.now();

  /// Schedules [fn] for throttled execution.
  ///
  /// The first publish executes immediately. While a publish is in flight or a
  /// throttle timer is active, newer publish requests replace the pending one.
  void publish(FutureOr<void> Function() fn) {
    if (_isDisposed) return;
    _pendingPublish = fn;
    _isPending = true;

    if (_timer != null || _isExecuting) {
      return;
    }

    final now = _now();
    final lastPublishTime = _lastPublishTime;
    if (lastPublishTime == null) {
      _startPendingPublish();
      return;
    }

    final timeSinceLastPublish = now.difference(lastPublishTime);

    if (timeSinceLastPublish >= interval) {
      _startPendingPublish();
    } else {
      _schedulePublish(interval - timeSinceLastPublish);
    }
  }

  void _startPendingPublish() {
    final pending = _pendingPublish;
    if (pending == null) return;

    _pendingPublish = null;
    _isPending = false;
    _startPublish(pending);
  }

  void _startPublish(FutureOr<void> Function() fn) {
    final future = _executePublish(fn);
    _inFlight = future;
    unawaited(future);
  }

  Future<void> _executePublish(FutureOr<void> Function() fn) async {
    _isExecuting = true;
    try {
      await Future.sync(fn);
      _lastPublishTime = _now();
      _isPending = false;
    } catch (error, stackTrace) {
      // publish() is fire-and-forget. Observe callback errors here so they do
      // not escape the async root, and continue to the latest pending value.
      loggy.error('ThrottledPublisher callback threw', error, stackTrace);
    } finally {
      _isExecuting = false;
      _inFlight = null;
    }

    if (_pendingPublish != null) {
      _schedulePublish(interval);
    }
  }

  void _schedulePublish(Duration delay) {
    if (_timer != null) return;

    _isPending = true;
    _timer = Timer(delay, () {
      _timer = null;
      _startPendingPublish();
    });
  }

  /// Waits for any in-flight publish to complete, then immediately runs the
  /// latest pending publish, if any.
  Future<void> flush() async {
    if (_isDisposed) return;
    if (!_isPending && _pendingPublish == null && !_isExecuting) {
      return;
    }

    if (_isExecuting) {
      await _inFlight;
    }
    // dispose() can run while the in-flight callback above is awaited.
    if (_isDisposed) return;

    // Cancel any existing timer
    _timer?.cancel();
    _timer = null;

    // Execute any pending publish immediately
    if (_pendingPublish != null) {
      final pending = _pendingPublish!;
      _pendingPublish = null;
      _isPending = false;
      _startPublish(pending);
      await _inFlight;
    }

    _isPending = false;
  }

  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
    _timer = null;
    _pendingPublish = null;
  }
}
