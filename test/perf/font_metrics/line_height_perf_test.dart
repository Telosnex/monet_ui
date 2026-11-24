@Tags(['perf'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:monet_ui/fonts/font_size_adjust.dart';
import 'package:monet_ui/fonts/google_fonts_catalog.g.dart';
import 'package:monet_ui/fonts/line_height.dart';

void main() {
  const hot = [
    'Roboto',
    'packages/google_fonts/Roboto_700italic',
    'Open Sans_400',
    'Laila',
    'Mukta_500',
    'Tenali Ramakrishna',
    'Noto Sans',
    'Lato_italic',
  ];
  for (final adjust in [false, true]) {
    test('full line-height lookup, size adjustment $adjust', () {
      final previous = fontSizeAdjustEnabled;
      addTearDown(() => setFontSizeAdjustEnabled(previous));
      setFontSizeAdjustEnabled(adjust);
      for (final (name, families) in [
        ('8 recurring names', hot),
        ('catalog scan', googleFontsList),
      ]) {
        final elapsed = <int>[];
        double? checksum;
        const count = 20000;
        for (var pass = 0; pass < 10; pass++) {
          var sum = 0.0;
          final timer = Stopwatch()..start();
          for (var i = 0; i < count; i++) {
            sum += lineHeightForFontFamily(families[i % families.length]) ?? 0;
          }
          timer.stop();
          if (pass > 0) elapsed.add(timer.elapsedMicroseconds);
          checksum ??= sum;
          expect(sum, checksum);
        }
        elapsed.sort();
        // ignore: avoid_print
        print(
          '$name, adjust=$adjust: ${elapsed[4]} us / $count lookups; sum=$checksum',
        );
      }
    });
  }
}
