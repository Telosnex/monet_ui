import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';
import 'package:monet_ui/core/hex_codes.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/palette.dart';
import 'package:monet_ui/util/lru_cache.dart';
import 'package:monet_ui/util/use_animation_controller2.dart';
import 'package:monet_ui/widgets/animated_color_cycle_hook.dart';
import 'package:monet_ui/widgets/icon_size.dart';
import 'package:monet_ui/widgets/stateful_color_resolver.dart';
import 'package:monet_ui/widgets/chevron_icon.dart';

/// A reusable expand/collapse arrow animation component
/// Optimized to handle color animations efficiently without causing widget rebuilds
class ExpandArrow extends StatelessWidget {
  static const kAnimationDuration = Duration(milliseconds: 300);

  static double iconSize(BuildContext context) {
    return iconSizeForTextStyle(Theme.of(context).textTheme.labelLarge!)
        .roundToDouble();
  }

  /// The expand/collapse state
  final bool isExpanded;

  /// Callback when the expand button is pressed
  final VoidCallback onExpandPressed;

  /// Animated color source - preferred over static color
  /// When provided, the widget will listen to the animation internally
  final AnimatedColorCycleResult? colorAnimation;

  /// Optional external state controller for hover/pressed handling.
  final WidgetStatesController? statesController;

  /// Whether to render the circular background behind the chevron.
  final bool showBackground;

  /// Whether to handle mouse/gesture events internally.
  /// Set to false when the parent widget handles hover/pressed states.
  final bool handleGestures;

  /// Pre-resolved icon colour. When provided, the internal colour
  /// [AnimatedBuilder] is skipped entirely — the parent is responsible
  /// for rebuilding when the colour changes.
  final Color? resolvedIconColor;

  /// Pre-resolved background colour (only used when [showBackground] is true).
  final Color? resolvedBackgroundColor;

  /// When true, the chevron inherits its foreground color from [IconTheme]
  /// instead of resolving/receiving one directly.
  final bool useInheritedIconColor;

  /// Optional paint-time icon color. With [paintListenable], color/state ticks
  /// repaint the chevron without rebuilding this widget subtree.
  final Color Function()? paintIconColor;
  final Listenable? paintListenable;

  const ExpandArrow({
    super.key,
    required this.colorAnimation,
    required this.isExpanded,
    required this.onExpandPressed,
    this.statesController,
    this.showBackground = true,
    this.handleGestures = true,
    this.resolvedIconColor,
    this.resolvedBackgroundColor,
    this.useInheritedIconColor = false,
    this.paintIconColor,
    this.paintListenable,
  }) : assert(
         (paintIconColor == null) == (paintListenable == null),
         'paintIconColor and paintListenable must be supplied together.',
       );

  @override
  Widget build(BuildContext context) {
    if (statesController != null || !handleGestures) {
      return _ExpandArrowWithStates(
        isExpanded: isExpanded,
        onExpandPressed: onExpandPressed,
        colorAnimation: colorAnimation,
        statesController: statesController,
        showBackground: showBackground,
        handleGestures: handleGestures,
        resolvedIconColor: resolvedIconColor,
        resolvedBackgroundColor: resolvedBackgroundColor,
        useInheritedIconColor: useInheritedIconColor,
        paintIconColor: paintIconColor,
        paintListenable: paintListenable,
      );
    }

    return _ExpandArrowWithInternalStates(
      isExpanded: isExpanded,
      onExpandPressed: onExpandPressed,
      colorAnimation: colorAnimation,
      showBackground: showBackground,
      resolvedIconColor: resolvedIconColor,
      resolvedBackgroundColor: resolvedBackgroundColor,
      useInheritedIconColor: useInheritedIconColor,
      paintIconColor: paintIconColor,
      paintListenable: paintListenable,
    );
  }
}

// ignore: prefer-single-widget-per-file
class _ExpandArrowWithInternalStates extends HookWidget {
  final bool isExpanded;
  final VoidCallback onExpandPressed;
  final AnimatedColorCycleResult? colorAnimation;
  final bool showBackground;
  final Color? resolvedIconColor;
  final Color? resolvedBackgroundColor;
  final bool useInheritedIconColor;
  final Color Function()? paintIconColor;
  final Listenable? paintListenable;

