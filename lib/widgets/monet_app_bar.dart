// ignore_for_file: prefer-single-widget-per-file

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:monet_ui/theming/monet_paint_colors.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/monet_theme_data.dart';
import 'package:monet_ui/util/blur_radius.dart';
import 'package:monet_ui/util/text_controller_update_text.dart';
import 'package:monet_ui/widgets/h4.dart';
import 'package:monet_ui/widgets/h6.dart';
import 'package:monet_ui/widgets/header_paint_colors.dart';
import 'package:monet_ui/widgets/monet_app_bar_metrics.dart';
import 'package:monet_ui/widgets/monet_back_button.dart';
import 'package:monet_ui/widgets/monet_handedness.dart';
import 'package:monet_ui/widgets/monet_rich_text.dart';
import 'package:monet_ui/widgets/monet_screen_size.dart';
import 'package:monet_ui/widgets/monet_wallpaper_header.dart';
import 'package:monet_ui/widgets/padding.dart';
import 'package:monet_ui/widgets/screen_breakpoints.dart';
import 'package:monet_ui/widgets/title_text_field.dart';
import 'package:pixel_snap_fork/material.dart';

export 'package:monet_ui/widgets/monet_app_bar_metrics.dart';

class MonetAppBarTitleOnly extends HookWidget implements PreferredSizeWidget {
  final bool forceMaterialTransparency;
  final String title;
  final List<Widget>? actions;
  final Color? textColor;
  final List<Shadow>? shadows;

  /// Explicit palette roles for wallpaper-derived titles. If absent, default
  /// titles bind the nearest primary palette; explicit color/shadow overrides
  /// retain their static behavior.
  final HeaderPaintColors? titlePaintColors;
  final bool isScreenBackgroundWallpaper;
  final TextStyle? textStyle;
  final Widget? leading;
  final VoidCallback? onBackPressed;

  /// Theme for the title row and status bar, if it differs from the
  /// surrounding theme.
  final MonetThemeData? monetThemeData;

  const MonetAppBarTitleOnly(
    this.title, {
    super.key,
    this.forceMaterialTransparency = false,
    required this.isScreenBackgroundWallpaper,
    this.actions = const [],
    this.textColor,
    this.shadows,
    this.titlePaintColors,
    this.textStyle,
    this.leading,
    this.onBackPressed,
    this.monetThemeData,
  });

