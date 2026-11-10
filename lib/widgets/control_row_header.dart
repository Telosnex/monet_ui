import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/palette.dart';
import 'package:monet_ui/util/color_deprecated.dart';
import 'package:monet_ui/widgets/icon_size.dart';
import 'package:monet_ui/widgets/monet_handedness.dart';
import 'package:monet_ui/widgets/monet_icon.dart';
import 'package:monet_ui/widgets/monet_rich_text.dart';
import 'package:monet_ui/widgets/monet_tooltip.dart';
import 'package:monet_ui/widgets/monet_tooltip_icon.dart';
import 'package:monet_ui/widgets/padding.dart';
import 'package:monet_ui/widgets/settings_row.dart';
import 'package:monet_ui/widgets/theme_selection.dart';
import 'package:pixel_snap_fork/material.dart';

/// A shared header widget for control rows.
///
/// Renders: [optional icon] [label (with optional width stabilization suffixes)] [gap] [tooltip icon]
/// Handles small/large layouts, handedness, optional label color, tooltip color, and width options.
class ControlRowHeader extends StatelessWidget {
  const ControlRowHeader({
    super.key,
    required this.label,
    required this.tooltip,
    required this.isSmall,
    this.hand = Hand.left,
    this.icon,
    this.colors,
    this.respectHandednessInSmall = true,
    this.suffixes,
    this.activeSuffixIndex,
    this.gap,
    this.includeGapOnlyInSmall = false,
    this.enableTooltip = true,
  });

  final String label;
  final String tooltip;
  final bool isSmall;
  final Hand hand;
  final IconData? icon;
  final Palette? colors;

  /// In small layouts, if true (default) align label/tooltip to start for left hand
  /// and end for right hand. If false, always align start.
  final bool respectHandednessInSmall;

  /// Optional suffixes appended to the label for width stabilization and
  /// active state visibility (e.g., [": On", ": Off"]).
  final List<String>? suffixes;

  /// Index into [suffixes] which is the visible/active one. Others are rendered
  /// transparently to stabilize width. Ignored if [suffixes] is null.
  final int? activeSuffixIndex;

  /// Gap widget between label area and tooltip icon. Defaults to HorizontalPadding().
  /// For compact cases, pass HorizontalPaddingHalf().
  final Widget? gap;

  /// If true, only include [gap] in small mode. If false (default), always include.
  final bool includeGapOnlyInSmall;

  /// If false, render the header without its own tooltip wrapper. Useful when
  /// a parent combines the header with adjacent content under one tooltip.
  final bool enableTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = MonetTheme.of(context);
    final textStyleBase = Theme.of(context).textTheme.labelMedium!;
    final labelStyle = colors != null
        ? textStyleBase.copyWith(color: colors!.backgroundText)
        : textStyleBase;
    final iconColor = (colors ?? theme.primary).fill;
    final tooltipColors = colors ?? theme.primary;

    final double? width = ((!isSmall)
        ? SettingsRow.labelWidth(MonetTheme.of(context))
        : null);

    final mainAxis = isSmall
        ? (respectHandednessInSmall
              ? (hand == .left
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.end)
              : MainAxisAlignment.start)
        : MainAxisAlignment.spaceBetween;

    final gapWidget = gap ?? const HorizontalPadding();
    final showGap = includeGapOnlyInSmall ? isSmall : true;

    Widget buildLabelContent() {
      // If suffixes provided, overlay all variants, show only the active one.
      if (suffixes != null && suffixes!.isNotEmpty) {
        final int activeIndex = activeSuffixIndex ?? 0;
        return Stack(
          children: [
            for (int i = 0; i < suffixes!.length; i++)
              MonetRichText(
                text: '$label${suffixes![i]}',
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: 1,
                textStyle: labelStyle.copyWith(
                  color: (i == activeIndex)
                      // ignore: avoid-passing-self-as-argument
                      ? labelStyle.color
                      : (labelStyle.color ?? textStyleBase.color)
                            ?.withOpacityNeue(0.0),
                ),
              ),
          ],
        );
      }
      // MonetRichText centres the label's capitals on the icons beside
      // it (centerCapHeight), not its line box. SelectionArea keeps it
      // selectable, as SelectableText was.
      return ThemeSelection(
        child: SelectionArea(
          child: MonetRichText(
            text: label,
            textStyle: labelStyle,
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          ),
        ),
      );
    }

    final labelRow = Row(
      mainAxisSize: .min,
      children: [
        if (icon != null)
          Padding(
            padding: .only(right: HorizontalPaddingHalf.amount),
            child: MonetIcon(
              icon,
              size: iconSizeForTextStyleOrNull(textStyleBase),
              color: iconColor,
            ),
          ),
        // Flexible avoids overflow in some integration test environments.
        Flexible(child: buildLabelContent()),
      ],
    );

    final header = SizedBox(
      width: width,
      child: Row(
        mainAxisSize: .min,
        mainAxisAlignment: mainAxis,
        crossAxisAlignment: .center,
        children: [
          Flexible(child: labelRow),
          if (showGap) gapWidget,
          MonetTooltipIcon.customColor(color: iconColor),
        ],
      ),
    );

    if (!enableTooltip) {
      return header;
    }

    return MonetTooltip(
      colors: tooltipColors,
      content: Text(tooltip),
      child: header,
    );
  }
}
