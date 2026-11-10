import 'package:monet_ui/widgets/monet_handedness.dart';
import 'package:monet_ui/widgets/padding.dart';
import 'package:monet_ui/widgets/screen_breakpoints.dart';
import 'package:pixel_snap_fork/material.dart';

class ScreenConstrainedHandAligned extends StatelessWidget {
  static const maxWidth = ScreenBreakpoints.maxScreenWidth;
  final Widget child;
  final double width;
  const ScreenConstrainedHandAligned({
    super.key,
    required this.child,
    this.width = ScreenConstrained.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final hand = MonetHandedness.of(context);
    final platformWidth = ScreenConstrained.platformWidthOf(context, width);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: platformWidth),
        child: Align(
          alignment: hand == .left
              ? Alignment.bottomLeft
              : Alignment.bottomRight,
          child: child,
        ),
      ),
    );
  }
}
