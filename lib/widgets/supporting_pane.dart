import 'dart:math' as math;

import 'package:monet_ui/widgets/monet_handedness.dart';
import 'package:monet_ui/widgets/screen_breakpoints.dart';
import 'package:pixel_snap_fork/material.dart';

/// The rules for a supporting pane: a pane beside the screen's primary
/// content, such as Design's preview beside its settings.
///
/// Widths are in calibrated dp, the unit of [ScreenBreakpoints]. Convert a
/// result with [ScreenBreakpoints.platformWidthOf] before laying it out.
abstract final class SupportingPane {
  /// Whether a screen [width] wide has room for a supporting pane.
  static bool fits(double width) =>
      width.round() >= ScreenBreakpoints.splitMinWidth;

  /// Whether this screen shows a supporting pane.
  ///
  /// Rebuilds dependents only when the answer changes.
  static bool isShownIn(BuildContext context) =>
      ScreenBreakpoints.isWidthAtLeast(
        context,
        ScreenBreakpoints.splitMinWidth,
      );

  /// The pane's width on a screen [width] wide that [fits] one.
  ///
  /// The pane gets [desiredWidth], at least [ScreenBreakpoints.splitMinSupportingWidth]
  /// and at most [ScreenBreakpoints.splitMaxSupportingFraction] of [width]. Its content
  /// may need room it doesn't ask for, such as buttons under a small
  /// preview, so a smaller desired width still gets the minimum. The
  /// primary content keeps the rest: on a screen that [fits], at least
  /// [ScreenBreakpoints.splitMinPrimaryWidth].
  static double widthFor(double width, {required double desiredWidth}) =>
      math.max(
        ScreenBreakpoints.splitMinSupportingWidth,
        math.min(
          desiredWidth,
          width * ScreenBreakpoints.splitMaxSupportingFraction,
        ),
      );

  /// Whether the pane goes on the left. It goes on the side away from the
  /// hand, so the controls stay near the hand.
  static bool onLeft(Hand hand) => hand == .right;
}
