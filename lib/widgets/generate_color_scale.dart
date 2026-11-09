import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:monet_ui/colorspaces/color_model.dart';
import 'package:monet_ui/colorspaces/hct.dart';
import 'package:monet_ui/contrast/contrast.dart';
import 'package:monet_ui/theming/palette.dart';

/// The golden angle in degrees (~137.508°).
///
/// Each successive point placed at this angular offset from the previous one
/// lands in the largest remaining gap on the circle. This is the same
/// packing strategy used by sunflower seed heads and is optimal for
/// maximising the minimum angular distance among the first K points for
/// any K ≤ count.
const double _kGoldenAngle = 360.0 * (1.0 - 1.0 / _kPhi);
const double _kPhi = 1.6180339887498948482; // (1 + √5) / 2

/// Generates a list of [Palette]s by rotating the hue of a seed color around
/// the color wheel, maximizing the angular distance between colors.
///
/// [background] is constant across all palettes, hue is not rotated.
/// Pass its original [backgroundTone] when sharing a logical context with other
/// palettes; otherwise this explicit RGB background defines its own context.
List<Palette> generateColorScaleFixedBackground(
  Color seed,
  Color background, {
  required int count,
  required double contrast,
  Algo algo = .apca,
  double? backgroundTone,
  ColorModel colorModel = .kDefault,
}) {
  final base = Hct.fromColor(seed, model: colorModel);
  final startHue = base.hue;
  // Native-unit design floors, not a numerical conversion between models.
  final chroma = math.max(base.chroma, colorModel == .oklch ? .1 : 40.0);
  final tone = base.tone.clamp(40.0, 70.0);
  return List.generate(count, (i) {
    final hue = (startHue + _kGoldenAngle * i) % 360;
    final color = Hct.from(hue, chroma, tone, model: colorModel).color;
    return Palette.fromColorAndBackground(
      color,
      background,
      backgroundTone: backgroundTone,
      contrast: contrast,
      algo: algo,
      colorModel: colorModel,
    );
  });
}

/// Generates a list of [Palette]s by rotating the hue of a seed color around
/// the color wheel, maximizing the angular distance between colors.
///
/// As opposed to [generateColorScaleFixedBackground], the hue is rotated for
/// [Palette.background] as well.
List<Palette> generateColorScale(
  Color seed, {
  required int count,
  required double contrast,
  required double backgroundTone,
  Algo algo = .apca,
}) {
  final base = Hct.fromColor(seed);
  final startHue = base.hue;
  final chroma = math.max(base.chroma, 40.0);
  final tone = base.tone.clamp(40.0, 70.0);

  return List.generate(count, (i) {
    final hue = (startHue + 30 * i) % 360;
    final color = Hct.from(hue, chroma, tone).color;
    return Palette.from(
      color,
      backgroundTone: backgroundTone,
      contrast: contrast,
      algo: algo,
    );
  });
}
