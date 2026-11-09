import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:loggy/loggy.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pixel_snap_fork/material.dart';

import 'package:monet_ui/util/custom_cupertino_page_route.dart';
import 'package:monet_ui/util/is_web.dart';

/// A widget that indicates its descendants should be prioritized for horizontal
/// gestures over the TrackpadDismissGestureDetector.
///
/// If [needsPriority] is provided it is called at hit-test time.  Return false
/// to yield priority back to the dismiss detector (e.g. when a horizontal
/// scroll view is already at its leading edge and can't scroll further).
class HorizontalGesturePriority extends StatelessWidget {
  final Widget child;

  /// Called during hit-test to decide whether this widget still needs
  /// horizontal gesture priority.  When null, priority is always claimed.
  final bool Function()? needsPriority;

  const HorizontalGesturePriority({
    super.key,
    required this.child,
    this.needsPriority,
  });

  @override
  Widget build(BuildContext context) {
    return MetaData(metaData: this, child: child);
  }
}

final _trackpadDismissClock = Stopwatch()..start();
Duration _defaultTrackpadDismissNow() => _trackpadDismissClock.elapsed;

typedef _Now = Duration Function();

final class _TrackpadDismissCoordinator {
  _TrackpadDismissCoordinator({required this._now});

  static const nonScrollSignalSuppression = Duration(milliseconds: 80);

  _Now _now;
  Duration? _lastDismissAt;
  Duration? _ignoreScrollUntil;
  bool _dismissInFlight = false;

  Duration get now => _now();

  bool get isCoolingDown {
    final last = _lastDismissAt;
    return last != null &&
        now - last < TrackpadDismissGestureDetector.kPopCooldown;
  }

  bool get canReserveDismiss => !_dismissInFlight && !isCoolingDown;

  bool tryReserveDismiss() {
    if (!canReserveDismiss) return false;
    _dismissInFlight = true;
    return true;
  }

  void markDismissed() {
    _lastDismissAt = now;
    _dismissInFlight = false;
  }

  void cancelReservation() {
    _dismissInFlight = false;
  }

  void ignoreScrollBriefly(Duration eventTimeStamp) {
    _ignoreScrollUntil = eventTimeStamp + nonScrollSignalSuppression;
  }

  bool shouldIgnoreScroll(Duration eventTimeStamp) {
    final until = _ignoreScrollUntil;
    return until != null && eventTimeStamp <= until;
  }

  void resetForTesting({_Now? now}) {
    _now = now ?? _defaultTrackpadDismissNow;
    _lastDismissAt = null;
    _ignoreScrollUntil = null;
    _dismissInFlight = false;
  }
}

// ignore: prefer-single-widget-per-file
class TrackpadDismissGestureDetector extends HookWidget with UiLoggy {
  static final _coordinator = _TrackpadDismissCoordinator(
    now: _defaultTrackpadDismissNow,
  );

  @visibleForTesting
  static void resetCoordinatorForTesting({Duration Function()? now}) {
    _coordinator.resetForTesting(now: now);
  }

  /// Gate for the conditional horizontal-priority feature: when a
  /// [HorizontalGesturePriority] provides a [needsPriority] callback that
  /// returns false, treat the trackpad pan-zoom end as a dismiss.
  /// Set to false to revert to the old unconditional priority behaviour.
  static const _kConditionalHorizontalPriority = true;
  static bool kEnabledForTouchFirstOS = false;
  // Match Chromium's desktop touchpad history-navigation thresholds.
  static const kOverscrollStartThreshold = 60.0;
  static const kHorizontalDominanceRatio = 2.5;
  static const kCompleteTouchpadThresholdPercent = 0.3;
  static const kFlingVelocityThreshold = 1100.0;
  static const kListenerSpeedThreshold = kConstIsWeb ? 25 : 200;
  // Longest animation time in CupertinoPageRoute and just so happens to match
  // the time its needed to avoid having the chat list view scroll when
  // the photo is vertically dismissed on web.
  static const kPopCooldown = Duration(
    milliseconds: kMaxDroppedSwipePageForwardAnimationTime,
  );

  final bool topToBottom;

  /// When provided, called instead of [Navigator.pop] on dismiss.
  final VoidCallback? onDismiss;

  final Widget child;
  const TrackpadDismissGestureDetector({
    super.key,
    this.topToBottom = false,
    this.onDismiss,
    required this.child,
  });

  // onPanEnd does not fire on Web or Linux.
  static bool needsListener(BuildContext context) {
    return isWeb ||
        Theme.of(context).platform == .linux ||
        Theme.of(context).platform == .macOS;
  }

