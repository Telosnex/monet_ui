import 'package:monet_ui/contrast/contrast.dart';
import 'package:monet_ui/core/argb_srgb_xyz_lab.dart';
import 'package:monet_ui/core/hex_codes.dart';
import 'package:pixel_snap_fork/material.dart';

Brightness brightnessOfColor(Color color) {
  final lstar = lstarFromArgb(color.argb);
  return brightnessOfTone(lstar);
}

Brightness brightnessOfTone(double tone) {
  return lstarPrefersLighterPair(tone.roundToDouble()) ? .dark : .light;
}
