// ignore_for_file: prefer-single-widget-per-file

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:monet_ui/theming/button_style.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/monet_theme_data.dart';
import 'package:monet_ui/theming/palette.dart';
import 'package:monet_ui/widgets/icon_size.dart';
import 'package:monet_ui/widgets/monet_icon.dart';
import 'package:monet_ui/widgets/monet_rich_text.dart';
import 'package:monet_ui/widgets/monet_tooltip.dart';
import 'package:monet_ui/widgets/padding.dart';
import 'package:monet_ui/widgets/semantic_colors.dart';
import 'package:pixel_snap_fork/material.dart';

typedef TrailingWidgetBuilder = Widget? Function(
  BuildContext context,
  WidgetStatesController statesController,
);

/// Base class for menu entries in the custom menu overlay system.
/// This replaces PopupMenuEntry to give us full control over rendering.
abstract class MenuEntry extends Widget {
  const MenuEntry({super.key});

  /// The height of this menu entry. Return 0.0 for flexible height.
  double get height => 0.0;

  /// Whether this entry is enabled/interactive.
  bool get isEnabled => true;

  /// Uses primary color palette.
  ///
  /// Distinguished from [MenuEntry.primary] in that MenuEntry.create signals
  /// the color expects the "default" theme in the popup, as opposed to a
  /// specific color palette.
  ///
  /// i.e. it differs in API support contract, not appearance, from
  /// [MenuEntry.primary].
  factory MenuEntry.create({
    Key? key,
    required String title,
    String? subtitle,
    int? subtitleMaxLines,
    required IconData? icon,
    Palette? safeColors,

    /// Only one of [icon] or [iconWidget] should be provided. [iconWidget]
    /// takes precedence if both are provided.
    Widget? iconWidget,
    TrailingWidgetBuilder? trailing,

    /// Draws [icon] inline before the title's first line, so a long title
    /// wraps under it instead of beside it. Ignored with [iconWidget].
    bool iconInline = false,

    /// Replaces [subtitle], e.g. for text that changes while the menu is open.
    Widget? subtitleWidget,

    /// Dictates space between [title] and [trailing].
    MainAxisAlignment mainAxisAlignment = .start,
    bool isTapDismissal = true,
    required void Function()? action,
  }) {
    return MenuEntryStandard(
      key: key,
      iconInline: iconInline,
      subtitleWidget: subtitleWidget,
      action: action,
      isTapDismissal: isTapDismissal,
      subtitle: subtitle,
      subtitleMaxLines: subtitleMaxLines,
      icon: iconWidget == null ? icon : null,
      iconWidget: iconWidget,
      mainAxisAlignment: mainAxisAlignment,
      title: title,
      trailing: trailing,
      safeColors: safeColors,
    );
  }

  /// Builds a dropdown-style entry.
  ///
  /// [title] is intentionally nullable and coerced to the empty string when
  /// null: icon-only dropdown entries are a legitimate, supported use case
  /// (e.g. a compact row of icon choices). Callers that want a textual entry
  /// are responsible for passing a non-null, non-empty [title]; passing null
  /// here will not assert or substitute a placeholder like '(untitled)'.
  factory MenuEntry.dropdown({
    Key? key,
    String? title,
    String? subtitle,
    int? subtitleMaxLines,
    IconData? icon,

    /// Only one of [icon] or [iconWidget] should be provided. [iconWidget]
    /// takes precedence if both are provided.
    Widget? iconWidget,
    void Function()? action,
  }) {
    return MenuEntry.create(
      // Null → '' is deliberate; see factory doc comment above. Icon-only
      // entries rely on this coercion.
      title: title ?? '',
      subtitle: subtitle,
      subtitleMaxLines: subtitleMaxLines,
      icon: iconWidget == null ? icon : null,
      iconWidget: iconWidget,
      action: action,
      key: key,
    );
  }

  factory MenuEntry.error({
    Key? key,
    required BuildContext context,
    required String title,
    required IconData icon,
    required void Function() action,
    bool isTapDismissal = true,
  }) {
    return MenuEntryStandard(
      key: key,
      title: title,
      icon: icon,
      safeColors: SemanticColors.errorPalette(context),
      action: action,
      isTapDismissal: isTapDismissal,
    );
  }
}

