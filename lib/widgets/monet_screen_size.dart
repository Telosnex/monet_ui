import 'package:pixel_snap_fork/material.dart';

/// Supplies the app's logical screen size to Monet widgets.
///
/// Apps that scale or correct the display can provide their own size. Without
/// a provider, widgets use [MediaQuery.sizeOf].
///
/// Widgets depend on a width threshold, not the exact size, so they rebuild
/// only when the width crosses it.
class MonetScreenSize extends InheritedModel<double> {
  const MonetScreenSize({super.key, required this.size, required super.child});

  final Size size;

  /// Whether the screen is at least [width] wide.
  static bool isAtLeastWide(BuildContext context, double width) {
    final scope = InheritedModel.inheritFrom<MonetScreenSize>(
      context,
      aspect: width,
    );
    return (scope?.size.width ?? MediaQuery.sizeOf(context).width) >= width;
  }

  @override
  bool updateShouldNotify(MonetScreenSize oldWidget) =>
      size.width != oldWidget.size.width;

  @override
  bool updateShouldNotifyDependent(
    MonetScreenSize oldWidget,
    Set<double> dependencies,
  ) => dependencies.any(
    (width) => (size.width >= width) != (oldWidget.size.width >= width),
  );
}
