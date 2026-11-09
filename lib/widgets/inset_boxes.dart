// ignore_for_file: prefer-single-widget-per-file

import 'dart:math' as math;

import 'package:pixel_snap_fork/material.dart';

import 'package:monet_ui/widgets/padding.dart';

abstract final class TopInsetSizedBox {
  static double height(BuildContext context) {
    return MediaQuery.viewPaddingOf(context).top;
  }
}

/// The keyboard's height while it is open, else the system's bottom padding
/// (home indicator or gesture bar).
abstract final class BottomKeyboardInset {
  static double height(BuildContext context) {
    final viewBottom = MediaQuery.viewPaddingOf(context).bottom;
    final viewInsetsBottom = MediaQuery.viewInsetsOf(context).bottom;
    // Max handles case when viewInsetsBottom => 0 as soft keyboard dismisses,
    // and view button immediately becomes size of gesture navbar. (observed
    final bottom = viewInsetsBottom > 0
        ? math.max(viewInsetsBottom, viewBottom)
        : viewBottom;
    return bottom;
  }
}

/// A gap for the bottom of a screen: the system's bottom padding, but at
/// least [ScreenPadding.amount]. It does not include the keyboard; see
/// [BottomKeyboardInset].
class BottomPaddingSizedBox extends StatelessWidget {
  const BottomPaddingSizedBox({super.key});

  @override
  Widget build(BuildContext context) {
    final height = getBottomPadding(context);
    return SizedBox(height: height);
  }

  static double getBottomPadding(BuildContext context) {
    final padding = MediaQuery.paddingOf(context).bottom;
    // e.g. on touch / iOS, it's enough to match padding of gesture bar.
    // on desktop, where paddingOf is 0, having ScreenPadding.amount at the
    // bottom of a list provides symmetry.
    return math.max(padding, ScreenPadding.amount);
  }
}

/// The system's top padding, such as the status bar.
abstract final class TopPaddingSizedBox {
  static double getTopPadding(BuildContext context) {
    return MediaQuery.paddingOf(context).top;
  }
}
