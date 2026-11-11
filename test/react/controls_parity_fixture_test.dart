// Reads files (dart:io): the VM only.
@TestOn('vm')
library;

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' as flutter;
import 'package:flutter_test/flutter_test.dart';
import 'package:monet_ui/theming/monet_shape_theme.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/monet_theme_data.dart';
import 'package:monet_ui/third_party/flutter/expansion_tile_2.dart';
import 'package:monet_ui/util/blur_radius.dart';
import 'package:monet_ui/widgets/bordered.dart';
import 'package:monet_ui/widgets/menu/menu_entry.dart';
import 'package:monet_ui/widgets/menu/monet_menu_overlay.dart';
import 'package:monet_ui/widgets/monet_button.dart';
import 'package:monet_ui/widgets/monet_button_core.dart';
import 'package:monet_ui/widgets/monet_dropdown.dart';
import 'package:monet_ui/widgets/monet_expansion.dart';
import 'package:monet_ui/widgets/monet_fallback_shapes.dart';
import 'package:monet_ui/widgets/monet_segmented.dart';
import 'package:monet_ui/widgets/monet_slider.dart';
import 'package:pixel_snap_fork/material.dart';

/// Writes `react/fixtures/monet_controls_parity.json`: what the Dart controls
/// resolve to, per theme, variant and state. The React package's tests
/// compare their own resolved values with it (ADR 003 D5).
///
/// Values are read from the built widgets. Where a value lives in a private
/// painter or render object, the test reads the public input that the widget
/// passes to it, and a comment names the private code.
const _fixturePath = 'react/fixtures/monet_controls_parity.json';

/// The top-left corner of Flutter's `RSuperellipse` at radius 100 in a
/// large square, as points every 2 logical pixels along the path. The
/// curve reaches about 3 × the radius along each edge.
Map<String, Object?> _superellipseCorner() {
  const radius = 100.0;
  const reach = 300.0;
  final path = Path()
    ..addRSuperellipse(
      RSuperellipse.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 1000, 1000),
        const Radius.circular(radius),
      ),
    );
  final points = <List<double>>[];
  for (final metric in path.computeMetrics()) {
    for (var d = 0.0; d < metric.length; d += 2) {
      final p = metric.getTangentForOffset(d)!.position;
      if (p.dx <= reach && p.dy <= reach) {
        points.add([_round(p.dx), _round(p.dy)]);
      }
    }
  }
  return {'radius': radius, 'points': points};
}

class _ThemeCase {
  const _ThemeCase({
    required this.name,
    required this.color,
    required this.backgroundTone,
    required this.brightness,
    required this.scale,
    required this.shapeTheme,
    required this.corner,
  });

  final String name;
  final int color;
  final double backgroundTone;
  final Brightness brightness;
  final double scale;
  final MonetShapeTheme shapeTheme;
  final String corner;
  static const contrast = 0.5;

  MonetThemeData get data => MonetThemeData.fromColor(
    color: Color(color),
    backgroundTone: backgroundTone,
    brightness: brightness,
    contrast: contrast,
    scale: scale,
    shapeTheme: shapeTheme,
  );

  Map<String, Object?> toJson() => {
    'color': _hex(Color(color)),
    'backgroundTone': backgroundTone,
    'brightness': brightness.name,
    'contrast': contrast,
    'scale': scale,
    'radius': _round(
      shapeTheme.borderRadius.resolve(TextDirection.ltr).topLeft.x,
    ),
    'corner': corner,
  };
}

final _themes = [
  const _ThemeCase(
    name: 'light',
    color: 0xff4b778f,
    backgroundTone: 93,
    brightness: .light,
    scale: 1,
    shapeTheme: kMonetFallbackShapeTheme,
    corner: 'superellipse',
  ),
  const _ThemeCase(
    name: 'dark',
    color: 0xff4b778f,
    backgroundTone: 10,
    brightness: .dark,
    scale: 1,
    shapeTheme: MonetShapeTheme(),
    corner: 'rounded',
  ),
  const _ThemeCase(
    name: 'small',
    color: 0xffd29c57,
    backgroundTone: 93,
    brightness: .light,
    scale: 0.64,
    shapeTheme: kMonetFallbackShapeTheme,
    corner: 'superellipse',
  ),
];