  bool _hasHorizontalPriorityAt(BuildContext context, Offset position) {
    final HitTestResult result = HitTestResult();
    if (!context.mounted) return false;
    final viewId = View.maybeOf(context)?.viewId ?? 0;
    WidgetsBinding.instance.hitTestInView(result, position, viewId);
    return result.path.any((entry) {
      final target = entry.target;
      if (target is RenderMetaData &&
          target.metaData is HorizontalGesturePriority) {
        if (!_kConditionalHorizontalPriority) return true;
        final priority = target.metaData as HorizontalGesturePriority;
        return priority.needsPriority?.call() ?? true;
      }
      return false;
    });
  }

  static bool needsDetection(BuildContext context) {
    final isIOS = !isWeb && Theme.of(context).platform == .iOS;
    final isAndroid = !isWeb && Theme.of(context).platform == .android;
    final isTouchFirstOS = isIOS || isAndroid;
    return (!isTouchFirstOS || kEnabledForTouchFirstOS) ||
        needsListener(context);
  }

  bool _isHorizontalScrollDismiss(
    BuildContext context,
    PointerScrollEvent event,
  ) {
    final platform = Theme.of(context).platform;
    if (!isWeb && platform != .linux) return false;

    final delta = event.scrollDelta;
    return delta.dx < -kListenerSpeedThreshold &&
        delta.dx.abs() > delta.dy.abs();
  }

  bool _isVerticalScrollDismiss(PointerScrollEvent event) {
    final delta = event.scrollDelta;
    return topToBottom &&
        delta.dy < -kListenerSpeedThreshold &&
        delta.dy.abs() > delta.dx.abs();
  }

  bool _isChromeStyleBackGesture(
    BuildContext context, {
    required Offset pan,
    required Offset velocity,
  }) {
    if (!context.mounted) return false;
    final direction = Directionality.maybeOf(context);
    if (direction == null) return false;
    final logicalPan = direction == .rtl ? -pan : pan;
    final logicalVelocity = direction == .rtl ? -velocity : velocity;
    final hasStarted =
        logicalPan.dx > kOverscrollStartThreshold &&
        logicalPan.dx.abs() > logicalPan.dy.abs() * kHorizontalDominanceRatio;
    if (!hasStarted) return false;

    final view = View.maybeOf(context);
    final displayLongestSide = view == null
        ? MediaQuery.sizeOf(context).longestSide
        : view.display.size.longestSide / view.display.devicePixelRatio;
    final isFarEnough =
        displayLongestSide > 0 &&
        logicalPan.dx / displayLongestSide >= kCompleteTouchpadThresholdPercent;
    final isFastEnough = logicalVelocity.dx > kFlingVelocityThreshold;
    return isFarEnough || isFastEnough;
  }

