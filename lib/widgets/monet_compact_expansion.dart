import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/widgets/monet_icon.dart';
import 'package:monet_ui/widgets/monet_icons.dart';
import 'package:monet_ui/widgets/monet_material.dart';
import 'package:monet_ui/widgets/padding.dart';
import 'package:pixel_snap_fork/material.dart';

/// A lightweight disclosure row for dense lists.
///
/// This is intentionally much smaller than [MonetExpansion]: it does not own
/// expansion state, draw a section container, or apply the settings-row header
/// treatment. Use it when the parent already provides the section and each row
/// just needs tap-to-reveal content.
class MonetCompactExpansion extends StatelessWidget {
  const MonetCompactExpansion({
    super.key,
    required this.title,
    required this.isExpanded,
    required this.onToggle,
    required this.children,
    this.trailing = const [],
    this.titleStyle,
    this.headerPadding = const .symmetric(
      horizontal: HorizontalPaddingHalf.amount,
      vertical: VerticalPaddingHalf.amount,
    ),
    this.childrenPadding = const .only(
      left: HorizontalPaddingHalf.amount,
      right: HorizontalPaddingHalf.amount,
      bottom: VerticalPaddingHalf.amount,
    ),
  });

  final String title;
  final bool isExpanded;
  final VoidCallback onToggle;
  final List<Widget> children;
  final List<Widget> trailing;
  final TextStyle? titleStyle;
  final EdgeInsets headerPadding;
  final EdgeInsets childrenPadding;

  @override
  Widget build(BuildContext context) {
    final colors = MonetTheme.of(context).primary;
    final shape = isExpanded
        ? MonetTheme.shapesOf(
            context,
          ).border(side: BorderSide(color: colors.backgroundBorder, width: 1))
        : MonetTheme.shapesOf(context)
              .border(side: BorderSide(color: Colors.transparent, width: 0));

    return MonetMaterial(
      color: colors.background,
      clipBehavior: .antiAlias,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onToggle,
        child: Column(
          // ignore: telosnex_lints/telosnex_avoid_cross_axis_stretch
          crossAxisAlignment: .stretch,
          children: [
            Padding(
              padding: headerPadding,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style:
                          titleStyle ?? Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  ...trailing,
                  MonetIcon(
                    isExpanded
                        ? MonetIcons.expandLess
                        : MonetIcons.chevronForward,
                  ),
                ],
              ),
            ),
            ClipRect(
              child: AnimatedSize(
                alignment: .topCenter,
                duration: kThemeAnimationDuration,
                curve: Curves.easeInOut,
                child: isExpanded
                    ? Padding(
                        padding: childrenPadding,
                        child: Column(
                          // ignore: telosnex_lints/telosnex_avoid_cross_axis_stretch
                          crossAxisAlignment: .stretch,
                          children: children,
                        ),
                      )
                    : const SizedBox(width: .infinity),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
