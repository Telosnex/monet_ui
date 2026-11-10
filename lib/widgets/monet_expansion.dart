import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/monet_theme_data.dart';
import 'package:monet_ui/third_party/flutter/expansion_tile_2.dart';
import 'package:monet_ui/widgets/monet_handedness.dart';
import 'package:monet_ui/widgets/monet_section_header.dart';
import 'package:monet_ui/widgets/padding.dart';
import 'package:pixel_snap_fork/material.dart';

class MonetExpansion extends HookWidget {
  final List<Widget> children;

  /// Displayed after title in header.
  final List<Widget> titleChildren;

  /// Displayed as label in header. If empty, no label is shown.
  final String title;
  final String? subtitle;
  final IconData? titleIcon;
  final TextStyle? titleTextStyle;

  /// Replaces the default title header while retaining expansion behavior.
  final Widget? header;
  final bool initiallyExpanded;
  final EdgeInsets? childrenPadding;
  final ValueChanged<bool>? onExpansionChanged;
  final double titleWidgetsSpacing;

  /// Default: primary.background
  final Color? backgroundColor;

  /// Default: primary.fill
  final Color? iconColor;

  /// Whether to show a border around the tile when expanded.
  /// Defaults to true.
  final bool showExpandedBorder;

  /// When true, interior rows are set to MainAxisSize.min rather than leaving
  /// it unset. This is not a standard Flutter option or behavior, it is added
  /// to allow Mods to not have to expand to their max constrained width just
  /// because an expansion tile is present.
  final bool shrinkToFit;

  /// CrossAxisAlignment for the expanded children. Defaults to start, which
  final CrossAxisAlignment expandedCrossAxisAlignment;

  const MonetExpansion({
    super.key,
    required this.title,
    this.subtitle,
    this.titleIcon,
    this.titleTextStyle,
    this.header,
    this.titleChildren = const [],
    this.initiallyExpanded = false,
    this.titleWidgetsSpacing = 0,
    this.childrenPadding,
    this.backgroundColor,
    this.iconColor,
    this.onExpansionChanged,
    // Center title and titleChildren by default to match the original
    // behavior in [ExpansionTile2], where the param was not exposed and thus
    // always defaulted to center.
    this.expandedCrossAxisAlignment = CrossAxisAlignment.center,
    this.showExpandedBorder = true,
    this.shrinkToFit = false,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final hand = MonetHandedness.inclWideOf(context);
    final iconColor = this.iconColor ?? MonetTheme.of(context).primary.fill;
    return ListTileTheme(
      data: ListTileThemeData(
        minVerticalPadding: 0,
        minTileHeight: MonetThemeData.touchSize,
        contentPadding: EdgeInsets.zero,
      ),
      child: ExpansionTile2(
        key: key,
        initiallyExpanded: initiallyExpanded,
        expandedAlignment: .centerLeft,
        onExpansionChanged: onExpansionChanged,
        backgroundColor:
            backgroundColor ?? MonetTheme.of(context).primary.background,
        collapsedBackgroundColor:
            backgroundColor ?? MonetTheme.of(context).primary.background,
        shrinkToFit: shrinkToFit,
        iconColor: iconColor,
        collapsedIconColor: iconColor,
        collapsedShape: Border.all(color: Colors.transparent, width: 0),
        shape: showExpandedBorder
            ? MonetTheme.shapesOf(context).border(
                side: BorderSide(
                  color: MonetTheme.of(context).primary.backgroundBorder,
                  width: 1,
                ),
              )
            : Border.all(color: Colors.transparent, width: 0),
        // title.isEmpty case here added for showing art provider title from AI
        // screen in Art control panel.
        tilePadding: .only(
          left: title.isEmpty
              ? HorizontalPaddingHalf.amount
              : HorizontalPadding.amount,
        ),
        titleExpandRowMainAxisAlignment: (hand == .left
            ? .start
            : .spaceBetween),
        trailing: const SizedBox.shrink(),
        expandedCrossAxisAlignment: .start,
        title: Wrap(
          runSpacing: VerticalPaddingHalf.amount,
          spacing: titleWidgetsSpacing,
          crossAxisAlignment: .center,
          children: [
            if (title.isNotEmpty)
              header ??
                  MonetExpansionHeader(
                    title: title,
                    subtitle: subtitle,
                    icon: titleIcon,
                    textStyle: titleTextStyle,
                  ),
            ...titleChildren,
          ],
        ),
        children: [
          Padding(
            padding: childrenPadding ?? .zero,
            child: Column(crossAxisAlignment: .start, children: [...children]),
          ),
        ],
      ),
    );
  }
}

// ignore: prefer-single-widget-per-file
class MonetExpansionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final TextStyle? textStyle;

  const MonetExpansionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return MonetSectionHeader(
      title: title,
      subtitle: subtitle,
      icon: icon,
      textStyle: textStyle,
    );
  }
}
