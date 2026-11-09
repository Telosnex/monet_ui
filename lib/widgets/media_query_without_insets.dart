import 'package:pixel_snap_fork/material.dart';

/// Removes all system insets from the [MediaQuery] seen by [child].
///
/// Keep this as a dedicated widget instead of spelling this as
/// `MediaQuery.of(context).copyWith(...)` in a screen's build method. The
/// latter makes the entire screen depend on every MediaQuery aspect, causing
/// the screen to rebuild on every window-resize tick. Here that broad
/// dependency is isolated to this tiny wrapper; [MediaQuery] then notifies
/// descendants only for the aspects they actually consume.
class MediaQueryWithoutInsets extends StatelessWidget {
  const MediaQueryWithoutInsets({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        viewPadding: .zero,
        padding: .zero,
        systemGestureInsets: .zero,
        viewInsets: .zero,
      ),
      child: child,
    );
  }
}
