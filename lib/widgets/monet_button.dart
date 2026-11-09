import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:monet_ui/theming/button_style.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/palette.dart';
import 'package:monet_ui/util/blur_radius.dart';
import 'package:monet_ui/widgets/icon_size.dart';
import 'package:monet_ui/widgets/padding.dart';
import 'package:monet_ui/widgets/semantic_colors.dart';
import 'package:monet_ui/widgets/shared_border.dart';
import 'package:pixel_snap_fork/material.dart';
import 'package:monet_ui/widgets/monet_button_core.dart';
import 'package:monet_ui/widgets/monet_button_icon.dart';
import 'package:monet_ui/widgets/monet_button_label.dart';
import 'package:monet_ui/widgets/monet_icon.dart';
import 'package:monet_ui/widgets/monet_pulse.dart';

/// Size, spacing, type and corners. Behavior is independent of the preset.
///
/// | Preset  | Height             | Edges | Text        | Icon        | Corners |
/// |---------|--------------------|-------|-------------|-------------|---------|
/// | compact | 16 minimum         | 4     | labelMedium | labelMedium | ½       |
/// | tool    | ¾ of touch height  | 6     | labelMedium | labelLarge  | ¾       |
/// | regular | touch height       | 8     | labelLarge  | bodyLarge   | theme   |
///
/// Touch height is libmonet's scaled minimum (`minimumSizeForScale`). Corners
/// are fractions of the theme's radius, which is for full-height buttons.
enum MonetButtonPreset { compact, tool, regular }

/// Which libmonet button style colours the button, and its default shadow.
enum MonetButtonKind {
  /// `colorButtonStyle`. Shadow: the [SharedBorderScope] border, else
  /// `colorBorder`.
  color,

  /// `fillButtonStyle`. Shadow: `fillBorder`.
  fill,

  /// `backgroundButtonStyle`. Shadow: `backgroundBorder`.
  background,

  /// `backgroundButtonStyle` with no shadow, outlined in `backgroundBorder`.
  outline,
}

/// The app's button: a palette, a preset and optional icon and label on the
/// shared [MonetButtonCore] surface.
///
/// [kind] or [style] set the colours; [preset] sets the geometry, whatever
/// the style. Icons flow inline with string labels, with the label's
/// capitals centred on the icon ([MonetButtonLabel]). [foreground] replaces
/// the string label and sits beside the icon. Content changes animate.
class MonetButton extends HookWidget {
  static const compactCornerScale = 0.5;

  /// The regular preset's edges and icon-to-label gap.
  static const regularPadding = HorizontalPadding.amount;
  static const toolCornerScale = 0.75;

  const MonetButton({
    super.key,
    this.colors,
    this.kind = .color,
    this.icon,
    this.label,
    this.labelKey,
    this.foreground,
    required this.onPressed,
    this.preset = .regular,
    this.selected,
    this.statesController,
    this.isAnimating = false,
    this.animateContent = true,
    this.animationClipBehavior,
    this.fontSize,
    this.style,
    this.internalPadding,
    this.shadowColor,
    this.outlineColor,
    this.paintListenable,
    this.paintPalette,
    this.isolateAnimationRepaints = false,
  });

  factory MonetButton.primary(
    BuildContext context, {
    Key? key,
    Widget? icon,
    String? label,
    Key? labelKey,
    Widget? foreground,
    required VoidCallback? onPressed,
    MonetButtonPreset preset = .regular,
    MonetButtonKind kind = .color,
    bool? selected,
    WidgetStatesController? statesController,
    bool isAnimating = false,
    double? fontSize,
    Color? shadowColor,
    Listenable? paintListenable,
    Palette Function()? paintPalette,
    bool isolateAnimationRepaints = false,
    // ignore: avoid-recursive-widget-calls
  }) => MonetButton(
    key: key,
    colors: MonetTheme.of(context).primary,
    kind: kind,
    icon: icon,
    label: label,
    labelKey: labelKey,
    foreground: foreground,
    onPressed: onPressed,
    preset: preset,
    selected: selected,
    statesController: statesController,
    isAnimating: isAnimating,
    fontSize: fontSize,
    shadowColor: shadowColor,
    paintListenable: paintListenable,
    paintPalette: paintPalette,
    isolateAnimationRepaints: isolateAnimationRepaints,
  );

