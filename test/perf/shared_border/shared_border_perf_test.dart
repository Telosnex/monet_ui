// Performance: uncached AnyBackground.sharedBorder vs today's per-palette
// colorBorder, per kind of background.
//
// Every candidate call clears the background's answer cache first, so each
// one is a full solve. PerfTester runs each case many times, and with the
// cache on, nearly all of those were hits: the old version of this test
// reported a speedup that was the cache's, not the solve's.
//
// Implementations, per chip set of three:
// - today: 3x Palette.from, reading each colorBorder.
// - palettes + solve: the same palettes, then one uncached shared border.
// - solve only: the uncached shared border alone, surfaces precomputed.
//
// Kinds: solid (one color), flat (synthetic blobs with noise), photo (the
// Unsplash fixtures, scaled to 96px like Extract), unknown.
//
// Run: flutter test test/perf/shared_border/shared_border_perf_test.dart

// ignore_for_file: avoid_print

@Tags(['perf'])
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monet_ui/monet_ui.dart';

import 'package:perf_tester/perf_tester.dart';

const _contrast = 0.5;

typedef _Input = ({
  List<Color> chips,
  List<int> surfaces,
  double backgroundTone,
  AnyBackground background,
});

List<Palette> _palettes(_Input input) => [
  for (final c in input.chips)
    Palette.from(c, backgroundTone: input.backgroundTone, contrast: _contrast),
];

/// Baseline: what a chip set costs today.
int _today(_Input input) {
  var acc = 0;
  for (final p in _palettes(input)) {
    acc ^= p.color.argb ^ p.colorBorder.argb;
  }
  return acc;
}

/// Same palettes, then one uncached shared border.
int _palettesAndSolve(_Input input) {
  final palettes = _palettes(input);
  input.background.clearAnswerCaches();
  final border = input.background.sharedBorder([
    for (final p in palettes) p.color.argb,
  ]);
  var acc = 0;
  for (var i = 0; i < palettes.length; i++) {
    acc ^= palettes[i].color.argb ^ border.borderArgbs[i];
  }
  return acc;
}

/// The uncached shared border alone.
int _solveOnly(_Input input) {
  input.background.clearAnswerCaches();
  final border = input.background.sharedBorder(input.surfaces);
  return border.borderArgbs.fold(0, (a, b) => a ^ b);
}

/// A synthetic wallpaper: [regions] blobs of random color with noise.
List<int> _wallpaper(math.Random rng, int regions, int pixels) {
  final centers = [
    for (var i = 0; i < regions; i++) 0xff000000 | rng.nextInt(0xffffff),
  ];
  return [
    for (var i = 0; i < pixels; i++)
      () {
        final c = centers[rng.nextInt(regions)];
        int ch(int shift) =>
            (((c >> shift) & 0xff) + rng.nextInt(31) - 15).clamp(0, 255);
        return 0xff000000 | (ch(16) << 16) | (ch(8) << 8) | ch(0);
      }(),
  ];
}

Future<List<int>> _photo(String path) async {
  final rgba = await imageProviderToScaledRgba(FileImage(File(path)), 96);
  final bytes = rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes);
  return [
    for (var i = 0; i + 3 < bytes.length; i += 4)
      0xff000000 | (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2],
  ];
}

