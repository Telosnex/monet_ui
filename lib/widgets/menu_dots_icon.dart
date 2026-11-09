import 'package:monet_ui/widgets/animated_color_hook.dart';
import 'package:monet_ui/widgets/monet_icons.dart';
import 'package:pixel_snap_fork/material.dart';
import 'package:monet_ui/widgets/monet_icon.dart';

class MenuDotsIcon extends StatelessWidget {
  // Ratios are calibrated for the app's menu icon size, a label-derived box
  // (~18-19dp under default typography): dots land at ~4.5-4.75dp, matching
  // the visual weight they had when the box was H6-derived (~25dp) with the
  // old 5/26 ratio. Density is uniform at any size, so larger boxes (e.g.
  // IconTheme-sized fallbacks) scale proportionally.
  static const double _baseSize = 20.0;
  static const double _baseDiameter = 5;
  static const double _baseSpacing = 1.5;
  // ignore: unused_field
  static final bool _kDebugUseTraditionalIcon = false;

  final double? size;
  final Color? color;

  const MenuDotsIcon({super.key, this.size, this.color});

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final resolvedSize = size ?? iconTheme.size ?? 24.0;
    final paintScope = PaintDrivenColorScope.maybeOf(context);
    final resolvedColor =
        color ?? paintScope?.iconColor ?? iconTheme.color ?? Colors.black;

    if (_kDebugUseTraditionalIcon) {
      return MonetIcon(
        MonetIcons.menu,
        size: resolvedSize,
        color: resolvedColor,
      );
    }

    final scale = resolvedSize / _baseSize;
    final dotDiameter = _baseDiameter * scale;
    final dotSpacing = _baseSpacing * scale;

    return CustomPaint(
      size: Size.square(resolvedSize),
      painter: _MenuDotsPainter(
        color: resolvedColor,
        repaint: paintScope?.repaint,
        paintColor: color == null ? paintScope?.paintColor : null,
        dotDiameter: dotDiameter,
        dotSpacing: dotSpacing,
      ),
    );
  }
}

class _MenuDotsPainter extends CustomPainter {
  _MenuDotsPainter({
    required this.color,
    super.repaint,
    required this.paintColor,
    required this.dotDiameter,
    required this.dotSpacing,
  });

  final Color color;
  final Color Function()? paintColor;
  final double dotDiameter;
  final double dotSpacing;
  final Paint _paint = Paint()..isAntiAlias = true;

  @override
  void paint(Canvas canvas, Size size) {
    _paint.color = paintColor?.call() ?? color;
    final radius = dotDiameter / 2;
    final contentWidth = (dotDiameter * 3) + (dotSpacing * 2);
    final firstCenterX = ((size.width - contentWidth) / 2) + radius;
    final centerY = size.height / 2;
    for (var index = 0; index < 3; index++) {
      canvas.drawCircle(
        Offset(firstCenterX + (index * (dotDiameter + dotSpacing)), centerY),
        radius,
        _paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MenuDotsPainter oldDelegate) =>
      color != oldDelegate.color ||
      !identical(paintColor, oldDelegate.paintColor) ||
      dotDiameter != oldDelegate.dotDiameter ||
      dotSpacing != oldDelegate.dotSpacing;
}