  const _ExpandArrowWithInternalStates({
    required this.isExpanded,
    required this.onExpandPressed,
    required this.colorAnimation,
    required this.showBackground,
    this.resolvedIconColor,
    this.resolvedBackgroundColor,
    required this.useInheritedIconColor,
    this.paintIconColor,
    this.paintListenable,
  });

  @override
  Widget build(BuildContext context) {
    return _ExpandArrowWithStates(
      isExpanded: isExpanded,
      onExpandPressed: onExpandPressed,
      colorAnimation: colorAnimation,
      statesController: useWidgetStatesController(),
      showBackground: showBackground,
      handleGestures: true,
      resolvedIconColor: resolvedIconColor,
      resolvedBackgroundColor: resolvedBackgroundColor,
      useInheritedIconColor: useInheritedIconColor,
      paintIconColor: paintIconColor,
      paintListenable: paintListenable,
    );
  }
}

// ignore: prefer-single-widget-per-file
class _ExpandArrowWithStates extends HookWidget {
  final bool isExpanded;
  final VoidCallback onExpandPressed;
  final AnimatedColorCycleResult? colorAnimation;
  final WidgetStatesController? statesController;
  final bool showBackground;
  final bool handleGestures;
  final Color? resolvedIconColor;
  final Color? resolvedBackgroundColor;
  final bool useInheritedIconColor;
  final Color Function()? paintIconColor;
  final Listenable? paintListenable;

  const _ExpandArrowWithStates({
    required this.isExpanded,
    required this.onExpandPressed,
    required this.colorAnimation,
    required this.statesController,
    required this.showBackground,
    required this.handleGestures,
    this.resolvedIconColor,
    this.resolvedBackgroundColor,
    required this.useInheritedIconColor,
    this.paintIconColor,
    this.paintListenable,
  });

  @override
  Widget build(BuildContext context) {
    final controller = useAnimationController2(
      duration: ExpandArrow.kAnimationDuration,
      initialValue: isExpanded ? 1.0 : 0.0,
    );

    // ignore: function-always-returns-null
    useEffect(() {
      if (isExpanded) {
        controller.forward();
      } else {
        controller.reverse();
      }
      return null;
    }, [isExpanded, controller]);

    return _ExpandArrowRender(
      rotationController: controller,
      statesController: statesController,
      colorAnimation: colorAnimation,
      onExpandPressed: onExpandPressed,
      showBackground: showBackground,
      handleGestures: handleGestures,
      resolvedIconColor: resolvedIconColor,
      resolvedBackgroundColor: resolvedBackgroundColor,
      useInheritedIconColor: useInheritedIconColor,
      paintIconColor: paintIconColor,
      paintListenable: paintListenable,
    );
  }
}

/// Handles rendering and animation listening
// ignore: prefer-single-widget-per-file
class _ExpandArrowRender extends HookWidget {
  final Animation<double> rotationController;
  final WidgetStatesController? statesController;
  final AnimatedColorCycleResult? colorAnimation;
  final VoidCallback onExpandPressed;
  final bool showBackground;
  final bool handleGestures;
  final Color? resolvedIconColor;
  final Color? resolvedBackgroundColor;
  final bool useInheritedIconColor;
  final Color Function()? paintIconColor;
  final Listenable? paintListenable;

  const _ExpandArrowRender({
    required this.rotationController,
    required this.statesController,
    required this.onExpandPressed,
    required this.colorAnimation,
    required this.showBackground,
    required this.handleGestures,
    this.resolvedIconColor,
    this.resolvedBackgroundColor,
    required this.useInheritedIconColor,
    this.paintIconColor,
    this.paintListenable,
  });