  factory MonetButton.secondary(
    BuildContext context, {
    Key? key,
    Widget? icon,
    String? label,
    Key? labelKey,
    Widget? foreground,
    required VoidCallback? onPressed,
    MonetButtonPreset preset = .regular,
    MonetButtonKind kind = .color,
    bool? selected,
    WidgetStatesController? statesController,
    bool isAnimating = false,
    double? fontSize,
    Color? shadowColor,
    Listenable? paintListenable,
    Palette Function()? paintPalette,
    bool isolateAnimationRepaints = false,
    // ignore: avoid-recursive-widget-calls
  }) => MonetButton(
    key: key,
    colors: MonetTheme.of(context).secondary,
    kind: kind,
    icon: icon,
    label: label,
    labelKey: labelKey,
    foreground: foreground,
    onPressed: onPressed,
    preset: preset,
    selected: selected,
    statesController: statesController,
    isAnimating: isAnimating,
    fontSize: fontSize,
    shadowColor: shadowColor,
    paintListenable: paintListenable,
    paintPalette: paintPalette,
    isolateAnimationRepaints: isolateAnimationRepaints,
  );

  factory MonetButton.tertiary(
    BuildContext context, {
    Key? key,
    Widget? icon,
    String? label,
    Key? labelKey,
    Widget? foreground,
    required VoidCallback? onPressed,
    MonetButtonPreset preset = .regular,
    MonetButtonKind kind = .color,
    bool? selected,
    WidgetStatesController? statesController,
    bool isAnimating = false,
    double? fontSize,
    Color? shadowColor,
    Listenable? paintListenable,
    Palette Function()? paintPalette,
    bool isolateAnimationRepaints = false,
    // ignore: avoid-recursive-widget-calls
  }) => MonetButton(
    key: key,
    colors: MonetTheme.of(context).tertiary,
    kind: kind,
    icon: icon,
    label: label,
    labelKey: labelKey,
    foreground: foreground,
    onPressed: onPressed,
    preset: preset,
    selected: selected,
    statesController: statesController,
    isAnimating: isAnimating,
    fontSize: fontSize,
    shadowColor: shadowColor,
    paintListenable: paintListenable,
    paintPalette: paintPalette,
    isolateAnimationRepaints: isolateAnimationRepaints,
  );

  factory MonetButton.error(
    BuildContext context, {
    Key? key,
    Widget? icon,
    String? label,
    Key? labelKey,
    Widget? foreground,
    required VoidCallback? onPressed,
    MonetButtonPreset preset = .regular,
    MonetButtonKind kind = .color,
    bool? selected,
    WidgetStatesController? statesController,
    bool isAnimating = false,
    double? fontSize,
    Color? shadowColor,
    Listenable? paintListenable,
    Palette Function()? paintPalette,
    bool isolateAnimationRepaints = false,
    // ignore: avoid-recursive-widget-calls
  }) => MonetButton(
    key: key,
    colors: SemanticColors.errorPalette(context),
    kind: kind,
    icon: icon,
    label: label,
    labelKey: labelKey,
    foreground: foreground,
    onPressed: onPressed,
    preset: preset,
    selected: selected,
    statesController: statesController,
    isAnimating: isAnimating,
    fontSize: fontSize,
    shadowColor: shadowColor,
    paintListenable: paintListenable,
    paintPalette: paintPalette,
    isolateAnimationRepaints: isolateAnimationRepaints,
  );

  /// [context] is unused; it keeps the factories' signatures alike.
  factory MonetButton.color(
    BuildContext context, {
    Key? key,
    required Palette colors,
    Widget? icon,
    String? label,
    Key? labelKey,
    Widget? foreground,
    required VoidCallback? onPressed,
    MonetButtonPreset preset = .regular,
    MonetButtonKind kind = .color,
    bool? selected,
    WidgetStatesController? statesController,
    bool isAnimating = false,
    double? fontSize,
    Color? shadowColor,
    Listenable? paintListenable,
    Palette Function()? paintPalette,
    bool isolateAnimationRepaints = false,
    // ignore: avoid-recursive-widget-calls
  }) => MonetButton(
    key: key,
    colors: colors,
    kind: kind,
    icon: icon,
    label: label,
    labelKey: labelKey,
    foreground: foreground,
    onPressed: onPressed,
    preset: preset,
    selected: selected,
    statesController: statesController,
    isAnimating: isAnimating,
    fontSize: fontSize,
    shadowColor: shadowColor,
    paintListenable: paintListenable,
    paintPalette: paintPalette,
    isolateAnimationRepaints: isolateAnimationRepaints,
  );

  /// Defaults to the theme's primary palette.
  final Palette? colors;
  final MonetButtonKind kind;
  final Widget? icon;
  final String? label;

