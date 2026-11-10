import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_snap_fork/material.dart';

import 'package:monet_ui/third_party/flutter/expansion_tile_2.dart';

void main() {
  for (final useController in [false, true]) {
    testWidgets(
      '${useController ? 'controller' : 'header'} announces the new expansion state',
      (tester) async {
        final controller = ExpansionTile2Controller();
        final changes = <bool>[];
        const headerKey = ValueKey('expansion-header');
        await tester.pumpWidget(
          MaterialApp(
            home: Material(
              child: Center(
                child: SizedBox(
                  width: 300,
                  child: ExpansionTile2(
                    controller: controller,
                    onExpansionChanged: changes.add,
                    title: const Text('Details', key: headerKey),
                    children: const [Text('Expanded content')],
                  ),
                ),
              ),
            ),
          ),
        );
        final localizations = MaterialLocalizations.of(
          tester.element(find.byType(ExpansionTile2)),
        );
        expect(tester.takeAnnouncements(), isEmpty);

        if (useController) {
          controller.expand();
        } else {
          await tester.tap(find.byKey(headerKey));
        }
        await tester.pumpAndSettle();
        expect(controller.isExpanded, isTrue);
        expect(changes, [true]);
        expect(
          tester.takeAnnouncements().map(
            (announcement) => announcement.message,
          ),
          [localizations.expandedHint],
        );

        if (useController) {
          controller.expand();
          await tester.pumpAndSettle();
          expect(tester.takeAnnouncements(), isEmpty);
          controller.collapse();
        } else {
          await tester.tap(find.byKey(headerKey));
        }
        await tester.pumpAndSettle();
        expect(controller.isExpanded, isFalse);
        expect(changes, [true, false]);
        expect(
          tester.takeAnnouncements().map(
            (announcement) => announcement.message,
          ),
          [localizations.collapsedHint],
        );
      },
    );
  }
}
