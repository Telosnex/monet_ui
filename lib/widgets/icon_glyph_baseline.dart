import 'package:flutter/widgets.dart';

/// Distance from the top of an icon's box to its glyph's baseline, before
/// SkParagraph rounds it.
///
/// The glyph is laid out as [Icon] lays it out: alone, with `height: 1`, so
/// its line box is [size] tall. SkParagraph then draws the glyph at this
/// value rounded to a whole logical pixel (`TextLine::buildTextBlob`).
double iconExactBaseline(IconData icon, double size) =>
    _IconBaselineCache.lookup(icon, size).exact;

/// Distance from the top of an [Icon]'s box to where its glyph's baseline is
/// drawn, in logical pixels, before the rasterizer snaps it to a device
/// pixel.
///
/// SkParagraph can round the paragraph height, for example 17.33 to 17, and
/// [Icon] centres the paragraph in its box. The baseline is then drawn at
/// the centring offset plus the alphabetic baseline rounded to a whole
/// logical pixel.
double iconDrawnBaseline(IconData icon, double size) =>
    _IconBaselineCache.lookup(icon, size).drawn;

/// An icon font and size, which together fix the glyph baselines.
final class const _BaselineKey(
  final String? fontFamily,
  final String? fontPackage,
  final double size,
) {
  @override
  bool operator ==(Object other) =>
      other is _BaselineKey &&
      other.fontFamily == fontFamily &&
      other.fontPackage == fontPackage &&
      other.size == size;

  @override
  int get hashCode => Object.hash(fontFamily, fontPackage, size);
}

/// The exact and drawn baselines of one icon font and size.
final class const _Baselines(final double exact, final double drawn);

abstract final class _IconBaselineCache {
  static final _baselines = <_BaselineKey, _Baselines>{};
  static bool _listening = false;

  static _Baselines lookup(IconData icon, double size) {
    final key = _BaselineKey(icon.fontFamily, icon.fontPackage, size);
    final cached = _baselines[key];
    if (cached != null) return cached;
    if (!_listening) {
      _listening = true;
      // A font that loads late changes the metrics of later layouts.
      PaintingBinding.instance.systemFonts.addListener(_baselines.clear);
    }
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          inherit: false,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: size,
          height: 1,
          leadingDistribution: .even,
        ),
      ),
      textDirection: .ltr,
    )..layout();
    final exact = painter.computeDistanceToActualBaseline(.alphabetic);
    final drawn = (size - painter.height) / 2 + (exact + 0.5).floorToDouble();
    painter.dispose();
    // Icon sizes are few; the bound only guards against unbounded animation.
    if (_baselines.length >= 128) _baselines.clear();
    return _baselines[key] = _Baselines(exact, drawn);
  }
}
