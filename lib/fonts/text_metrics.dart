import 'package:flutter/painting.dart';
import 'package:monet_ui/fonts/font_height_equalizer.g.dart';
import 'package:monet_ui/fonts/line_height.dart';

/// Helpers that size and place text from the font tables.
///
/// They read only font facts, so every app of monet_ui can use them
/// (docs/design/ADR_fonts_in_monet_ui.md in telosnex, D4).

/// [size] rounded to 1/64 px, a difference no one can see.
///
/// Snap a computed (scaled or matched) font size. At other fractional sizes,
/// FreeType (Linux) rounds glyph advances to 1/64 px and CoreText (macOS)
/// does not, so the same text had different widths on each platform.
double snapFontSize(double size) => (size * 64).roundToDouble() / 64;

/// [style] with the line height of its own font family, as createTextTheme
/// sets it for its text styles (docs/design/ADR_font_line_height.md in
/// telosnex).
///
/// A style that sets a different font family than the theme must set its own
/// height. Otherwise it inherits the height of the theme font from
/// DefaultTextStyle, sized for another font.
///
/// [fit] is [MonetThemeData.compactLineHeights]: true for
/// [lineHeightForFontFamily] at [clearance], false for the font's own box.
TextStyle withFontLineHeight(
  TextStyle style, {
  required bool fit,
  required double clearance,
}) {
  final height = fit
      ? lineHeightForFontFamily(style.fontFamily, clearance: clearance)
      : naturalLineHeightForFontFamily(style.fontFamily);
  if (height == null) return style;
  return style.copyWith(
    height: height,
    leadingDistribution: TextLeadingDistribution.even,
  );
}

/// Height of one line of [style] as laid out: the font size, the text
/// scale, and the line height the theme sets per font.
///
/// Use it to size a box that holds one line of text. 1.5 is only for styles
/// with no height.
double lineHeightForTextScaler(TextScaler textScaler, TextStyle style) =>
    textScaler.scale(style.fontSize!) * (style.height ?? 1.5);

/// Distance to move a line down so its capitals are centred in the line.
///
/// [lineHeight] and [baseline] are measured from the top of the line.
/// Negative moves the line up.
///
/// Returns zero when [capHeight] is not positive or exceeds [ascent]: that
/// measurement is not a cap band, for example in fonts that draw guide lines.
///
/// Across the Google Fonts in the tables, the shift reaches 0.44 em
/// (Linefont) and is over 0.1 em for 261 fonts. A widget that applies it
/// must leave room for it.
double capHeightCentringShift({
  required double ascent,
  required double lineHeight,
  required double baseline,
  required double capHeight,
}) {
  if (capHeight <= 0 || capHeight > ascent) return 0;
  return lineHeight / 2 - (baseline - capHeight / 2);
}

/// Distance to move one line of [style] down so its capitals are centred in
/// its line box, rounded to a device pixel. Negative moves it up.
///
/// For text that a cap-centring text widget cannot draw, such as a
/// TextField and its hint, so it lines up with an icon beside it. Measured
/// from the loaded font, so it is right for whatever copy of the font the
/// app has. Zero for fonts without a measured cap height.
///
/// [mixedCase] centres halfway between the capitals' centre and the
/// lowercase centre, where mixed-case text such as 'Enter web address' looks
/// centred. Matters most in fonts with tall lowercase, such as Tenali
/// Ramakrishna. Falls back to the capitals for fonts without a measured
/// x-height.
double capHeightShiftForTextStyle(
  TextStyle style, {
  required TextScaler textScaler,
  required double devicePixelRatio,
  bool mixedCase = false,
}) {
  final capHeightEm = rasterCapHeightEmForFontFamily(style.fontFamily);
  if (capHeightEm == null) return 0;
  final xHeightEm = mixedCase
      ? rasterXHeightEmForFontFamily(style.fontFamily)
      : null;
  // Centring a band of height h puts its centre at baseline - h / 2, so the
  // average of the two heights centres the midpoint of the two centres.
  final centredHeightEm = xHeightEm == null
      ? capHeightEm
      : (capHeightEm + xHeightEm) / 2;
  final painter = TextPainter(
    text: TextSpan(text: 'H', style: style),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();
  try {
    final line = painter.computeLineMetrics().first;
    // Glyphs are painted at the baseline rounded to a whole logical pixel.
    final paintedBaseline =
        (painter.computeDistanceToActualBaseline(TextBaseline.alphabetic) + 0.5)
            .floorToDouble();
    final shift = capHeightCentringShift(
      ascent: line.unscaledAscent,
      lineHeight: line.height,
      baseline: paintedBaseline,
      capHeight:
          centredHeightEm *
          textScaler.scale(style.fontSize ?? kDefaultFontSize),
    );
    return (shift * devicePixelRatio).roundToDouble() / devicePixelRatio;
  } finally {
    painter.dispose();
  }
}
