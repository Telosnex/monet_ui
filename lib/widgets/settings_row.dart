import 'dart:math' as math;

import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/monet_theme_data.dart';
import 'package:pixel_snap_fork/material.dart'
    show BuildContext, MediaQuery, TextStyle, Theme;

/// Class with static values for components of a setting row.
///
/// # Visual Order
/// Right-handed: [label] [value] [control]
/// Left-handed: [control] [value] [label]
/// Wrap:
/// [label]
/// [value]
/// [control]
class SettingsRow {
  static double labelWidth(MonetTheme theme) {
    return 140.0 + math.sqrt(theme.monetThemeData.scale) * 40.0;
  }

  static TextStyle labelTextStyle(BuildContext context) {
    return Theme.of(context).textTheme.headlineSmall!
        .copyWith(fontWeight: .w400);
  }

  /// Width of the value column beside a slider or field.
  ///
  /// Grows with the app's size setting and the OS text size, measured at
  /// [style]'s font size (labelMedium by default) because OS text scaling
  /// can be nonlinear.
  static double valueWidth(BuildContext context, {TextStyle? style}) {
    final fontSize =
        (style ?? Theme.of(context).textTheme.labelMedium!).fontSize!;
    final textScale =
        MediaQuery.textScalerOf(context).scale(fontSize) / fontSize;
    // Based on widest Google Font found on 2024-11-10, BioRhyme Expanded.
    // Test by exploring size setting and verifying % always fits.
    return 90 *
        math.sqrt(MonetTheme.of(context).monetThemeData.scale) *
        textScale;
  }

  // Match height of collapsed expansion tile. Observed to be 34.
  // Believe to to be MonetThemeData.touchSize + 2 * borderWidth.
  static const height = MonetThemeData.touchSize + 2;
}
