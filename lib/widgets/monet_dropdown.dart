// ignore_for_file: prefer-single-widget-per-file

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:loggy/loggy.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/palette.dart';
import 'package:monet_ui/widgets/animated_color_hook.dart';
import 'package:monet_ui/widgets/chevron_icon.dart';
import 'package:monet_ui/widgets/icon_size.dart';
import 'package:monet_ui/widgets/menu/menu_button.dart';
import 'package:monet_ui/widgets/menu/menu_entry.dart';
import 'package:monet_ui/widgets/menu/monet_menu_overlay.dart';
import 'package:monet_ui/widgets/monet_button.dart';
import 'package:monet_ui/widgets/monet_dropdown_controller.dart';
import 'package:monet_ui/widgets/monet_rich_text.dart';
import 'package:monet_ui/widgets/monet_scrollbar.dart';
import 'package:monet_ui/widgets/padding.dart';
import 'package:pixel_snap_fork/material.dart';

/// A dropdown that uses Monet theming.
class MonetDropdown<T> extends HookWidget with UiLoggy {
  static const kKeyMonetDropdown = ValueKey('monet_dropdown');

  /// Creates a MonetDropdown.
  ///
  /// [items] is the list of items to display in the dropdown.
  /// [selectedLabel] is the text displayed on the menu button.
  /// [selectedValue] is the currently selected item.
  /// [onChanged] is called when the selected item changes.
  /// [menuItemBuilder] is a function that builds the widget for each item.
  /// [selectedWidget] is the widget to display when an item is selected.
  MonetDropdown({
    required this.items,
    required this.selectedLabel,
    required this.selectedValue,
    required this.onChanged,
    required this.menuItemBuilder,
    this.longestLabel,
    super.key,
    this.selectedWidget,
    this.chevronStyle,
    this.closedButton,
    this.isItemEnabled,
    this.controller,
    this.colors,
    this.menuColors,
    this.paintListenable,
    this.paintPalette,
    this.onOpened,
  }) : assert(
         (paintListenable == null) == (paintPalette == null),
         'paintListenable and paintPalette must be supplied together.',
       );

  /// The function that builds the widget for each item.
  final MenuEntry Function(BuildContext context, T e) menuItemBuilder;

  /// The list of items to display in the dropdown.
  final List<T> items;

  /// The text displayed on the menu button.
  final String selectedLabel;

  /// If provided, used to ensure Dropdown is sized to at least this width.
  ///
  /// Useful for maintaining a consistent width across multiple dropdowns, ex.
  /// the Role dropdown in the script editor.
  final String? longestLabel;

  /// The currently selected item.
  final T? selectedValue;

  /// The widget to display when an item is selected.
  ///
  /// Custom content is preserved verbatim. To animate its foreground with a
  /// paint-driven button, consume [PaintDrivenColorScope] inside that widget.
  /// The default string label and chevron already do so.
  final Widget? selectedWidget;

  /// Text style the chevron is sized from ([iconSizeForTextStyle]).
  ///
  /// Defaults to the button's text style. Pass the style of
  /// [selectedWidget]'s text when it differs, so the chevron matches its
  /// letters.
  final TextStyle? chevronStyle;

  /// Replaces the standard closed button while retaining the dropdown's
  /// gestures, controller, and menu. Useful when a passive chip becomes a
  /// dropdown without changing its visual identity.
  final Widget? closedButton;

  /// Optional callback that determines whether a given item should be treated
  /// as *enabled* inside the popup menu. When an item is disabled:
  ///   * The menu entry will not trigger [onChanged] when tapped.
  ///   * The default hover/splash highlight from the surrounding [InkWell]
  ///     is suppressed, preventing the grey hover effect from appearing.
  ///
  /// This is useful for items that render their *own* interactive UI (e.g. a
  /// nested button) and therefore need to avoid the default highlight so that
  /// only their internal widgets show a hover indication.
  ///
  /// If null, all items are treated as enabled.
  final bool Function(T item)? isItemEnabled;

  /// Called when the selected item changes.
  final void Function(T? newValue) onChanged;

  /// Called immediately before the popup menu is shown.
  final VoidCallback? onOpened;

  /// Optional controller for programmatic control of the dropdown
  final MonetDropdownController? controller;

  /// Optional palette used for the closed button, and, unless [menuColors] is
  /// supplied, the opened menu surface.
  final Palette? colors;

  /// Optional palette for the opened menu surface only.
  ///
  /// Use this when the closed button is intentionally vivid (ex. a branded
  /// chip) but the menu should stay on an ambient surface.
  final Palette? menuColors;

  /// Paint-only color animation for the closed dropdown button.
  ///
  /// Both fields must be supplied together. The button then resolves the
  /// current palette during paint rather than waiting for an inherited theme
  /// rebuild. The popup menu remains governed by [menuColors].
  final Listenable? paintListenable;
  final Palette Function()? paintPalette;

