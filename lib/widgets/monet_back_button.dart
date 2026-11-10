import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:monet_ui/theming/button_style.dart';
import 'package:monet_ui/theming/monet_theme_data.dart';
import 'package:monet_ui/util/blur_radius.dart';
import 'package:monet_ui/widgets/header_paint_colors.dart';
import 'package:monet_ui/widgets/icon_size.dart';
import 'package:monet_ui/widgets/monet_app_bar_metrics.dart';
import 'package:monet_ui/widgets/monet_icon.dart';
import 'package:monet_ui/widgets/monet_icons.dart';
import 'package:monet_ui/widgets/monet_rich_text.dart';
import 'package:monet_ui/widgets/monet_wallpaper_header.dart';
import 'package:monet_ui/widgets/padding.dart';
import 'package:pixel_snap_fork/material.dart';

class ModBackConfig {
  final TextStyle textStyle;

  const ModBackConfig({required this.textStyle});
}

class MonetBackButton extends HookWidget {
  /// Key of the button inside, for tests that tap it.
  static const buttonKey = ValueKey('backButton');

  final bool isScreenBackgroundWallpaper;
  final bool showText;
  final VoidCallback? onPressed;
  final ModBackConfig? modConfig;

  const MonetBackButton({
    super.key,
    required this.isScreenBackgroundWallpaper,
    this.showText = false,
    this.modConfig,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final header = isScreenBackgroundWallpaper
        ? MonetWallpaperHeader.maybeOf(context)
        : null;
    final isWallpaperShowing = header?.isWallpaperShowing ?? false;
    final monetThemeData = isWallpaperShowing && modConfig == null
        ? header!.themeData
        : headerThemeEndpointOf(context);
    final paint = useHeaderPaintColors(
      context,
      palette: isWallpaperShowing && modConfig == null
          ? monetThemeData.primary
          : null,
      themePalette: isWallpaperShowing ? .primary : .tertiary,
      foreground: isWallpaperShowing ? .colorText : .text,
      onColorSurface: isWallpaperShowing,
      shadowsForColor: headerProtectionShadows,
    );
    final iconColor =
        paint?.readTextColor() ??
        (isWallpaperShowing
            ? monetThemeData.primary.colorText
            : monetThemeData.tertiary.text);
    final iconShadows = isWallpaperShowing
        ? headerProtectionShadows(monetThemeData.primary.color)
        : headerProtectionShadows(monetThemeData.tertiary.background);
    var style = iconButtonStyle(
      isWallpaperShowing ? monetThemeData.primary : monetThemeData.tertiary,
    );
    if (modConfig != null) {
      style = style.copyWith(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        minimumSize: const WidgetStatePropertyAll(Size.zero),
        tapTargetSize: .shrinkWrap,
      );
    }
    final button = IconButton(
      visualDensity: .compact,
      alignment: Alignment.centerLeft,
      style: style,
      padding: EdgeInsets.zero,
      key: buttonKey,
      onPressed:
          onPressed ??
          () {
            Navigator.maybeOf(context)?.maybePop();
          },
      icon: showText
          ? SizedBox(
              child: Row(
                crossAxisAlignment: .center,
                mainAxisSize: .min,
                children: [
                  MonetIcon(
                    _iconData(),
                    color: iconColor,
                    size:
                        iconSizeForTextStyleOrNull(modConfig?.textStyle) ??
                        MonetAppBarMetrics.iconSizeOf(context),
                    shadows: iconShadows,
                    strokeColor: iconShadows.first.color,
                    paintColorListenable: paint?.binding,
                    paintColor: paint?.readTextColor,
                    paintStrokeColor: paint?.readStrokeColor,
                    paintShadows: paint?.readShadows,
                  ),
                  HorizontalPadding(),
                  MonetRichText(
                    text: 'Back',
                    paintColorListenable: paint?.binding,
                    paintColor: paint?.readTextColor,
                    paintStrokeColor: paint?.readStrokeColor,
                    paintShadows: paint?.readShadows,
                    strokeColor: iconShadows.first.color,
                    textStyle:
                        (modConfig?.textStyle ??
                                Theme.of(context).textTheme.labelLarge)!
                            .copyWith(shadows: iconShadows, color: iconColor)
                            .merge(boldTextStyleOf(context)),
                    textScaler: MediaQuery.textScalerOf(context),
                    ellipsis: '',
                    centerCapHeight: false,
                  ),
                  HorizontalPaddingHalf(),
                ],
              ),
            )
          : MonetIcon(
              _iconData(),
              color: iconColor,
              size:
                  iconSizeForTextStyleOrNull(modConfig?.textStyle) ??
                  MonetAppBarMetrics.iconSizeOf(context),
              shadows: iconShadows,
              strokeColor: iconShadows.first.color,
              paintColorListenable: paint?.binding,
              paintColor: paint?.readTextColor,
              paintStrokeColor: paint?.readStrokeColor,
              paintShadows: paint?.readShadows,
            ),
    );
    if (modConfig != null) {
      // Invisibly pad out the back button action. 26 04 15, It's only ~21 dp at
      // 100% scale. Between that and OS-level touch area dead zones on side of
      // screen, it's a bad experience on, for example, iOS.
      return GestureDetector(
        behavior: .translucent,
        onTap: button.onPressed,
        child: Padding(
          padding: .only(
            right:
                (MonetThemeData.touchSize -
                        iconSizeForTextStyle(modConfig!.textStyle))
                    .clamp(0.0, 500),
          ),
          child: button,
        ),
      );
    }

    if (showText) {
      return Padding(
        padding: const .only(left: HorizontalPadding.amount),
        child: SizedBox(
          height: 0,
          child: Align(alignment: .centerLeft, child: button),
        ),
      );
    }
    return Padding(
      padding: const .only(left: HorizontalPadding.amount),
      child: SizedBox(
        width: AppBarTheme.of(context).toolbarHeight ?? kToolbarHeight,
        height: 0,
        child: Align(alignment: .center, child: button),
      ),
    );
  }

  /// Copied from Flutter's BackButtonIcon widget.
  IconData _iconData() {
    return MonetIcons.back;
  }
}