@visibleForTesting
class MenuEntryStandard extends HookWidget implements MenuEntry {
  final String title;
  final String? subtitle;

  /// Overrides the default subtitle limit of two lines when a title is shown.
  final int? subtitleMaxLines;
  final IconData? icon;

  /// See [MenuEntry.create].
  final bool iconInline;

  /// See [MenuEntry.create].
  final Widget? subtitleWidget;
  final Widget? iconWidget;
  final VoidCallback? action;
  final Palette? safeColors;

  /// Overrides [SafeColors], intent is ex. a delete menu item that has same
  /// bg as other menu items but red text/icon & hover/splash.
  final Color? backgroundColor;
  final TrailingWidgetBuilder? trailing;

  final bool isTapDismissal;

  /// Whether this entry represents the dropdown's current value.
  final bool selected;

  /// Dictates space between [title] and [trailing].
  final MainAxisAlignment mainAxisAlignment;
  const MenuEntryStandard({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleMaxLines,
    this.icon,
    this.iconInline = false,
    this.subtitleWidget,
    this.iconWidget,
    this.action,
    this.safeColors,
    this.trailing,
    this.backgroundColor,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.isTapDismissal = true,
    this.selected = false,
  });

  @override
  double get height => 0.0;

  @override
  bool get isEnabled => action != null;

  @override
  Widget build(BuildContext context) {
    final safeColors = this.safeColors ?? MonetTheme.of(context).primary;
    return MenuEntryCompat(
      title: title,
      action: action,
      icon: icon,
      iconInline: iconInline,
      subtitleWidget: subtitleWidget,
      iconWidget: iconWidget,
      backgroundColor:
          backgroundColor ?? MonetTheme.of(context).primary.background,
      backgroundHoveredColor: safeColors.backgroundHovered,
      backgroundSplashedColor: safeColors.backgroundSplashed,
      iconColor: safeColors.fill,
      iconHoveredColor: safeColors.backgroundHoveredFill,
      iconSplashedColor: safeColors.backgroundSplashedFill,
      mainAxisAlignment: mainAxisAlignment,
      textColor: safeColors.backgroundText,
      textHoveredColor: safeColors.backgroundHoveredText,
      textSplashedColor: safeColors.backgroundSplashedText,
      trailingBuilder: trailing,
      isTapDismissal: isTapDismissal,
      selected: selected,
      subtitle: subtitle,
      subtitleMaxLines: subtitleMaxLines,
    );
  }
}

class MenuEntryWidget extends MenuEntry {
  final Widget child;
  const MenuEntryWidget({super.key, required this.child});

  @override
  Element createElement() => _MenuEntryWidgetElement(this);
}

class _MenuEntryWidgetElement extends ComponentElement {
  _MenuEntryWidgetElement(MenuEntryWidget super.widget);

  @override
  MenuEntryWidget get widget => super.widget as MenuEntryWidget;

  // ComponentElement does not rebuild for a new widget; StatelessElement
  // does it here. Without this, a parent that rebuilds the entry with a new
  // icon or title while the menu is open still shows the first build.
  @override
  void update(MenuEntryWidget newWidget) {
    super.update(newWidget);
    rebuild(force: true);
  }

  // Intentionally returns [widget.child] verbatim: callers of
  // [MenuEntryWidget] are responsible for matching [MenuEntryImpl]'s visual
  // rhythm (padding, height) themselves when they want to slot a raw widget
  // into a menu.
  @override
  Widget build() {
    return widget.child;
  }
}

class MenuEntryCompat extends MenuEntry {
  const MenuEntryCompat({
    super.key,
    this.tooltip,
    required this.title,
    this.subtitle,
    this.subtitleMaxLines,
    this.action,
    this.enabled,
    this.icon,
    this.iconInline = false,
    this.subtitleWidget,
    this.iconWidget,
    this.backgroundColor,
    this.backgroundHoveredColor,
    this.backgroundSplashedColor,
    this.iconColor,
    this.iconHoveredColor,
    this.iconSplashedColor,
    this.textColor,
    this.textHoveredColor,
    this.textSplashedColor,
    this.iconWidgetIsFlexible = false,
    this.mainAxisAlignment,
    this.textStyle,
    this.trailing,
    this.trailingBuilder,
    this.hoverColor,
    this.splashColor,
    this.isTapDismissal = true,
    this.selected = false,
  });

