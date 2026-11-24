@Tags(['perf'])
library;

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monet_ui/util/blur_radius.dart';
import 'package:monet_ui/widgets/rich_text/paint_strategy.dart';
import 'package:monet_ui/widgets/rich_text/paragrapher.dart';
import 'package:monet_ui/widgets/snapped_icons/icon_grid_fit.dart';

import '../../widgets/paint_reuse_fixtures.dart';

// Alternate order; discard warm-up and report medians. No CI time threshold.
void compare(String label, void Function(bool reuse) batch) {
  final before = <int>[], after = <int>[];
  for (var pass = 0; pass <= 9; pass++) {
    for (final reuse in [pass.isOdd, pass.isEven]) {
      final timer = Stopwatch()..start();
      batch(reuse);
      timer.stop();
      if (pass > 0) (reuse ? after : before).add(timer.elapsedMicroseconds);
    }
  }
  before.sort();
  after.sort();
  // ignore: avoid_print
  print('$label: median ${before[4]} -> ${after[4]} us/batch');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('64 distinct path misses per size, same outline', () {
    final shape = barsOutline();
    compare('16 sizes × 64 distinct phase pairs', (reuse) {
      final cache = IconPathCache();
      for (var size = 16.0; size < 32; size++) {
        for (var x = 0; x < 8; x++) {
          for (var y = 0; y < 8; y++) {
            final phase = Offset(x / 8, y / 8);
            if (reuse) {
              cache.lookup(shape, size: size, deviceScale: 2, phase: phase);
            } else {
              gridFitIconOutline(
                shape,
                size: size,
                deviceScale: 2,
                phase: phase,
              );
            }
          }
        }
      }
    });
  });
  test('spread stroke recording, standard and offset-only recipes', () {
    const color = Color(0x996688aa);
    final p = Paragrapher(),
        painter = TextPainter(textDirection: TextDirection.ltr);
    final label = spreadLabel(p);
    addTearDown(p.dispose);
    addTearDown(painter.dispose);
    for (final (name, shadows) in [
      ('protection (1 spread)', protectionShadows(color)),
      (
        '4 offset spreads',
        [
          for (var i = 0; i < 4; i++)
            BoxShadow(
              color: color,
              spreadRadius: 1,
              offset: Offset(i * 1.5, 1),
            ),
        ],
      ),
    ]) {
      compare('256 × $name', (reuse) {
        final draw = reuse ? paintSpreadStrokes : referenceSpreadStrokes;
        for (var i = 0; i < 256; i++) {
          final recorder = ui.PictureRecorder();
          draw(Canvas(recorder), painter, label, shadows, asMask: true);
          recorder.endRecording().dispose();
        }
      });
    }
  });
}
