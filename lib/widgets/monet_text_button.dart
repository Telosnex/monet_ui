// ignore_for_file: avoid-recursive-widget-calls

import 'package:monet_ui/theming/button_style.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/palette.dart';
import 'package:pixel_snap_fork/material.dart';
import 'package:monet_ui/widgets/icon_size.dart';
import 'package:monet_ui/widgets/padding.dart';

class MonetTextButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Color shadowColor;
  final WidgetStatesController? statesController;
  final ButtonStyle? style;
  final Widget? icon;
  final Widget? label;
  final Color? outlineColorWhenNoShadow;

  const MonetTextButton({
    super.key,
    required this.shadowColor,
    this.statesController,
    required this.onPressed,
    this.icon,
    required this.label,
    this.outlineColorWhenNoShadow,
    this.style,
  });

  factory MonetTextButton.primary(
    BuildContext context, {
    Key? key,
    Widget? icon,
    required String? label,

    /// Overrides [label] if both are provided.
    Widget? foreground,
    WidgetStatesController? statesController,
    required VoidCallback? onPressed,
  }) {
    final outerMonetTheme = MonetTheme.of(context);
    final safeColors = outerMonetTheme.primary;
    return MonetTextButton.color(
      context,
      key: key,
      colors: safeColors,
      icon: icon,
      label: label,
      foreground: foreground,
      statesController: statesController,
      onPressed: onPressed,
    );
  }

  factory MonetTextButton.secondary(
    BuildContext context, {
    Key? key,
    Widget? icon,
    required String? label,

    /// Overrides [label] if both are provided.
    Widget? foreground,
    WidgetStatesController? statesController,
    required VoidCallback? onPressed,
  }) {
    final outerMonetTheme = MonetTheme.of(context);
    final safeColors = outerMonetTheme.secondary;
    return MonetTextButton.color(
      context,
      key: key,
      colors: safeColors,
      icon: icon,
      label: label,
      foreground: foreground,
      statesController: statesController,
      onPressed: onPressed,
    );
  }

  factory MonetTextButton.tertiary(
    BuildContext context, {
    Key? key,
    Widget? icon,
    required String? label,
    Widget? foreground,
    WidgetStatesController? statesController,
    required VoidCallback? onPressed,
  }) {
    final outerMonetTheme = MonetTheme.of(context);
    final safeColors = outerMonetTheme.tertiary;
    return MonetTextButton.color(
      context,
      key: key,
      colors: safeColors,
      icon: icon,
      label: label,
      foreground: foreground,
      statesController: statesController,
      onPressed: onPressed,
    );
  }

  factory MonetTextButton.color(
    BuildContext context, {
    Key? key,
    required Palette colors,
    Widget? icon,
    required String? label,
    Widget? foreground,
    WidgetStatesController? statesController,
    required VoidCallback? onPressed,
  }) {
    final isLabelOverriden = foreground != null;
    final isLabelStringSpecified = label != null && label.isNotEmpty;
    final isRichTextLabelRecommended =
        !isLabelOverriden && isLabelStringSpecified;
    final finalLabelWidget = switch (isLabelOverriden) {
      true => foreground,
      false =>
        isLabelStringSpecified
            ? Text.rich(
                TextSpan(
                  children: [
                    if (icon != null)
                      WidgetSpan(
                        alignment: .middle,
                        child: Padding(
                          padding: .only(
                            right: HorizontalPaddingHalf.amount + 2,
                          ),
                          child: Builder(
                            builder: (context) {
                              // This uses the color from the animation states
                              // injected by ElevatedButton. Side effect is
                              // icon color is same as text color.
                              return IconTheme(
                                data: IconTheme.of(context).copyWith(
                                  color: DefaultTextStyle.of(context)
                                      .style
                                      .color,
                                ),
                                child: icon,
                              );
                            },
                          ),
                        ),
                      ),
                    TextSpan(text: label),
                  ],
                ),
                textAlign: .center,
              )
            : null,
    };
    return MonetTextButton(
      key: key,
      shadowColor: colors.colorBorder,
      statesController: statesController,
      onPressed: onPressed,
      icon: (!isRichTextLabelRecommended) ? icon : null,
      label: finalLabelWidget,
      // textButtonStyle2 bakes in a SQUARE minimum (touchSize·√scale per
      // side, via minimumSizeForScale). The copyWith is a deliberate
      // override, not a leftover: it zeroes the minimum WIDTH so buttons
      // can hug narrow content, keeping only the scaled minimum height.
      style: textButtonStyle2(colors)
          .copyWith(minimumSize: _minimumSizeProperty(context)),
    );
  }

  /// libmonet's [minimumSizeForScale] is a square; telosnex buttons keep
  /// its scaled minimum height but allow any width (hug narrow content).
  static Size _minimumSize(BuildContext context) {
    final scale = MonetTheme.of(context).scale;
    return Size(0, minimumSizeForScale(scale).height);
  }

  static WidgetStateProperty<Size> _minimumSizeProperty(BuildContext context) {
    return WidgetStatePropertyAll(_minimumSize(context));
  }

  @override
  Widget build(BuildContext context) {
    final hasOutline =
        shadowColor == Colors.transparent && outlineColorWhenNoShadow != null;
    final finalStyle = (style ?? const ButtonStyle()).copyWith(
      iconSize:
          style?.iconSize ??
          WidgetStateProperty.all(
            iconSizeForTextStyleOrNull(Theme.of(context).textTheme.bodyLarge!),
          ),
      elevation: WidgetStateProperty.all(0),
      shadowColor: WidgetStateProperty.all(Colors.transparent),
      shape: WidgetStateProperty.all(MonetTheme.shapesOf(context).border()),
      side: WidgetStateProperty.all(
        hasOutline
            ? BorderSide(color: outlineColorWhenNoShadow!, width: 1)
            : BorderSide.none,
      ),
      minimumSize: style?.minimumSize ?? _minimumSizeProperty(context),
      // For some reason, default is 8/2 on iOS and 8/12 on ex. macOS.
      //
      // This was found while investigating why iOS/Android had little vertical
      // padding on home ideas buttons compared to other platforms.
      //
      // It looks like this is due to quite complicated conditional logic in
      // ex. ElevatedButton based on font size and visual density.
      padding: WidgetStatePropertyAll(
        EdgeInsets.only(
          // left tends to have inherent padding due to icon.
          // / 2 was initially selected. This worked well for read/ideas chips
          // but not for home ideas buttons.
          left: HorizontalPaddingHalf.amount + 2,
          right: label != null
              ? HorizontalPaddingHalf.amount + 2
              : HorizontalPadding.amount - 4,
          top: VerticalPaddingHalf.amount,
          bottom: VerticalPaddingHalf.amount,
        ),
      ),
    );
    TextButton button;
    if (icon != null) {
      if (label != null) {
        // ElevatedButton.icon has a non-configurable gap between the icon
        // and text.
        //
        // This meant we could not get the "Change AI" button in the script
        // to have the same padding as the slider header icon and text.
        //
        // ElevatedButton.icon is a very thin wrapper implemented much like this
        button = TextButton(
          statesController: statesController,
          onPressed: onPressed,
          style: finalStyle,
          child: Row(
            mainAxisSize: .min,
            children: [
              Builder(
                builder: (context) {
                  return IconTheme(
                    data: IconTheme.of(
                      context,
                    ).copyWith(color: DefaultTextStyle.of(context).style.color),
                    child: icon!,
                  );
                },
              ),
              SizedBox(width: 6),
              Flexible(child: label!),
            ],
          ),
        );
      } else {
        button = TextButton(
          statesController: statesController,
          onPressed: onPressed,
          style: finalStyle,
          child: icon!,
        );
      }
    } else {
      // icon == null
      button = TextButton(
        statesController: statesController,
        onPressed: onPressed,
        style: finalStyle,
        child: label ?? SizedBox.shrink(),
      );
    }

    return SelectionContainer.disabled(child: button);
  }
}

