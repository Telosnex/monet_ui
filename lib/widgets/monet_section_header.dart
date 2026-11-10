import 'package:monet_ui/widgets/harmony_icon.dart';
import 'package:monet_ui/widgets/icon_size.dart';
import 'package:monet_ui/widgets/monet_icon.dart';
import 'package:monet_ui/widgets/monet_rich_text.dart';
import 'package:monet_ui/widgets/padding.dart';
import 'package:monet_ui/widgets/settings_row.dart';
import 'package:pixel_snap_fork/material.dart';

/// A section title with an optional icon and subtitle.
///
/// Explicit harmony coordinates decorate only this header. An inherited
/// [HarmonyIconSlot] supports existing AI-screen expansion headers.
class MonetSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final TextStyle? textStyle;
  final int? harmonyIndex;
  final int? harmonyCount;

  const MonetSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.textStyle,
    this.harmonyIndex,
    this.harmonyCount,
  }) : assert((harmonyIndex == null) == (harmonyCount == null));

  @override
  Widget build(BuildContext context) {
    final baseStyle = textStyle ?? SettingsRow.labelTextStyle(context);
    // Follow the platform bold-text setting, as Text does.
    final style = baseStyle.merge(boldTextStyleOf(context));
    final icon = this.icon;
    final iconSize = icon == null ? null : _iconSize(context, baseStyle);
    // The icon is the title's leading child, so the title's capitals are
    // centred on it, not its line box. The icon keeps its square box, so
    // titles in a column of headers start at the same x whatever the icon.
    final label = MonetRichText(
      text: title,
      textStyle: style,
      textScaler: MediaQuery.textScalerOf(context),
      leading: [
        if (icon != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              end: HorizontalPadding.amount,
            ),
            child: _icon(context, icon, iconSize!, baseStyle.color),
          ),
      ],
    );
    final subtitle = this.subtitle;
    return Padding(
      padding: const .only(right: HorizontalPadding.amount),
      child: subtitle == null
          ? label
          : Column(
              mainAxisSize: .min,
              crossAxisAlignment: .start,
              children: [
                label,
                Padding(
                  // Under the title, not the icon.
                  padding: EdgeInsetsDirectional.only(
                    start: iconSize == null
                        ? 0
                        : iconSize + HorizontalPadding.amount,
                  ),
                  child: Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
    );
  }

  /// The width and height of the icon's box. MonetIcon snaps an explicit
  /// size to whole device pixels; this does too, so the subtitle lines up.
  double _iconSize(BuildContext context, TextStyle style) {
    final size =
        iconSizeForTextStyleOrNull(style) ??
        (_harmony(context) != null
            ? _kDefaultHarmonyIconSize
            : (IconTheme.of(context).size ?? kDefaultFontSize));
    return size.pixelSnap(PixelSnap.of(context));
  }

  _HarmonyCoordinates? _harmony(BuildContext context) {
    final slot = harmonyIndex == null ? HarmonyIconSlot.maybeOf(context) : null;
    final index = harmonyIndex ?? slot?.index;
    final count = harmonyCount ?? slot?.count;
    return index == null || count == null
        ? null
        : _HarmonyCoordinates(index, count);
  }

  Widget _icon(BuildContext context, IconData icon, double size, Color? color) {
    final harmony = _harmony(context);
    if (harmony == null) return MonetIcon(icon, size: size, color: color);
    final _HarmonyCoordinates(:index, :count) = harmony;
    return HarmonyIcon(icon: icon, iconSize: size, index: index, count: count);
  }
}

const _kDefaultHarmonyIconSize = 14.0;

class const _HarmonyCoordinates(final int index, final int count);
