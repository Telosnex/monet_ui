import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/monet_theme_data.dart';
import 'package:monet_ui/widgets/menu/menu_entry.dart';
import 'package:monet_ui/widgets/monet_icon.dart';

/// A menu entry that a parent rebuilds with new properties must show them.
/// Its custom element once kept the first widget's build, so a row that
/// changed its icon while the menu was open kept the old icon.
void main() {
  Widget host(ValueNotifier<bool> on, MenuEntry Function(bool on) entry) =>
      MaterialApp(
        home: MonetTheme(
          monetThemeData: MonetThemeData.fromColors(
            brightness: Brightness.light,
            backgroundTone: 94,
            primary: Colors.blue,
            secondary: Colors.teal,
            tertiary: Colors.orange,
          ),
          child: Material(
            child: ValueListenableBuilder<bool>(
              valueListenable: on,
              builder: (_, value, _) => entry(value),
            ),
          ),
        ),
      );

  testWidgets('MenuEntry.create shows a new icon', (tester) async {
    final on = ValueNotifier(false);
    addTearDown(on.dispose);
    await tester.pumpWidget(
      host(
        on,
        (value) => MenuEntry.create(
          title: 'Kitchen',
          icon: value ? Icons.check_box : Icons.check_box_outline_blank,
          action: () {},
        ),
      ),
    );
    IconData? icon() => tester.widget<MonetIcon>(find.byType(MonetIcon)).icon;
    expect(icon(), Icons.check_box_outline_blank);

    on.value = true;
    await tester.pump();
    expect(icon(), Icons.check_box);
  });

  testWidgets('MenuEntryWidget shows a new child', (tester) async {
    final on = ValueNotifier(false);
    addTearDown(on.dispose);
    await tester.pumpWidget(
      host(on, (value) => MenuEntryWidget(child: Text(value ? 'On' : 'Off'))),
    );
    expect(find.text('Off'), findsOneWidget);

    on.value = true;
    await tester.pump();
    expect(find.text('On'), findsOneWidget);
  });
}
