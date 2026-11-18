import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:monet_ui/widgets/monet_rich_text.dart';

void main() {
  bool didTruncate(WidgetTester tester) =>
      tester
              .renderObject(find.byType(MonetRichText))
              .toDiagnosticsNode()
              .getProperties()
              .firstWhere((p) => p.name == 'didTruncate')
              .value!
          as bool;

  Widget wrapping(double width, {int? maxLines}) => MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: MonetRichText(
          text: 'Google Calendar',
          textStyle: const TextStyle(fontSize: 20),
          maxLines: maxLines,
          trailing: const [SizedBox(key: Key('tail'), width: 80, height: 10)],
        ),
      ),
    ),
  );

  // Each glyph of the test font is as wide as the font size: the text is
  // 300 wide, "Calendar" 160.
  testWidgets('without a line limit, the last word wraps with the trailing '
      'widget', (tester) async {
    await tester.pumpWidget(wrapping(300));
    expect(didTruncate(tester), isFalse);
    final box = tester.getRect(find.byType(MonetRichText));
    expect(box.height, 40);
    final tail = tester.getRect(find.byKey(const Key('tail')));
    expect(tail.left - box.left, moreOrLessEquals(160, epsilon: 1));
    expect(tail.center.dy, greaterThan(box.top + 20));
  });

  testWidgets('without a line limit, the trailing widget wraps alone when '
      'the last word and it are too wide', (tester) async {
    await tester.pumpWidget(wrapping(200));
    expect(didTruncate(tester), isFalse);
    final box = tester.getRect(find.byType(MonetRichText));
    expect(box.height, 60);
    final tail = tester.getRect(find.byKey(const Key('tail')));
    expect(tail.left, moreOrLessEquals(box.left, epsilon: 1));
    expect(tail.center.dy, greaterThan(box.top + 40));
  });

  testWidgets('at the line limit, the text truncates', (tester) async {
    await tester.pumpWidget(wrapping(300, maxLines: 1));
    expect(didTruncate(tester), isTrue);
  });
}
