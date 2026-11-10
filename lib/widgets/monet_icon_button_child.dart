import 'package:monet_ui/widgets/monet_icon_button.dart';
import 'package:pixel_snap_fork/material.dart';

/// The size of every [MonetIconButton]: as wide as [icon] and [height] tall,
/// with [icon] centered.
///
/// It has no tap handling. [MonetIconButton] uses it as its child. A button
/// that handles taps itself, such as `MenuButton` with `naturalSize: true`,
/// uses it as its child to get the same size.
class MonetIconButtonChild extends StatelessWidget {
  const MonetIconButtonChild({super.key, required this.icon, this.height});

  /// Usually a `MonetIcon`.
  final Widget icon;

  /// Null uses [MonetIconButton.targetHeightFor] the [IconTheme] size.
  final double? height;

  @override
  Widget build(BuildContext context) {
    final height =
        this.height ??
        MonetIconButton.targetHeightFor(
          context,
          MonetIconButton.iconSizeOf(context),
        );
    return SizedBox(
      height: height,
      child: Center(widthFactor: 1, child: icon),
    );
  }
}
