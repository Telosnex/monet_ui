import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:monet_ui/colorspaces/hct.dart';
import 'package:monet_ui/core/hex_codes.dart';
import 'package:monet_ui/util/lru_cache.dart';
import 'package:monet_ui/util/use_animation_controller2.dart';
import 'package:monet_ui/widgets/hct_lerp_cartesian.dart';
import 'package:pixel_snap_fork/material.dart';

// Create a static cache for lerpKeepHue results
final _lerpKeepHueCache = LruCache<String, Color>(capacity: 1000);

class AnimatedColorResult {
  final Color Function() getColor;
  final Animation<double> animation;

  const AnimatedColorResult(this.getColor, this.animation);
}

/// Supplies an opt-in foreground color that descendants resolve at paint time.
///
/// This scope deliberately performs a non-dependent lookup in [maybeOf]. The
/// [repaint] listenable updates paint directly; it must not notify widget
/// elements on hover, press, or animation ticks.
///
/// [color] / [iconColor] are build-time snapshots (the *settled* values, for
/// widgets that cannot paint-drive and for `shouldRepaint` comparisons);
/// [paintColor] / [paintIconColor] resolve the current in-flight values at
/// paint time. Icon variants default to the text ones.
class PaintDrivenColorScope extends InheritedWidget {
  const PaintDrivenColorScope({
    super.key,
    required this.color,
    required this.repaint,
    required this.paintColor,
    Color? iconColor,
    Color Function()? paintIconColor,
    required super.child,
  }) : iconColor = iconColor ?? color,
       paintIconColor = paintIconColor ?? paintColor;

  final Color color;
  final Listenable repaint;
  final Color Function() paintColor;
  final Color iconColor;
  final Color Function() paintIconColor;

  static PaintDrivenColorScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType();

  /// Dependent lookup: for descendants that *build* from the settled values
  /// (or hand the paint closures to a render object) and must pick up a new
  /// closure when the scope is rebuilt. Bus ticks never rebuild the scope, so
  /// depending on it is a one-shot rebuild per state change, not per frame.
  static PaintDrivenColorScope? dependOn(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType();

  @override
  bool updateShouldNotify(PaintDrivenColorScope oldWidget) =>
      color != oldWidget.color ||
      iconColor != oldWidget.iconColor ||
      repaint != oldWidget.repaint ||
      !identical(paintColor, oldWidget.paintColor) ||
      !identical(paintIconColor, oldWidget.paintIconColor);
}

/// A shape fill whose color is resolved at paint time from [paintColor].
///
/// Animation ticks call `markNeedsPaint` directly on the render object; they
/// never rebuild [child] or this widget. The shape is fill-only by design:
/// static borders and shadows should remain outside this repaint boundary so
/// a color pulse does not re-record them on every frame.
// ignore: prefer-single-widget-per-file
class PaintDrivenShapeFill extends StatelessWidget {
  const PaintDrivenShapeFill({
    super.key,
    required this.color,
    required this.repaint,
    required this.paintColor,
    this.shape = const RoundedRectangleBorder(),
    required this.child,
  });

  /// Build-time color snapshot used by [CustomPainter.shouldRepaint].
  final Color color;

  /// Animation or paint bus that invalidates only this render object's paint.
  final Listenable repaint;

  /// Resolves the current fill color during paint.
  final Color Function() paintColor;

  /// Fill geometry. Its border side is deliberately not painted.
  final ShapeBorder shape;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PaintDrivenShapeFillPainter(
        color: color,
        repaint: repaint,
        paintColor: paintColor,
        shape: shape,
        textDirection: Directionality.maybeOf(context),
      ),
      child: child,
    );
  }
}

class _PaintDrivenShapeFillPainter extends CustomPainter {
  _PaintDrivenShapeFillPainter({
    required this.color,
    required Listenable repaint,
    required this.paintColor,
    required this.shape,
    required this.textDirection,
  }) : super(repaint: repaint);

  final Paint _fill = Paint()..isAntiAlias = true;
  final Color color;
  final Color Function() paintColor;
  final ShapeBorder shape;
  final TextDirection? textDirection;
  Path? _cachedPath;
  Size? _cachedPathSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width > 0 && size.height > 0) {
      _fill.color = paintColor();
      if (_fill.color.a > 0) {
        if (_cachedPathSize != size) {
          _cachedPath = shape.getOuterPath(
            Offset.zero & size,
            textDirection: textDirection,
          );
          _cachedPathSize = size;
        }
        canvas.drawPath(_cachedPath!, _fill);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PaintDrivenShapeFillPainter oldDelegate) =>
      color != oldDelegate.color ||
      !identical(paintColor, oldDelegate.paintColor) ||
      shape != oldDelegate.shape ||
      textDirection != oldDelegate.textDirection;
}

