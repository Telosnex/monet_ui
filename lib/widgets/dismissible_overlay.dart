import 'package:material_ui/material_ui.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/monet_theme_data.dart';
import 'package:monet_ui/widgets/monet_icon.dart';
import 'package:monet_ui/widgets/monet_icons.dart';

class DismissibleOverlay extends StatelessWidget {
  const DismissibleOverlay({
    super.key,
    required this.child,
    required this.onDismiss,
    this.cornerOffset = const EdgeInsets.all(4),
  });

  final Widget child;
  final VoidCallback onDismiss;
  final EdgeInsets cornerOffset;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: .none,
      children: [
        child,
        Positioned(
          top: cornerOffset.top,
          right: cornerOffset.right,
          child: _CloseButton(
            size: MonetThemeData.touchSize / 1.5,
            onPressed: onDismiss,
          ),
        ),
      ],
    );
  }
}

// ignore: prefer-single-widget-per-file
class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.size, required this.onPressed});

  final double size;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = MonetTheme.of(context);
    final surfaceColor = theme.primary.fill;
    final onSurfaceColor = theme.primary.fillText;
    final borderColor = theme.primary.fillBorder;
    return Material(
      shape: CircleBorder(side: BorderSide(color: borderColor, width: 1.0)),
      color: surfaceColor,
      child: InkWell(
        customBorder: CircleBorder(
          side: BorderSide(color: borderColor, width: 1.0),
        ),
        hoverColor: theme.primary.fillHovered,
        splashColor: theme.primary.fillSplashed,
        onTap: onPressed,
        child: SizedBox.square(
          dimension: size,
          child: MonetIcon(
            MonetIcons.close,
            size: size * 0.6,
            color: onSurfaceColor,
          ),
        ),
      ),
    );
  }
}
