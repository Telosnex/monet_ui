import 'package:monet_ui/fonts/font_height_equalizer.g.dart';

/// The size adjust: a font's letters are made the reference size in its
/// bytes, not in its font size (docs/design/ADR_font_size_adjust.md in
/// telosnex).
///
/// Off by default. [MonetFonts.install] turns it on, and gives the font
/// transform that scales the bytes. The two must agree: with the size adjust
/// on, a font that loads without the transform draws its letters at the
/// requested size, not the reference size.
bool get fontSizeAdjustEnabled => _fontSizeAdjustEnabled;
bool _fontSizeAdjustEnabled = false;

/// Sets [fontSizeAdjustEnabled]. Only [MonetFonts.install] calls it.
void setFontSizeAdjustEnabled(bool enabled) {
  _fontSizeAdjustEnabled = enabled;
}

/// Whether the size adjust scales [fontFamily]'s bytes.
///
/// True when the size adjust is on and the family has Latin ink data (D3),
/// and rounding its unitsPerEm is exact enough (D7). Then the theme gives it
/// the requested font size, and its values in em are scaled by
/// [fontEmScale].
bool isFontSizeAdjusted(String? fontFamily) {
  if (!_fontSizeAdjustEnabled || fontFamily == null) return false;
  final key = normalizeFontFamilyForFontMetrics(fontFamily);
  return kLatinInkAboveEmByFontFamily.containsKey(key) &&
      !kFontSizeAdjustExcludedFontFamilies.contains(key) &&
      rasterVisualHeightScaleForFontFamily(fontFamily) != 1.0;
}

/// The size of the em of [fontFamily] as it loads, in ems of its file.
///
/// [rasterVisualHeightScaleForFontFamily] for a font that the size adjust
/// scales, else 1.0. A value in em from the font tables times this is in the
/// em of the loaded font.
double fontEmScale(String? fontFamily) => isFontSizeAdjusted(fontFamily)
    ? rasterVisualHeightScaleForFontFamily(fontFamily)
    : 1.0;

/// head.unitsPerEm that the size adjust writes for a file of [fontFamily]
/// with [unitsPerEm], or null if it does not scale the family.
int? adjustedUnitsPerEm(String fontFamily, int unitsPerEm) {
  if (!isFontSizeAdjusted(fontFamily)) return null;
  return (unitsPerEm / rasterVisualHeightScaleForFontFamily(fontFamily))
      .round();
}
