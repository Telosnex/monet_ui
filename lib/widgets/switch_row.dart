import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:monet_ui/theming/palette.dart';
import 'package:monet_ui/third_party/flutter/switch2.dart';
import 'package:monet_ui/widgets/control_row_header.dart';
import 'package:monet_ui/widgets/monet_handedness.dart';
import 'package:monet_ui/widgets/padding.dart';
import 'package:monet_ui/widgets/screen_breakpoints.dart';
import 'package:pixel_snap_fork/material.dart';

class SwitchRow extends HookWidget {
  final String label;
  final ValueChanged<bool> onChanged;
  final String tooltip;
  final bool value;

  /// Whether the switch accepts input. [value] still controls its on/off state.
  final bool isEnabled;
  final bool forceSmallWidth;
  final Color? textColor;
  final IconData? icon;
  final Palette? colors;

  const SwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.tooltip,
    this.forceSmallWidth = false,
    this.isEnabled = true,
    required this.onChanged,
    this.textColor,
    this.icon,
    this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final handededness = MonetHandedness.inclWideOf(context);
    final isSmall =
        forceSmallWidth || ScreenBreakpoints.isScreenSmallWidth(context);
    final labelWidget = ControlRowHeader(
      label: label,
      tooltip: tooltip,
      isSmall: true, // force not-forced-width mode
      hand: handededness,
      icon: icon,
      colors: colors,
      // Keep handedness-aware alignment in small mode.
      respectHandednessInSmall: true,
      // Use smaller gap consistent with previous implementation.
      gap: const HorizontalPaddingHalf(),
      includeGapOnlyInSmall: false,
      // Width stabilization and visible suffix for current value.
      suffixes: const [': On', ': Off'],
      activeSuffixIndex: value ? 0 : 1,
    );

    final control = Row(
      mainAxisSize: .min,
      mainAxisAlignment: handededness == .right ? .end : .start,
      children: [
        if (colors == null)
          Switch2(
            key: key,
            materialTapTargetSize: .shrinkWrap,
            value: value,
            onChanged: isEnabled ? onChanged : null,
          ),
        if (colors != null)
          SwitchTheme(
            data: memoizedMonetSwitchThemeData(colors!),
            child: Switch2(
              key: key,
              materialTapTargetSize: .shrinkWrap,
              value: value,
              onChanged: isEnabled ? onChanged : null,
            ),
          ),
      ],
    );
    if (isSmall) {
      return SizedBox(
        child: Column(
          // Ignore handedness: it feels weird when the label is "after" the
          // control horizontally for right-handers.
          crossAxisAlignment: .start,
          children: [
            labelWidget,
            Row(
              // Setting this to min enabled a Wrap containing a switch set
              // to force small width to stay on one line when both the switch
              // and its peer content could fit. (specifically, wallpaper
              // screen with wrap below wallpaper preview, containing credit
              // for Unsplash wallpaper and switch for turning on/off wallpaper
              // based colors)
              mainAxisSize: .min,
              mainAxisAlignment: handededness == .right ? .end : .start,
              children: [control],
            ),
          ],
        ),
      );
    }
    final flexibleSwitch = Flexible(child: control);

    return Row(
      mainAxisAlignment: handededness == .right ? .end : .start,
      children: [
        // Added for interesting edge case, art provider tiles in AI settings,
        // screen size 800 x 600, 3 columns, not forced small. Therefore it
        // uses a [SizedBox] with fixed width, but, thats too big and causes the switch to wrap to the next line. Wrapping switch looks weird, so make the label take up remaining space with Flexible, and align it to the start, so the switch is always right-aligned and on the same line as the label.
        // overflow. Noticed during integration testing of AI settings screen.
        Flexible(child: labelWidget),
        const HorizontalPadding(),
        flexibleSwitch,
      ],
    );
  }
}
