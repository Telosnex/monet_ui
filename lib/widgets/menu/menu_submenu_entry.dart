// ignore_for_file: prefer-single-widget-per-file

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:monet_ui/theming/button_style.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/widgets/menu/menu_button.dart';
import 'package:monet_ui/widgets/menu/menu_controller.dart';
import 'package:monet_ui/widgets/menu/menu_entry.dart';
import 'package:monet_ui/widgets/monet_icon.dart';
import 'package:monet_ui/widgets/monet_tooltip.dart';
import 'package:monet_ui/widgets/padding.dart';
import 'package:pixel_snap_fork/material.dart';

class MenuSubmenuEntry extends PopupMenuEntry<Object> implements MenuEntry {
  const MenuSubmenuEntry({
    super.key,
    this.tooltip,
    required this.title,
    required this.icon,
    required this.submenuEntries,
    this.iconColor,
    this.mainAxisAlignment,
    this.textColor,
    // Required because inner context will not see text theme changes.
    required this.textStyle,
  });

  final MainAxisAlignment? mainAxisAlignment;

  final String title;
  final String? tooltip;
  final IconData? icon;
  final Color? iconColor;
  final Color? textColor;
  final List<MenuEntry> submenuEntries;
  final TextStyle? textStyle;

  @override
  State<MenuSubmenuEntry> createState() => _PopupActionEntryState();

  @override
  double get height => 0.0;

  @override
  bool represents(Object? value) {
    return false;
  }

  @override
  bool get isEnabled => true;
}

class _PopupActionEntryState extends State<MenuSubmenuEntry> {
  @override
  Widget build(BuildContext context) {
    return MenuSubmenuEntryImpl(
      icon: widget.icon,
      tooltip: widget.tooltip,
      title: widget.title,
      mainAxisAlignment: widget.mainAxisAlignment,
      textColor: widget.textColor,
      iconColor: widget.iconColor,
      submenuEntries: widget.submenuEntries,
      textStyle: widget.textStyle,
    );
  }
}

class MenuSubmenuEntryImpl extends HookWidget {
  const MenuSubmenuEntryImpl({
    super.key,
    this.icon,
    this.tooltip,
    required this.title,
    this.iconColor,
    this.mainAxisAlignment,
    this.textColor,
    required this.submenuEntries,
    this.textStyle,
  });
  final MainAxisAlignment? mainAxisAlignment;
  final Color? textColor;
  final String title;
  final String? tooltip;
  final IconData? icon;
  final Color? iconColor;
  final TextStyle? textStyle;
  final List<MenuEntry> submenuEntries;

  @override
  Widget build(BuildContext context) {
    final finalIconColor = iconColor ?? MonetTheme.of(context).primary.fill;
    final row = Row(
      mainAxisSize: .max,
      mainAxisAlignment: mainAxisAlignment ?? .start,
      children: [
        const HorizontalPadding(),
        if (icon != null) ...[
          MonetIcon(icon, color: finalIconColor),
          const HorizontalPadding(),
        ],
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: .ellipsis,
            style: (textStyle ?? Theme.of(context).textTheme.labelLarge!)
                .copyWith(
                  color: textColor ?? MonetTheme.of(context).primary.text,
                ),
          ),
        ),
        const HorizontalPadding(),
      ],
    );
    final menuController = useMemoized(() => MenuButtonController());
    useEffect(() {
      return () {
        menuController.dispose();
      };
    }, [menuController]);
    final menuButton = MenuButton(
      controller: menuController,
      naturalSize: true,
      items: submenuEntries,
      child: row,
    );

    final entry = MenuEntryStandard(
      action: () {
        menuController.show();
      },
      title: title,
      isTapDismissal: false,
      icon: icon,
      // Stack a visible chevron on top of the (invisible) anchor MenuButton
      // so users can see that tapping opens a submenu. The MenuButton itself
      // must remain in the tree to provide a stable anchor/RenderBox for
      // [MonetMenuOverlayController.show]; the chevron ignores pointers so
      // taps continue to reach the parent MenuEntry's InkWell.
      trailing: (context, statesController) => Stack(
        alignment: Alignment.center,
        children: [
          Visibility.maintain(
            visible: false,
            child: ConstrainedBox(
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              child: menuButton,
            ),
          ),
          IgnorePointer(
            // The trailing slot isn't a descendant of the title's text style,
            // and `DefaultTextStyle` doesn't update on hover/press — so resolve
            // the chevron colour against the same WidgetStatesController that
            // MenuEntryImpl attaches to its InkWell. This mirrors the palette
            // used for the leading icon in MenuEntryImpl.
            child: ListenableBuilder(
              listenable: statesController,
              builder: (context, _) {
                final safeColors = MonetTheme.of(context).primary;
                final arrowColorByState = widgetPropertyByState<Color>(
                  normal: () => iconColor ?? safeColors.fill,
                  hover: () => safeColors.backgroundHoveredFill,
                  splash: () => safeColors.backgroundSplashedFill,
                );
                return MonetIcon(
                  Icons.arrow_right,
                  color: arrowColorByState.resolve(statesController.value),
                );
              },
            ),
          ),
        ],
      ),
    );
    if (tooltip == null) return entry;
    // Wrap the whole submenu row in a hover/long-press tooltip rather than
    // tacking a permanent help_outline icon beside the label — matches the
    // platform-standard tooltip affordance.
    return MonetTooltip(
      colors: MonetTheme.of(context).primary,
      content: Text(tooltip!),
      child: entry,
    );
  }
}