  @override
  Widget build(BuildContext context) {
    // Create a stable controller if none provided
    final localController = useMemoized(() => MonetDropdownController());
    final effectiveController = controller ?? localController;

    // Memoize menu items to avoid rebuilding entire list on every render
    final menuItems = useMemoized(() {
      return items.map((e) {
        final isSelected = e == selectedValue;
        final enabled = isItemEnabled == null ? true : isItemEnabled!(e);
        final rawEntry = menuItemBuilder(context, e);
        final shouldNotifySelection = !isSelected;
        return rawEntry._forDropdown(
          dropdownEnabled: enabled,
          selected: isSelected,
          onDropdownSelected: shouldNotifySelection ? () => onChanged(e) : null,
        );
      }).toList();
    }, [items, selectedValue, isItemEnabled, menuItemBuilder, onChanged]);
    // Memoize label widget to avoid rebuilds when selectedLabel hasn't changed
    final label = useMemoized(
      () => _DropdownLabel(
        label: selectedLabel,
        selectedWidget: selectedWidget,
        chevronStyle: chevronStyle,
      ),
      [selectedLabel, selectedWidget, chevronStyle],
    );

    // Memoize hiddenLongestLabel to avoid rebuilds
    final hiddenLongestLabel = useMemoized(
      () => longestLabel == null || longestLabel!.trim().isEmpty
          ? null
          : Visibility(
              visible: false,
              maintainSize: true,
              maintainInteractivity: false,
              maintainAnimation: true,
              maintainState: true,
              child: Row(
                mainAxisSize: .min,
                mainAxisAlignment: .spaceBetween,
                children: [
                  Text(longestLabel ?? '', maxLines: 1, overflow: .ellipsis),
                  // The same size as _DropdownLabel's chevron, so the
                  // measured width matches. Builder: read the button's text
                  // style, which is below this widget's context.
                  Builder(
                    builder: (context) => ChevronIcon(
                      size: iconSizeForTextStyle(
                        chevronStyle ?? DefaultTextStyle.of(context).style,
                      ),
                    ),
                  ),
                ],
              ),
            ),
      [longestLabel],
    );
    final standardButton = colors != null
        ? MonetButton.color(
            context,
            colors: colors!,
            paintListenable: paintListenable,
            paintPalette: paintPalette,
            icon: null,
            label: null,
            foreground: hiddenLongestLabel != null
                ? Stack(
                    children: [
                      hiddenLongestLabel,
                      Positioned.fill(child: label),
                    ],
                  )
                : label,
            onPressed: () {
              // Direct call to show the dropdown
              effectiveController.show();
            },
          )
        : MonetButton.primary(
            context,
            paintListenable: paintListenable,
            paintPalette: paintPalette,
            icon: null,
            label: null,
            foreground: hiddenLongestLabel != null
                ? Stack(
                    children: [
                      hiddenLongestLabel,
                      Positioned.fill(child: label),
                    ],
                  )
                : label,
            onPressed: () {
              // Direct call to show the dropdown
              effectiveController.show();
            },
          );
    final menuChild = closedButton ?? standardButton;

    return MonetScrollbar(
      child: MonetDropdownButton(
        key: MonetDropdown.kKeyMonetDropdown,
        items: menuItems,
        controller: effectiveController,
        colors: menuColors ?? colors,
        onOpened: onOpened,
        child: menuChild,
      ),
    );
  }
}

/// The dropdown supplies a custom foreground to MonetButton, bypassing
/// its ordinary paint-aware string label. Resolve the scope *below* the button:
/// the same stateful palette getter must tint the surface, text and chevron.
/// Scope dependencies refresh callbacks on state/style changes, not paint ticks.
class _DropdownLabel extends StatelessWidget {
  const _DropdownLabel({
    required this.label,
    required this.selectedWidget,
    required this.chevronStyle,
  });

  final String label;
  final Widget? selectedWidget;
  final TextStyle? chevronStyle;

  @override
  Widget build(BuildContext context) {
    final scope = PaintDrivenColorScope.dependOn(context);
    final style = DefaultTextStyle.of(context).style;
    // Matches the label's letters, as a compact MonetButton's icon does.
    final chevronSize = iconSizeForTextStyle(chevronStyle ?? style);
    return Row(
      mainAxisSize: .min,
      mainAxisAlignment: .spaceBetween,
      children: [
        // Hug short labels, but allow long values to ellipsize. The hidden
        // longestLabel remains ordinary, non-painting Text for width measurement.
        Flexible(
          child:
              selectedWidget ??
              // MonetRichText centres the label's capitals on the
              // chevron (centerCapHeight), as MonetButtonLabel does for chips.
              MonetRichText(
                text: label,
                textStyle: style,
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: 1,
                paintColorListenable: scope?.repaint,
                paintColor: scope?.paintColor,
              ),
        ),
        const HorizontalPaddingHalf(),
        scope == null
            ? ChevronIcon(size: chevronSize)
            : ChevronIcon.animated(
                size: chevronSize,
                repaint: scope.repaint,
                colorGetter: scope.paintIconColor,
              ),
      ],
    );
  }
}

