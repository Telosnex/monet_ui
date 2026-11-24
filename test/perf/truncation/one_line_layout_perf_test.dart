@Tags(['perf'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monet_ui/widgets/rich_text/paragrapher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final (name, text, width, remount) in [
    ('fitting clock', '12:34', 200.0, false),
    ('narrow title', 'A title that should end with an ellipsis', 65.0, false),
    (
      'remounted narrow title',
      'A title that should end with an ellipsis',
      65.0,
      true,
    ),
    ('crossing fit boundary', '12:34', 68.0, false),
  ]) {
    test(name, () {
      debugClearTruncationTailDecisionCache();
      final owner = Paragrapher();
      addTearDown(owner.dispose);
      final samples = <int>[];
      const count = 2400;
      int? expectedCuts;
      for (var pass = 0; pass < 12; pass++) {
        var cuts = 0;
        final timer = Stopwatch()..start();
        for (var i = 0; i < count; i++) {
          final p = remount ? Paragrapher() : owner;
          final input = ParagraphInput(
            text: text,
            textSpan: TextSpan(text: text),
            style: const TextStyle(fontSize: 14, fontFamily: 'Ahem'),
            paintColor: const Color(0xff223344),
            align: TextAlign.start,
            direction: TextDirection.ltr,
            textScaler: TextScaler.noScaling,
            maxLines: 1,
            maxWidth: width + i % 8,
            softWrap: true,
            strutStyle: null,
            placeholderSizes: const [],
          );
          final result = p.layoutReservingTail(
            input,
            reservedTailWidth: 0,
            ellipsis: '…',
          );
          if (result.didTruncate) cuts++;
          if (remount) p.dispose();
        }
        timer.stop();
        if (pass >= 3) samples.add(timer.elapsedMicroseconds);
        expectedCuts ??= cuts;
        expect(cuts, expectedCuts);
      }
      if (name == 'fitting clock') expect(expectedCuts, 0);
      if (name.contains('narrow')) expect(expectedCuts, count);
      if (name == 'crossing fit boundary') {
        expect(expectedCuts, inExclusiveRange(0, count));
      }
      samples.sort();
      // ignore: avoid_print
      print(
        '$name: ${samples[4]} us for $count calls, $expectedCuts truncated',
      );
    });
  }
}
