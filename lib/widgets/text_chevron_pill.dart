import 'package:monet_ui/widgets/padding.dart';
import 'package:pixel_snap_fork/material.dart';
import 'package:monet_ui/widgets/expand_arrow.dart';

/// A tappable row of [text] + expand/collapse chevron.
///
/// Analogous to [IconChevronPill] but shows a text label instead of an icon
/// and does not render a pill background.
class TextChevronPill extends StatelessWidget {
  const TextChevronPill({
    super.key,
    required this.text,
    required this.isExpanded,
    required this.onPressed,
    this.style,
  });

  final String text;
  final bool isExpanded;
  final VoidCallback onPressed;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Row(
        mainAxisSize: .min,
        children: [
          Flexible(child: Text(text, style: style)),
          HorizontalPaddingHalf(),
          ExpandArrow(
            colorAnimation: null,
            isExpanded: isExpanded,
            onExpandPressed: onPressed,
            showBackground: false,
            handleGestures: false,
            useInheritedIconColor: true,
          ),
        ],
      ),
    );
  }
}
