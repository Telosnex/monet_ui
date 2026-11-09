import 'package:pixel_snap_fork/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monet_ui/widgets/auto_size_title_field.dart';

Future<TextEditingController> _pump(
  WidgetTester tester, {
  required String text,
  required double width,
  double minWidth = 0,
}) async {
  final controller = TextEditingController(text: text);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: Align(
              alignment: Alignment.centerLeft,
              child: AutoSizeTitleField(
                controller: controller,
                style: const TextStyle(fontSize: 20),
                minFontSize: 10,
                maxFontSize: 20,
                cursorColor: Colors.black,
                minWidth: minWidth,
                decoration: const InputDecoration.collapsed(hintText: null),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return controller;
}

double _fontSize(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).style!.fontSize!;

double _width(WidgetTester tester) =>
    tester.getSize(find.byType(AutoSizeTitleField)).width;

void main() {
  testWidgets('keeps the style size when the text fits', (tester) async {
    await _pump(tester, text: 'Hi', width: 400);
    expect(_fontSize(tester), 20);
    expect(_width(tester), lessThan(400));
  });

  testWidgets('shrinks in whole points to fit', (tester) async {
    // The test font is 1 em wide per glyph: 13 glyphs with the caret space.
    await _pump(tester, text: 'abcdefghijkl', width: 200);
    final size = _fontSize(tester);
    expect(size, lessThan(20));
    expect(size, greaterThanOrEqualTo(10));
    expect(size, size.roundToDouble());
    expect(13 * size, lessThanOrEqualTo(200));
    expect(13 * (size + 1), greaterThan(200));
  });

  testWidgets('stops at the minimum size and takes the full width', (
    tester,
  ) async {
    await _pump(tester, text: 'a' * 100, width: 200);
    expect(_fontSize(tester), 10);
    expect(_width(tester), 200);
  });

  testWidgets('is never narrower than minWidth', (tester) async {
    await _pump(tester, text: '', width: 400, minWidth: 80);
    expect(_width(tester), 80);
  });

  testWidgets('resizes when the text changes', (tester) async {
    final controller = await _pump(tester, text: 'Hi', width: 200);
    expect(_fontSize(tester), 20);
    controller.text = 'a' * 30;
    await tester.pump();
    expect(_fontSize(tester), lessThan(20));
  });
}
