import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';
import 'package:monet_ui/flux/flux.dart';
import 'package:monet_ui/util/use_animation_controller2.dart';
import 'package:monet_ui/widgets/monet_expansion_animations.dart';

/// A light-weight expandable that animates both in **and** out.
/// The entrance animation fades the content in, and the content top is a little
/// bit above the header bottom at its peak.
/// The exit animation fades the content out, the net effect of the animations
/// is it looks like the content is shrinking down and going "behind" the
/// header as it fades.
class AnimatedExpandable extends HookWidget {
  const AnimatedExpandable({
    super.key,
    required this.persistentChild,
    required this.expandedChild,
    required this.isExpanded,
    this.duration = kThemeAnimationDuration,
  });

  /// Child that is always visible.
  final Widget persistentChild;

  /// Child that is shown / hidden when [isExpanded] changes.
  final Widget expandedChild;

  /// Whether the panel is currently expanded.
  final bool isExpanded;

  /// Duration of the expand / collapse animation.
  ///
  /// When [curve] is a [FluxCurve] (the default), this is ignored — the
  /// spring's natural settle time is used instead. Pass an explicit [duration]
  /// with a non-FluxCurve [curve] to override.
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final curve = useMemoized(
      () => FluxCurve(
        spring: FluxSpring.gentle,
        debugLabel: 'AnimatedExpandable',
      ),
      const [],
    );

    // When the curve is a FluxCurve, use the spring's natural settle time
    // as the animation duration. Otherwise the spring shape gets crammed
    // into an arbitrary duration and the overshoot is invisible.
    final duration = curve.duration;

    final animationController = useAnimationController2(
      duration: duration,
      initialValue: isExpanded ? 1.0 : 0.0,
    );

    // Status notifications rebuild only at animation boundaries, not per tick.
    final status = useState(animationController.status);
    useEffect(() {
      void onStatus(AnimationStatus value) => status.value = value;
      animationController.addStatusListener(onStatus);
      return () => animationController.removeStatusListener(onStatus);
    }, [animationController]);

    final expansionScroll = MonetExpansionAnimations.maybeOf(context);
    useEffect(() {
      expansionScroll?.registerAnimation(animationController);
      return () => expansionScroll?.unregisterAnimation(animationController);
    }, [expansionScroll, animationController]);

    // Drive the controller whenever [isExpanded] changes.
    // ignore: function-always-returns-null
    useEffect(() {
      if (isExpanded) {
        animationController.forward();
      } else {
        animationController.reverse();
      }
      return null;
    }, [isExpanded]);

    final animation = useMemoized(
      () => CurvedAnimation(parent: animationController, curve: curve),
      [animationController, curve],
    );

    useEffect(() {
      return animation.dispose;
    }, [animation]);

    // Keep the child in the tree while the controller is animating so that the
    // collapse animation is visible. Once the animation completes and the
    // panel is fully collapsed, remove it to save work during scrolling.
    final shouldBuildExpandedChild =
        isExpanded || animationController.isAnimating;

    // Reuse the old AnimatedSwitcher transitions: fade & slide/scale + size.
    // The new logic still drops the child when collapsed, but animates both
    // directions just as before.

    return Column(
      mainAxisSize: .min,
      // ignore: telosnex_lints/telosnex_avoid_cross_axis_stretch
      crossAxisAlignment: .stretch,
      children: [
        RepaintBoundary(child: persistentChild),
        SizeTransition(
          sizeFactor: animation,
          alignment: AlignmentDirectional.topStart,
          child: FadeTransition(
            opacity: animation,
            child: shouldBuildExpandedChild
                ? RepaintBoundary(child: expandedChild)
                : null,
          ),
        ),
      ],
    );
  }
}
