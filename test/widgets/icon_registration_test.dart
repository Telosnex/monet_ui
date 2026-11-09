import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monet_ui/widgets/icon_ink_bounds.dart';
import 'package:monet_ui/widgets/material_icon_ink.dart';
import 'package:monet_ui/widgets/snapped_icons/icon_outline.dart';

const _family = 'RegistrationTestIcons';
const _icon = IconData(0xe800, fontFamily: _family);

/// One unfitted family with one triangle, in the format that
/// [registerIconOutlines] reads.
String _triangle(String family) {
  final name = utf8.encode(family);
  // Verbs: move, line, line, close. Points as zigzag deltas: (0, 0),
  // (10, 0), (0, 10).
  final record = [4, 0, 1, 1, 3, 0, 0, 20, 0, 19, 20];
  return base64.encode([
    kIconOutlineDataVersion,
    1,
    name.length,
    ...name,
    0x80, 0x04, // em 512
    0, // not fitted
    1, // one glyph
    0x80, 0xd0, 0x03, // code point 0xe800
    record.length,
    ...record,
  ]);
}

void main() {
  test('an unregistered family has no outline or ink bounds', () {
    expect(iconOutline(_icon), isNull);
    expect(materialIconBoundsFor(_icon), isNull);
  });

  test('registered outlines are found by family and code point', () {
    registerIconOutlines(_triangle(_icon.fontFamily!));
    final outline = iconOutline(_icon)!;
    expect(outline.verbs, [0, 1, 1, 3]);
    expect(outline.points, [0, 0, 10, 0, 0, 10]);
    expect(
      debugIconOutlineCodePoints[_icon.fontFamily],
      contains(_icon.codePoint),
    );
    expect(iconOutline(const IconData(0xe801, fontFamily: _family)), isNull);
    expect(
      iconOutline(
        const IconData(0xe800, fontFamily: _family, fontPackage: 'x'),
      ),
      isNull,
    );
  });

  test('registered ink bounds are found by family and code point', () {
    const bounds = IconInkBounds(left: 28, top: 0, right: 485, bottom: 511);
    registerIconInkBounds({
      _icon.fontFamily!: {_icon.codePoint: bounds},
    });
    expect(materialIconBoundsFor(_icon), bounds);
  });

  test('an unknown format version throws', () {
    expect(
      () => registerIconOutlines(base64.encode([kIconOutlineDataVersion + 1])),
      throwsStateError,
    );
  });
}
