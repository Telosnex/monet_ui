import 'package:flutter/services.dart';
import 'package:monet_ui/fonts/font_line_metrics_patch.dart';
import 'package:monet_ui/fonts/font_size_adjust.dart';

/// Changes the bytes of a font as it loads.
typedef FontBytesTransform = ByteData Function(
  String fontFamily,
  ByteData bytes,
);

/// How monet_ui loads fonts: the one place that sets it
/// (docs/design/ADR_fonts_in_monet_ui.md in telosnex, D5).
abstract final class MonetFonts {
  /// Sets monet_ui's font state, and returns the transform for every font
  /// the app loads.
  ///
  /// Call it once, before the first font loads, and give the transform to
  /// the font loader, for example
  /// `GoogleFontsLite.config.fontBytesTransform = MonetFonts.install();`.
  /// Tests call it too, and load fonts with [loadMonetFont].
  ///
  /// [sizeAdjust] scales each Google Font's letters to the reference size in
  /// its bytes ([fontSizeAdjustEnabled]). Then fallback fonts, such as
  /// emoji, keep their own size. Fonts that loaded before a change keep their
  /// bytes, so a change needs a restart.
  static FontBytesTransform install({bool sizeAdjust = false}) {
    setFontSizeAdjustEnabled(sizeAdjust);
    return _transform;
  }

  static ByteData _transform(String fontFamily, ByteData bytes) =>
      patchFontLineMetrics(bytes, fontFamily);
}

/// Loads [bytes] as [fontFamily] with the transform of [MonetFonts.install],
/// as the app loads its fonts. For tests that draw real fonts.
Future<void> loadMonetFont(String fontFamily, ByteData bytes) => (FontLoader(
  fontFamily,
)..addFont(Future.value(MonetFonts._transform(fontFamily, bytes)))).load();