AnyBackground _bg(List<int> argbs) =>
    AnyBackground(argbs, algo: Algo.apca, contrast: _contrast);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clearAnswerCaches forces a fresh solve', () {
    final bg = _bg(_wallpaper(math.Random(1), 4, 96 * 64));
    const surfaces = [0xffb431ed, 0xff4d394f, 0xff536d2d];
    final a = bg.sharedBorder(surfaces);
    expect(identical(bg.sharedBorder(surfaces), a), isTrue);
    bg.clearAnswerCaches();
    final b = bg.sharedBorder(surfaces);
    expect(identical(b, a), isFalse);
    expect(b, a);
  });

  test('shared border perf, uncached, by background kind', () async {
    final rng = math.Random(42);
    // 96px wide at 3:2, as Extract downscales.
    const pixels = 96 * 64;
    final photoPaths = [
      for (final f in Directory('test/fixtures/wallpapers').listSync())
        if (f.path.endsWith('.jpg')) f.path,
    ]..sort();
    final photos = [for (final path in photoPaths) await _photo(path)];
    final kinds = <String, List<List<int>>>{
      'solid': [
        for (var i = 0; i < 24; i++) [0xff000000 | rng.nextInt(0xffffff)],
      ],
      'flat': [
        for (final regions in [1, 2, 4, 8, 16, 32])
          for (var i = 0; i < 4; i++) _wallpaper(rng, regions, pixels),
      ],
      'photo': photos,
      'unknown': [const []],
    };

    final summary = <String>[];
    for (final MapEntry(key: kind, value: images) in kinds.entries) {
      final backgrounds = [
        for (final w in images)
          w.isEmpty
              ? AnyBackground.unknown(algo: Algo.apca, contrast: _contrast)
              : _bg(w),
      ];
      final testCases = <_Input>[];
      for (var i = 0; i < 200; i++) {
        final chips = [
          for (var c = 0; c < 3; c++)
            Hct.from(
              rng.nextDouble() * 360,
              10 + rng.nextDouble() * 60,
              5 + rng.nextDouble() * 90,
            ).color,
        ];
        final backgroundTone = rng.nextDouble() * 100;
        testCases.add((
          chips: chips,
          surfaces: [
            for (final c in chips)
              Palette.from(
                c,
                backgroundTone: backgroundTone,
                contrast: _contrast,
              ).color.argb,
          ],
          backgroundTone: backgroundTone,
          background: backgrounds[rng.nextInt(backgrounds.length)],
        ));
      }
      // Reduce pixels outside the timed runs; that's per wallpaper change.
      for (final b in backgrounds) {
        b.sharedBorder(const [0xff808080]);
      }
      final distinct = [
        for (final w in images) {for (final p in w) p | 0xff000000}.length,
      ]..sort();

      final result = await PerfTester<_Input, int>.multi(
        testName:
            'sharedBorder, uncached, $kind backgrounds '
            '(${images.length}, distinct pixels '
            '${distinct.first}..${distinct.last})',
        testCases: testCases,
        implementations: const [
          PerfImpl('today: 3x Palette.colorBorder', _today),
          PerfImpl('palettes + uncached sharedBorder', _palettesAndSolve),
          PerfImpl('uncached sharedBorder only', _solveOnly),
        ],
      ).run(warmupRuns: 10, benchmarkRuns: 20, skipEqualityCheck: true);
      String perSet(ImplResult r) {
        final median = r.sortedSamples[r.sortedSamples.length ~/ 2];
        return '${(median / r.casesPerSample * 1000).toStringAsFixed(1)} µs';
      }

      summary.add(
        '${kind.padRight(8)}${[for (final r in result.implementations) '${r.name}: ${perSet(r)}'].join(' | ')}',
      );
    }
    print('');
    print('Median per chip set of three:');
    summary.forEach(print);

    // Per-image setup: a new background reducing its pixels, then its first
    // answer. Once per wallpaper change.
    const surfaces = [0xffb431ed, 0xff4d394f, 0xff536d2d];
    for (final kind in ['flat', 'photo']) {
      final images = kinds[kind]!;
      const runs = 100;
      final watch = Stopwatch()..start();
      for (var i = 0; i < runs; i++) {
        _bg(images[i % images.length]).sharedBorder(surfaces);
      }
      print(
        'New $kind background + first sharedBorder: '
        '${(watch.elapsedMicroseconds / runs / 1000).toStringAsFixed(2)} ms',
      );
    }
  }, timeout: Timeout.none);
}
