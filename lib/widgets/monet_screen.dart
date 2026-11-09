import 'dart:math' as math;

import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/widgets/inset_boxes.dart';
import 'package:monet_ui/widgets/media_query_without_insets.dart';
import 'package:monet_ui/widgets/monet_scaffold.dart';
import 'package:monet_ui/widgets/monet_scrollbar.dart';
import 'package:monet_ui/widgets/monet_wallpaper_scrollbar_color.dart';
import 'package:monet_ui/widgets/padding.dart';
import 'package:monet_ui/widgets/trackpad_dismiss_gesture_detector.dart';
import 'package:pixel_snap_fork/material.dart';

/// The standard Telosnex screen chrome, replacing the historical 6-layer
/// per-screen sandwich:
///
/// ```dart
/// TrackpadDismissGestureDetector(
///   child: Scaffold(
///     appBar: appBar,
///     extendBodyBehindAppBar: true,
///     body: MediaQuery(
///       data: /* zeroed insets */,
///       child: LayoutBuilder(
///         builder: (context, constraints) => MonetScrollbar(
///           child: ListView2(
///             padding: listViewInsetsCalculator(outerContext, constraints, appBar),
///             ...
/// ```
///
/// With [MonetScreen] + `MonetListView` this becomes:
///
/// ```dart
/// MonetScreen(
///   appBar: appBar,
///   builder: (context, contentPadding) => MonetListView(
///     padding: contentPadding,
///     children: [...],
///   ),
/// )
/// ```
///
/// What it does, top to bottom:
/// - [TrackpadDismissGestureDetector]: horizontal-swipe back navigation.
/// - [MonetScaffold]: Material surface + pinned app bar, *without* Material
///   [Scaffold]'s `_BodyBuilder` [LayoutBuilder] (which turns descendant
///   animation rebuilds into layout-phase rebuild scopes).
/// - Zeroed [MediaQuery] insets: the body extends behind the app bar and
///   system bars; safe areas are handled once, via [contentInsetsOf], rather
///   than re-applied piecemeal by descendants.
/// - [MonetScrollbar]: scrollbar theming at the true screen edge.
/// - [builder] receives `contentPadding` — the safe-area + app-bar +
///   [ScreenPadding] gutter — to pass to a scrollable's `padding:` so content
///   is inset *inside* the viewport while the scrollbar stays at the edge.
///
/// Width constraining/centering is intentionally *not* part of the padding:
/// pair this with `MonetListView`, which centers its sliver at
/// [ScreenConstrained.maxWidth] during layout (no [LayoutBuilder] needed).
///
/// There is no notion of a screen-level [LayoutBuilder] here on purpose; if a
/// body genuinely needs constraints, add one locally around the part that
/// needs it.
class MonetScreen extends StatelessWidget {
  const MonetScreen({
    super.key,
    this.appBar,
    required this.builder,
    this.hasWallpaperBackground = false,
    this.backgroundColor,
    this.scrollbarColor,
    this.trackpadDismissEnabled = true,
  });

  /// Pinned to the top, body extends behind it. `contentPadding.top` reserves
  /// the theme-resolved app-bar height plus `viewPadding.top` inside scrollables.
  final PreferredSizeWidget? appBar;

  /// Builds the body. `contentPadding` is the resolved safe-area/app-bar/
  /// gutter inset; pass it to `MonetListView.padding` (or apply it manually
  /// for non-list bodies). The `context` already has zeroed MediaQuery insets.
  final Widget Function(BuildContext context, EdgeInsets contentPadding)
  builder;

  /// Whether the screen sits on top of the app wallpaper.
  ///
  /// When true, does "the normal wallpaper thing": [backgroundColor] defaults
  /// to transparent (the wallpaper underneath shows through) and
  /// [scrollbarColor] defaults to the color from
  /// [MonetWallpaperScrollbarColor] (null, i.e. the theme color, when no
  /// wallpaper is showing or no app provides it).
  final bool hasWallpaperBackground;

  /// Overrides the default background: `MonetTheme.primary.background`, or
  /// transparent when [hasWallpaperBackground].
  final Color? backgroundColor;

  /// Overrides the scrollbar color otherwise derived from
  /// [hasWallpaperBackground]; forwarded to [MonetScrollbar].
  final Color? scrollbarColor;

  /// Whether horizontal trackpad swipes dismiss the screen.
  final bool trackpadDismissEnabled;

  /// The padding scrollable content needs so it clears the app bar, system
  /// UI (status bar, gesture nav, display cutouts, keyboard), and keeps the
  /// [ScreenPadding] horizontal gutter.
  ///
  /// Equivalent to `listViewInsetsCalculator` minus the width-centering term,
  /// which `MonetListView` now performs at layout time. Must be computed from
  /// a context *outside* the zeroed [MediaQuery] (i.e. the context passed to
  /// [build], not to [builder]) — [MonetScreen] does this itself.
  static EdgeInsets contentInsetsOf(
    BuildContext context, {
    PreferredSizeWidget? appBar,
  }) {
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    double side(double base, double padding, double inset) {
      return math.max(base, math.max(padding, inset));
    }

    return EdgeInsets.only(
      left: side(ScreenPadding.amount, viewPadding.left, viewInsets.left),
      right: side(ScreenPadding.amount, viewPadding.right, viewInsets.right),
      top:
          viewPadding.top +
          (appBar == null
              ? 0
              : AppBar.preferredHeightFor(context, appBar.preferredSize)),
      bottom: math.max(
        BottomPaddingSizedBox.getBottomPadding(context),
        viewInsets.bottom,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contentPadding = contentInsetsOf(context, appBar: appBar);
    final resolvedBackgroundColor =
        backgroundColor ??
        (hasWallpaperBackground
            ? Colors.transparent
            : MonetTheme.of(context).primary.background);
    Widget screen(Color? resolvedScrollbarColor) => MonetScaffold(
      appBar: appBar,
      backgroundColor: resolvedBackgroundColor,
      body: MediaQueryWithoutInsets(
        child: MonetScrollbar(
          scrollbarColor: resolvedScrollbarColor,
          child: Builder(
            builder: (innerContext) => builder(innerContext, contentPadding),
          ),
        ),
      ),
    );

    // Gated on the flag so opaque screens don't depend on the wallpaper color.
    final wallpaperColorBuilder =
        scrollbarColor == null && hasWallpaperBackground
        ? MonetWallpaperScrollbarColor.maybeOf(context)
        : null;
    final scaffold = wallpaperColorBuilder == null
        ? screen(scrollbarColor)
        : wallpaperColorBuilder(context, (_, color) => screen(color));

    if (!trackpadDismissEnabled) return scaffold;
    return TrackpadDismissGestureDetector(child: scaffold);
  }
}
