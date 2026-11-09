import 'package:flutter_test/flutter_test.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/monet_theme_data.dart';
import 'package:monet_ui/widgets/isolated_scrollbar.dart';
import 'package:monet_ui/widgets/monet_screen.dart';
import 'package:monet_ui/widgets/monet_scrollbar.dart';
import 'package:monet_ui/widgets/monet_wallpaper_scrollbar_color.dart';
import 'package:pixel_snap_fork/material.dart';

const _wallpaperColor = Color(0xFF123456);

Widget _app(Widget child) => MaterialApp(
  home: MonetTheme(
    monetThemeData: MonetThemeData.fromColor(
      color: Colors.blue,
      backgroundTone: 95,
      brightness: .light,
    ),
    child: MonetWallpaperScrollbarColor(
      builder: (context, builder) => builder(context, _wallpaperColor),
      child: child,
    ),
  ),
);

Color? _thumbColor(WidgetTester tester) =>
    ScrollbarTheme.of(tester.element(find.byType(ListView))).thumbColor
        ?.resolve({});

Widget _screen({required bool wallpaper}) => MonetScreen(
  hasWallpaperBackground: wallpaper,
  builder: (context, padding) => ListView(
    padding: padding,
    children: [for (var i = 0; i < 50; i++) Text('$i')],
  ),
);

void main() {
  testWidgets('wallpaper screens use the provided scrollbar color', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_screen(wallpaper: true)));
    expect(_thumbColor(tester), _wallpaperColor);
  });

  testWidgets('opaque screens use the theme scrollbar color', (tester) async {
    await tester.pumpWidget(_app(_screen(wallpaper: false)));
    expect(_thumbColor(tester), isNot(_wallpaperColor));
  });

  testWidgets('keeps the inherited scroll behavior', (tester) async {
    const behavior = MaterialScrollBehavior();
    await tester.pumpWidget(
      _app(
        ScrollConfiguration(
          behavior: behavior,
          child: MonetScrollbar(child: ListView(children: const [])),
        ),
      ),
    );
    expect(
      ScrollConfiguration.of(tester.element(find.byType(ListView))),
      same(behavior),
    );
  });

  testWidgets('isolated layer wraps vertical desktop scrollables', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        MonetScrollbar(
          isolateScrollbarLayer: true,
          child: ListView(children: [for (var i = 0; i < 50; i++) Text('$i')]),
        ),
      ),
    );
    expect(find.byType(IsolatedScrollbar), findsOneWidget);
  }, variant: TargetPlatformVariant.desktop());
}
