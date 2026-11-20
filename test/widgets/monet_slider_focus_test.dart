import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/monet_theme_data.dart';
import 'package:monet_ui/widgets/monet_slider.dart';

void main() {
  final theme = MonetThemeData.fromColor(
    color: const Color(0xff3366cc),
    backgroundTone: 95,
    brightness: Brightness.light,
  );

  Widget app() => MaterialApp(
    home: MonetTheme(
      monetThemeData: theme,
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: MonetSlider(value: 0.5, onChanged: (_) {}),
          ),
        ),
      ),
    ),
  );

  // _MonetSliderPainter is private; read its fields dynamically.
  dynamic painter(WidgetTester tester) => tester
      .widgetList<CustomPaint>(
        find.descendant(
          of: find.byType(MonetSlider),
          matching: find.byType(CustomPaint),
        ),
      )
      .map((w) => w.painter)
      .singleWhere((p) => p.runtimeType.toString() == '_MonetSliderPainter');

  void expectRest(WidgetTester tester) {
    final p = painter(tester);
    expect(p.activeTrackColor, theme.primary.color);
    expect(p.borderColor, theme.primary.colorBorder);
    expect(p.thumbContentColor, theme.primary.colorIcon);
    expect(p.borderWidth, MonetSlider.kBorderWidth);
  }

  void expectFocused(WidgetTester tester) {
    final p = painter(tester);
    expect(p.activeTrackColor, theme.primary.colorHovered);
    expect(p.borderColor, theme.primary.colorHoveredBorder);
    expect(p.thumbContentColor, theme.primary.colorHoveredIcon);
    expect(p.borderWidth, MonetSlider.kFocusedBorderWidth);
  }

  testWidgets('keyboard focus shows the hover colors and a 2dp border', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    expectRest(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expectFocused(tester);

    FocusManager.instance.primaryFocus!.unfocus();
    // The focus change applies after one frame, the rebuild in the next.
    await tester.pump();
    await tester.pump();
    expectRest(tester);
  });

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testWidgets('focus from a ${kind.name} shows nothing until a key', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.tap(find.byType(MonetSlider), kind: kind);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.hasPrimaryFocus, isTrue);
      expectRest(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expectFocused(tester);
    });
  }
}
