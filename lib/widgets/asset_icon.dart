import 'package:pixel_snap_fork/material.dart';

import 'package:monet_ui/widgets/tool_icon_size.dart';

/// An icon rendered from an image asset that respects [IconTheme] for sizing
/// but preserves the image's original colors (no tinting).
///
/// Drop-in replacement for [Icon] when you want a PNG/WebP product logo
/// instead of a Material icon glyph.
///
/// ```dart
/// // Sizes itself from IconTheme.of(context).size, just like Icon does:
/// AssetIcon('assets/images/google_gmail.png')
/// ```
class AssetIcon extends StatelessWidget {
  final String assetPath;
  final String semanticLabel;

  const AssetIcon(this.assetPath, {super.key, required this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    // Prefer IconTheme size when set (e.g. by HeaderContent's IconTheme.merge).
    // Fall back to the tool header metric when no IconTheme ancestor.
    final iconThemeSize = IconTheme.of(context).size;
    final double size;
    if (iconThemeSize != null) {
      size = iconThemeSize;
    } else {
      size = toolIconSizeFor(toolHeaderIconSize(context));
    }
    return Image.asset(
      assetPath,
      width: size.floorToDouble(),
      height: size.floorToDouble(),
      semanticLabel: semanticLabel,
    );
  }
}