  @override
  Widget build(BuildContext context) {
    // Cache the driven animation - this avoids creating a new
    // Animation wrapper on every build.
    final turnsAnimation = useMemoized(
      () => rotationController.drive(_kHalfTurnTween),
      [rotationController],
    );

    final theme = MonetTheme.of(context);
    final iconSize = ExpandArrow.iconSize(context);

    final paintGetter = paintIconColor;
    if (paintGetter != null) {
      final visual = _ExpandArrowVisual(
        rotationAnimation: turnsAnimation,
        iconSize: iconSize,
        iconColor: null,
        iconColorGetter: paintGetter,
        iconRepaint: paintListenable,
        backgroundColor: resolvedBackgroundColor ?? Colors.transparent,
        showBackground: showBackground,
      );
      if (!handleGestures) return visual;
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => statesController?.update(.hovered, true),
        onExit: (_) => statesController?.update(.hovered, false),
        child: GestureDetector(
          onTapDown: (_) => statesController?.update(.pressed, true),
          onTapUp: (_) => statesController?.update(.pressed, false),
          onTapCancel: () => statesController?.update(.pressed, false),
          onTap: onExpandPressed,
          child: visual,
        ),
      );
    }

    if (useInheritedIconColor) {
      assert(
        !showBackground,
        'useInheritedIconColor is only supported when showBackground is false.',
      );
      final visual = _ExpandArrowVisual(
        rotationAnimation: turnsAnimation,
        iconSize: iconSize,
        iconColor: null,
        backgroundColor: Colors.transparent,
        showBackground: false,
      );
      if (!handleGestures) return visual;
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => statesController?.update(.hovered, true),
        onExit: (_) => statesController?.update(.hovered, false),
        child: GestureDetector(
          onTapDown: (_) => statesController?.update(.pressed, true),
          onTapUp: (_) => statesController?.update(.pressed, false),
          onTapCancel: () => statesController?.update(.pressed, false),
          onTap: onExpandPressed,
          child: visual,
        ),
      );
    }

    // When colours are pre-resolved by the parent, skip the internal
    // AnimatedBuilder entirely — avoids duplicate colour computation.
    if (resolvedIconColor != null) {
      final visual = _ExpandArrowVisual(
        rotationAnimation: turnsAnimation,
        iconSize: iconSize,
        iconColor: resolvedIconColor!,
        backgroundColor: resolvedBackgroundColor ?? Colors.transparent,
        showBackground: showBackground,
      );
      if (!handleGestures) return visual;
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => statesController?.update(.hovered, true),
        onExit: (_) => statesController?.update(.hovered, false),
        child: GestureDetector(
          onTapDown: (_) => statesController?.update(.pressed, true),
          onTapUp: (_) => statesController?.update(.pressed, false),
          onTapCancel: () => statesController?.update(.pressed, false),
          onTap: onExpandPressed,
          child: visual,
        ),
      );
    }

    Widget buildAnimatedContent() {
      final colorAnim = colorAnimation;
      final fallbackFill = theme.monetThemeData.primary.fill;

      // While idle, the chevron should simply *be* the animated colour so
      // it matches the header label/accessories (which paint with
      // [colorAnimation.getColor()] directly). Colour ticks flow straight to
      // the chevron's painter (ChevronIcon.animated) — zero widget rebuilds
      // per tick; the pulse repaints only the chevron's own tiny layer.
      Widget idleVisual() => _ExpandArrowVisual(
        rotationAnimation: turnsAnimation,
        iconSize: iconSize,
        iconColor: colorAnim == null ? fallbackFill : null,
        iconColorGetter: colorAnim?.getColor,
        iconRepaint: colorAnim?.animation,
        backgroundColor: Colors.transparent,
        showBackground: showBackground,
      );

      final states = statesController;
      if (states == null) {
        return idleVisual();
      }

      // Rotation is handled internally by RotationTransition which is much
      // more efficient - it doesn't rebuild the widget tree. Only hover/press
      // state changes rebuild here (rare, and only for the row under the
      // pointer); the colour pulse never does.
      return AnimatedBuilder(
        animation: states,
        builder: (context, _) {
          final bool isInteracting =
              states.value.contains(WidgetState.hovered) ||
              states.value.contains(WidgetState.pressed);

          // The palette-derived background-text colour is only needed so the
          // chevron stays readable on top of the hover/press background fill
          // (which is transparent otherwise). Deriving it while idle made the
          // chevron flip between near-black and near-white as the source
          // colour cycled — looked broken and never matched the text.
          if (!showBackground || !isInteracting) {
            return idleVisual();
          }

          // Interacting: the hover/press fill and its readable text colour
          // are derived from the current animated colour, so this (single)
          // row rebuilds per colour tick while the pointer is over it.
          return AnimatedBuilder(
            animation: Listenable.merge([?colorAnim?.animation]),
            builder: (context, _) {
              final Palette safeColors = _getCachedSafeColors(
                colorAnim?.getColor() ?? fallbackFill,
                theme.backgroundTone,
                theme.contrast,
              );

              return _ExpandArrowVisual(
                rotationAnimation: turnsAnimation,
                iconSize: iconSize,
                iconColor: resolveBackgroundTextColor(safeColors, states.value),
                backgroundColor: resolveBackgroundColor(
                  safeColors,
                  states.value,
                ),
                showBackground: true,
              );
            },
          );
        },
      );
    }

    final content = buildAnimatedContent();

    if (!handleGestures) {
      return content;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => statesController?.update(.hovered, true),
      onExit: (_) => statesController?.update(.hovered, false),
      child: GestureDetector(
        onTapDown: (_) => statesController?.update(.pressed, true),
        onTapUp: (_) => statesController?.update(.pressed, false),
        onTapCancel: () => statesController?.update(.pressed, false),
        onTap: onExpandPressed,
        child: content,
      ),
    );
  }
}

