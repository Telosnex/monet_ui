import 'dart:ui' show lerpDouble;

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:monet_ui/colorspaces/cam16V11/cam16_v11.dart';
import 'package:monet_ui/colorspaces/hct.dart';
import 'package:monet_ui/core/hex_codes.dart';
import 'package:pixel_snap_fork/material.dart';

import 'package:monet_ui/util/use_animation_controller2.dart';
import 'package:monet_ui/widgets/hct_color_tween.dart';
import 'package:monet_ui/widgets/hct_lerp_cartesian.dart';

class AnimatedColorCycleResult {
  final Color Function() getColor;
  final Animation<double> animation;

  const AnimatedColorCycleResult(this.getColor, this.animation);
}

AnimatedColorCycleResult useAnimatedColorCycle({
  required List<Color> colors,
  required bool isLoading,
  Duration cycleDuration = const Duration(milliseconds: 4000),
  bool keepChroma = true,
  Color? finalColor,
}) {
  final wasActive = useRef(false);
  final isStopping = useRef(false);

  // The stopping transition is prepared synchronously when loading ends.
  // Keeping the converted endpoints here avoids both a one-frame jump back to
  // the cycle's first color and repeated HCT/CAM16 conversions while ticking.
  final stopStartHct = useRef<Hct?>(null);
  final stopEndHct = useRef<Hct?>(null);
  final stopStartCam = useRef<Cam16V11?>(null);
  final stopEndCam = useRef<Cam16V11?>(null);
  final stopEndColor = useRef<Color?>(null);

  void clearStopTransition() {
    stopStartHct.value = null;
    stopEndHct.value = null;
    stopStartCam.value = null;
    stopEndCam.value = null;
    stopEndColor.value = null;
  }

  final shouldAnimate = isLoading || wasActive.value || isStopping.value;

  // Keep a single controller managed by flutter_hooks. A stopped controller is "free".
  final controller = useAnimationController2(duration: cycleDuration);

  final cycleAnimation = useMemoized<Animation<double>>(() {
    if (!shouldAnimate) {
      return const AlwaysStoppedAnimation(1.0);
    }
    return CurvedAnimation(parent: controller, curve: Curves.easeInOut);
  }, [controller, shouldAnimate]);

  useEffect(() {
    return () {
      final animation = cycleAnimation;
      if (animation is CurvedAnimation) {
        animation.dispose();
      }
    };
  }, [cycleAnimation]);
  // --------------------------------------------------------------------------
  // Handle lifecycle of the animation.
  // --------------------------------------------------------------------------
  // We start the endless cycle when [isLoading] becomes true and perform a
  // single, graceful transition back to the first (or [finalColor]) color when
  // it becomes false. Critically, we must not kick-off that transition if the
  // hook was never active in the first place (i.e. [wasActive] is still
  // false). We also need to be sure that housekeeping flags are always reset –
  // even when no exception is thrown – otherwise `getColor` may think we are
  // still in the “stopping” phase and will keep returning the last animated
  // color.
  //
  // rationale: useAnimationController will dispose.
  useEffect(
    // ignore: function-always-returns-null
    () {
      // ----------------------------------------------------------------------
      // Start / restart the infinite colour cycle.
      // ----------------------------------------------------------------------
      if (isLoading) {
        wasActive.value = true;
        isStopping.value = false;
        clearStopTransition();
        controller.repeat();
        return null;
      }

      // ----------------------------------------------------------------------
      // If we were never active there is nothing to animate back from.
      // ----------------------------------------------------------------------
      if (!wasActive.value) {
        return null;
      }

      // ----------------------------------------------------------------------
      // Initiate the graceful transition back to the first / final colour.
      // ----------------------------------------------------------------------
      if (!isStopping.value) {
        isStopping.value = true;

        // Capture the colour currently being displayed so that we can blend
        // back to the resting colour.
        final position = controller.value * colors.length;
        final currentIndex = position.floor() % colors.length;
        final nextIndex = (currentIndex + 1) % colors.length;
        final progress = position - position.floor();

        final currentColor = colors[currentIndex];
        final nextColor = colors[nextIndex];
        final startColor = keepChroma
            ? hctLerpCartesian(currentColor, nextColor, progress)
            : Hct.lerpKeepHue(currentColor, nextColor, progress);
        final endColor = finalColor ?? colors.first;
        final startHct = Hct.fromInt(startColor.argb);
        final endHct = Hct.fromInt(endColor.argb);

        stopStartHct.value = startHct;
        stopEndHct.value = endHct;
        stopEndColor.value = endColor;
        if (keepChroma) {
          stopStartCam.value = Cam16V11.fromInt(startColor.argb);
          stopEndCam.value = Cam16V11.fromInt(endColor.argb);
        }

        // Stop the repeating cycle and drive a one-off animation from 0 ➜ 1.
        controller.stop();
        controller.value = 0;

        controller
            .animateTo(
              1.0,
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeOutCubic,
            )
            .whenComplete(() {
              // Mark the transition finished *before* resetting the controller.
              // reset() notifies animation listeners synchronously; if the
              // stopping state is still active, that notification exposes the
              // captured start color instead of the documented resting color.
              isStopping.value = false;
              wasActive.value = false;
              clearStopTransition();

              // The controller might have been disposed in tests. Guard and
              // swallow that specific error.
              try {
                controller.reset();
              } catch (e) {
                if (!e.toString().contains(
                  'AnimationController.stop() called after AnimationController.dispose()',
                )) {
                  rethrow;
                }
              }
            });
      }
      return null;
    },
    [
      controller,
      isLoading,
      finalColor?.argb,
      ...colors.map((e) => e.argb),
      keepChroma,
    ],
  );

  // ------------------------------------------------------------------------
  // Build a list of tweens once, in order, so colour lookup becomes O(1)
  // instead of the O(N) walk performed by `TweenSequence.evaluate`.
  // ------------------------------------------------------------------------
  final tweenCache = useMemoized(
    () {
      if (!shouldAnimate || colors.isEmpty) {
        return const <HctColorTween>[];
      }
      final list = <HctColorTween>[];
      for (var i = 0; i < colors.length; i++) {
        final next = (i + 1) % colors.length;
        list.add(
          HctColorTween(
            begin: colors[i],
            end: colors[next],
            keepChroma: keepChroma,
          ),
        );
      }
      return list;
    },
    [
      shouldAnimate,
      if (colors.isNotEmpty) ...colors.map((c) => c.argb),
      keepChroma,
    ],
  );

  // Memoize the getColor function. Only inexpensive operations inside.
  final getColor = useCallback(
    () {
      // Resting states -------------------------------------------------------
      if (colors.isEmpty) {
        // If we are not animating and have no final color, signal invalid input.
        if (!isLoading && !wasActive.value && finalColor == null) {
          throw StateError('No colors provided and no final color specified.');
        }
        // While animating (or stopping), return a neutral color gracefully.
        if (finalColor != null && !isLoading && !wasActive.value) {
          return finalColor;
        }
        return const Color(0xFF000000);
      }
      if (!isLoading && !wasActive.value) return finalColor ?? colors.first;
      if (!isLoading && !isStopping.value) return finalColor ?? colors.first;

      // Stopping transition --------------------------------------------------
      if (isStopping.value && stopStartHct.value != null) {
        final t = controller.value;

        // HCT/CAM16 round trips are not guaranteed to reproduce the endpoint
        // bit-for-bit (and the hue-locked path cannot represent a differently
        // hued endpoint). Return the documented resting color exactly when the
        // transition finishes.
        if (t >= 1) return stopEndColor.value!;

        final start = stopStartHct.value!;
        final end = stopEndHct.value!;
        if (keepChroma) {
          // Interpolate in Cartesian CAM16-UCS space using endpoints converted
          // once when the stopping transition began.
          final camA = stopStartCam.value!;
          final camB = stopEndCam.value!;
          final aStar = lerpDouble(camA.astar, camB.astar, t)!;
          final bStar = lerpDouble(camA.bstar, camB.bstar, t)!;
          final jStar = lerpDouble(camA.jstar, camB.jstar, t)!;
          final tone = lerpDouble(start.tone, end.tone, t)!;
          final cam = Cam16V11.fromUcs(jStar, aStar, bStar);
          return Hct.from(cam.hue, cam.chroma, tone).color;
        } else {
          final chroma = lerpDouble(start.chroma, end.chroma, t)!;
          final tone = lerpDouble(start.tone, end.tone, t)!;
          return Hct.from(start.hue, chroma, tone).color;
        }
      }

      // Regular looping cycle -----------------------------------------------
      // Compute index directly instead of using TweenSequence.evaluate.
      final position = controller.value * colors.length;
      final index = tweenCache.isEmpty
          ? 0
          : position.floor() % tweenCache.length;
      final frac = position - index;
      if (tweenCache.isEmpty) {
        return colors.first;
      }
      return tweenCache[index].lerp(frac)!;
    },
    [
      controller,
      colors.length,
      if (colors.isNotEmpty) ...colors.map((c) => c.argb),
      isLoading,
      keepChroma,
      finalColor?.argb,
      tweenCache,
      isStopping.value,
    ],
  );
  return AnimatedColorCycleResult(getColor, cycleAnimation);
}

AnimatedColorCycleResult useStaticAnimatedColorCycle({required Color color}) {
  return AnimatedColorCycleResult(
    () => color,
    const AlwaysStoppedAnimation(1.0),
  );
}
