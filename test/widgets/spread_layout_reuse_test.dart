import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monet_ui/widgets/raster_cache_diagnostics.dart';
import 'package:monet_ui/widgets/rich_text/paint_strategy.dart';
import 'package:monet_ui/widgets/rich_text/paragrapher.dart';

import 'paint_reuse_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final mask in [false, true]) {
    test(
      'offset-only spread passes match separate draws, mask=$mask',
      () async {
        final p = Paragrapher();
        final painter = TextPainter(textDirection: TextDirection.ltr);
        addTearDown(p.dispose);
        addTearDown(painter.dispose);
        final label = spreadLabel(p);
        BoxShadow s(
          double x, {
          Color color = const Color(0x80449922),
          double spread = 1,
          double blur = 0,
        }) => BoxShadow(
          color: color,
          offset: Offset(x, 2),
          blurRadius: blur,
          spreadRadius: spread,
        );
        final shadows = [
          s(1),
          const Shadow(),
          s(2.5),
          s(4, color: const Color(0x80441166)),
          s(4, color: const Color(0xa0441166)),
          s(4, spread: 2),
          s(5, spread: 2, blur: 2),
          s(6, spread: 2, blur: 2),
        ];
        Future<Uint8List> pixels(bool separate) async {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder)..translate(10, 10);
          final draw = separate ? referenceSpreadStrokes : paintSpreadStrokes;
          draw(canvas, painter, label, shadows, asMask: mask);
          final picture = recorder.endRecording();
          final image = await picture.toImage(176, 50);
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          picture.dispose();
          return data!.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
        }

        final reference = await pixels(true);
        expect(reference.any((byte) => byte != 0), isTrue);
        final before = RasterCacheDiagnostics.snapshot();
        expect(await pixels(false), orderedEquals(reference));
        final counts = RasterCacheDiagnostics.since(before);
        expect(counts['text.spreadLayoutBuilt'], mask ? 4 : 5);
        expect(counts['text.spreadLayoutReused'], mask ? 3 : 2);
      },
    );
  }
}