  final MainAxisAlignment? mainAxisAlignment;

  final String title;
  final String? tooltip;
  final String? subtitle;

  /// Overrides the default subtitle limit of two lines when a title is shown.
  final int? subtitleMaxLines;

  /// Whether this menu entry is enabled. If null, defaults to [action] != null.
  final bool? enabled;
  final IconData? icon;
  final bool iconInline;
  final Widget? subtitleWidget;
  final Widget? iconWidget;
  final bool iconWidgetIsFlexible;
  final Widget? trailing;
  final TrailingWidgetBuilder? trailingBuilder;
  final VoidCallback? action;
  final Color? backgroundColor;
  final Color? backgroundHoveredColor;
  final Color? backgroundSplashedColor;
  final Color? iconColor;
  final Color? iconHoveredColor;
  final Color? iconSplashedColor;
  final Color? textColor;
  final Color? textHoveredColor;
  final Color? textSplashedColor;
  final Color? hoverColor;
  final Color? splashColor;
  final TextStyle? textStyle;

  final bool isTapDismissal;

  /// Whether this entry represents the dropdown's current value.
  final bool selected;

  @override
  bool get isEnabled => enabled ?? (action != null);

  @override
  Element createElement() => _MenuEntryActionElement(this);
}

class _MenuEntryActionElement extends ComponentElement {
  _MenuEntryActionElement(MenuEntryCompat super.widget);

  @override
  MenuEntryCompat get widget => super.widget as MenuEntryCompat;

  // ComponentElement does not rebuild for a new widget; StatelessElement
  // does it here. Without this, a parent that rebuilds the entry with a new
  // icon or title while the menu is open still shows the first build.
  @override
  void update(MenuEntryCompat newWidget) {
    super.update(newWidget);
    rebuild(force: true);
  }

  @override
  Widget build() {
    return MenuEntryImpl(
      icon: widget.icon,
      iconInline: widget.iconInline,
      subtitleWidget: widget.subtitleWidget,
      tooltip: widget.tooltip,
      title: widget.title,
      subtitle: widget.subtitle,
      subtitleMaxLines: widget.subtitleMaxLines,
      action: widget.action,
      enabled: widget.enabled,
      backgroundColor: widget.backgroundColor,
      backgroundHoveredColor: widget.backgroundHoveredColor,
      backgroundSplashedColor: widget.backgroundSplashedColor,
      iconHoveredColor: widget.iconHoveredColor,
      iconSplashedColor: widget.iconSplashedColor,
      textHoveredColor: widget.textHoveredColor,
      textSplashedColor: widget.textSplashedColor,
      mainAxisAlignment: widget.mainAxisAlignment,
      textColor: widget.textColor,
      iconColor: widget.iconColor,
      iconWidget: widget.iconWidget,
      iconWidgetIsFlexible: widget.iconWidgetIsFlexible,
      textStyle: widget.textStyle,
      trailingBuilder: widget.trailingBuilder,
      isTapDismissal: widget.isTapDismissal,
      selected: widget.selected,
    );
  }
}

class MenuEntryImpl extends HookWidget {
  const MenuEntryImpl({
    super.key,
    this.icon,
    this.iconInline = false,
    this.subtitleWidget,
    this.tooltip,
    required this.title,
    this.subtitle,
    this.subtitleMaxLines,
    this.action,
    this.enabled,
    this.backgroundColor,
    this.backgroundHoveredColor,
    this.backgroundSplashedColor,
    this.iconColor,
    this.iconHoveredColor,
    this.iconSplashedColor,
    this.textColor,
    this.textHoveredColor,
    this.textSplashedColor,
    this.mainAxisAlignment,
    this.textStyle,
    this.iconWidgetIsFlexible = false,
    this.iconWidget,
    this.trailing,
    this.trailingBuilder,
    this.isTapDismissal = true,
    this.selected = false,
  });
  final MainAxisAlignment? mainAxisAlignment;
  final TextStyle? textStyle;
  final Color? backgroundColor;
  final Color? backgroundHoveredColor;
  final Color? backgroundSplashedColor;

  /// Whether this menu entry is enabled. If null, defaults to [action] != null.
  final bool? enabled;

  final Color? iconColor;
  final Color? iconHoveredColor;
  final Color? iconSplashedColor;