/// Average awake resting breath: ~4.3s cycle (~14 breaths/min), with the
/// exhale longer than the inhale (~1:1.5). Shared so loading pulses stay in
/// sync.
///
/// Normal adult resting rate is 12-20 breaths/min. Doubling the cycle
/// (~8.6s, ~7 breaths/min) reads as meditative rather than ambient: that's
/// the default rate of Apple Watch's Breathe/Mindfulness app (range 4-10).
/// Sources:
/// - https://www.macrumors.com/2016/06/20/watchos-3-apple-watch-breathe-app/
/// - https://appleinsider.com/articles/16/06/18/inside-watchos-3-new-breathe-app-for-apple-watch-reminds-you-to-relax-focus
/// - https://malaysia.news.yahoo.com/beyond-breathing-behind-apple-approach-022914833.html
const kBreathInhaleDuration = Duration(milliseconds: 1700);
const kBreathExhaleDuration = Duration(milliseconds: 2600);
const kBreathCurve = Curves.easeInOutSine;

/// How long a pulse takes to fade in when loading starts, and out when it
/// stops. Independent of the breath, so stopping doesn't wait for an exhale.
const kBreathFadeDuration = Duration(milliseconds: 500);

/// Breath position (0 = fully out, 1 = fully in) at frame time [time].
///
/// A pure function of the clock, so everything that breathes agrees on the
/// phase regardless of when it started.
double breathAt(Duration time) {
  final inhale = kBreathInhaleDuration.inMicroseconds;
  final exhale = kBreathExhaleDuration.inMicroseconds;
  final t = time.inMicroseconds % (inhale + exhale);
  final x = t < inhale ? t / inhale : 1 - (t - inhale) / exhale;
  return kBreathCurve.transform(x);
}

/// The app-wide breath, as an [Animation] every loading pulse listens to.
///
/// One [Ticker] for the whole app, sampling [breathAt] with the scheduler's
/// frame timestamp (respects `timeDilation`, driven by `pump` in tests). It
/// runs only while something is listening, and every listener reads the same
/// value on a given frame, so pulses are in phase by construction.
final Animation<double> breathAnimation = _BreathAnimation();

class _BreathAnimation extends Animation<double>
    with
        AnimationLazyListenerMixin,
        AnimationLocalListenersMixin,
        AnimationLocalStatusListenersMixin {
  // Process-lifetime singleton: stopped, never disposed.
  Ticker? _ticker;
  double _value = 0;

  @override
  double get value => _value;

  @override
  AnimationStatus get status => .forward;

  @override
  void didStartListening() {
    (_ticker ??= Ticker(
      _tick,
      debugLabel: kDebugMode ? 'breathAnimation' : null,
    )).start();
  }

  @override
  void didStopListening() {
    _ticker?.stop();
  }

  void _tick(Duration _) {
    // Read inside a frame callback, where the frame timestamp is always set.
    _value = breathAt(SchedulerBinding.instance.currentFrameTimeStamp);
    notifyListeners();
  }
}

/// One widget's pulse: its own fade [_intensity] times the shared breath.
///
/// Subscribes to [breathAnimation] only while [breathing] and while it has
/// listeners itself, so idle widgets keep the app-wide ticker stopped.
class _LoadingPulse extends Animation<double>
    with
        AnimationLazyListenerMixin,
        AnimationLocalListenersMixin,
        AnimationLocalStatusListenersMixin {
  _LoadingPulse(this._intensity);

  final LazyAnimationController _intensity;
  bool _breathing = false;

  bool get breathing => _breathing;
  set breathing(bool value) {
    if (value == _breathing) return;
    _breathing = value;
    if (!isListening) return;
    if (value) {
      breathAnimation.addListener(notifyListeners);
    } else {
      breathAnimation.removeListener(notifyListeners);
    }
  }

  @override
  double get value {
    final intensity = _intensity.value;
    if (!_breathing || intensity == 0) return 0;
    return Curves.easeInOut.transform(intensity) * breathAnimation.value;
  }

  @override
  AnimationStatus get status => _intensity.status;

  @override
  void didStartListening() {
    _intensity
      ..addListener(notifyListeners)
      ..addStatusListener(notifyStatusListeners);
    if (_breathing) breathAnimation.addListener(notifyListeners);
  }

  @override
  void didStopListening() {
    _intensity
      ..removeListener(notifyListeners)
      ..removeStatusListener(notifyStatusListeners);
    if (_breathing) breathAnimation.removeListener(notifyListeners);
  }
}

