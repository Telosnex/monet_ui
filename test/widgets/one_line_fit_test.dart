import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monet_ui/widgets/rich_text/paragrapher.dart';

class _Input extends ParagraphInput {
  _Input(
    String text,
    double width, {
    double scale = 1,
    super.direction = TextDirection.ltr,
    int lines = 1,
    List<Size> leading = const [],
  }) : super(
         text: text,
         textSpan: TextSpan(text: text),
         style: const TextStyle(fontSize: 14),
         paintColor: const Color(0xff123456),
         maxLines: lines,
         align: TextAlign.start,
         textScaler: TextScaler.linear(scale),
         strutStyle: null,
         placeholderSizes: leading,
         maxWidth: width,
         softWrap: true,
       );

  // Fail the fit-path test if a rich key is constructed, even on a cache hit.
  final keyReads = <int>[];
  @override
  String get spanMetricSignature {
    keyReads.add(1);
    return super.spanMetricSignature;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(debugClearTruncationTailDecisionCache);
  test('only a verified fit skips the rich key', () {
    final p = Paragrapher();
    addTearDown(p.dispose);
    ParagraphResult run(_Input input, {double tail = 0}) =>
        p.layoutReservingTail(input, reservedTailWidth: tail, ellipsis: '…');
    run(_Input('12:34', 150));
    final fit = _Input('12:35', 151);
    expect(run(fit).didTruncate, isFalse);
    expect(fit.keyReads, isEmpty);
    final noLongerFits = _Input('12:35', 151, scale: 3);
    expect(run(noLongerFits).didTruncate, isTrue);
    expect(noLongerFits.keyReads, isNotEmpty);
    for (final input in [
      _Input('12:35', 151, scale: 3),
      _Input('12:35', 400, lines: 2),
      _Input('12:35', 400, leading: [const Size(12, 12)]),
    ]) {
      run(input);
      expect(input.keyReads, isNotEmpty);
    }
    final tail = _Input('12:35', 400);
    run(tail, tail: 20);
    expect(tail.keyReads, isNotEmpty);
    p.systemFontsDidChange();
    final afterChange = _Input('12:35', 400);
    run(afterChange);
    expect(afterChange.keyReads, isNotEmpty);
  });
  test('resize across fit boundary matches uncached layout and ellipsis', () {
    final owner = Paragrapher(), reference = Paragrapher();
    final wasEnabled = truncationTailDecisionCacheEnabled;
    addTearDown(() {
      truncationTailDecisionCacheEnabled = wasEnabled;
      owner.dispose();
      reference.dispose();
    });
    for (final text in [
      '12:34',
      'longer title with spaces',
      'a👩‍🚀b',
      '12\n34',
      '',
      'שלום',
    ]) {
      for (final width in [
        160.0,
        190.0,
        72.0,
        71.0,
        68.0,
        40.0,
        1.0,
        70.0,
        180.0,
      ]) {
        for (final scale in [1.0, 1.3]) {
          final input = _Input(
            text,
            width,
            scale: scale,
            direction: text == 'שלום' ? TextDirection.rtl : TextDirection.ltr,
          );
          truncationTailDecisionCacheEnabled = false;
          final expected = reference.layoutReservingTail(
            input,
            reservedTailWidth: 0,
            ellipsis: '…',
          );
          truncationTailDecisionCacheEnabled = true;
          final actual = owner.layoutReservingTail(
            input,
            reservedTailWidth: 0,
            ellipsis: '…',
          );
          expect(actual.didTruncate, expected.didTruncate);
          expect(actual.didExceedMaxLines, expected.didExceedMaxLines);
          expect(actual.input.text, expected.input.text);
          expect(sameParagraphGeometry(expected, actual), isTrue);
        }
      }
    }
  });
}
