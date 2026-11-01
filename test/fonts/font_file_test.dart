// Reads files (dart:io): the VM only.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:monet_ui/monet_ui.dart';

ByteData _tenali() => ByteData.sublistView(
  File('test/assets/fonts/TenaliRamakrishna-Regular.ttf').readAsBytesSync(),
);

/// docs/design/ADR_fonts_in_monet_ui.md in telosnex, D2 and I4.
void main() {
  test('reads the facts of a font file', () {
    final font = _tenali();
    expect(unitsPerEm(font), 750);
    expect(fontOutlines(font), FontOutlines.trueType);
    expect(colorTables(font), isEmpty);
    final tables = fontTableRecords(font)!;
    expect(tables.keys, containsAll(['head', 'hhea', 'cmap', 'glyf']));
  });

  test('I4: a family with Latin ink data has A-Z and a-z in its cmap', () {
    final codePoints = cmapCodePoints(_tenali());
    expect(hasLatinLetters(codePoints), isTrue);
    expect(latinInkForFontFamily('Tenali Ramakrishna'), isNotNull);
    // Telugu too.
    expect(codePoints, contains(0x0C15));
  });

  test('hasLatinLetters needs every letter', () {
    final all = kLatinLetterCodePoints.toSet();
    expect(hasLatinLetters(all), isTrue);
    expect(hasLatinLetters(all..remove(0x71)), isFalse);
  });

  test('not a font', () {
    final bytes = ByteData(64);
    expect(fontTableRecords(bytes), isNull);
    expect(cmapCodePoints(bytes), isEmpty);
    expect(colorTables(bytes), isEmpty);
    expect(unitsPerEm(bytes), isNull);
    expect(fontOutlines(bytes), FontOutlines.none);
  });
}