  // [textStyle] takes precedence over [textColor]
  final Color? textColor;
  final Color? textHoveredColor;
  final Color? textSplashedColor;

  final String title;
  final String? tooltip;
  final String? subtitle;

  /// Overrides the default subtitle limit of two lines when a title is shown.
  final int? subtitleMaxLines;
  final IconData? icon;

  /// Draws [icon] inline before the title's first line (see
  /// [MenuEntry.create]).
  final bool iconInline;

  /// Replaces [subtitle].
  final Widget? subtitleWidget;

  final VoidCallback? action;
  final bool iconWidgetIsFlexible;
  final Widget? iconWidget;
  final Widget? trailing;
  final TrailingWidgetBuilder? trailingBuilder;

  final bool isTapDismissal;

  /// Whether this entry represents the dropdown's current value.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final statesController = useWidgetStatesController();
    final currentStates = useState<Set<WidgetState>>({});
    useEffect(() {
      listener() {
        final weakContext = WeakReference(context);
        Future.microtask(() {
          final context = weakContext.target;
          if (context != null && context.mounted) {
            currentStates.value = Set.of(statesController.value);
          }
        });
      }

      statesController.addListener(listener);
      return () => statesController.removeListener(listener);
    }, [statesController]);
    final textColorByState = widgetPropertyByState(
      normal: () => selected
          ? (textSplashedColor ??
                MonetTheme.of(context).primary.backgroundSplashedText)
          : (textColor ?? MonetTheme.of(context).primary.backgroundText),
      hover: () =>
          textHoveredColor ??
          MonetTheme.of(context).primary.backgroundHoveredText,
      splash: () =>
          textSplashedColor ??
          MonetTheme.of(context).primary.backgroundSplashedText,
    );
    final iconColorByState = widgetPropertyByState(
      normal: () => selected
          ? (iconSplashedColor ??
                MonetTheme.of(context).primary.backgroundSplashedFill)
          : (iconColor ?? MonetTheme.of(context).primary.fill),
      hover: () =>
          iconHoveredColor ??
          MonetTheme.of(context).primary.backgroundHoveredFill,
      splash: () =>
          iconSplashedColor ??
          MonetTheme.of(context).primary.backgroundSplashedFill,
    );

    final states = currentStates.value;
    final resolvedTextColor = textColorByState.resolve(states);
    final resolvedIconColor = iconColorByState.resolve(states);

