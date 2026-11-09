import 'package:pixel_snap_fork/material.dart';

/// Builds a subtree with the scrollbar color for screens drawn over a
/// wallpaper. Null uses the theme's scrollbar color.
typedef MonetWallpaperScrollbarColorBuilder = Widget Function(
  BuildContext context,
  Widget Function(BuildContext context, Color? color) builder,
);

/// Supplies the scrollbar color for screens drawn over a wallpaper.
///
/// The theme's scrollbar color is not checked against the wallpaper. An app
/// with a wallpaper provides this once, near the root. [MonetScreen] calls
/// [builder] only when `hasWallpaperBackground` is true, so the color is
/// computed in that screen's context, and only screens on the wallpaper
/// rebuild when it changes.
class MonetWallpaperScrollbarColor extends InheritedWidget {
  const MonetWallpaperScrollbarColor({
    super.key,
    required this.builder,
    required super.child,
  });

  final MonetWallpaperScrollbarColorBuilder builder;

  /// The nearest [builder], or null without a provider.
  static MonetWallpaperScrollbarColorBuilder? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<MonetWallpaperScrollbarColor>()
          ?.builder;

  @override
  bool updateShouldNotify(MonetWallpaperScrollbarColor oldWidget) =>
      builder != oldWidget.builder;
}
