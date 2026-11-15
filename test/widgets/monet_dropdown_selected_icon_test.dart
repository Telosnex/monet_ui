import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/monet_theme_data.dart';
import 'package:monet_ui/widgets/chevron_icon.dart';
import 'package:monet_ui/widgets/icon_size.dart';
import 'package:monet_ui/widgets/menu/menu_entry.dart';
import 'package:monet_ui/widgets/monet_button.dart';
import 'package:monet_ui/widgets/monet_dropdown.dart';
import 'package:monet_ui/widgets/monet_rich_text.dart';

void main() {
  Widget app({IconData? icon, String? longestLabel}) => MaterialApp(
    home: MonetTheme(
      monetThemeData: MonetThemeData.fromColor(
        color: const Color(0xff3366cc),
        backgroundTone: 95,
        brightness: Brightness.light,
      ),
      child: Scaffold(
        body: Center(
          child: MonetDropdown<String>(
            items: const ['a', 'b'],
            selectedLabel: 'Ask each time',
            selectedValue: 'a',
            selectedIcon: icon,
            longestLabel: longestLabel,
            onChanged: (_) {},
            menuItemBuilder: (context, item) =>
                MenuEntry.create(title: item, icon: null, action: null),
          ),
        ),
      ),
    ),
  );

  testWidgets('no icon by default', (tester) async {
    await tester.pumpWidget(app());
    expect(find.byIcon(Icons.bolt), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selectedIcon is before the label, at the size of the letters', (
    tester,
  ) async {
    await tester.pumpWidget(app(icon: Icons.bolt));
    final icon = find.byIcon(Icons.bolt);
    expect(icon, findsOneWidget);
    final label = find.byType(MonetRichText);
    expect(label, findsOneWidget);
    expect(
      tester.getTopRight(icon).dx,
      lessThanOrEqualTo(tester.getTopLeft(label).dx),
    );
    expect(
      tester.getTopLeft(label).dx,
      lessThan(tester.getTopLeft(find.byType(ChevronIcon)).dx),
    );
    final style = DefaultTextStyle.of(tester.element(icon)).style;
    expect(tester.widget<Icon>(icon).size, iconSizeForTextStyle(style));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the button with an icon is wider by the icon and its gap', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    final plain = tester.getSize(find.byType(MonetButton)).width;
    await tester.pumpWidget(app(icon: Icons.bolt));
    // The button animates to its new size.
    await tester.pumpAndSettle();
    final withIcon = tester.getSize(find.byType(MonetButton)).width;
    expect(withIcon, greaterThan(plain));

    // longestLabel reserves the same room for the icon.
    await tester.pumpWidget(app(longestLabel: 'Ask each time'));
    await tester.pumpAndSettle();
    final plainLongest = tester.getSize(find.byType(MonetButton)).width;
    await tester.pumpWidget(
      app(icon: Icons.bolt, longestLabel: 'Ask each time'),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(MonetButton)).width - plainLongest,
      moreOrLessEquals(withIcon - plain, epsilon: 0.01),
    );
  });
}
