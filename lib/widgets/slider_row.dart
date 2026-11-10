import 'package:flutter_hooks/flutter_hooks.dart';
// ignore_for_file: prefer-single-widget-per-file

import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/palette.dart';
import 'package:monet_ui/widgets/control_row_header.dart';
import 'package:monet_ui/widgets/icon_size.dart';
import 'package:monet_ui/widgets/monet_handedness.dart';
import 'package:monet_ui/widgets/monet_icon.dart';
import 'package:monet_ui/widgets/monet_icons.dart';
import 'package:monet_ui/widgets/monet_mono_text_style.dart';
import 'package:monet_ui/widgets/monet_rich_text.dart';
import 'package:monet_ui/widgets/monet_slider.dart';
import 'package:monet_ui/widgets/monet_tooltip.dart';
import 'package:monet_ui/widgets/padding.dart';
import 'package:monet_ui/widgets/screen_breakpoints.dart';
import 'package:monet_ui/widgets/settings_row.dart';
import 'package:pixel_snap_fork/material.dart';

/// A labeled slider: the app's one slider row.
///
/// Wide, it reads left to right, like the other rows: label, value, slider.
/// Small, the label and value sit above the slider.
///
/// Sizes:
/// - [SliderRow.new]: rows inside a section, popup or panel. Their labels
///   match [SwitchRow] and [DropdownRow].
/// - [SliderRow.prominent]: rows at the top level of a settings screen.
///   Their labels match the screen's other top-level rows.
/// - [header]: a caller's own header, e.g. a Settings row's icon and title.
class SliderRow extends HookWidget {
  final String label;
  final Function(double newValue) onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final IconData? thumbIcon;
  final String? thumbLetter;
  final String tooltip;
  final double value;
  final double valueMin;
  final double valueMax;
  final String Function(double) valueToString;

  /// Uses the small layout whatever the screen width. Needed where the row
  /// cannot measure its space, such as in a popup menu.
  final bool forceSmallWidth;

  // Avoid setting this to true this is an exception added for the HCT sliders
  // in the color picker.
  final bool isHeaderHidden;

  // Optional trailing widget that is shown on the same row as the slider,
  // even when in small-width layout. Useful for add/remove buttons etc.
  final Widget? trailing;
  final Palette? colors;

  /// Replaces the label and its tooltip icon. It shows its own tooltip.
  final Widget? header;

  /// The header's width in the wide layout. Defaults to the label's.
  final double? headerWidth;

  /// The value's style. Defaults to match the label.
  final TextStyle? valueStyle;

  /// Key of the slider itself, for finding the part that is dragged.
  final Key? sliderKey;

  final bool _isProminent;

