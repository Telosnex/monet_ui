import 'dart:ui';

import 'package:monet_ui/colorspaces/cam16V11/cam16_v11.dart';
import 'package:monet_ui/colorspaces/hct.dart';
import 'package:monet_ui/core/argb_srgb_xyz_lab.dart';
import 'package:monet_ui/core/hex_codes.dart';

Color hctLerpCartesian(Color a, Color b, double t) {
  final camA = Cam16V11.fromInt(a.argb);
  final camB = Cam16V11.fromInt(b.argb);
  final aStar = lerpDouble(camA.astar, camB.astar, t)!;
  final bStar = lerpDouble(camA.bstar, camB.bstar, t)!;
  final jStar = lerpDouble(camA.jstar, camB.jstar, t)!;
  final camMerged = Cam16V11.fromUcs(jStar, aStar, bStar);
  final aTone = lstarFromArgb(a.argb);
  final bTone = lstarFromArgb(b.argb);
  final tone = lerpDouble(aTone, bTone, t)!;
  return Hct.from(camMerged.hue, camMerged.chroma, tone).color;
}