class MonetDropdownButton extends HookWidget with UiLoggy {
  final Widget child;
  final List<MenuEntry> items;
  final double? elevation;
  final Function()? onOpened;
  final BoxConstraints? constraints;
  final MonetDropdownController? controller;
  final Palette? colors;

  MonetDropdownButton({
    super.key,
    required this.items,
    required this.child,
    this.controller,
    this.elevation = 16,
    this.constraints,
    this.onOpened,
    this.colors,
  });

  static ShapeBorder shapeBorder(BuildContext context, Color? borderColor) {
    // Double width because clipping is applied to the center of the border,
    // and clipping is required to avoid shape of menu being over-width.
    return MonetTheme.shapesOf(context).border(
      side: BorderSide(color: borderColor ?? Colors.transparent, width: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Use a key to ensure the Builder is stable
    final builderKey = useMemoized(() => GlobalKey(), []);

    // Controller callbacks can outlive a build; keep their item list current.
    final itemsRef = useRef(items);
    itemsRef.value = items;

    final overlayController = useMemoized(
      () => MonetMenuOverlayController(),
      [],
    );

    useEffect(() {
      return () {
        overlayController.dispose();
      };
    }, [overlayController]);

    MonetMenuAppearance resolveAppearance(BuildContext ctx) {
      final primaryTheme = colors ?? MonetTheme.of(ctx).primary;
      final resolvedBackground = primaryTheme.background;
      return MonetMenuAppearance(
        backgroundColor: resolvedBackground,
        elevation: elevation ?? MenuButton.kElevation,
        shadowColor: primaryTheme.backgroundBorder,
        surfaceTintColor: resolvedBackground,
        clipBehavior: .antiAlias,
        // constraints:
        // constraints ?? BoxConstraints(maxWidth: ScreenBreakpoints.screenSmallWidth),
        shape: shapeBorder(context, primaryTheme.backgroundBorder),
      );
    }

    void showFromContext(BuildContext ctx) {
      loggy.debug('_showFromContext called');
      onOpened?.call();
      final currentItems = itemsRef.value;
      if (currentItems.isEmpty) {
        return;
      }
      final renderObject = ctx.findRenderObject();
      if (renderObject is! RenderBox) {
        loggy.error('renderObject is not a RenderBox');
        return;
      }
      final origin = renderObject.localToGlobal(.zero);
      final rect = Rect.fromLTWH(
        origin.dx,
        origin.dy,
        renderObject.size.width,
        renderObject.size.height,
      );
      overlayController.show(
        context: ctx,
        items: currentItems,
        geometry: MonetMenuGeometry.anchor(anchorRect: rect),
        appearance: resolveAppearance(ctx),
        anchorBox: renderObject,
      );
    }

    void showFromGlobalPosition(BuildContext ctx, Offset position) {
      onOpened?.call();
      final currentItems = itemsRef.value;
      if (currentItems.isEmpty) {
        return;
      }
      overlayController.show(
        context: ctx,
        items: currentItems,
        geometry: MonetMenuGeometry.pointer(position: position),
        appearance: resolveAppearance(ctx),
        anchorBox: null,
      );
    }

    if (overlayController.isShowing) {
      final weakContext = WeakReference(context);
      // Avoid markNeedsBuild() during build
      Future.microtask(() {
        final context = weakContext.target;
        if (context == null || !context.mounted) {
          loggy.warning('Cannot update dropdown - context not available');
          return;
        }
        overlayController.updateItems(itemsRef.value);
        overlayController.updateAppearance(resolveAppearance(context));
      });
    }

    // Read current build callbacks without reattaching the same controller.
    // Hook key changes create the replacement effect before disposing the old
    // one, so palette-keyed reattachment could detach the fresh callbacks.
    final showFromContextRef = useRef(showFromContext);
    showFromContextRef.value = showFromContext;
    final showFromGlobalPositionRef = useRef(showFromGlobalPosition);
    showFromGlobalPositionRef.value = showFromGlobalPosition;

    useEffect(() {
      final currentController = controller;
      // Only set up controller if one is provided
      if (currentController == null) return null;

      void showFromCurrentContext() {
        final currentContext = builderKey.currentContext;
        if (currentContext != null) {
          // itemsRef.value gives us the CURRENT items, not the ones from when
          // this closure was created. This is the key to fixing the stale selection!
          showFromContextRef.value(currentContext);
        } else {
          loggy.error('Cannot show dropdown - context not available');
        }
      }

      void showFromPosition(Offset position) {
        final currentContext = builderKey.currentContext;
        if (currentContext != null) {
          showFromGlobalPositionRef.value(currentContext, position);
        } else {
          loggy.error(
            'Cannot show dropdown from position - context not available',
          );
        }
      }

      // Attach the controller
      currentController.attach(showFromCurrentContext, showFromPosition);

      // Cleanup on dispose
      return () {
        currentController.detach();
      };
    }, [controller]);

    return Builder(
      key: builderKey,
      builder: (innerContext) {
        void onTap() {
          loggy.debug('Dropdown tap detected');
          showFromContext(innerContext);
        }

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: .translucent,
            onSecondaryTap: onTap,
            onTap: onTap,
            child: child,
          ),
        );
      },
    );
  }
}

