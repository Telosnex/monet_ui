import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monet_ui/colorspaces/hct.dart';
import 'package:monet_ui/theming/palette.dart';

double _hueDelta(double a, double b) => ((a - b + 540) % 360 - 180).abs();

void main() {
  const teal = Color(0xFF51B5B7); // H~198.6, C~24.9, T~68.2

  for (final achromatic in const [
    Color(0xFF000000),
    Color(0xFFFFFFFF),
    Color(0xFF808080),
  ]) {
    test('achromatic base $achromatic borrows background hue', () {
      final palette = Palette.fromColorAndBackground(
        achromatic,
        teal,
        contrast: 0.5,
      );
      final bgHue = Hct.fromColor(teal).hue;
      for (final (name, c) in [
        ('backgroundHovered', palette.backgroundHovered),
        ('backgroundSplashed', palette.backgroundSplashed),
      ]) {
        final hct = Hct.fromColor(c);
        if (hct.chroma < 5) continue;
        expect(
          _hueDelta(hct.hue, bgHue),
          lessThan(20),
          reason: '$name ${hct.hue.toStringAsFixed(1)} vs bg '
              '${bgHue.toStringAsFixed(1)}',
        );
      }
    });
  }

  test('chromatic base keeps its own hue', () {
    const red = Color(0xFFD04040);
    final palette = Palette.fromColorAndBackground(red, teal, contrast: 0.5);
    final hct = Hct.fromColor(palette.backgroundHovered);
    expect(_hueDelta(hct.hue, Hct.fromColor(red).hue), lessThan(10));
  });
}
