import 'package:monet_ui/widgets/screen_breakpoints.dart';
import 'package:pixel_snap_fork/material.dart';

/// Which hand the user holds the device with. Controls go on that side.
enum Hand { left, right }

/// The value a widget depends on. See [MonetHandedness].
enum MonetHandednessAspect { hand, handInclWide }

/// Supplies the user's [Hand] to Monet widgets.
///
/// An app provides it once, near the root, and updates it when the setting
/// or the window width changes. Without a provider, [hand] is [Hand.right]
/// and [handInclWide] follows the same rule using the [MediaQuery] width.
///
/// Widgets depend only on the value they read, so a width change does not
/// rebuild widgets that read only [hand].
class MonetHandedness extends InheritedModel<MonetHandednessAspect> {
  const MonetHandedness({
    super.key,
    required this.hand,
    required this.handInclWide,
    required super.child,
  });

  /// The user's setting.
  final Hand hand;

  /// [hand], except [Hand.left] on wide screens, where content reads left to
  /// right regardless of the hand.
  final Hand handInclWide;

  /// The user's setting. Registers a dependency on it only.
  static Hand of(BuildContext context) =>
      InheritedModel.inheritFrom<MonetHandedness>(
        context,
        aspect: MonetHandednessAspect.hand,
      )?.hand ??
      Hand.right;

  /// [handInclWide]. Registers a dependency on it only.
  static Hand inclWideOf(BuildContext context) {
    final scope = InheritedModel.inheritFrom<MonetHandedness>(
      context,
      aspect: MonetHandednessAspect.handInclWide,
    );
    if (scope != null) return scope.handInclWide;
    final isWide =
        MediaQuery.sizeOf(context).width > ScreenBreakpoints.screenSmallWidth;
    return isWide ? Hand.left : Hand.right;
  }

  @override
  bool updateShouldNotify(MonetHandedness oldWidget) =>
      hand != oldWidget.hand || handInclWide != oldWidget.handInclWide;

  @override
  bool updateShouldNotifyDependent(
    MonetHandedness oldWidget,
    Set<MonetHandednessAspect> dependencies,
  ) =>
      (dependencies.contains(MonetHandednessAspect.hand) &&
          hand != oldWidget.hand) ||
      (dependencies.contains(MonetHandednessAspect.handInclWide) &&
          handInclWide != oldWidget.handInclWide);
}