AnimatedColorResult useAnimatedColor({
  required Color baseColor,
  required bool isLoading,
  required bool isBackgroundWallpaper,
  String? debugTag,
  double toneDelta = 20.0,
  bool keepChroma = false,
}) {
  const logRebuildInMemoized = false;
  void logRebuild(String Function() name) {
    // rationale: intended when disabled
    // ignore: dead_code
    if (logRebuildInMemoized) {
      // rationale: intended
      // ignore: avoid_print
      print('Rebuilding ${name()}');
    }
  }

  // The controller only fades this widget's pulse in and out; the breath
  // itself is the shared [breathAnimation]. Lazy, so no ticker cost at rest.
  final wasActive = useRef(false);
  final intensity = useAnimationController2(duration: kBreathFadeDuration);
  final pulse = useMemoized(() => _LoadingPulse(intensity), [intensity]);
  // Never leave the app-wide ticker running on behalf of a disposed widget.
  useEffect(
    () =>
        () => pulse.breathing = false,
    [pulse],
  );

  // Calculate colors once
  // Only compute the HCT transforms when we actually animate
  final loadingColor = useMemoized<Color?>(() {
    if (!isLoading && !wasActive.value) return null;
    logRebuild(() => 'loadingColor');
    final colorHct = Hct.fromColor(baseColor);
    final destinationTone = colorHct.tone > 50.0
        ? colorHct.tone - toneDelta
        : colorHct.tone + toneDelta;
    return Hct.from(colorHct.hue, colorHct.chroma, destinationTone).color;
  }, [isLoading, wasActive.value, baseColor, toneDelta]);

  useEffect(
    // ignore: function-always-returns-null
    () {
      logRebuild(() => 'useEffect for animation');
      if (isLoading) {
        wasActive.value = true;
        pulse.breathing = true;
        intensity.forward();
      } else {
        // Fade out from wherever the breath is, then go idle. `then` (not
        // whenCompleteOrCancel): if loading restarts mid-fade, forward()
        // cancels this reverse and we must keep breathing.
        intensity.reverse().then((_) {
          pulse.breathing = false;
          wasActive.value = false;
        });
      }
      return null;
    },
    [isLoading],
  );

  // Memoize the getColor function to avoid recreating it on every build
  final getColor = useMemoized(
    () {
      logRebuild(
        () =>
            '$debugTag getColor callback. identity for dependencies: ${identityHashCode(pulse)}, ${identityHashCode(baseColor)}, ${identityHashCode(loadingColor)} (${loadingColor?.hex}) ${identityHashCode(isBackgroundWallpaper)}',
      );

      return () {
        // When idle, we avoid any heavy work and return a stable colour fast
        final value = pulse.value;
        if (!isLoading && !wasActive.value) {
          if (isBackgroundWallpaper) {
            return baseColor.withValues(alpha: 0.0);
          }
          return baseColor;
        }

        if (isBackgroundWallpaper) {
          final pulseOpacity = lerpDouble(0.0, 0.8, value)!;
          return baseColor.withValues(alpha: pulseOpacity * value);
        }

        final lc = loadingColor ?? baseColor;
        if (keepChroma) {
          final pulseColor = hctLerpCartesian(baseColor, lc, value);
          return pulseColor;
        } else {
          // Convert the value to an int from 0 to 100
          final valueAsInt = (value * 100).round();

          // Create a cache key: baseColor.argb_loadingColor.argb_valueAsInt
          final cacheKey = '${baseColor.argb}_${lc.argb}_$valueAsInt';

          // Check if the result is in the cache
          Color? cachedColor = _lerpKeepHueCache.getValue(cacheKey);

          if (cachedColor != null) {
            return cachedColor;
          }

          // If not in cache, calculate and store in cache
          final pulseColor = Hct.lerpKeepHue(baseColor, lc, value);
          _lerpKeepHueCache.putValue(cacheKey, pulseColor);

          return pulseColor;
        }
      };
    },
    [
      pulse,
      baseColor.argb,
      loadingColor?.argb,
      isLoading,
      isBackgroundWallpaper,
      keepChroma,
    ],
  );

  // If idle, still return a stable animation so callers can depend on it
  return AnimatedColorResult(getColor, pulse);
}
