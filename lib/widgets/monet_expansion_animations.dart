import 'package:pixel_snap_fork/material.dart';

/// Receives the size animations of expanding widgets below it.
///
/// For example, a scroll view can hold its position until every running
/// expansion has finished.
abstract interface class MonetExpansionAnimationObserver {
  void registerAnimation(Animation<double> animation);
  void unregisterAnimation(Animation<double> animation);
}

/// Gives expanding Monet widgets a [MonetExpansionAnimationObserver].
class MonetExpansionAnimations extends InheritedWidget {
  const MonetExpansionAnimations({
    super.key,
    required this.observer,
    required super.child,
  });

  final MonetExpansionAnimationObserver observer;

  static MonetExpansionAnimationObserver? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<MonetExpansionAnimations>()
          ?.observer;

  @override
  bool updateShouldNotify(MonetExpansionAnimations oldWidget) =>
      observer != oldWidget.observer;
}
