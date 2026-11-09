import 'package:monet_ui/theming/monet_theme.dart';
import 'package:pixel_snap_fork/material.dart';

import 'package:monet_ui/widgets/bordered.dart';

/// A [Bordered] box in the theme's background colors.
///
/// Use [Bordered] directly to choose both colors, or `MonetSurface` for a
/// box that looks like a button.
class MonetCard extends StatelessWidget {
  /// Defaults to the theme's `primary.background`.
  final Color? color;

  /// Defaults to the theme's `primary.backgroundBorder`.
  final Color? borderColor;

  /// Whether the card and its contents form one node for screen readers.
  /// If false, each child keeps its own node.
  final bool semanticContainer;

  final Widget child;

  const MonetCard({
    super.key,
    this.color,
    this.borderColor,
    this.semanticContainer = true,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = MonetTheme.of(context).primary;
    return Semantics(
      container: semanticContainer,
      child: Bordered(
        backgroundColor: color ?? colors.background,
        borderColor: borderColor ?? colors.backgroundBorder,
        child: Semantics(explicitChildNodes: !semanticContainer, child: child),
      ),
    );
  }
}