String _hex(Color c) {
  String two(double v) =>
      (v * 255).round().toRadixString(16).padLeft(2, '0').toUpperCase();
  final rgb = '#${two(c.r)}${two(c.g)}${two(c.b)}';
  return c.a >= 1 ? rgb : '$rgb${two(c.a)}';
}

/// The colour without its alpha, and the alpha as opacity.
String _rgb(Color c) => _hex(c.withValues(alpha: 1));

double _round(double v) => (v * 1000).round() / 1000;

Map<String, Object?> _shape(ShapeBorder shape) {
  final radius = switch (shape) {
    RoundedSuperellipseBorder(:final borderRadius) ||
    RoundedRectangleBorder(
      :final borderRadius,
    ) => borderRadius.resolve(TextDirection.ltr).topLeft.x,
    _ => throw StateError('Unexpected shape ${shape.runtimeType}'),
  };
  return {
    'radius': _round(radius),
    'corner': shape is RoundedSuperellipseBorder ? 'superellipse' : 'rounded',
  };
}

BorderSide _side(ShapeBorder shape) => switch (shape) {
  OutlinedBorder(:final side) => side,
  Border(:final top) => top,
  _ => throw StateError('Unexpected shape ${shape.runtimeType}'),
};

/// CSS draws a box shadow's blur as twice its Gaussian sigma; the fixture
/// keeps the sigma.
List<Map<String, Object?>> _shadows(List<BoxShadow> shadows) => [
  for (final s in shadows)
    {
      'color': _rgb(s.color),
      'opacity': _round(s.color.a),
      'spread': _round(s.spreadRadius),
      'sigma': _round(s.blurSigma),
      'dx': _round(s.offset.dx),
      'dy': _round(s.offset.dy),
    },
];

Widget _app(_ThemeCase theme, Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: MonetTheme(
    monetThemeData: theme.data,
    child: Scaffold(
      body: Center(child: SizedBox(width: 300, child: child)),
    ),
  ),
);

const _buttonStates = <String, Set<WidgetState>>{
  'rest': {},
  'hovered': {WidgetState.hovered},
  'focused': {WidgetState.focused},
  'pressed': {WidgetState.pressed},
  'disabled': {WidgetState.disabled},
};

/// The values of the [MonetButtonCore] that [finder] holds.
Map<String, Object?> _buttonValues(WidgetTester tester, Finder finder) {
  final core = tester.widget<MonetButtonCore>(
    find.descendant(of: finder, matching: find.byType(MonetButtonCore)),
  );
  final context = tester.element(
    find.descendant(of: finder, matching: find.byType(MonetButtonCore)),
  );
  final style = core.style!;
  // MonetButtonCore.build: the shape falls back to the theme's shapes.
  final shape =
      style.shape?.resolve(const {}) ?? MonetTheme.shapesOf(context).border();
  final minimum = style.minimumSize!.resolve(const {})!;
  // MonetButtonCore.build: VisualDensity.compact takes 8 from the minimum
  // size and from the vertical padding (4), which clamps at zero.
  const densityAdjustment = 8.0;
  // MonetButtonCore.build `sideFor`: the shadow colour doubles as a 1px
  // border; with no shadow, the outline colour does.
  final shadow = core.shadowColor;
  final hasShadow = shadow != Colors.transparent;
  final borderColor = hasShadow ? shadow : core.outlineColorWhenNoShadow;
  return {
    'states': {
      for (final MapEntry(:key, :value) in _buttonStates.entries)
        key: {
          'background': _hex(style.backgroundColor!.resolve(value)!),
          'foreground': _hex(style.foregroundColor!.resolve(value)!),
          'icon': _hex(style.iconColor!.resolve(value)!),
        },
    },
    'border': borderColor == null
        ? null
        : {'color': _hex(borderColor), 'width': 1},
    // _TintedAestheticShadow tints this white mask with the shadow colour.
    'shadows': hasShadow
        ? _shadows(aestheticShadows(shadow, includeOutline: false))
        : <Object>[],
    'minHeight': _round(
      (minimum.height - densityAdjustment).clamp(0, double.infinity),
    ),
    'minWidth': _round(
      (minimum.width - densityAdjustment).clamp(0, double.infinity),
    ),
    'paddingX': _round(core.internalPadding),
    'paddingY': 0,
    ..._shape(shape),
  };
}

