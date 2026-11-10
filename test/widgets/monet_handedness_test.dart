import 'package:flutter_test/flutter_test.dart';
import 'package:monet_ui/widgets/monet_handedness.dart';
import 'package:pixel_snap_fork/material.dart';

class _Probe extends StatelessWidget {
  const _Probe({required this.read, required this.log});

  final Hand Function(BuildContext context) read;
  final List<Hand> log;

  @override
  Widget build(BuildContext context) {
    log.add(read(context));
    return const SizedBox();
  }
}

void main() {
  testWidgets('defaults to right without a provider on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final hands = <Hand>[];
    final wide = <Hand>[];
    await tester.pumpWidget(
      MediaQuery.fromView(
        view: tester.view,
        child: Column(
          children: [
            _Probe(read: MonetHandedness.of, log: hands),
            _Probe(read: MonetHandedness.inclWideOf, log: wide),
          ],
        ),
      ),
    );
    expect(hands, [Hand.right]);
    expect(wide, [Hand.right]);
  });

  testWidgets('wide screens default handInclWide to left', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final wide = <Hand>[];
    await tester.pumpWidget(
      MediaQuery.fromView(
        view: tester.view,
        child: _Probe(read: MonetHandedness.inclWideOf, log: wide),
      ),
    );
    expect(wide, [Hand.left]);
  });

  testWidgets('rebuilds only dependents of the changed value', (tester) async {
    final hands = <Hand>[];
    final wide = <Hand>[];
    final probes = Column(
      children: [
        _Probe(read: MonetHandedness.of, log: hands),
        _Probe(read: MonetHandedness.inclWideOf, log: wide),
      ],
    );
    Widget scope(Hand hand, Hand inclWide) =>
        MonetHandedness(hand: hand, handInclWide: inclWide, child: probes);

    await tester.pumpWidget(scope(.right, .right));
    await tester.pumpWidget(scope(.right, .left));
    expect(hands, [Hand.right]);
    expect(wide, [Hand.right, Hand.left]);

    await tester.pumpWidget(scope(.left, .left));
    expect(hands, [Hand.right, Hand.left]);
    expect(wide, [Hand.right, Hand.left]);
  });
}
