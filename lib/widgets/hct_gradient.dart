/// Gradient constructors that interpolate through HCT color space.
///
/// Flutter's [Gradient] is a `base class` with native Skia/Impeller shaders,
/// so we can't subclass it. Instead we sample the HCT lerp curve at [steps]
/// evenly-spaced points and feed those to the standard multi-stop constructors.
/// With ≥16 stops the visual difference from true HCT interpolation is
/// imperceptible.
///
/// Two interpolation modes are provided, matching [Hct]'s static lerps:
///
/// - **keepHue** — hue rotates along the shortest arc while chroma and tone
///   interpolate linearly. Good for gradients between related colors (same
///   family, different lightness).
///
/// - **loseHueAndChroma** — interpolates in CAM16-UCS (Jstar/astar/bstar),
///   allowing the path to pass through lower-chroma midpoints. Good for
///   gradients between unrelated colors where a desaturated middle is
///   preferable to a hue-shifted one.
library;

import 'dart:typed_data';
import 'dart:ui';

import 'package:monet_ui/colorspaces/hct.dart';

/// Number of sample stops. 16 is enough for smooth HCT gradients — the max
/// delta-E between adjacent samples is well below the just-noticeable
/// difference threshold (~1.0) for typical color pairs.
const int _kDefaultSteps = 16;

class _SampledGradient {
  final List<Color> colors;
  final List<double> stops;
  const _SampledGradient(this.colors, this.stops);
}

/// A linear gradient that interpolates through HCT (keep-hue mode).
///
/// Drop-in replacement for [Gradient.linear] with perceptually uniform
/// color transitions.
Gradient hctLinearGradient(
  Offset from,
  Offset to,
  List<Color> colors, {
  List<double>? colorStops,
  TileMode tileMode = .clamp,
  Float64List? matrix4,
  int steps = _kDefaultSteps,
  bool keepHue = true,
}) {
  final sampled = _sampleGradient(colors, colorStops, steps, keepHue: keepHue);
  return Gradient.linear(
    from,
    to,
    sampled.colors,
    sampled.stops,
    tileMode,
    matrix4,
  );
}

/// A radial gradient that interpolates through HCT (keep-hue mode).
Gradient hctRadialGradient(
  Offset center,
  double radius,
  List<Color> colors, {
  List<double>? colorStops,
  TileMode tileMode = .clamp,
  Float64List? matrix4,
  Offset? focal,
  double focalRadius = 0.0,
  int steps = _kDefaultSteps,
  bool keepHue = true,
}) {
  final sampled = _sampleGradient(colors, colorStops, steps, keepHue: keepHue);
  return Gradient.radial(
    center,
    radius,
    sampled.colors,
    sampled.stops,
    tileMode,
    matrix4,
    focal,
    focalRadius,
  );
}

/// A sweep gradient that interpolates through HCT (keep-hue mode).
Gradient hctSweepGradient(
  Offset center,
  List<Color> colors, {
  List<double>? colorStops,
  TileMode tileMode = .clamp,
  double startAngle = 0.0,
  double endAngle = 3.14159265358979323846 * 2,
  Float64List? matrix4,
  int steps = _kDefaultSteps,
  bool keepHue = true,
}) {
  final sampled = _sampleGradient(colors, colorStops, steps, keepHue: keepHue);
  return Gradient.sweep(
    center,
    sampled.colors,
    sampled.stops,
    tileMode,
    startAngle,
    endAngle,
    matrix4,
  );
}

/// Samples a multi-stop gradient through HCT color space.
///
/// Given N input [colors] (with optional [colorStops]), produces
/// [steps] evenly-spaced output colors by lerping each adjacent pair
/// through HCT.
///
/// Returns (colors, stops) suitable for any [Gradient] constructor.
_SampledGradient _sampleGradient(
  List<Color> colors,
  List<double>? colorStops,
  int steps, {
  required bool keepHue,
}) {
  assert(colors.length >= 2, 'Need at least 2 colors');
  assert(steps >= 2, 'Need at least 2 steps');

  // Normalise stops: default to evenly spaced.
  final stops =
      colorStops ??
      List.generate(colors.length, (i) => i / (colors.length - 1));

  final lerp = keepHue ? Hct.lerpKeepHue : Hct.lerpLoseHueAndChroma;

  final outColors = <Color>[];
  final outStops = <double>[];

  for (var s = 0; s < steps; s++) {
    final t = s / (steps - 1); // 0.0 → 1.0

    // Find which segment of the input gradient this t falls in.
    var segIdx = 0;
    for (var i = 0; i < stops.length - 1; i++) {
      if (t >= stops[i]) segIdx = i;
    }

    final segStart = stops[segIdx];
    final segEnd = stops[segIdx + 1];
    final segT = segEnd == segStart
        ? 0.0
        : (t - segStart) / (segEnd - segStart);

    outColors.add(lerp(colors[segIdx], colors[segIdx + 1], segT));
    outStops.add(t);
  }

  return _SampledGradient(outColors, outStops);
}