/// Text button with transparent background, no border.
ButtonStyle textButtonStyle2(
  Palette sc, {
  TextStyle? textStyle,
  double scale = 1.0,
}) {
  return ButtonStyle(
    visualDensity: .compact,
    backgroundColor: widgetPropertyByState(
      normal: () => Colors.transparent,
      hover: () => sc.backgroundHovered,
      splash: () => sc.backgroundSplashed,
    ),
    surfaceTintColor: widgetPropertyByState(
      normal: () => Colors.transparent,
      hover: () => sc.backgroundHovered,
      splash: () => sc.backgroundSplashed,
    ),
    overlayColor: widgetPropertyByState(
      normal: () => Colors.transparent,
      hover: () => sc.backgroundHovered,
      splash: () => sc.backgroundSplashed,
    ),
    foregroundColor: widgetPropertyByState(
      normal: () => sc.text,
      hover: () => sc.backgroundHoveredText,
      splash: () => sc.backgroundSplashedText,
    ),
    iconColor: widgetPropertyByState(
      normal: () => sc.text,
      hover: () => sc.backgroundHoveredText,
      splash: () => sc.backgroundSplashedText,
    ),
    textStyle: textStyle != null ? WidgetStatePropertyAll(textStyle) : null,
    minimumSize: WidgetStatePropertyAll(minimumSizeForScale(scale)),
    maximumSize: WidgetStatePropertyAll(maximumSize),
    padding: WidgetStatePropertyAll(padding),
  );
}
