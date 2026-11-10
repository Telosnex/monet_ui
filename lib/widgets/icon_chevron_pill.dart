import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/widgets/animated_color_cycle_hook.dart';
import 'package:monet_ui/widgets/animated_color_hook.dart';
import 'package:monet_ui/widgets/expand_arrow.dart';
import 'package:monet_ui/widgets/icon_alignment_constants.dart';
import 'package:monet_ui/widgets/leading_overhang.dart';
import 'package:monet_ui/widgets/material_icon_ink.dart';
import 'package:monet_ui/widgets/monet_icon.dart';
import 'package:monet_ui/widgets/stateful_color_resolver.dart';
import 'package:monet_ui/widgets/tool_icon_size.dart';
import 'package:pixel_snap_fork/material.dart';

/// A pill-shaped widget containing an icon + expand chevron that share
/// hover/pressed state. Used for reasoning toggles.
///
/// The box starts at the ink of [icon], like a header's leading icon. The
/// hover background overhangs it by [kPillLeadingInset]. [IconLockPill] has
/// the same geometry.
class IconChevronPill extends HookWidget {
  const IconChevronPill({
    super.key,
    required this.icon,
    required this.animationHook,
    required this.isExpanded,
    required this.onPressed,
    this.iconSize,
  });

  final IconData icon;
  final AnimatedColorCycleResult animationHook;
  final bool isExpanded;
  final VoidCallback onPressed;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final statesController = useWidgetStatesController();
    final glyphSize = iconSize ?? toolHeaderIconSize(context);
    final backgroundSize = ExpandArrow.iconSize(context) - 2;
    final monetTheme = MonetTheme.of(context);
    final repaint = useMemoized(
      () => Listenable.merge([animationHook.animation, statesController]),
      [animationHook.animation, statesController],
    );

    bool isInteracting() {
      final states = statesController.value;
      return states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.pressed);
    }

    Color iconColor() {
      if (!isInteracting()) return animationHook.getColor();
      final safeColors = safeColorsFromColor(
        color: animationHook.getColor(),
        backgroundTone: monetTheme.backgroundTone,
        contrast: monetTheme.contrast,
      );
      return resolveBackgroundTextColor(safeColors, statesController.value);
    }

    Color backgroundColor() {
      if (!isInteracting()) return Colors.transparent;
      final safeColors = safeColorsFromColor(
        color: animationHook.getColor(),
        backgroundTone: monetTheme.backgroundTone,
        contrast: monetTheme.contrast,
      );
      return resolveBackgroundColor(safeColors, statesController.value);
    }

    final foreground = Padding(
      padding: const .only(left: kPillLeadingInset, right: 2),
      child: Row(
        mainAxisSize: .min,
        children: [
          MaterialIconInk.wrap(
            MonetIcon(
              icon,
              size: glyphSize,
              color: iconColor(),
              paintColorListenable: repaint,
              paintColor: iconColor,
            ),
          ),
          const SizedBox(width: kPillIconGap),
          ExpandArrow(
            isExpanded: isExpanded,
            colorAnimation: null,
            statesController: statesController,
            showBackground: false,
            handleGestures: false,
            paintIconColor: iconColor,
            paintListenable: repaint,
            onExpandPressed: onPressed,
          ),
        ],
      ),
    );

    return LeadingOverhang(
      overhang: kPillLeadingInset,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => statesController.update(.hovered, true),
        onExit: (_) => statesController.update(.hovered, false),
        child: GestureDetector(
          behavior: .opaque,
          onTapDown: (_) => statesController.update(.pressed, true),
          onTapUp: (_) => statesController.update(.pressed, false),
          onTapCancel: () => statesController.update(.pressed, false),
          onTap: onPressed,
          child: RepaintBoundary(
            child: PaintDrivenShapeFill(
              color: backgroundColor(),
              repaint: repaint,
              paintColor: backgroundColor,
              shape: RoundedRectangleBorder(
                borderRadius: .circular(backgroundSize / 2),
              ),
              child: SizedBox(
                height: backgroundSize,
                child: RepaintBoundary(child: foreground),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
