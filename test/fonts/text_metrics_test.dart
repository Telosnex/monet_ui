import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monet_ui/monet_ui.dart';

/// docs/design/ADR_fonts_in_monet_ui.md in telosnex, D4.
void main() {
  test('snapFontSize rounds to 1/64 px', () {
    expect(snapFontSize(17.0), 17.0);
    expect(snapFontSize(17.004), 17.0);
    expect(snapFontSize(17.01), 17.015625);
  });

  test('withFontLineHeight gives the style its own font height', () {
    const style = TextStyle(fontFamily: 'Tenali Ramakrishna', height: 1.5);
    final fitted = withFontLineHeight(
      style,
      fit: true,
      clearance: kLineHeightClearance,
    );
    expect(fitted.height, lineHeightForFontFamily('Tenali Ramakrishna'));
    expect(fitted.leadingDistribution, TextLeadingDistribution.even);
    final natural = withFontLineHeight(
      style,
      fit: false,
      clearance: kLineHeightClearance,
    );
    expect(
      natural.height,
      naturalLineHeightForFontFamily('Tenali Ramakrishna'),
    );
    // No data: unchanged.
    const unknown = TextStyle(fontFamily: 'Not A Font', height: 1.5);
    expect(
      withFontLineHeight(unknown, fit: true, clearance: 0.08),
      same(unknown),
    );
  });

  test('lineHeightForTextStyle', () {
    const style = TextStyle(fontSize: 10, height: 1.2);
    expect(lineHeightForTextStyle(TextScaler.noScaling, style), 12);
    expect(
      lineHeightForTextStyle(const TextScaler.linear(2), style),
      closeTo(24, 1e-9),
    );
    expect(
      lineHeightForTextStyle(
        TextScaler.noScaling,
        const TextStyle(fontSize: 10),
      ),
      15,
    );
  });

  test('capHeightCentringShift centres the capitals in the line', () {
    // Roboto, at 1 em: the capitals' middle moves to the line's middle.
    const ascent = 0.927734, descent = 0.244141, capHeight = 0.711;
    final shift = capHeightCentringShift(
      ascent: ascent,
      lineHeight: ascent + descent,
      baseline: ascent,
      capHeight: capHeight,
    );
    expect(
      ascent + shift - capHeight / 2,
      closeTo((ascent + descent) / 2, 1e-9),
    );
    double zero(double capHeight) => capHeightCentringShift(
      ascent: 0.9,
      lineHeight: 1.2,
      baseline: 0.9,
      capHeight: capHeight,
    );
    expect(zero(0), 0);
    expect(zero(0.95), 0);
  });

  test('capHeightShiftForTextStyle is zero without a cap height', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    expect(
      capHeightShiftForTextStyle(
        const TextStyle(fontFamily: 'Not A Font', fontSize: 17),
        textScaler: TextScaler.noScaling,
        devicePixelRatio: 2,
      ),
      0,
    );
  });
}
