import 'package:flutter_test/flutter_test.dart';
import 'package:monet_ui/fonts/font_height_equalizer.g.dart';
import 'package:monet_ui/fonts/google_fonts_catalog.g.dart';

void main() {
  test('every catalog family keeps its metrics key across spellings', () {
    for (final name in googleFontsList) {
      final key = name.replaceAll(RegExp('[^A-Za-z0-9]'), '').toLowerCase();
      for (final input in [
        name,
        'packages/google_fonts/$name',
        '${name}_regular',
        '${name}_italic',
        for (var weight = 100; weight <= 900; weight += 100) ...[
          '${name}_$weight',
          'packages/google_fonts/${name}_${weight}italic',
        ],
      ]) {
        expect(normalizeFontFamilyForFontMetrics(input), key, reason: input);
        expect(
          normalizeFontFamilyForFontMetrics(input),
          key,
          reason: 'repeat $input',
        );
      }
    }
  });

  test('nonstandard spellings stay distinct across eviction', () {
    const cases = {
      '': '',
      'packages/foo/': '',
      '!!!': '',
      'My-Fam.123': 'myfam123',
      'Roboto_ITALIC': 'robotoitalic',
      'Roboto_050': 'roboto050',
      'Roboto_1000': 'roboto1000',
      'Roboto_400_italic': 'roboto400',
      'path/path/Róboto': 'rboto',
    };
    for (var pass = 0; pass < 2; pass++) {
      for (final entry in cases.entries) {
        expect(normalizeFontFamilyForFontMetrics(entry.key), entry.value);
      }
      for (var i = 0; i < 100; i++) {
        normalizeFontFamilyForFontMetrics('other/$i');
      }
    }
  });
}