  const SliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.valueMin,
    required this.valueMax,
    required this.valueToString,
    required this.tooltip,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.thumbIcon,
    this.thumbLetter,
    this.forceSmallWidth = false,
    this.isHeaderHidden = false,
    this.trailing,
    this.colors,
    this.header,
    this.headerWidth,
    this.valueStyle,
    this.sliderKey,
  }) : _isProminent = false;

  /// A row at the top level of a settings screen.
  const SliderRow.prominent({
    super.key,
    required this.label,
    required this.value,
    required this.valueMin,
    required this.valueMax,
    required this.valueToString,
    required this.tooltip,
    required this.onChanged,
    required IconData this.thumbIcon,
    this.onChangeStart,
    this.onChangeEnd,
  }) : _isProminent = true,
       thumbLetter = null,
       forceSmallWidth = false,
       isHeaderHidden = false,
       trailing = null,
       colors = null,
       header = null,
       headerWidth = null,
       valueStyle = null,
       sliderKey = null;

  bool isSmall(BuildContext context) {
    if (forceSmallWidth) {
      return true;
    }
    // Screen width, not the row's: LayoutBuilder fails where the row is
    // measured for its intrinsic size, e.g. in a dialog or popup.
    return ScreenBreakpoints.isScreenSmallWidth(context);
  }

  @override
  Widget build(BuildContext context) {
    final isSmall = this.isSmall(context);
    final textTheme = Theme.of(context).textTheme;
    final palette = colors ?? MonetTheme.of(context).primary;

    final Widget labelWidget;
    if (header != null) {
      labelWidget = header!;
    } else if (_isProminent) {
      labelWidget = _ProminentLabel(
        label: label,
        tooltip: tooltip,
        width: isSmall ? null : SettingsRow.labelWidth(MonetTheme.of(context)),
      );
    } else {
      labelWidget = ControlRowHeader(
        label: label,
        tooltip: tooltip,
        isSmall: isSmall,
        hand: MonetHandedness.of(context),
        icon: thumbIcon,
        respectHandednessInSmall: false,
        colors: colors,
        // The tooltip covers the label and value together, below.
        enableTooltip: false,
      );
    }

    // The value's width is measured at the style it is drawn in.
    final valueBase =
        valueStyle ??
        (_isProminent || header != null
            ? textTheme.bodyLarge!
            : MonetMonoTextStyle.sizedTo(
                context,
                textTheme.labelMedium!,
              ).copyWith(color: palette.backgroundText));
    final valueWidget = SizedBox(
      width: isSmall
          ? null
          : SettingsRow.valueWidth(
              context,
              style:
                  valueStyle ??
                  (header != null || _isProminent ? textTheme.bodyLarge : null),
            ),
      // Centres the value's capitals and digits (liningFigures) like the
      // label's, so the two line up across the row.
      child: MonetRichText(
        text: valueToString(value),
        textStyle: valueBase.copyWith(
          fontFeatures: const [
            FontFeature.tabularFigures(),
            FontFeature.liningFigures(),
          ],
        ),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      ),
    );

    final slider = MonetSlider(
      key: sliderKey,
      value: value.clamp(valueMin, valueMax),
      min: valueMin,
      max: valueMax,
      onChanged: onChanged,
      onChangeStart: onChangeStart,
      onChangeEnd: onChangeEnd,
      thumbIcon: thumbIcon,
      thumbLetter: thumbLetter,
      activeTrackColor: colors?.color,
      inactiveTrackColor: colors?.background,
      borderColor: colors?.colorBorder,
      thumbContentColor: colors?.colorIcon,
      thumbLetterStyle: thumbLetter != null
          ? textTheme.labelLarge!.copyWith(color: palette.colorText)
          : null,
    );
    final sliderAndTrailing = Row(
      children: [
        Expanded(child: slider),
        if (trailing != null) ...[const HorizontalPadding(), trailing!],
      ],
    );

    // The default label shares one tooltip with the value; the others
    // show their own.
    Widget withTooltip(Widget child) => header != null || _isProminent
        ? child
        : MonetTooltip(colors: palette, content: Text(tooltip), child: child);

    if (isSmall) {
      final gestureInsets = MediaQuery.maybeSystemGestureInsetsOf(context);
      // Keeps the slider's ends clear of the system's edge gestures.
      double inset(double? gesture) =>
          ((gesture ?? 0) - ScreenPadding.amount).clamp(0, 1000) +
          (_isProminent ? HorizontalPadding.amount : 0);
      return Column(
        mainAxisSize: .min,
        children: [
          if (!isHeaderHidden)
            withTooltip(
              Row(
                children: [
                  // Truncates a long label (or large OS text) instead of
                  // overflowing the row.
                  Flexible(child: labelWidget),
                  const HorizontalPadding(),
                  valueWidget,
                ],
              ),
            ),
          const SizedBox(height: 1),
          Padding(
            padding: .only(
              left: inset(gestureInsets?.left),
              right: inset(gestureInsets?.right),
            ),
            child: sliderAndTrailing,
          ),
          // Room for the thumb's shadow, which the next row would clip.
          if (_isProminent) ...[
            const VerticalPaddingHalf(),
            const SizedBox(height: 2),
          ],
        ],
      );
    }

    if (isHeaderHidden) return sliderAndTrailing;

    final row = Row(
      children: [
        withTooltip(
          Row(
            mainAxisSize: .min,
            children: [
              if (headerWidth != null)
                SizedBox(width: headerWidth, child: labelWidget)
              else
                labelWidget,
              const HorizontalPadding(),
              valueWidget,
            ],
          ),
        ),
        const HorizontalPadding(),
        Expanded(child: sliderAndTrailing),
      ],
    );
    if (!_isProminent) return row;
    // As tall as a collapsed section header beside it.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: SettingsRow.height),
      child: row,
    );
  }
}

/// A top-level settings row's label: headline-size, with a tooltip icon.
class _ProminentLabel extends StatelessWidget {
  final String label;
  final String tooltip;
  final double? width;

  const _ProminentLabel({
    required this.label,
    required this.tooltip,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    final colors = MonetTheme.of(context).primary;
    return MonetTooltip(
      colors: colors,
      content: Text(tooltip),
      child: SizedBox(
        width: width,
        child: Row(
          mainAxisSize: .min,
          mainAxisAlignment: .spaceBetween,
          children: [
            Flexible(
              child: Padding(
                padding: const .only(left: HorizontalPadding.amount),
                // MonetRichText centres the label's capitals on the
                // tooltip icon (centerCapHeight), not its line box.
                child: MonetRichText(
                  text: label,
                  textStyle: SettingsRow.labelTextStyle(context),
                  textScaler: MediaQuery.textScalerOf(context),
                  maxLines: 1,
                ),
              ),
            ),
            const HorizontalPadding(),
            MonetIcon(
              MonetIcons.info,
              size: iconSizeForTextStyleOrNull(
                Theme.of(context).textTheme.labelMedium!,
              ),
              color: colors.text,
            ),
          ],
        ),
      ),
    );
  }
}
