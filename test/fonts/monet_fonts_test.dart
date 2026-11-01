// Reads files (dart:io): the VM only.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monet_ui/monet_ui.dart';

/// docs/design/ADR_fonts_in_monet_ui.md in telosnex, D5.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tenali = ByteData.sublistView(
    File('test/assets/fonts/TenaliRamakrishna-Regular.ttf').readAsBytesSync(),
  );

  test('install returns the line metrics patch', () {
    final transform = MonetFonts.install();
    final patched = transform('Tenali Ramakrishna', tenali);
    final expected = patchFontLineMetrics(tenali, 'Tenali Ramakrishna');
    expect(
      patched.buffer.asUint8List(patched.offsetInBytes, patched.lengthInBytes),
      expected.buffer.asUint8List(
        expected.offsetInBytes,
        expected.lengthInBytes,
      ),
    );
    // A font without data is unchanged.
    expect(transform('Not A Font', tenali), same(tenali));
  });

  testWidgets('loadMonetFont loads the patched font', (tester) async {
    await tester.runAsync(() => loadMonetFont('Tenali Ramakrishna', tenali));
    final painter = TextPainter(
      text: const TextSpan(
        text: 'H',
        style: TextStyle(fontFamily: 'Tenali Ramakrishna', fontSize: 100),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final line = painter.computeLineMetrics().single;
    final ink = latinInkForFontFamily('Tenali Ramakrishna')!;
    final height = lineHeightForFontFamily('Tenali Ramakrishna')!;
    final pad = (height - ink.$1 - ink.$2) / 2;
    // The patched ascent, not the file's.
    expect(line.ascent, closeTo((ink.$1 + pad) * 100, 0.5));
    painter.dispose();
  });
}
