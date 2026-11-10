// rationale: simple and tightly coupled widgets that are used in many places.
// ignore_for_file: prefer-single-widget-per-file

import 'package:monet_ui/util/list_view_padding_calculator.dart';
import 'package:monet_ui/widgets/screen_breakpoints.dart';
import 'package:pixel_snap_fork/material.dart';

class HorizontalPadding extends StatelessWidget {
  static const amount = 8.0;
  static const rightInset = EdgeInsets.only(right: amount);
  static const leftInset = EdgeInsets.only(left: amount);
  static const insets = EdgeInsets.only(left: amount, right: amount);
  const HorizontalPadding({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: 8);
  }
}

class HorizontalPaddingHalf extends StatelessWidget {
  static const amount = 4.0;
  const HorizontalPaddingHalf({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: amount);
  }
}

class VerticalPadding extends StatelessWidget {
  static const amount = 8.0;
  static const bottomInset = EdgeInsets.only(bottom: amount);

  const VerticalPadding({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: amount);
  }
}

class VerticalPaddingHalf extends StatelessWidget {
  static const amount = 4.0;

  const VerticalPaddingHalf({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: amount);
  }
}

class ScreenPadding extends StatelessWidget {
  static const amount = 8.0;
  // Good match for back button.
  static const inset = EdgeInsets.symmetric(horizontal: amount);

  final Widget child;

  const ScreenPadding({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(padding: inset, child: child);
  }
}

class ScreenConstrained extends StatelessWidget {
  static const maxWidth = ScreenBreakpoints.maxScreenWidth;

  static double platformWidthOf(
    BuildContext context, [
    double calibratedWidth = maxWidth,
  ]) => ScreenBreakpoints.platformWidthOf(context, calibratedWidth);

  final Alignment alignment;
  final Widget child;
  final double width;
  const ScreenConstrained({
    super.key,
    required this.child,
    this.width = ScreenConstrained.maxWidth,
    this.alignment = Alignment.centerLeft,
  });

  @override
  Widget build(BuildContext context) {
    final platformWidth = platformWidthOf(context, width);
    return Padding(
      padding: .only(
        left: listViewLeftPadding(
          context,
          BoxConstraints(maxWidth: platformWidth),
          enforceScreenPaddingFloor: false,
        ),
        right: listViewRightPadding(
          context,
          BoxConstraints(maxWidth: platformWidth),
          enforceScreenPaddingFloor: false,
        ),
      ),
      // - Center - ensure width-limited content is centered.
      // - ConstrainedBox - limit the max width of the content.
      // - Align - align the content to leading instead of center
      // - ConstrainedBox - limit the max width of the child content.
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: platformWidth),
          child: Align(
            alignment: alignment,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: platformWidth),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
