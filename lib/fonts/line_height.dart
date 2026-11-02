import 'package:monet_ui/fonts/font_height_equalizer.g.dart';
import 'package:monet_ui/fonts/font_size_adjust.dart';

/// Clearance between adjacent lines, as a fraction of the requested size.
///
/// Extra space beyond the measured A-Z and a-z envelope. Accents,
/// punctuation, and other scripts can extend into this space or beyond it.
/// Increase clearance if adjacent lines overlap. About 1.4 px at 17 px.
const kLineHeightClearance = 0.08;

/// Minimum baseline distance, as a fraction of the requested size.
const kLineHeightFloor = 1.0;

/// TextStyle.height for [fontFamily], or null if the font has no data.
///
/// The height fits the ink of A-Z and a-z, over every weight
/// and style, plus [clearance]. It is at least [kLineHeightFloor]. Both are
/// fractions of the requested size: the font size before
/// [visualHeightScaleForFontFamily] scales it. Thus the same [clearance]
/// adds the same space in pixels in every font; the floor can add more.
///
/// The height can be more or less than the font's own line box. Other
/// scripts can need more room than Latin: an app that shows them turns this
/// off ([MonetThemeData.compactLineHeights]).
///
/// The extra space is split evenly above and below the line. The letters
/// are centred in it only if the font's ascent and descent are centred on
/// its Latin ink: see [patchFontLineMetrics].
///
/// See docs/design/ADR_font_line_height.md in telosnex.
double? lineHeightForFontFamily(
  String? fontFamily, {
  double clearance = kLineHeightClearance,
}) {
  final ink = latinInkForFontFamily(fontFamily);
  if (ink == null) return null;
  final scale = visualHeightScaleForFontFamily(fontFamily!);
  final fitted = ink.$1 + ink.$2 + clearance / scale;
  final floor = kLineHeightFloor / scale;
  return fitted > floor ? fitted : floor;
}

/// The font's own line box (hhea ascent + descent) in em, or null if the
/// font has no Latin ink data.
///
/// For a font whose bytes [patchFontLineMetrics] changed, this height keeps
/// the original line height. The measured A-Z and a-z envelope is centred
/// in it.
double? naturalLineHeightForFontFamily(String? fontFamily) {
  if (latinInkForFontFamily(fontFamily) == null) return null;
  final ascent = ascentEmForFontFamily(fontFamily);
  final descent = descentEmForFontFamily(fontFamily);
  if (ascent == null || descent == null) return null;
  return ascent + descent;
}

/// How far the A-Z and a-z ink of [fontFamily] reaches (above, below) the
/// baseline in em, over every weight and style. Null if it is unknown.
///
/// In the em of the font as it loads ([fontEmScale]).
(double, double)? latinInkForFontFamily(String? fontFamily) {
  if (fontFamily == null) return null;
  final key = normalizeFontFamilyForFontMetrics(fontFamily);
  final above = kLatinInkAboveEmByFontFamily[key];
  final below = kLatinInkBelowEmByFontFamily[key];
  if (above == null || below == null) return null;
  final em = fontEmScale(fontFamily);
  return (above * em, below * em);
}
