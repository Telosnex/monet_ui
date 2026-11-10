import 'package:flutter_test/flutter_test.dart';
import 'package:monet_ui/widgets/screen_breakpoints.dart';
import 'package:monet_ui/widgets/supporting_pane.dart';

void main() {
  test('the split is two good columns beside one', () {
    expect(
      ScreenBreakpoints.splitMinPrimaryWidth,
      2 * ScreenBreakpoints.screenGoodColumnWidth,
    );
    expect(
      ScreenBreakpoints.splitMinSupportingWidth,
      ScreenBreakpoints.screenGoodColumnWidth,
    );
    expect(
      ScreenBreakpoints.splitMinWidth,
      ScreenBreakpoints.splitMinPrimaryWidth +
          ScreenBreakpoints.splitMinSupportingWidth,
    );
  });

  test('exactly splitMinWidth wide: each gets its minimum', () {
    const width = ScreenBreakpoints.splitMinWidth;
    expect(SupportingPane.fits(width), isTrue);
    final pane = SupportingPane.widthFor(width, desiredWidth: 10000);
    expect(pane, ScreenBreakpoints.splitMinSupportingWidth);
    expect(width - pane, ScreenBreakpoints.splitMinPrimaryWidth);
  });

  test('fits: from splitMinWidth, rounded', () {
    for (final (width, fits) in [
      (ScreenBreakpoints.splitMinWidth - 1, false),
      (ScreenBreakpoints.splitMinWidth - 0.6, false),
      (ScreenBreakpoints.splitMinWidth - 0.5, true),
      (ScreenBreakpoints.splitMinWidth, true),
      // Landscape phones and tablets, in dp.
      (844.0, false),
      (932.0, false),
      (1180.0, true),
      (1366.0, true),
    ]) {
      expect(SupportingPane.fits(width), fits, reason: '$width');
    }
  });

  test('widthFor: desired, within the minimum and the fraction', () {
    for (final (width, desired, pane) in [
      // The pane asks for less than the minimum: buttons still fit.
      (1440.0, 100.0, ScreenBreakpoints.splitMinSupportingWidth),
      (1440.0, 400.0, 400.0),
      // A third of the screen at most, however much it asks for.
      (1440.0, 1000.0, 480.0),
      (3840.0, 1000.0, 1000.0),
      (3840.0, 2000.0, 1280.0),
    ]) {
      final got = SupportingPane.widthFor(width, desiredWidth: desired);
      expect(got, pane, reason: '$width, desired $desired');
      expect(
        width - got,
        greaterThanOrEqualTo(ScreenBreakpoints.splitMinPrimaryWidth),
      );
    }
  });

  test('onLeft: away from the hand', () {
    expect(SupportingPane.onLeft(.right), isTrue);
    expect(SupportingPane.onLeft(.left), isFalse);
  });
}
