/// Flux: Spring animations with velocity handoff.
///
/// Ported from Fuchsia's Mondrian story shell animation system.
/// Original: topaz/shell/mondrian_story_shell/lib/anim/
///
/// The core idea: animations carry velocity. When you transition from one
/// animation to another (drag → spring, spring → spring), the new animation
/// picks up from the old one's velocity. No jerk.
///
/// ## Quick start
///
/// ```dart
/// // In a HookWidget:
/// final anim = useFluxSpring(
///   start: isExpanded ? 0.0 : 1.0,
///   end: isExpanded ? 1.0 : 0.0,
/// );
/// ```
///
/// ## For implicit animations (AnimatedContainer, etc.):
///
/// ```dart
/// AnimatedContainer(
///   duration: const Duration(milliseconds: 400),
///   curve: FluxCurve(spring: FluxSpring.snappy),
///   // ...
/// )
/// ```
///
/// ## For drag-to-spring:
///
/// ```dart
/// final drag = useFluxManual<double>(
///   initialValue: 0.0,
///   initialVelocity: 0.0,
///   builder: (value, velocity) => SimAnimationController(
///     vsync: this,
///     sim: springSimDouble(start: value, end: 0.0, velocity: velocity),
///   )..start(),
/// );
/// ```
library;

export 'flux_animation.dart';
export 'flux_curve.dart';
export 'hooks.dart';
export 'rk4_spring.dart';
export 'sim.dart';
export 'spring.dart';
export 'spring_frame_clock.dart';
