import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/widgets/animated_color_cycle_hook.dart';
import 'package:monet_ui/widgets/icon_alignment_constants.dart';
import 'package:monet_ui/widgets/leading_overhang.dart';
import 'package:monet_ui/widgets/monet_icons.dart';
import 'package:monet_ui/widgets/monet_tooltip.dart';
import 'package:monet_ui/widgets/tool_icon_size.dart';
import 'package:pixel_snap_fork/material.dart';
import 'package:monet_ui/widgets/expand_arrow.dart';
import 'package:monet_ui/widgets/material_icon_ink.dart';
import 'package:monet_ui/widgets/monet_icon.dart';

/// A pill-shaped widget containing an icon + lock icon.
///
/// Used for redacted reasoning indicators where expansion is not available.
/// Mirrors the visual appearance of [IconChevronPill] at rest, but deliberately
/// does not expose hover, splash, or tap affordances. A tooltip is allowed for
/// discoverability, but the pill itself should not visually react to hover/tap.
///
/// It has the geometry of [IconChevronPill], so swapping one for the other
/// moves nothing: the box starts at the ink of [icon].
class IconLockPill extends StatelessWidget {
  const IconLockPill({
    super.key,
    required this.icon,
    required this.animationHook,
    required this.tooltipMessage,
  });

  final IconData icon;
  final AnimatedColorCycleResult animationHook;
  final String tooltipMessage;

  @override
  Widget build(BuildContext context) {
    final iconSize = toolHeaderIconSize(context);
    final backgroundSize = ExpandArrow.iconSize(context) - 2;

    // This pill never reacts to hover/press (no background fill), so paint
    // the icons with the raw animated colour to match the header label and
    // accessories. Deriving a palette contrast colour here made the icons
    // flip black<->white as the source colour cycled. The icons are
    // MonetIcons, as IconChevronPill's are, so they keep one fitted shape
    // whether or not the colour animates, and a tick repaints them only.
    final animation = animationHook.animation;
    final repaint = animation is AlwaysStoppedAnimation<double>
        ? null
        : animation;
    MonetIcon glyph(IconData data) => .new(
      data,
      size: iconSize,
      color: animationHook.getColor(),
      paintColorListenable: repaint,
      paintColor: repaint == null ? null : animationHook.getColor,
    );
    return MonetTooltip(
      colors: MonetTheme.of(context).primary,
      content: Text(tooltipMessage),
      child: MouseRegion(
        cursor: SystemMouseCursors.basic,
        child: LeadingOverhang(
          overhang: kPillLeadingInset,
          child: SizedBox(
            height: backgroundSize,
            child: Padding(
              padding: const .only(left: kPillLeadingInset, right: 2),
              child: Row(
                mainAxisSize: .min,
                children: [
                  MaterialIconInk.wrap(glyph(icon)),
                  const SizedBox(width: kPillIconGap),
                  glyph(MonetIcons.lock),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