  /// Key of the label's text. Defaults to `ValueKey(label)`.
  final Key? labelKey;
  final Widget? foreground;
  final VoidCallback? onPressed;
  final MonetButtonPreset preset;

  /// Null leaves selection under the states controller's control.
  final bool? selected;

  /// Caller-owned controllers are never disposed by the button.
  final WidgetStatesController? statesController;
  final bool isAnimating;

  /// Animates size changes and cross-fades icon changes.
  final bool animateContent;

  /// Clip while the size animates. Defaults to [Clip.hardEdge] for compact
  /// and tool buttons, [Clip.none] for regular ones.
  final Clip? animationClipBehavior;
  final double? fontSize;

  /// Replaces [kind]'s colours. The [preset] still sets the minimum size,
  /// text style and icon size; the style's shape wins if it has one.
  final ButtonStyle? style;

  /// Defaults to the [preset]'s edges.
  final double? internalPadding;

  /// Defaults to [kind]'s shadow.
  final Color? shadowColor;

  /// Drawn when there is no shadow. Defaults to `backgroundBorder` for
  /// [MonetButtonKind.outline].
  final Color? outlineColor;
  final Listenable? paintListenable;
  final Palette Function()? paintPalette;
  final bool isolateAnimationRepaints;

  /// The width of the icon box for [preset]: the icon matches the letters of
  /// the label in every font ([iconSizeForTextStyle]).
  static double iconSizeFor(BuildContext context, MonetButtonPreset preset) {
    final textTheme = Theme.of(context).textTheme;
    return iconSizeForTextStyle(switch (preset) {
      .compact => textTheme.labelMedium!,
      .tool => textTheme.labelLarge!,
      .regular => textTheme.bodyLarge!,
    });
  }

  /// The edges and the gap between icon and label for [preset].
  static double paddingFor(MonetButtonPreset preset) => switch (preset) {
    .compact => HorizontalPaddingHalf.amount,
    .tool => (HorizontalPaddingHalf.amount + HorizontalPadding.amount) / 2,
    .regular => regularPadding,
  };

  /// [kind]'s libmonet style for [colors].
  static ButtonStyle kindStyle(
    MonetButtonKind kind,
    Palette colors,
    double scale,
  ) => switch (kind) {
    .color => colorButtonStyle(colors, scale: scale),
    .fill => fillButtonStyle(colors, scale: scale),
    .background || .outline => backgroundButtonStyle(colors, scale: scale),
  };

