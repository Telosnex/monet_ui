import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:monet_ui/widgets/rich_text/paragrapher.dart';
import 'package:monet_ui/widgets/snapped_icons/icon_outline.dart';

// Three vertical bars with repeated stems, plus a horizontal bar.
IconOutline barsOutline() {
  final verbs = <int>[];
  final points = <int>[];
  void rect(int x, int y, int w, int h) {
    verbs.addAll([
      OutlineVerb.move,
      OutlineVerb.line,
      OutlineVerb.line,
      OutlineVerb.line,
      OutlineVerb.close,
    ]);
    points.addAll([x, y, x + w, y, x + w, y + h, x, y + h]);
  }

  for (final x in [64, 192, 320]) {
    rect(x, 48, 43, 320);
  }
  rect(48, 400, 384, 44);
  return IconOutline(Uint8List.fromList(verbs), Int16List.fromList(points));
}

ParagraphResult spreadLabel(Paragrapher p) => p.layout(
  ParagraphInput(
    textSpan: const TextSpan(text: 'Resize'),
    text: 'Resize',
    style: const TextStyle(fontSize: 14),
    paintColor: const Color(0xffffffff),
    direction: TextDirection.ltr,
    maxLines: 1,
    align: TextAlign.left,
    textScaler: TextScaler.noScaling,
    strutStyle: null,
    placeholderSizes: const [],
    maxWidth: 144,
    softWrap: true,
  ),
);

// Reference for both pixel parity and timing: configure and lay out every
// visible spread, exactly as before offset-only reuse.
void referenceSpreadStrokes(
  Canvas canvas,
  TextPainter painter,
  ParagraphResult layout,
  List<Shadow> shadows, {
  required bool asMask,
}) {
  for (final s in shadows) {
    if (s is! BoxShadow || s.spreadRadius <= 0 || s.color.a <= 0) continue;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * s.spreadRadius
      ..strokeJoin = StrokeJoin.round
      ..color = asMask
          ? Color.from(alpha: s.color.a, red: 1, green: 1, blue: 1)
          : s.color;
    if (s.blurRadius > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, s.blurSigma);
    }
    final input = layout.input.copyWith(
      style: layout.input.style.copyWith(shadows: const [], foreground: paint),
    );
    Paragrapher.configure(painter, input);
    painter.layout(maxWidth: input.maxWidth);
    painter.paint(canvas, s.offset);
  }
}