Future<Map<String, Object?>> _buttonCase(
  WidgetTester tester,
  _ThemeCase theme, {
  required MonetButtonKind kind,
  required MonetButtonPreset preset,
  required String family,
}) async {
  await tester.pumpWidget(
    _app(
      theme,
      Builder(
        builder: (context) {
          final monet = MonetTheme.of(context);
          return MonetButton(
            colors: switch (family) {
              'secondary' => monet.secondary,
              'tertiary' => monet.tertiary,
              _ => monet.primary,
            },
            kind: kind,
            preset: preset,
            label: 'Button',
            onPressed: () {},
          );
        },
      ),
    ),
  );
  return {
    'control': 'MonetButton',
    'theme': theme.name,
    'props': {'kind': kind.name, 'preset': preset.name, 'family': family},
    'values': _buttonValues(tester, find.byType(MonetButton)),
  };
}

Future<Map<String, Object?>> _expansionCase(
  WidgetTester tester,
  _ThemeCase theme, {
  required String title,
}) async {
  await tester.pumpWidget(
    _app(theme, MonetExpansion(title: title, children: const [Text('Body')])),
  );
  final tile = tester.widget<ExpansionTile2>(find.byType(ExpansionTile2));
  final listTile = ListTileTheme.of(
    tester.element(find.byType(ExpansionTile2)),
  );
  final expandedSide = _side(tile.shape!);
  final collapsedSide = _side(tile.collapsedShape!);
  return {
    'control': 'MonetExpansion',
    'theme': theme.name,
    'props': {'title': title},
    'values': {
      'collapsed': {
        'background': _hex(tile.collapsedBackgroundColor!),
        'icon': _hex(tile.collapsedIconColor!),
        'border': {
          'color': _hex(collapsedSide.color),
          'width': collapsedSide.width,
        },
      },
      'expanded': {
        'background': _hex(tile.backgroundColor!),
        'icon': _hex(tile.iconColor!),
        'border': {
          'color': _hex(expandedSide.color),
          'width': expandedSide.width,
        },
      },
      'headerMinHeight': _round(listTile.minTileHeight!),
      'headerPaddingStart': _round(
        tile.tilePadding!.resolve(TextDirection.ltr).left,
      ),
      ..._shape(tile.shape!),
    },
  };
}

enum _Segment { a, b, c }

Future<Map<String, Object?>> _segmentedCase(
  WidgetTester tester,
  _ThemeCase theme, {
  required bool isSmall,
}) async {
  await tester.pumpWidget(
    _app(
      theme,
      Align(
        alignment: Alignment.centerLeft,
        child: MonetSegmented<_Segment>(
          isSmall: isSmall,
          options: const [
            MonetSegment(value: _Segment.a, label: 'i'),
            MonetSegment(value: _Segment.b, label: 'Selected'),
            MonetSegment(value: _Segment.c, label: 'Other'),
          ],
          selectedValue: _Segment.b,
          onChanged: (_) {},
        ),
      ),
    ),
  );
  final segmented = find.byType(MonetSegmented<_Segment>);
  final outer = tester.widget<Container>(
    find.descendant(of: segmented, matching: find.byType(Container)).first,
  );
  final decoration = outer.decoration! as ShapeDecoration;
  // _SegmentedRow is private; its divider colour is a public field.
  final row = tester
      .widgetList(
        find.descendant(
          of: segmented,
          matching: find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_SegmentedRow',
          ),
        ),
      )
      .single;
  final dividerColor = (row as dynamic).dividerColor as Color;

  // The segment labels paint their own text, so find segments by order.
  const order = ['i', 'Selected', 'Other'];
  Finder segmentBox(String label) => find
      .descendant(of: segmented, matching: find.byType(AnimatedContainer))
      .at(order.indexOf(label));

  Map<String, Object?> read(String label) {
    final box = tester.widget<AnimatedContainer>(segmentBox(label));
    final text = tester.widget<DefaultTextStyle>(
      find
          .descendant(
            of: segmentBox(label),
            matching: find.byType(DefaultTextStyle),
          )
          .first,
    );
    final icon = tester.widget<IconTheme>(
      find
          .descendant(of: segmentBox(label), matching: find.byType(IconTheme))
          .first,
    );
    return {
      'background': _hex((box.decoration! as BoxDecoration).color!),
      'foreground': _hex(text.style.color!),
      'icon': _hex(icon.data.color!),
    };
  }

  Future<Map<String, Object?>> states(String label) async {
    final rest = read(label);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(segmentBox(label)));
    await tester.pumpAndSettle();
    final hovered = read(label);
    await mouse.down(tester.getCenter(segmentBox(label)));
    await tester.pumpAndSettle();
    final pressed = read(label);
    await mouse.up();
    await mouse.moveTo(Offset.zero);
    await mouse.removePointer();
    await tester.pumpAndSettle();
    return {'rest': rest, 'hovered': hovered, 'pressed': pressed};
  }

  final selected = await states('Selected');
  final unselected = await states('Other');
  final narrow = tester.getSize(segmentBox('i')).width;
  final padding = tester
      .widget<AnimatedContainer>(segmentBox('Other'))
      .padding!
      .resolve(TextDirection.ltr);
  return {
    'control': 'MonetSegmented',
    'theme': theme.name,
    'props': {'isSmall': isSmall},
    'values': {
      'selected': selected,
      'unselected': unselected,
      'divider': {'color': _hex(dividerColor), 'width': 1},
      'shadows': _shadows(decoration.shadows!),
      'minSegmentWidth': _round(narrow),
      'paddingX': _round(padding.left),
      ..._shape(decoration.shape),
    },
  };
}