  @override
  Widget build(BuildContext context) {
    final needListener = needsListener(context);
    if (!needListener && !needsDetection(context)) {
      return child;
    }

    final panAccumulator = useRef(Offset.zero);

    // Accumulates trackpad pan delta across PointerPanZoom updates and derives
    // release velocity, which PointerPanZoomEndEvent does not provide.
    final panZoomAccumulator = _kConditionalHorizontalPriority
        ? useRef(Offset.zero)
        : null;
    final panZoomVelocityTracker = _kConditionalHorizontalPriority
        ? useRef<VelocityTracker?>(null)
        : null;

    // Handle horizontal gestures with GestureDetector
    return GestureDetector(
      onPanEnd: (details) {
        if (_hasHorizontalPriorityAt(context, details.globalPosition)) {
          panAccumulator.value = .zero;
          return;
        }
        final shouldDismiss = _isChromeStyleBackGesture(
          context,
          pan: panAccumulator.value,
          velocity: details.velocity.pixelsPerSecond,
        );
        panAccumulator.value = .zero;
        if (shouldDismiss) {
          _popIfPossible(context);
        }
      },
      onPanCancel: () => panAccumulator.value = .zero,
      onPanStart: (_) => panAccumulator.value = .zero,
      onPanUpdate: (details) => panAccumulator.value += details.delta,
      child: Listener(
        onPointerSignal:
            // No specific motivation for this, just seems expensive to have
            // an extremely high traffic listener if its not needed.
            !needListener
            ? null
            : (event) {
                if (event is! PointerScrollEvent) {
                  _coordinator.ignoreScrollBriefly(event.timeStamp);
                  return;
                }

                if (_coordinator.shouldIgnoreScroll(event.timeStamp)) {
                  return;
                }

                if (_hasHorizontalPriorityAt(context, event.position)) {
                  return;
                }

                final shouldDismiss =
                    _isHorizontalScrollDismiss(context, event) ||
                    _isVerticalScrollDismiss(event);
                if (shouldDismiss) {
                  GestureBinding.instance.pointerSignalResolver.register(
                    event,
                    (_) => _popIfPossible(context),
                  );
                }
              },
        onPointerPanZoomEnd: !needListener
            ? null
            : (event) {
                if (!_kConditionalHorizontalPriority) {
                  return;
                }
                // On macOS native, trackpad gestures arrive as
                // PointerPanZoom events, not PointerScrollEvents.
                final pan = panZoomAccumulator!.value;
                panZoomAccumulator.value = .zero;
                final velocity =
                    panZoomVelocityTracker!.value
                        ?.getVelocity()
                        .pixelsPerSecond ??
                    .zero;
                panZoomVelocityTracker.value = null;
                if (!_isChromeStyleBackGesture(
                  context,
                  pan: pan,
                  velocity: velocity,
                )) {
                  return;
                }
                final hitResult = HitTestResult();
                final viewId = View.maybeOf(context)?.viewId ?? 0;
                WidgetsBinding.instance.hitTestInView(
                  hitResult,
                  event.position,
                  viewId,
                );
                for (final entry in hitResult.path) {
                  final target = entry.target;
                  if (target is RenderMetaData &&
                      target.metaData is HorizontalGesturePriority) {
                    final priority =
                        target.metaData as HorizontalGesturePriority;
                    if (priority.needsPriority != null &&
                        !priority.needsPriority!()) {
                      _popIfPossible(context);
                      return;
                    }
                  }
                }
              },
        onPointerPanZoomUpdate: !needListener
            ? null
            : !_kConditionalHorizontalPriority
            ? null
            : (event) {
                // Chromium only counts the portion the child did not consume
                // as overscroll. Start over while the child still has room.
                if (_hasHorizontalPriorityAt(context, event.position)) {
                  panZoomAccumulator!.value = .zero;
                  final velocityTracker = VelocityTracker.withKind(event.kind);
                  velocityTracker.addPosition(event.timeStamp, .zero);
                  panZoomVelocityTracker!.value = velocityTracker;
                  return;
                }
                panZoomAccumulator!.value += event.panDelta;
                panZoomVelocityTracker!.value?.addPosition(
                  event.timeStamp,
                  panZoomAccumulator.value,
                );
              },
        onPointerPanZoomStart: !needListener
            ? null
            : (event) {
                if (_kConditionalHorizontalPriority) {
                  panZoomAccumulator!.value = .zero;
                  final velocityTracker = VelocityTracker.withKind(event.kind);
                  velocityTracker.addPosition(event.timeStamp, .zero);
                  panZoomVelocityTracker!.value = velocityTracker;
                }
              },
        onPointerDown: (details) {
          final x = smallestButton(details.buttons);
          // back button on logitech mouse
          if (x == 8) {
            _popIfPossible(context);
          }
        },
        child: child,
      ),
    );
  }

  // Fancy implementation avoids an issue if triggered on macOS.
  // Repro case: tap Home chat tile, then swipe back quickly.
  static final _maxAttempts = 50; // Maximum number of retry attempts
  static final _maxWaitTime = Duration(seconds: 5); // Maximum wait time

  void _popIfPossible(
    BuildContext context, {
    int attempts = 0,
    Duration? firstAttemptTime,
    bool hasReservation = false,
  }) {
    if (!hasReservation && !_coordinator.tryReserveDismiss()) {
      return;
    }
    hasReservation = true;

    // When an override is provided, invoke it with cooldown protection
    // but skip the Navigator transition dance.
    if (onDismiss != null) {
      _coordinator.markDismissed();
      onDismiss!();
      return;
    }

    if (!context.mounted) {
      _coordinator.cancelReservation();
      return;
    }

    final now = _coordinator.now;
    firstAttemptTime ??= now;

    final navigator = Navigator.of(context);

    // Check if we've exceeded the maximum wait time or attempts
    if (attempts >= _maxAttempts || now - firstAttemptTime > _maxWaitTime) {
      loggy.error(
        'Pop attempt timed out or max attempts reached. Forcing pop.',
      );
      if (navigator.canPop()) {
        _coordinator.markDismissed();
        navigator.pop();
      } else {
        _coordinator.cancelReservation();
      }
      return;
    }

    // Check if any route transition is in progress
    bool isTransitionInProgress() {
      final route = ModalRoute.of(context);
      return route?.animation?.status == .forward ||
          route?.animation?.status == .reverse;
    }

    // Check for user gesture or any route transition
    final transitionInProgress = isTransitionInProgress();
    if (navigator.userGestureInProgress || transitionInProgress) {
      // Wait for the transition to complete before popping.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _popIfPossible(
          context,
          attempts: attempts + 1,
          firstAttemptTime: firstAttemptTime,
          hasReservation: hasReservation,
        );
      });
      WidgetsBinding.instance.scheduleFrame();
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) {
        _coordinator.cancelReservation();
        return;
      }
      final navigator = Navigator.of(context);
      if (!navigator.canPop()) {
        _coordinator.cancelReservation();
        return;
      }
      _coordinator.markDismissed();
      navigator.pop();
    });
    WidgetsBinding.instance.scheduleFrame();
  }
}