/// Tween for 180° rotation (0.5 turns). Defined at top-level to avoid
/// allocating a new Tween on every build.
final Tween<double> _kHalfTurnTween = Tween(begin: 0.0, end: 0.5);

/// Ultra-lightweight visual component using RotationTransition
///
/// Uses RotationTransition for the rotation animation which is much more
/// efficient than Transform.rotate - it applies the transform at the render
/// layer without rebuilding the child widget tree.
// ignore: prefer-single-widget-per-file
class _ExpandArrowVisual extends StatelessWidget {
  const _ExpandArrowVisual({
    // ignore: unused_element_parameter
    super.key,
    required this.rotationAnimation,
    required this.iconSize,
    required this.iconColor,
    this.iconColorGetter,
    this.iconRepaint,
    required this.backgroundColor,
    required this.showBackground,
  });

  /// Animation for rotation - passed directly to RotationTransition
  final Animation<double> rotationAnimation;
  final double iconSize;
  final Color? iconColor;

  /// Paint-time colour source. When provided (with [iconRepaint]), colour
  /// animation ticks repaint the chevron directly without widget rebuilds.
  final Color Function()? iconColorGetter;
  final Listenable? iconRepaint;

  final Color backgroundColor;
  final bool showBackground;

  Widget _chevron() {
    final getter = iconColorGetter;
    if (getter != null) {
      return ChevronIcon.animated(
        size: iconSize,
        colorGetter: getter,
        repaint: iconRepaint!,
      );
    }
    return ChevronIcon(size: iconSize, color: iconColor);
  }

  @override
  Widget build(BuildContext context) {
    if (!showBackground) {
      return RotationTransition(turns: rotationAnimation, child: _chevron());
    }

    // SizedBox + DecoratedBox is lighter than Container.
    return SizedBox(
      height: iconSize - 2,
      width: iconSize - 2,
      child: DecoratedBox(
        decoration: BoxDecoration(color: backgroundColor, shape: .circle),
        child: Center(
          // RotationTransition is optimized for animated rotations -
          // it applies the transform at the render layer without
          // rebuilding the Icon child on every frame.
          child: RotationTransition(
            // rotationAnimation is already driven with _kHalfTurnTween
            // (0.0 -> 0.5 turns = 180° rotation)
            turns: rotationAnimation,
            child: _chevron(),
          ),
        ),
      ),
    );
  }
}

// Cache for Palette to avoid recomputing
final LruCache<String, Palette> _safeColorsCache = LruCache(capacity: 1000);

Palette _getCachedSafeColors(Color c, double bgTone, double ctr) {
  final String key =
      '${c.argb.toString()}:${bgTone.round()}:${(ctr * 100).round()}';
  final existing = _safeColorsCache[key];
  if (existing != null) {
    return existing;
  }

  final generated = Palette.from(
    c,
    backgroundTone: bgTone.toDouble(),
    contrast: ctr,
  );
  _safeColorsCache[key] = generated;
  return generated;
}