  @override
  Widget build(BuildContext context) {
    final defaultPaint = useHeaderPaintColors(
      context,
      enabled: titlePaintColors == null && textColor == null && shadows == null,
      shadowsForColor: headerProtectionShadows,
    );
    final paint = titlePaintColors ?? defaultPaint;
    final logicalTheme =
        paint?.themeOverride ??
        (paint == null ? null : MonetPaintColorsScope.maybeOf(context)?.target);
    var style = H4.style(context);
    if (textStyle != null) {
      style = style.merge(textStyle);
    }
    if (textColor != null || shadows != null) {
      if (textColor != null && shadows != null) {
        style = style.copyWith(shadows: shadows, color: textColor);
      } else if (textColor != null) {
        style = style.copyWith(color: textColor);
      } else if (shadows != null) {
        style = style.copyWith(shadows: shadows);
      }
    } else {
      style = style.copyWith(
        shadows:
            paint?.readShadows() ??
            headerProtectionShadows(MonetTheme.of(context).primary.background),
      );
    }
    final hand = MonetHandedness.of(context);
    final actionsConcrete = spacedAppBarActions(actions ?? [], hand: hand);
    final isExtraWide = MonetScreenSize.isAtLeastWide(
      context,
      ScreenBreakpoints.maxScreenWidth,
    );

    // One line with an ellipsis, as AppBar's DefaultTextStyle lays out Text.
    final titleText = MonetRichText(
      text: title,
      textStyle: style.merge(boldTextStyleOf(context)),
      paintColorListenable: paint?.binding,
      paintColor:
          titlePaintColors != null ||
              (textColor == null &&
                  textStyle?.color == null &&
                  textStyle?.foreground == null)
          ? paint?.readTextColor
          : null,
      paintStrokeColor: paint?.readStrokeColor,
      paintShadows: paint?.readShadows,
      strokeColor:
          shadows?.firstOrNull?.color ?? style.shadows?.firstOrNull?.color,
      textScaler: MediaQuery.textScalerOf(context),
      softWrap: false,
      centerCapHeight: false,
    );

    final backButton = MonetBackButton(
      isScreenBackgroundWallpaper: isScreenBackgroundWallpaper,
      onPressed: onBackPressed,
    );

    return AppBar(
      systemOverlayStyle: systemUiOverlayStyleFor(
        MonetWallpaperHeader.statusBarBrightnessOf(
          context,
          isScreenBackgroundWallpaper: isScreenBackgroundWallpaper,
          monetThemeData: monetThemeData ?? logicalTheme,
        ),
      ),
      automaticallyImplyLeading: false,
      // Balance out width of back button.
      // See app_bar.dart _kLeadingWidth for why kToolbarHeight is used.
      actions: [SizedBox(width: _leadingWidthOf(context), height: 1)],
      forceMaterialTransparency: forceMaterialTransparency,
      centerTitle: false,
      titleSpacing: 0,
      leadingWidth: _leadingWidthOf(context),
      leading: backButton,
      title: _withTheme(
        monetThemeData,
        ScreenConstrained(
          child: Center(
            child: MonetAppBarMetrics.iconTheme(
              context,
              child: Row(
                crossAxisAlignment: .center,
                children: [
                  if (hand == .left) ...actionsConcrete,
                  if (leading != null) ...[leading!, const HorizontalPadding()],
                  AnimatedSize(
                    duration: kThemeAnimationDuration,
                    child: (leading == null && isExtraWide)
                        ? const HorizontalPadding()
                        : const SizedBox(),
                  ),
                  Flexible(child: titleText),
                  if (hand == .right) ...actionsConcrete,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => AppBar().preferredSize;
}

Widget _withTheme(MonetThemeData? data, Widget child) =>
    data == null ? child : MonetTheme(monetThemeData: data, child: child);

class MonetAppBarEmpty extends HookWidget implements PreferredSizeWidget {
  final bool forceMaterialTransparency;
  final bool isScreenBackgroundWallpaper;
  final bool hasBackButton;

  const MonetAppBarEmpty({
    super.key,
    this.forceMaterialTransparency = false,
    required this.isScreenBackgroundWallpaper,
    // TODOLONG: this was set up as implicitly true, because until now, callers
    // got it. After adding it to OobeNavigator to avoid being under the iOS
    // status bar, we now need to be able to set it to false. Ideally, it was
    // sensitive to *if it could go back* -- ex. when used in the OOBE navigator
    // tapping it doesn't do anything anyway.
    this.hasBackButton = true,
  });
  @override
  Widget build(BuildContext context) {
    return AppBar(
      forceMaterialTransparency: forceMaterialTransparency,
      titleSpacing: 0,
      leadingWidth: _leadingWidthOf(context),
      leading: hasBackButton
          ? MonetBackButton(
              isScreenBackgroundWallpaper: isScreenBackgroundWallpaper,
            )
          : const SizedBox.shrink(),
      title: const SizedBox.shrink(),
    );
  }

  @override
  Size get preferredSize => AppBar().preferredSize;
}

class MonetAppBarEditableTitle extends HookWidget
    implements PreferredSizeWidget {
  final bool forceMaterialTransparency;
  final String label;
  final String initialLabel;
  final Key? textFieldKey;
  final Function(String) onTextFieldChanged;
  final TabBar? bottomTabBar;
  final List<Widget>? actions;
  final Color? textColor;
  final List<Shadow>? shadows;
  final bool isScreenBackgroundWallpaper;
  final MonetThemeData? monetThemeData;
  final Widget? leading;
  final bool isForUntitledChatThatWillBeLabelled;
  final Color? cursorColor;
  final VoidCallback? onBackPressed;

  const MonetAppBarEditableTitle({
    super.key,
    required this.label,
    required this.initialLabel,
    required this.isForUntitledChatThatWillBeLabelled,
    required this.onTextFieldChanged,
    this.bottomTabBar,
    this.monetThemeData,
    this.forceMaterialTransparency = false,
    required this.isScreenBackgroundWallpaper,
    this.leading,
    this.textFieldKey,
    this.actions,
    this.textColor,
    this.cursorColor,
    this.shadows,
    this.onBackPressed,
  });

  @override
  Widget build(BuildContext context) {
    final initialValue = label.trim().isEmpty ? initialLabel : label;
    final controller = useTextEditingController(text: initialValue);
    useEffect(
      // ignore: function-always-returns-null
      () {
        if (controller.text != label) {
          controller.safelyUpdateText(label);
        }
        return null;
      },
      [label],
    );

    useEffect(() {
      listener() {
        // This avoids an interesting issue only reproducible in testing.
        // 1. Edit conversation title.
        // 2. useEffect that updates TextEditingController notices and starts
        // rebuild.
        // 3. This useEffect sees TextEditingController has changed and upserts
        // conversation.
        // 4. This causes a rebuild during build, throwing an exception in
        // Riverpod.
        if (controller.text == label) {
          return;
        }
        // This avoids issue with triggering rebuild during build.
        Future.microtask(() {
          onTextFieldChanged(controller.text);
        });
      }

      controller.addListener(listener);
      return () {
        controller.removeListener(listener);
      };
    });
    var style = H6.style(context);
    var cursorColor = this.cursorColor ?? MonetTheme.of(context).primary.fill;
    if (textColor != null || shadows != null) {
      if (textColor != null && shadows != null) {
        style = style.copyWith(shadows: shadows, color: textColor);
      } else if (textColor != null) {
        style = style.copyWith(color: textColor);
      } else if (shadows != null) {
        style = style.copyWith(shadows: shadows);
      }
    } else {
      final monet = MonetTheme.of(context);
      style = style.copyWith(
        shadows: headerProtectionShadows(monet.primary.background),
      );
    }
    final hand = MonetHandedness.of(context);
    final actionsConcrete = spacedAppBarActions(actions ?? [], hand: hand);
    // Determine status bar brightness based on whether we're showing wallpaper or app theme
    final isExtraWide = MonetScreenSize.isAtLeastWide(
      context,
      ScreenBreakpoints.maxScreenWidth,
    );
    return AppBar(
      systemOverlayStyle: systemUiOverlayStyleFor(
        MonetWallpaperHeader.statusBarBrightnessOf(
          context,
          isScreenBackgroundWallpaper: isScreenBackgroundWallpaper,
          monetThemeData: monetThemeData,
        ),
      ),
      forceMaterialTransparency: forceMaterialTransparency,
      titleSpacing: 0,
      leadingWidth: _leadingWidthOf(context),
      leading: MonetBackButton(
        // Ensure back button uses wallpaper when:
        // - [isScreenBackgroundWallpaper] is true, covering the case when
        //   conversation screen passes true/false based on how far the chat
        //   is scrolled.
        // - when the back button is on a wide screen, on an island, i.e.
        //   to the left of the constrained conversation screen. Thus, it will
        //   never have a background of the theme surface color.
        isScreenBackgroundWallpaper: isScreenBackgroundWallpaper || isExtraWide,
        onPressed: onBackPressed,
      ),
      bottom: bottomTabBar,
      title: MonetTheme(
        monetThemeData: monetThemeData ?? MonetTheme.of(context).monetThemeData,
        child: ScreenConstrained(
          child: Center(
            child: MonetAppBarMetrics.iconTheme(
              context,
              child: Row(
                crossAxisAlignment: .center,
                children: [
                  if (hand == .left) ...actionsConcrete,
                  if (leading != null) ...[leading!, HorizontalPadding()],
                  AnimatedSize(
                    duration: kThemeAnimationDuration,
                    child: (leading == null && isExtraWide)
                        ? HorizontalPadding()
                        : SizedBox(),
                  ),
                  Flexible(
                    child: AnimatedSwitcher(
                      duration: kThemeAnimationDuration,
                      child: isForUntitledChatThatWillBeLabelled
                          ? SizedBox()
                          : TitleTextField(
                              cursorColor: cursorColor,
                              strokeColor: style.shadows?.firstOrNull?.color,
                              key: textFieldKey,
                              controller: controller,
                              style: style,
                            ),
                    ),
                  ),
                  if (hand == .right) ...actionsConcrete,
                ],
              ),
            ),
          ),
        ),
      ),
      // Balance out width of back button.
      // See app_bar.dart _kLeadingWidth for why kToolbarHeight is used.
      actions: [SizedBox(width: _leadingWidthOf(context), height: 1)],
    );
  }

  @override
  Size get preferredSize {
    return AppBar(bottom: bottomTabBar).preferredSize;
  }
}

/// Puts a [HorizontalPadding] between [actions] and the title, and one
/// between each pair of actions.
///
/// With right-handed layout the actions follow the title, so the padding
/// comes first: `[pad, a, pad, b]`. With left-handed layout the actions come
/// before the title, so the padding comes last: `[a, pad, b, pad]`.
/// No actions gives an empty list.
@visibleForTesting
List<Widget> spacedAppBarActions(List<Widget> actions, {required Hand hand}) {
  if (actions.isEmpty) return const [];
  final spaced = <Widget>[];
  for (final action in actions) {
    if (hand == .right || spaced.isNotEmpty) {
      spaced.add(const HorizontalPadding());
    }
    spaced.add(action);
  }
  if (hand == .left) spaced.add(const HorizontalPadding());
  return spaced;
}

double _toolbarHeightOf(BuildContext context) =>
    AppBarTheme.of(context).toolbarHeight ?? kToolbarHeight;

double _leadingWidthOf(BuildContext context) =>
    AppBarTheme.of(context).leadingWidth ?? _toolbarHeightOf(context);
