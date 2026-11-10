import 'package:flutter/services.dart';
import 'package:monet_ui/contrast/brightness_of_color.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/monet_theme_data.dart';
import 'package:pixel_snap_fork/material.dart';

/// Describes the wallpaper behind the app's header, for headers and app bars.
///
/// Without a provider, Monet widgets assume no wallpaper.
class MonetWallpaperHeader extends InheritedWidget {
  const MonetWallpaperHeader({
    super.key,
    required this.isWallpaperShowing,
    required this.themeData,
    required this.brightness,
    required super.child,
  });

  /// Whether a wallpaper is visible behind the app.
  final bool isWallpaperShowing;

  /// The theme for content drawn over the wallpaper's header area.
  final MonetThemeData themeData;

  /// The brightness of the wallpaper's header area.
  final Brightness brightness;

  static MonetWallpaperHeader? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MonetWallpaperHeader>();

  /// The status bar brightness behind a header.
  ///
  /// Uses the wallpaper when [isScreenBackgroundWallpaper] and a wallpaper
  /// header is provided. Otherwise uses [monetThemeData], or the ambient theme.
  static Brightness statusBarBrightnessOf(
    BuildContext context, {
    required bool isScreenBackgroundWallpaper,
    MonetThemeData? monetThemeData,
  }) {
    final header = isScreenBackgroundWallpaper ? maybeOf(context) : null;
    if (header != null) return header.brightness;
    final theme = monetThemeData ?? MonetTheme.of(context).monetThemeData;
    return brightnessOfColor(theme.primary.background);
  }

  @override
  bool updateShouldNotify(MonetWallpaperHeader oldWidget) =>
      isWallpaperShowing != oldWidget.isWallpaperShowing ||
      themeData != oldWidget.themeData ||
      brightness != oldWidget.brightness;
}

/// Transparent system bars with icons that contrast with [brightness].
SystemUiOverlayStyle systemUiOverlayStyleFor(Brightness brightness) {
  final inverse = brightness == .dark ? Brightness.light : Brightness.dark;
  return SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: inverse,
    systemNavigationBarContrastEnforced: false,
    statusBarColor: Colors.transparent,
    statusBarBrightness: brightness,
    statusBarIconBrightness: inverse,
  );
}
