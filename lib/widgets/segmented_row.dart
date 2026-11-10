import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/palette.dart';
import 'package:monet_ui/third_party/flutter/single_child_scroll_view_2.dart';
import 'package:monet_ui/widgets/icon_size.dart';
import 'package:monet_ui/widgets/monet_handedness.dart';
import 'package:monet_ui/widgets/monet_icon.dart';
import 'package:monet_ui/widgets/monet_mono_text_style.dart';
import 'package:monet_ui/widgets/monet_scrollbar.dart';
import 'package:monet_ui/widgets/monet_segmented.dart';
import 'package:monet_ui/widgets/monet_tooltip.dart';
import 'package:monet_ui/widgets/monet_tooltip_icon.dart';
import 'package:monet_ui/widgets/padding.dart';
import 'package:monet_ui/widgets/screen_breakpoints.dart';
import 'package:monet_ui/widgets/scroll_edge_fade.dart';
import 'package:monet_ui/widgets/trackpad_dismiss_gesture_detector.dart';
import 'package:pixel_snap_fork/material.dart';

/// A settings-style row that looks like SliderRow but hosts a MonetSegmented
/// control instead of a slider.
///
/// Behavior:
/// - On wide layouts (non-small), the label and segmented control share a row
///   and respect handedness (control appears to the left or right of the label).
/// - On small layouts (or when [forceSmallWidth] is true), the label appears
///   on the first line and the segmented control appears underneath.
class SegmentedRow<T> extends HookWidget {
  final String label;
  final String labelValue;
  final String tooltip;
  final List<MonetSegment<T>> options;
  final T selectedValue;
  final ValueChanged<T> onChanged;
  final EdgeInsetsGeometry padding;

  /// Optional icon to show next to the label (matches SliderRow label style).
  final IconData? icon;

  /// Force the compact layout even on wide screens.
  final bool forceSmallWidth;

  /// Pass through to MonetSegmented to adjust text/icon sizing inside segments.
  final bool? isSmallOverride;

  /// Optional colors for MonetSegmented. If null, uses the current theme.
  final Palette? colors;

  const SegmentedRow({
    super.key,
    required this.label,
    this.labelValue = '',
    required this.tooltip,
    required this.options,
    required this.selectedValue,
    required this.onChanged,
    this.colors,
    this.forceSmallWidth = false,
    this.icon,
    this.isSmallOverride,
    this.padding = EdgeInsets.zero,
  });

  bool _isSmall(BuildContext context) {
    if (forceSmallWidth) return true;
    return ScreenBreakpoints.isScreenSmallWidth(context);
  }

  @override
  Widget build(BuildContext context) {
    final isSmall = _isSmall(context);
    final hand = MonetHandedness.inclWideOf(context);
    final labelWidget = _SegmentedRowLabel(
      tooltip: tooltip,
      isSmall: isSmall,
      icon: icon,
      label: label,
      labelValue: labelValue,
    );

    final segmented = MonetSegmented(
      options: options,
      selectedValue: selectedValue,
      onChanged: onChanged,
      isSmall: isSmallOverride ?? isSmall,
      colors: colors,
    );

    if (isSmall) {
      // Small layout: label on first line, control beneath.
      return Column(
        children: [
          Padding(
            padding: padding,
            child: Row(children: [labelWidget]),
          ),
          const SizedBox(height: 1),
          Align(
            alignment: hand == .left
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: ScrollEdgeFade.builder(
              builder: (_, scrollController) => MonetScrollbar(
                child: HorizontalGesturePriority(
                  child: SingleChildScrollView2(
                    controller: scrollController,
                    clipBehavior: .none,
                    scrollDirection: .horizontal,
                    child: Padding(
                      padding: .symmetric(horizontal: HorizontalPadding.amount),
                      child: segmented,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Wide layout: keep label and segmented on one row, respect handedness.
    final flexibleSegmented = Flexible(child: segmented);

    final List<Widget> children;
    switch (hand) {
      case .left:
        children = <Widget>[
          labelWidget,
          const HorizontalPadding(),
          flexibleSegmented,
        ];
        break;
      case .right:
        children = <Widget>[
          flexibleSegmented,
          const HorizontalPadding(),
          labelWidget,
        ];
        break;
    }

    return Padding(
      padding: padding,
      child: Row(children: children),
    );
  }
}

// ignore: prefer-single-widget-per-file
class _SegmentedRowLabel extends HookWidget {
  const _SegmentedRowLabel({
    required this.tooltip,
    required this.isSmall,
    required this.icon,
    required this.label,
    required this.labelValue,
  });

  final String tooltip;
  final bool isSmall;
  final String label;
  final String labelValue;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return MonetTooltip(
      colors: MonetTheme.of(context).primary,
      content: Text(tooltip),
      child: SizedBox(
        width: null,
        child: Row(
          mainAxisSize: .min,
          mainAxisAlignment: .spaceBetween,
          crossAxisAlignment: .center,
          children: [
            Flexible(
              child: Row(
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
                  // Not having Flexible throws an exception during an integration
                  // test with a screen width of 800. This does not happen at runtime.
                  Flexible(
                    child: Text(
                      maxLines: 1,
                      label,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
            ),
            const HorizontalPadding(),
            const MonetTooltipIcon.fixed(),
            if (labelValue.isNotEmpty) ...[
              const HorizontalPadding(),
              Text(
                labelValue,
                style:
                    MonetMonoTextStyle.sizedTo(
                      context,
                      TextTheme.of(context).labelSmall!,
                    ).copyWith(
                      color: MonetTheme.of(context).primary.backgroundText,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
