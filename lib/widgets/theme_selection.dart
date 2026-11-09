import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/palette.dart';
import 'package:pixel_snap_fork/cupertino.dart';
import 'package:pixel_snap_fork/material.dart';

import 'package:monet_ui/util/lru_cache.dart';

class ThemeSelection extends StatelessWidget {
  static final _dataCache = LruCache<Palette, _ThemeSelectionData>(
    capacity: 96,
  );

  final Widget child;
  final Palette? colors;
  const ThemeSelection({super.key, this.colors, required this.child});

  @override
  Widget build(BuildContext context) {
    final safeColors = colors ?? MonetTheme.of(context).primary;
    // ~40% cache hit rate on window resize on macOS, ~90%+ when theme is stable
    // as judged by entering and exiting chats.
    final cachedData = _dataCache[safeColors];
    final data = cachedData ?? _ThemeSelectionData(safeColors);
    if (cachedData == null) {
      _dataCache[safeColors] = data;
    }

    return CupertinoTheme(
      data: data.cupertinoThemeData,
      child: TextSelectionTheme(
        data: data.textSelectionThemeData,
        child: child,
      ),
    );
  }
}

class _ThemeSelectionData {
  final CupertinoThemeData cupertinoThemeData;
  final TextSelectionThemeData textSelectionThemeData;

  _ThemeSelectionData(Palette colors)
    : cupertinoThemeData = CupertinoThemeData(
        primaryColor: colors.color,
        primaryContrastingColor: colors.colorText,
        selectionHandleColor: colors.fill,
      ),
      textSelectionThemeData = TextSelectionThemeData(
        cursorColor: colors.text,
        selectionHandleColor: colors.text,
        selectionColor: colors.text.withValues(alpha: 0.3),
      );
}
