// Reads files (dart:io): the VM only.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart'
    show Brightness, TextTheme, Typography;
import 'package:monet_ui/monet_ui.dart';

const _kTenali = 'Tenali Ramakrishna';

/// docs/design/ADR_font_size_adjust.md in telosnex.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tenali = ByteData.sublistView(
    File('test/assets/fonts/TenaliRamakrishna-Regular.ttf').readAsBytesSync(),
  );
  final scale = rasterVisualHeightScaleForFontFamily(_kTenali);

  /// [body] with the size adjust on, then off.
  T both<T>(T Function() body) {
    MonetFonts.install(sizeAdjust: true);
    try {
      return body();
    } finally {
      MonetFonts.install();
    }
  }

  tearDown(MonetFonts.install);

  test('off by default', () {
    expect(fontSizeAdjustEnabled, isFalse);
    expect(isFontSizeAdjusted(_kTenali), isFalse);
    expect(visualHeightScaleForFontFamily(_kTenali), scale);
    expect(fontEmScale(_kTenali), 1.0);
  });

  test('D2: an adjusted font has scale 1, and em values times the scale', () {
    final capOff = rasterCapHeightEmForFontFamily(_kTenali)!;
    final inkOff = latinInkForFontFamily(_kTenali)!;
    final naturalOff = naturalLineHeightForFontFamily(_kTenali)!;
    both(() {
      expect(isFontSizeAdjusted(_kTenali), isTrue);
      expect(visualHeightScaleForFontFamily(_kTenali), 1.0);
      expect(fontEmScale(_kTenali), scale);
      expect(rasterCapHeightEmForFontFamily(_kTenali), capOff * scale);
      expect(latinInkForFontFamily(_kTenali)!.$1, inkOff.$1 * scale);
      expect(naturalLineHeightForFontFamily(_kTenali), naturalOff * scale);
      expect(
        requestedFontSize(const TextStyle(fontFamily: _kTenali, fontSize: 17)),
        17,
      );
    });
  });

  test(
    'D3, D7: fonts without Latin ink and excluded fonts keep their size',
    () {
      both(() {
        expect(isFontSizeAdjusted('Noto Color Emoji'), isFalse);
        expect(isFontSizeAdjusted('Bytesized'), isFalse);
        expect(
          visualHeightScaleForFontFamily('Bytesized'),
          rasterVisualHeightScaleForFontFamily('Bytesized'),
        );
        expect(isFontSizeAdjusted('Not A Font'), isFalse);
      });
    },
  );

  test('I3: the line height in px is the same with the size adjust', () {
    final offSize = 17 * scale;
    final offHeight = lineHeightForFontFamily(_kTenali)! * offSize;
    final onHeight = both(() => lineHeightForFontFamily(_kTenali)! * 17);
    expect(onHeight, closeTo(offHeight, 1e-9));
  });

  group('createTextTheme', () {
    const style = TextStyle(fontFamily: _kTenali);
    final textTheme = const TextTheme(
      displayLarge: style,
      displayMedium: style,
      displaySmall: style,
      headlineLarge: style,
      headlineMedium: style,
      headlineSmall: style,
      titleLarge: style,
      titleMedium: style,
      titleSmall: style,
      bodyLarge: style,
      bodyMedium: style,
      bodySmall: style,
      labelLarge: style,
      labelMedium: style,
      labelSmall: style,
    );
    final typography = Typography(
      black: textTheme,
      white: textTheme,
      englishLike: textTheme,
      dense: textTheme,
      tall: textTheme,
    );
    TextTheme create() => MonetThemeData.fromColor(
      backgroundTone: 95,
      brightness: Brightness.light,
      color: const Color(0xff3366cc),
    ).createTextTheme(typography, TextScaler.noScaling, 1.0, 1.0);

    test('gives the requested size, and the same line height in px', () {
      final off = create().bodyMedium!;
      final on = both(() => create().bodyMedium!);
      expect(on.fontSize, closeTo(off.fontSize! / scale, 1e-9));
      expect(
        on.fontSize! * on.height!,
        closeTo(off.fontSize! * off.height!, 1e-6),
      );
    });
  });

  group('D1: the patch', () {
    test('I5: off, the bytes are the same as the line metrics patch alone', () {
      final off = patchFontLineMetrics(tenali, _kTenali);
      expect(unitsPerEm(off), 750);
    });

    test('I6: on, writes unitsPerEm, same length, valid checksum', () {
      final on = both(() => patchFontLineMetrics(tenali, _kTenali));
      expect(unitsPerEm(on), (750 / scale).round());
      expect(on.lengthInBytes, tenali.lengthInBytes);
      var sum = 0;
      for (var i = 0; i < on.lengthInBytes; i += 4) {
        var word = 0;
        for (var b = 0; b < 4; b++) {
          word =
              (word << 8) | (i + b < on.lengthInBytes ? on.getUint8(i + b) : 0);
        }
        sum = (sum + word) & 0xffffffff;
      }
      expect(sum, 0xB1B0AFBA);
    });

    testWidgets('I2: letters at the requested size match the old size', (
      tester,
    ) async {
      final off = patchFontLineMetrics(tenali, _kTenali);
      final on = both(() => patchFontLineMetrics(tenali, _kTenali));
      await tester.runAsync(() async {
        await (FontLoader('TenaliOff')..addFont(Future.value(off))).load();
        await (FontLoader('TenaliOn')..addFont(Future.value(on))).load();
      });
      LineMetrics line(String family, double size) {
        final painter = TextPainter(
          text: TextSpan(
            text: 'H',
            style: TextStyle(fontFamily: family, fontSize: size),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final metrics = painter.computeLineMetrics().single;
        painter.dispose();
        return metrics;
      }

      final a = line('TenaliOff', 17 * scale);
      final b = line('TenaliOn', 17);
      expect(b.ascent, closeTo(a.ascent, 0.05));
      expect(b.height, closeTo(a.height, 0.05));
      expect(b.width, closeTo(a.width, 0.05));
    });
  });
}
