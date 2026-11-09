import 'package:flutter/widgets.dart';

/// Opt-in selection policy for a subtree that moves between a passive preview
/// and an interactive surface. Used by the app's ExclusiveSelectionArea and
/// ExclusiveMarkdownSelectionArea, not a replacement for IgnorePointer.
///
/// Keep this scope mounted in BOTH owners and toggle [enabled]. Selection
/// regions can then omit their gestures/toolbars/leader layers in the preview
/// while retaining their keyed content when full selection is restored.
/// Inputs, menus and tooltips are not changed by this policy.
class SelectionInteractionScope extends InheritedWidget {
  const SelectionInteractionScope({
    super.key,
    required this.enabled,
    required super.child,
  });

  final bool enabled;

  /// null means the caller has not opted into preview/interactive switching.
  static bool? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SelectionInteractionScope>()
      ?.enabled;

  @override
  bool updateShouldNotify(SelectionInteractionScope oldWidget) =>
      enabled != oldWidget.enabled;
}
