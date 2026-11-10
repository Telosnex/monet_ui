import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monet_ui/widgets/ink_centered_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'unavailable readback keeps estimated ink and completes pending work',
    () async {
      var calls = 0;
      final completion = Completer<GlyphInk?>();
      final cache = GlyphInkCache.forTesting(
        measure: (style, grapheme, {required fontSize}) {
          calls++;
          return completion.future;
        },
      );
      addTearDown(cache.dispose);
      const style = TextStyle(fontSize: 20);
      final painter = TextPainter(
        text: const TextSpan(text: '1', style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      addTearDown(painter.dispose);
      final estimate = cache.inkOf(painter, '1', style);
      expect(cache.isIdle, isFalse);
      completion.completeError(Exception('Impeller context was null.'));
      await Future<void>.delayed(Duration.zero);
      expect(cache.isIdle, isTrue);
      expect(cache.inkOf(painter, '1', style), estimate);
      expect(cache.inkOf(painter, '1', style), estimate);
      expect(calls, 1);
    },
  );

  test(
    'failed glyph is unknown, not an empty glyph in a measured run',
    () async {
      final cache = GlyphInkCache.forTesting(
        measure: (style, grapheme, {required fontSize}) async {
          if (grapheme == '1') throw Exception('Impeller context was null.');
          return const GlyphInk(left: .1, right: .1, top: .5, bottom: 0);
        },
      );
      addTearDown(cache.dispose);
      const style = TextStyle(fontSize: 20);
      final painter = TextPainter(
        text: const TextSpan(text: '21', style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      addTearDown(painter.dispose);
      final estimate = cache.inkOf(painter, '21', style);
      await Future<void>.delayed(Duration.zero);
      // The first lookup starts only the first unmeasured glyph.
      cache.inkOf(painter, '21', style);
      await Future<void>.delayed(Duration.zero);
      expect(cache.isIdle, isTrue);
      expect(cache.inkOf(painter, '21', style), estimate);
    },
  );
}