Future<Map<String, Object?>> _sliderCase(
  WidgetTester tester,
  _ThemeCase theme,
) async {
  var value = 0.5;
  Future<void> pump({required bool enabled}) => tester.pumpWidget(
    _app(
      theme,
      MonetSlider(
        value: value,
        enabled: enabled,
        thumbIcon: Icons.add,
        onChanged: (v) => value = v,
      ),
    ),
  );

  // _MonetSliderPainter is private; its colours and height are public
  // fields.
  dynamic painter() => tester
      .widgetList<CustomPaint>(
        find.descendant(
          of: find.byType(MonetSlider),
          matching: find.byType(CustomPaint),
        ),
      )
      .map((w) => w.painter)
      .singleWhere((p) => p.runtimeType.toString() == '_MonetSliderPainter');

  Map<String, Object?> colors() {
    final p = painter();
    final active = p.activeTrackColor as Color;
    return {
      'activeTrack': _rgb(active),
      'inactiveTrack': _rgb(p.inactiveTrackColor as Color),
      'border': _rgb(p.borderColor as Color),
      'thumbContent': _rgb(p.thumbContentColor as Color),
      'opacity': _round(active.a),
    };
  }

  await pump(enabled: true);
  final rest = colors();
  final trackHeight = painter().trackHeight as double;
  final focus = tester
      .widgetList<Focus>(
        find.descendant(
          of: find.byType(MonetSlider),
          matching: find.byType(Focus),
        ),
      )
      .firstWhere((f) => f.focusNode != null);
  focus.focusNode!.requestFocus();
  await tester.pump();
  final focused = colors();
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
  await tester.pumpAndSettle();
  final keyStep = value - 0.5;
  value = 0.5;
  await pump(enabled: false);
  final disabled = colors();
  return {
    'control': 'MonetSlider',
    'theme': theme.name,
    'props': <String, Object?>{},
    'values': {
      'rest': rest,
      'focused': focused,
      'disabled': disabled,
      'trackHeight': _round(trackHeight),
      // _MonetSliderPainter.paint: the track border and the thumb's
      // half-circle are 1px strokes; an outer blur of sigma 2 in the border
      // colour; thumb content is 1.2 × the radius.
      'borderWidth': 1,
      'glowSigma': 2,
      'thumbContentFraction': 0.6,
      'keyStep': _round(keyStep),
    },
  };
}