extension _MonetDropdownMenuEntryAdapter on MenuEntry {
  MenuEntry _forDropdown({
    required bool dropdownEnabled,
    required bool selected,
    required VoidCallback? onDropdownSelected,
  }) {
    final bool builderEnabled = isEnabled;
    final bool allowAutoEnable = switch (this) {
      // ignore: invalid_use_of_visible_for_testing_member
      MenuEntryStandard _ => true,
      MenuEntryCompat entry => entry.enabled != false,
      _ => false,
    };
    final bool effectiveEnabled =
        dropdownEnabled && (builderEnabled || allowAutoEnable);

    VoidCallback? combinedAction;
    if (effectiveEnabled) {
      final VoidCallback? originalAction = switch (this) {
        // ignore: invalid_use_of_visible_for_testing_member
        MenuEntryStandard entry => entry.action,
        MenuEntryCompat entry => entry.action,
        _ => null,
      };
      combinedAction = () {
        onDropdownSelected?.call();
        originalAction?.call();
      };
    }

    return switch (this) {
      // ignore: invalid_use_of_visible_for_testing_member
      MenuEntryStandard entry => MenuEntryStandard(
        key: entry.key,
        title: entry.title,
        icon: entry.icon,
        iconWidget: entry.iconWidget,
        action: combinedAction,
        safeColors: entry.safeColors,
        trailing: entry.trailing,
        backgroundColor: entry.backgroundColor,
        subtitle: entry.subtitle,
        subtitleMaxLines: entry.subtitleMaxLines,
        mainAxisAlignment: entry.mainAxisAlignment,
        isTapDismissal: entry.isTapDismissal,
        selected: selected || entry.selected,
      ),
      MenuEntryCompat entry => MenuEntryCompat(
        key: entry.key,
        tooltip: entry.tooltip,
        title: entry.title,
        action: combinedAction,
        enabled: effectiveEnabled ? entry.enabled : false,
        icon: entry.icon,
        iconWidget: entry.iconWidget,
        iconWidgetIsFlexible: entry.iconWidgetIsFlexible,
        trailing: entry.trailing,
        trailingBuilder: entry.trailingBuilder,
        mainAxisAlignment: entry.mainAxisAlignment,
        textStyle: entry.textStyle,
        backgroundColor: entry.backgroundColor,
        backgroundHoveredColor: entry.backgroundHoveredColor,
        backgroundSplashedColor: entry.backgroundSplashedColor,
        iconColor: entry.iconColor,
        iconHoveredColor: entry.iconHoveredColor,
        iconSplashedColor: entry.iconSplashedColor,
        textColor: entry.textColor,
        textHoveredColor: entry.textHoveredColor,
        textSplashedColor: entry.textSplashedColor,
        hoverColor: entry.hoverColor,
        splashColor: entry.splashColor,
        subtitle: entry.subtitle,
        subtitleMaxLines: entry.subtitleMaxLines,
        isTapDismissal: entry.isTapDismissal,
        selected: selected || entry.selected,
      ),
      // Preserve the original key so Flutter can correctly reconcile
      // elements when the menu items update while the overlay is open.
      // Dropping the key here can cause stale widgets to be reused.
      MenuEntryWidget entry => MenuEntryWidget(
        // This fixed a REALLY nasty issue. 25-10-21, MonetMenu stuff relatively
        // new, LLM model dropdown doesn't refresh after a new model is
        // selected. i.e. the menu stays open and we expect selecting a new
        // model changes its menu entry to show it is selected.
        //
        // After ~6 hours, the fix was to assign a key to the _LlmIdMenuItem
        // inside the dropdown and pass it as key here. However, I want
        // something that feels "safer", and to me here, that is ensuring
        // the widget changes when the entry does.
        key: ValueKey(identityHashCode(entry)),
        child: GestureDetector(onTap: combinedAction, child: entry.child),
      ),
      _ => this,
    };
  }
}
