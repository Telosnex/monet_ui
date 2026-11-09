import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/widgets/deferred_scrollable_selection.dart';
import 'package:monet_ui/widgets/isolated_scrollbar.dart';
import 'package:pixel_snap_fork/material.dart';

class MonetScrollbar extends HookWidget {
  final double crossAxisMargin;
  final double mainAxisMargin;
  final Widget child;

  /// Overrides the theme's color. On top of the wallpaper, pass the app's
  /// wallpaper scrollbar color: the theme's color is not checked against the
  /// wallpaper.
  final Color? scrollbarColor;

  /// Opt in for layer-heavy desktop scroll views. Mobile remains unchanged.
  ///
  /// Otherwise the inherited scroll behavior (usually the app's
  /// `scrollBehavior`) is used unchanged.
  final bool isolateScrollbarLayer;

  const MonetScrollbar({
    super.key,
    this.crossAxisMargin = 1,
    this.mainAxisMargin = 1,
    this.scrollbarColor,
    this.isolateScrollbarLayer = false,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedScrollbarColor =
        scrollbarColor ?? MonetTheme.of(context).primary.backgroundBorder;

    final scrollbarThemeData = useMemoized(
      () => ScrollbarTheme.of(context).copyWith(
        thumbColor: WidgetStateProperty.all(resolvedScrollbarColor),
        // These *exactly* match macOS TextEdit & Safari on 25-06-30, 15" MBP.
        crossAxisMargin: crossAxisMargin,
        mainAxisMargin: mainAxisMargin,
        thickness: WidgetStatePropertyAll(7),
      ),
      [resolvedScrollbarColor, crossAxisMargin, mainAxisMargin],
    );

    return ScrollbarTheme(
      data: scrollbarThemeData,
      child: isolateScrollbarLayer
          ? ScrollConfiguration(
              behavior: _IsolatedScrollBehavior(
                ScrollConfiguration.of(context),
              ),
              child: child,
            )
          : child,
    );
  }
}

/// The inherited behavior, with an [IsolatedScrollbar] for vertical
/// scrollables on desktop. Like the app's behavior, it installs the deferred
/// scrollable selection delegate around that scrollbar.
class _IsolatedScrollBehavior implements ScrollBehavior {
  const _IsolatedScrollBehavior(this.delegate);

  final ScrollBehavior delegate;

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (axisDirectionToAxis(details.direction) == .vertical &&
        details.controller != null) {
      switch (getPlatform(context)) {
        case .macOS:
        case .windows:
        case .linux:
          return buildDeferredScrollableSelection(
            context,
            IsolatedScrollbar(controller: details.controller!, child: child),
          );
        case .android:
        case .iOS:
        case .fuchsia:
          break;
      }
    }
    return delegate.buildScrollbar(context, child, details);
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => delegate.buildOverscrollIndicator(context, child, details);

  @override
  Set<PointerDeviceKind> get dragDevices => delegate.dragDevices;

  @override
  Set<LogicalKeyboardKey> get pointerAxisModifiers =>
      delegate.pointerAxisModifiers;

  @override
  MultitouchDragStrategy getMultitouchDragStrategy(BuildContext context) =>
      delegate.getMultitouchDragStrategy(context);

  @override
  TargetPlatform getPlatform(BuildContext context) =>
      delegate.getPlatform(context);

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      delegate.getScrollPhysics(context);

  @override
  GestureVelocityTrackerBuilder velocityTrackerBuilder(BuildContext context) =>
      delegate.velocityTrackerBuilder(context);

  @override
  ScrollViewKeyboardDismissBehavior getKeyboardDismissBehavior(
    BuildContext context,
  ) => delegate.getKeyboardDismissBehavior(context);

  // Copies (e.g. scrollbars: false for nested scrollables) drop the isolated
  // scrollbar and keep the inherited behavior's own copy semantics.
  @override
  // ignore: avoid-incomplete-copy-with
  ScrollBehavior copyWith({
    bool? scrollbars,
    bool? overscroll,
    Set<PointerDeviceKind>? dragDevices,
    MultitouchDragStrategy? multitouchDragStrategy,
    Set<LogicalKeyboardKey>? pointerAxisModifiers,
    ScrollPhysics? physics,
    TargetPlatform? platform,
    ScrollViewKeyboardDismissBehavior? keyboardDismissBehavior,
  }) => delegate.copyWith(
    scrollbars: scrollbars,
    overscroll: overscroll,
    dragDevices: dragDevices,
    multitouchDragStrategy: multitouchDragStrategy,
    pointerAxisModifiers: pointerAxisModifiers,
    physics: physics,
    platform: platform,
    keyboardDismissBehavior: keyboardDismissBehavior,
  );

  @override
  bool shouldNotify(covariant ScrollBehavior oldDelegate) =>
      oldDelegate is! _IsolatedScrollBehavior ||
      oldDelegate.delegate.runtimeType != delegate.runtimeType ||
      delegate.shouldNotify(oldDelegate.delegate);
}