Future<Map<String, Object?>> _dropdownCase(
  WidgetTester tester,
  _ThemeCase theme,
) async {
  await tester.pumpWidget(
    _app(
      theme,
      Align(
        alignment: Alignment.topLeft,
        child: MonetDropdown<String>(
          items: const ['One', 'Two', 'Three'],
          selectedLabel: 'Two',
          selectedValue: 'Two',
          onChanged: (_) {},
          menuItemBuilder: (context, item) =>
              MenuEntry.create(title: item, icon: null, action: () {}),
        ),
      ),
    ),
  );
  final trigger = _buttonValues(tester, find.byType(MonetDropdown<String>));
  await tester.tap(find.byType(MonetDropdown<String>));
  await tester.pumpAndSettle();
  // The overlay uses Flutter's Container, not pixel_snap's.
  final body = tester.widget<flutter.Container>(
    find.byKey(MonetMenuOverlayController.kMenuBodyKey),
  );
  final decoration = body.decoration! as ShapeDecoration;
  final side = _side(decoration.shape);
  final padding = body.padding!.resolve(TextDirection.ltr);

  Map<String, Object?> item(String title) {
    final entry = tester
        .widgetList<MenuEntryCompat>(find.byType(MenuEntryCompat))
        .singleWhere((e) => e.title == title);
    // MenuEntryCompat.build: a selected entry rests in the splashed colours.
    return {
      'rest': {
        'background': _hex(
          entry.selected
              ? entry.backgroundSplashedColor!
              : entry.backgroundColor!,
        ),
        'foreground': _hex(
          entry.selected ? entry.textSplashedColor! : entry.textColor!,
        ),
        'icon': _hex(
          entry.selected ? entry.iconSplashedColor! : entry.iconColor!,
        ),
      },
      'hovered': {
        'background': _hex(entry.backgroundHoveredColor!),
        'foreground': _hex(entry.textHoveredColor!),
        'icon': _hex(entry.iconHoveredColor!),
      },
      'pressed': {
        'background': _hex(entry.backgroundSplashedColor!),
        'foreground': _hex(entry.textSplashedColor!),
        'icon': _hex(entry.iconSplashedColor!),
      },
    };
  }

  return {
    'control': 'MonetDropdown',
    'theme': theme.name,
    'props': <String, Object?>{},
    'values': {
      'trigger': trigger,
      'menu': {
        'background': _hex(decoration.color!),
        'border': {'color': _hex(side.color), 'width': side.width},
        'shadows': _shadows(decoration.shadows!),
        'paddingY': _round(padding.top),
        ..._shape(decoration.shape),
      },
      'item': item('One'),
      'selectedItem': item('Two'),
    },
  };
}

Future<Map<String, Object?>> _borderedCase(
  WidgetTester tester,
  _ThemeCase theme,
) async {
  await tester.pumpWidget(
    _app(
      theme,
      Builder(
        builder: (context) => Bordered(
          backgroundColor: MonetTheme.of(context).primary.background,
          borderColor: MonetTheme.of(context).primary.backgroundBorder,
          child: const SizedBox(height: 40),
        ),
      ),
    ),
  );
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byType(Bordered),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  final decoration = box.decoration as ShapeDecoration;
  final side = _side(decoration.shape);
  return {
    'control': 'Bordered',
    'theme': theme.name,
    'props': <String, Object?>{},
    'values': {
      'background': _hex(decoration.color!),
      'border': {'color': _hex(side.color), 'width': side.width},
      ..._shape(decoration.shape),
    },
  };
}

void main() {
  testWidgets('generate React controls parity fixture', (tester) async {
    final cases = <Map<String, Object?>>[];
    for (final theme in _themes) {
      for (final kind in MonetButtonKind.values) {
        cases.add(
          await _buttonCase(
            tester,
            theme,
            kind: kind,
            preset: .regular,
            family: 'primary',
          ),
        );
      }
      for (final preset in [
        MonetButtonPreset.tool,
        MonetButtonPreset.compact,
      ]) {
        cases.add(
          await _buttonCase(
            tester,
            theme,
            kind: .color,
            preset: preset,
            family: 'primary',
          ),
        );
      }
      for (final family in ['secondary', 'tertiary']) {
        cases.add(
          await _buttonCase(
            tester,
            theme,
            kind: .color,
            preset: .regular,
            family: family,
          ),
        );
      }
      cases.add(await _expansionCase(tester, theme, title: 'Section'));
      cases.add(await _expansionCase(tester, theme, title: ''));
      cases.add(await _segmentedCase(tester, theme, isSmall: true));
      cases.add(await _segmentedCase(tester, theme, isSmall: false));
      cases.add(await _sliderCase(tester, theme));
      cases.add(await _dropdownCase(tester, theme));
      cases.add(await _borderedCase(tester, theme));
    }
    final fixture = {
      'schema': 1,
      'themes': {for (final t in _themes) t.name: t.toJson()},
      'cases': cases,
      'superellipseCorner': _superellipseCorner(),
    };
    final file = File(_fixturePath);
    // Real file IO does not complete inside the test's fake async zone.
    file.parent.createSync(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    file.writeAsStringSync('${encoder.convert(fixture)}\n');
    print('wrote $_fixturePath (${cases.length} cases)');
  });
}