  @override
  Widget build(BuildContext context) {
    final theme = MonetTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final colors = this.colors ?? theme.primary;
    final padding = internalPadding ?? paddingFor(preset);
    final touchHeight = minimumSizeForScale(theme.scale).height;
    final cornerScale = switch (preset) {
      .compact => compactCornerScale,
      .tool => toolCornerScale,
      .regular => null,
    };
    final presetTextStyle = preset == .regular
        ? textTheme.labelLarge!
        : textTheme.labelMedium!;
    final kindStyle = MonetButton.kindStyle(kind, colors, theme.scale);
    final colorStyle = style?.merge(kindStyle) ?? kindStyle;
    final baseStyle = colorStyle.copyWith(
      minimumSize: WidgetStatePropertyAll(switch (preset) {
        .compact => const Size(16, 16),
        .tool => Size(0, touchHeight * toolCornerScale),
        .regular => Size(0, touchHeight),
      }),
      textStyle: WidgetStatePropertyAll(presetTextStyle),
      iconSize: WidgetStatePropertyAll(iconSizeFor(context, preset)),
      shape:
          style?.shape ??
          (cornerScale == null
              ? null
              : WidgetStatePropertyAll(
                  theme.shapes.border(
                    borderRadius: theme.shapes.theme.borderRadius * cornerScale,
                  ),
                )),
    );
    final suppliedController = statesController;
    final states = useMemoized(
      () => suppliedController ?? WidgetStatesController(),
      [suppliedController],
    );
    useEffect(() {
      if (suppliedController != null) return null;
      return states.dispose;
    }, [states, suppliedController]);
    // ignore: function-always-returns-null
    useEffect(() {
      final selected = this.selected;
      if (selected != null) states.update(.selected, selected);
      return null;
    }, [states, selected]);

    final palettePaintDriven = paintListenable != null && paintPalette != null;
    final scale = theme.scale;
    Palette? lastPalette;
    ButtonStyle? lastStyle;
    ButtonStyle liveStyle() {
      if (!palettePaintDriven) return baseStyle;
      final palette = paintPalette!();
      if (!identical(palette, lastPalette)) {
        lastPalette = palette;
        lastStyle = MonetButton.kindStyle(kind, palette, scale);
      }
      return lastStyle!;
    }

    Color baseBackground(Set<WidgetState> states) =>
        liveStyle().backgroundColor?.resolve(states) ?? Colors.transparent;
    final pulse = useMonetPulse(
      style: baseStyle,
      isAnimating: isAnimating,
      paintBaseColor: baseBackground,
    );
    final shadows = pulse.contentShadows;
    List<Shadow> settledShadows(Set<WidgetState> states) => protectionShadows(
      baseStyle.backgroundColor?.resolve(states) ?? Colors.transparent,
    );
    final paintShadows = shadows.isEmpty
        ? null
        : () => protectionShadows(baseBackground(states.value));
    final paintTextShadows = paintShadows == null
        ? null
        : () => [
            ...?baseStyle.textStyle?.resolve(states.value)?.shadows,
            ...paintShadows(),
          ];
    final finalStyle = shadows.isEmpty
        ? baseStyle
        : baseStyle.copyWith(
            textStyle: WidgetStateProperty.resolveWith((states) {
              final textStyle =
                  baseStyle.textStyle?.resolve(states) ?? presetTextStyle;
              return textStyle.copyWith(
                shadows: [...?textStyle.shadows, ...settledShadows(states)],
              );
            }),
          );

    Widget? icon = this.icon;
    if (icon != null) {
      final key = ValueKey(
        _IconIdentity(icon.runtimeType, icon.key, iconDataOfWidget(icon)),
      );
      icon = MonetButtonIcon(
        key: key,
        paintDriven: palettePaintDriven,
        shadows: shadows.isEmpty ? const [] : settledShadows(states.value),
        paintShadows: paintShadows,
        child: icon,
      );
      if (animateContent) {
        icon = AnimatedSwitcher(duration: kThemeAnimationDuration, child: icon);
      }
    }
    final hasStringLabel = foreground == null && (label?.isNotEmpty ?? false);
    Widget? content =
        foreground ??
        (hasStringLabel
            ? MonetButtonLabel(
                label: label!,
                labelKey: labelKey ?? ValueKey(label!),
                icon: icon,
                paintDriven: palettePaintDriven,
                fontSize: fontSize,
                gap: padding,
                paintShadows: paintTextShadows,
              )
            : null);
    final clip =
        animationClipBehavior ?? (preset == .regular ? .none : .hardEdge);
    if (animateContent && content != null) {
      content = AnimatedSize(
        alignment: AlignmentDirectional.centerStart,
        duration: kThemeAnimationDuration,
        clipBehavior: clip,
        child: content,
      );
    }
    final button = MonetButtonCore(
      icon: hasStringLabel ? null : icon,
      label: content,
      internalPadding: padding,
      onPressed: onPressed,
      statesController: states,
      style: finalStyle,
      shadowColor: shadowColor ?? _defaultShadow(context, colors),
      outlineColorWhenNoShadow:
          outlineColor ?? (kind == .outline ? colors.backgroundBorder : null),
      paintListenable: paintListenable,
      paintPalette: paintPalette,
      backgroundListenable: pulse.repaint,
      paintBackgroundColor: pulse.paintBackgroundColor,
      isolateAnimationRepaints: isolateAnimationRepaints,
    );
    if (!animateContent) return button;
    return AnimatedSize(
      alignment: Alignment.center,
      duration: kThemeAnimationDuration,
      curve: Curves.easeInOut,
      clipBehavior: clip,
      child: button,
    );
  }

  Color _defaultShadow(BuildContext context, Palette colors) =>
      kindShadow(context, kind, colors);

  /// [kind]'s shadow for [colors]. Colour buttons share an enclosing
  /// [SharedBorderScope] border.
  static Color kindShadow(
    BuildContext context,
    MonetButtonKind kind,
    Palette colors,
  ) => switch (kind) {
    .color =>
      SharedBorderScope.borderFor(context, colors) ?? colors.colorBorder,
    .fill => colors.fillBorder,
    .background => colors.backgroundBorder,
    .outline => Colors.transparent,
  };
}

/// What makes a button icon the same icon. A change swaps the icon, which
/// [AnimatedSwitcher] animates.
final class const _IconIdentity(
  final Type type,
  final Key? key,
  final IconData? data,
) {
  @override
  bool operator ==(Object other) =>
      other is _IconIdentity &&
      other.type == type &&
      other.key == key &&
      other.data == data;

  @override
  int get hashCode => Object.hash(type, key, data);
}
