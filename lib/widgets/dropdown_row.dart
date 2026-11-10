import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/widgets/icon_size.dart';
import 'package:monet_ui/widgets/monet_dropdown.dart';
import 'package:monet_ui/widgets/monet_handedness.dart';
import 'package:monet_ui/widgets/monet_icon.dart';
import 'package:monet_ui/widgets/monet_rich_text.dart';
import 'package:monet_ui/widgets/monet_tooltip.dart';
import 'package:monet_ui/widgets/monet_tooltip_icon.dart';
import 'package:monet_ui/widgets/padding.dart';
import 'package:monet_ui/widgets/screen_breakpoints.dart';
import 'package:pixel_snap_fork/material.dart';

class DropdownRow extends HookWidget {
  final MonetDropdown dropdown;
  final String tooltipMessage;
  final String label;
  final IconData? icon;
  final bool respectHand;
  final Widget? trailing;

  /// Always show label above dropdown, instead of to side if screen is wide enough.
  final bool forceSmall;

  const DropdownRow({
    super.key,
    required this.dropdown,
    required this.tooltipMessage,
    required this.label,
    this.icon,
    this.forceSmall = false,
    // LLM dropdown wants false - it always wants the label before the dropdown,
    // the right hand treatment. It was not clear at the time what dropdowns
    // required the inverse treatment, thus, the default is the existing
    // behavior, which respects handedness.
    this.respectHand = true,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final hand = MonetHandedness.of(context);

    final labelWidget = Row(
      mainAxisSize: .min,
      children: [
        if (icon != null)
          Padding(
            padding: .only(right: HorizontalPaddingHalf.amount),
            child: MonetIcon(
              icon,
              size: iconSizeForTextStyleOrNull(
                Theme.of(context).textTheme.labelMedium,
              ),
              color: MonetTheme.of(context).primary.fill,
            ),
          ),
        // MonetRichText centres the label's capitals on the icon
        // (centerCapHeight), not its line box.
        Flexible(
          child: MonetRichText(
            text: label,
            textStyle: Theme.of(context).textTheme.labelMedium!,
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          ),
        ),
      ],
    );
    final isSmall = forceSmall || ScreenBreakpoints.isScreenSmallWidth(context);
    if (isSmall) {
      // Ignore handedness, it feels weird for right handers if the label is
      // after the dropdown.
      return Column(
        crossAxisAlignment: .start,
        key: ValueKey(isSmall),
        children: [
          MonetTooltip(
            colors: MonetTheme.of(context).primary,
            content: Text(tooltipMessage),
            child: Row(
              mainAxisSize: .min,
              // Ignore handedness, it feels weird for right handers if the label is
              // after the dropdown.
              mainAxisAlignment: .start,
              children: [
                labelWidget,
                const HorizontalPadding(),
                const MonetTooltipIcon.fixed(),
              ],
            ),
          ),
          SizedBox(height: 1),
          if (trailing != null)
            Wrap(
              spacing: HorizontalPaddingHalf.amount,
              children: [dropdown, trailing!],
            )
          else
            dropdown,
        ],
      );
    }

    final useRight = hand == .right || !respectHand;
    final useLeft = hand == .left && respectHand;
    final coreRow = MonetTooltip(
      colors: MonetTheme.of(context).primary,
      content: Text(tooltipMessage),
      child: Row(
        mainAxisSize: .min,
        mainAxisAlignment: hand == .right ? .end : .start,
        children: [
          if (useRight) ...[
            labelWidget,
            const HorizontalPadding(),
            const MonetTooltipIcon.fixed(),
            const HorizontalPadding(),
          ],
          Flexible(child: dropdown),
          if (useLeft) ...[
            const HorizontalPadding(),
            labelWidget,
            const HorizontalPadding(),
            const MonetTooltipIcon.fixed(),
            const HorizontalPadding(),
          ],
        ],
      ),
    );

    return Row(
      children: [
        Flexible(child: coreRow),
        if (trailing != null) ...[
          const HorizontalPadding(),
          Align(alignment: Alignment.centerRight, child: trailing!),
        ],
      ],
    );
  }
}