    final textStyle =
        (this.textStyle ?? Theme.of(context).textTheme.labelLarge!).copyWith(
          color: resolvedTextColor,
        );
    final subtitleStyle = (Theme.of(context).textTheme.bodySmall ?? textStyle)
        .copyWith(color: resolvedTextColor);
    final subtitleText = subtitle?.trim();
    final hasSubtitle =
        subtitleWidget != null || (subtitleText?.isNotEmpty ?? false);
    final inlineIcon = iconInline && iconWidget == null ? icon : null;
    final hasTitle = title.isNotEmpty;
    final largeLabelFontSize = iconSizeForTextStyleOrNull(textStyle);
    // Icons are sized from bodyLarge, a step up from the labelLarge title, so
    // they read at a comfortable size next to it. A custom [textStyle] still
    // drives the icon size, to keep icons proportional to that text.
    final iconSize = iconSizeForTextStyleOrNull(
      this.textStyle ?? Theme.of(context).textTheme.bodyLarge!,
    );
    final row = Row(
      mainAxisSize: .min,
      mainAxisAlignment: mainAxisAlignment ?? .start,
      children: [
        Flexible(
          child: MouseRegion(
            cursor: action != null
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            child: Row(
              mainAxisSize: .min,
              children: [
                if (iconWidget != null) ...[
                  const HorizontalPadding(),
                  iconWidgetIsFlexible
                      ? Flexible(
                          child: IconTheme.merge(
                            data: IconThemeData(opacity: 1.0, size: iconSize),
                            child: iconWidget!,
                          ),
                        )
                      : IconTheme.merge(
                          data: IconThemeData(opacity: 1.0, size: iconSize),
                          child: iconWidget!,
                        ),
                  const HorizontalPadding(),
                ] else if (icon != null && inlineIcon == null) ...[
                  const HorizontalPadding(),
                  // This needs to be manually specified. Otherwise, the
                  // IconTheme from the parent of the menu button is captured,
                  // and those sizes are inconsistent/based on the button size.
                  // Identified via home chat tile menu having very different
                  // icon size from the go button.
                  IconTheme.merge(
                    data: IconThemeData(opacity: 1.0, size: iconSize),
                    child: MonetIcon(icon, color: resolvedIconColor),
                  ),
                  const HorizontalPadding(),
                ] else
                  const HorizontalPadding(),

                if (hasTitle || hasSubtitle)
                  Flexible(
                    // Constraint specifically added to fix runaway wide file
                    // picker menu items. It seems generally useful and was added
                    // to all MenuEntry instances.
                    child: Column(
                      mainAxisSize: .min,
                      crossAxisAlignment: .start,
                      children: [
                        if (hasTitle)
                          // MonetRichText centres the title's capitals
                          // on the icon (centerCapHeight), not its line box.
                          MonetRichText(
                            leading: [
                              if (inlineIcon != null) ...[
                                IconTheme.merge(
                                  data: IconThemeData(
                                    opacity: 1.0,
                                    size: iconSize,
                                  ),
                                  child: MonetIcon(
                                    inlineIcon,
                                    color: resolvedIconColor,
                                  ),
                                ),
                                const HorizontalPaddingHalf(),
                              ],
                            ],
                            text: title,
                            textStyle: textStyle,
                            textScaler: MediaQuery.textScalerOf(context),
                            maxLines: hasSubtitle ? 2 : 3,
                          ),
                        if (subtitleWidget case final subtitleWidget?) ...[
                          if (hasTitle) const SizedBox(height: 2),
                          DefaultTextStyle.merge(
                            style: subtitleStyle,
                            child: subtitleWidget,
                          ),
                        ] else if (hasSubtitle) ...[
                          if (hasTitle) const SizedBox(height: 2),
                          Text(
                            textAlign: .start,
                            subtitleText!,
                            maxLines: subtitleMaxLines ?? (hasTitle ? 2 : 3),
                            overflow: .ellipsis,
                            style: subtitleStyle,
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        Row(
          children: [
            if (trailingBuilder != null)
              ?trailingBuilder?.call(context, statesController),
            if (trailingBuilder == null && trailing != null) trailing!,
            if (trailing == null && trailingBuilder == null) ...[
              HorizontalPadding(),
              HorizontalPaddingHalf(),
            ],
          ],
        ),
      ],
    );

    final baseFontSize = 21;
    final baseHeight = MonetThemeData.touchSize;

    final extrapolatedHeight =
        baseHeight * (largeLabelFontSize! / baseFontSize);
    final popupMenuItem = MouseRegion(
      cursor: (enabled ?? (action != null))
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: extrapolatedHeight
              .clamp(
                MonetThemeData.touchSize * 0.66,
                MonetThemeData.touchSize * 5,
              )
              .ceilToDouble(),
        ),
        child: Material(
          // A selected dropdown entry rests in the palette's splashed state.
          // This gives selection the same established Monet treatment as a
          // held button, while hover and press continue to resolve normally.
          color: selected
              ? (backgroundSplashedColor ??
                    MonetTheme.of(context).primary.backgroundSplashed)
              : backgroundColor,
          child: InkWell(
            statesController: statesController,
            // NOTE: InkWell's `enabled:` flag is intentionally omitted —
            // we drive the enabled state through [onTap]: a null callback
            // disables the ripple/hover, which matches the visual intent.
            hoverColor:
                backgroundHoveredColor ??
                MonetTheme.of(context).primary.backgroundHovered,
            splashColor:
                backgroundSplashedColor ??
                MonetTheme.of(context).primary.backgroundSplashed,
            onTap: (enabled ?? (action != null))
                ? () {
                    if (isTapDismissal) {
                      Navigator.of(context).pop();
                    }
                    action?.call();
                  }
                : null,
            child: row,
          ),
        ),
      ),
    );

    if (tooltip == null) return popupMenuItem;
    // Wrap the whole entry in a hover/long-press tooltip rather than tacking
    // a permanent help_outline icon beside the label — matches the
    // platform-standard tooltip affordance and keeps the trailing slot clean
    // for real trailing widgets.
    return MonetTooltip(
      colors: MonetTheme.of(context).primary,
      content: Text(tooltip!),
      child: popupMenuItem,
    );
  }
}
