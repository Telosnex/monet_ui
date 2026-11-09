import 'package:monet_ui/widgets/h4.dart';
import 'package:monet_ui/widgets/icon_size.dart';
import 'package:pixel_snap_fork/material.dart';
import 'package:monet_ui/widgets/monet_icon_button.dart';

/// Icon sizes shared by every AppBarNx bar.
///
/// The back button, the leading widget and the actions use one icon size.
/// The bars give the leading widget and actions an [IconTheme] with
/// [iconSizeOf], so a `MonetIcon` or [MonetIconButton] without a size gets
/// it. A widget that sizes its icon itself, such as a menu button, reads
/// these values instead of choosing a text style.
abstract final class AppBarNxMetrics {
  /// The size of every icon in an AppBarNx bar: the H4 font size, which is
  /// also the title size.
  static double iconSizeOf(BuildContext context) =>
      iconSizeForTextStyle(H4.style(context));

  /// The target height of every icon button in an AppBarNx bar. See
  /// [MonetIconButton.targetHeight].
  static double actionTargetHeightOf(BuildContext context) =>
      MonetIconButton.targetHeightFor(context, iconSizeOf(context));

  /// Gives icons in [child] the app bar icon size.
  static Widget iconTheme(BuildContext context, {required Widget child}) =>
      IconTheme.merge(
        data: IconThemeData(size: iconSizeOf(context)),
        child: child,
      );
}
