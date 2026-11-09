import 'package:pixel_snap_fork/material.dart';

import 'package:monet_ui/widgets/monet_button_icon.dart';
import 'package:monet_ui/widgets/monet_icon.dart';

/// A chip icon whose horizontal layout hugs its ink, not the font's square.
///
/// The glyph keeps its nominal size and vertical alignment. Registered ink
/// bounds (see `registerIconInkBounds`) remove only blank side bearings;
/// nothing is stretched or clipped, including pulse protection shadows.
/// Icons without registered bounds stay square.
/// This does not change standalone icons or button tap-target policy.
class MonetChipIcon extends StatelessWidget {
  const MonetChipIcon({
    super.key,
    required this.icon,
    required this.size,
    this.shadows = const [],
  }) : assert(size >= 0);

  final IconData icon;
  final double size;
  final List<Shadow> shadows;

  @override
  Widget build(BuildContext context) {
    return MonetButtonIcon(
      shadows: shadows,
      child: MonetIcon(icon, size: size),
    );
  }
}
