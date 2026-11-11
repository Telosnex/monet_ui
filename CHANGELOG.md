## Unreleased

- `MonetShapeTheme()` borders are now `RoundedSuperellipseBorder`, as
  `kMonetFallbackShapeTheme` and the Telosnex app already use. For the old
  rounded rectangles, pass `borderBuilder: RoundedRectangleBorder.new`.
  Input borders are still `OutlineInputBorder`.

## 1.6.2

- Requires pixel_snap_fork 1.0.0. It is the same code as 0.2.0.

## 1.6.1

- `InkCenteredText` no longer reports a FlutterError when the engine
  cannot read glyph pixels back (for example "Impeller context was null" on
  Windows). It keeps the layout-based position, caches the ink as unknown
  rather than empty, and logs once.

## 1.6.0

- New in `lib/widgets/`, moved from the Telosnex app: `MonetAppBar` (was
  `AppBarNx`; `AppBarNxMetrics` is now `MonetAppBarMetrics`),
  `MonetBackButton`, `MonetAlertDialog`, `AnimatedExpandable`, `MonetDropdown`,
  `DropdownRow`, the menu widgets in `lib/widgets/menu/`, settings rows
  (`SettingsRow`, `SwitchRow`, `SliderRow`, `SegmentedRow`, `TextFieldRow`,
  `KeyValueTextField`, `StringListField`), `MonetExpansion`,
  `MonetSectionHeader`, `SupportingPane` and `ScreenConstrainedHandAligned`.
- New scopes that apps provide near the root. Each has a fallback:
  `MonetHandedness`, `MonetMonoTextStyle`, `MonetScreenSize` (falls back to
  `MediaQuery`), `MonetWallpaperHeader` (falls back to no wallpaper) and
  `MonetExpansionAnimations`.
- `MonetMenuOverlayController.overlayScopeFor` lets an app wrap menu overlays,
  for example to pass its state container to menu items.
- `MenuButton.debugAnchorOffset` moves menus for screen recordings.
- New helpers: `brightnessOfColor`, `systemUiOverlayStyleFor` and
  `safelyUpdateText`.
- Flutter-derived `ExpansionTile2`, `SingleChildScrollView2` and `Switch2`
  (with `Toggleable2StateMixin`) in `lib/third_party/flutter/`.

## 1.5.0

- New in `lib/widgets/`, moved from the Telosnex app: `MonetScreen`,
  `MonetScrollbar`, `MonetListView`, `TitleTextField`,
  `AutoSizeTitleField` and `ExclusiveSelectionArea`.
- New `MonetWallpaperScrollbarColor`. An app with a wallpaper provides it
  near the root. `MonetScreen` uses its color only when
  `hasWallpaperBackground` is true.
- `MonetScrollbar` keeps the inherited scroll behavior. Apps set theirs
  once, for example with `MaterialApp.scrollBehavior`.
  `isolateScrollbarLayer` wraps that behavior and changes only vertical
  scrollbars on desktop.
- `MonetListView` uses a Flutter-derived `ListView` in
  `lib/third_party/flutter/`. New dependency: `super_sliver_list_fork`.

## 1.4.0

- New in `lib/widgets/`: `MonetIcon`, `MonetButton` and the controls built on
  them (icon buttons, chip and tooltip icons, segmented buttons, pulses,
  chevron and lock pills, `MonetSurface`, `ProgressStepList`, `TinySpinner`
  and more), and `snapped_icons/` `icon_box`, `icon_outline` and
  `icon_shadow`. They moved from the Telosnex app.
- `registerIconOutlines` adds icon outlines by font family. `MonetIcon`
  draws registered icons as paths and other icons with their font.
- `registerIconInkBounds` adds ink bounds by font family for
  `MaterialIconInk`, `MonetChipIcon` and button icons. Icons without them keep
  their square layout.
- The package registers no icon data itself. Apps register theirs before
  the first frame.
- Also corrects the 1.3.0 note: `lib/widgets/` gained 69 files, not 69
  controls; some are helpers.

## 1.3.0

- New `lib/widgets/`: 69 Monet controls (buttons, fields, sliders, switches,
  menus, tooltips, layout helpers and more) that moved from the Telosnex app.
  They do not import the app; a test checks this.
- New `lib/util/` helpers the controls use: `is_web`, `blur_radius`,
  `deep_json_equals`, `throttled_publisher`, `list_view_padding_calculator`,
  `use_animation_controller2`, `custom_cupertino_page_route` and
  `color_deprecated`.
- `lib/flux/`: adds `hooks.dart`, `flux_spring_controller.dart` and
  `spring_frame_clock.dart`; `flux.dart` exports them. Comments match the
  original port. No change to spring results.
- New dependencies: `clock`, `flutter_hooks`, `flutter_svg`, `loggy`,
  `pixel_snap_fork` and `vector_graphics`.

## 1.2.3

- Longer package description.
- Generated files turn `dart format` off, so pub.dev's format check passes. No code changes.

## 1.2.2

- The package no longer includes Python bytecode from `lib/fonts/`. No code
  changes.

## 1.2.1

- `AnyBackground.sharedBorder`: removed a tiebreak that never applied.
  1.1.2 and 1.2.0 said ties go to a tone outside every surface's tone, then
  to the darker; tied tones mirror each other around the surfaces' midpoint,
  so both are outside or both inside, and the darker always won. No change
  in results.

## 1.2.0

- `MonetThemeData.transitionProgress`: how far through a theme transition a
  theme is, 0..1, 1 at rest. The shared progress that lerps
  `backgroundTone`, `contrast` and `scale`. Lerp values solved once per
  endpoint by it, instead of solving each frame.
- `AnyBackground.sharedBorder` is fast again uncached: it checks tones in
  order of preference and stops at the first that works, with the same
  answers as 1.1.2. 1.1.2 checked all 101 and was 3 to 20 times slower than
  1.1.1. Same in the JS port.
- `AnyBackground.clearAnswerCaches`, for benchmarks (`@visibleForTesting`).

## 1.1.2

- `AnyBackground.sharedBorder`: of the tones that work, picks the one
  nearest its farthest surface, instead of the first working tone darker
  than every surface, then lighter, then between. Surfaces far apart in tone
  no longer get a near-white or near-black border when a tone between them
  works: Telosnex's T84, T53 and T17 colors went from T94 to T38. Ties go to
  the darker. Same in the JS port.

## 1.1.1

- Fit Latin line heights to A-Z and a-z, excluding accented letters. This
  tightens many line heights and changes vertical placement in single-line
  controls too. The font-metrics patch centres this smaller envelope even
  when compact line heights are disabled; natural line heights keep their
  original total height. Accents, punctuation, and other scripts can extend
  outside the measured envelope. Increase line-height clearance if needed
  to avoid overlap. The default clearance stays at 0.08 and the minimum
  baseline distance stays at 1.0 times the requested size.

## 1.1.0

- Size adjust (docs/design/ADR_font_size_adjust.md in telosnex), off by
  default: `MonetFonts.install(sizeAdjust: true)` scales each Google Font's
  letters to the reference size in its bytes (`head.unitsPerEm`), like CSS
  `size-adjust`, instead of in its font size. Fallback fonts, such as emoji,
  then keep their own size. With it on, `visualHeightScaleForFontFamily` is
  1.0 for adjusted fonts, and the em accessors (`rasterCapHeightEmForFontFamily`,
  `latinInkForFontFamily`, ...) give values in the em of the loaded font.
  New: `font_size_adjust.dart` (`fontSizeAdjustEnabled`,
  `isFontSizeAdjusted`, `fontEmScale`, `adjustedUnitsPerEm`),
  `rasterVisualHeightScaleForFontFamily`,
  `kFontSizeAdjustExcludedFontFamilies` (Bytesized), and the `unitsPerEm`
  argument of `patchFontAscentDescent`. The generator fails on a CFF font.
- Font code from telosnex (docs/design/ADR_fonts_in_monet_ui.md there):
  - `font_file.dart`: `fontTableRecords`, `cmapCodePoints`, `colorTables`,
    `unitsPerEm`, `fontOutlines`, `hasLatinLetters`.
  - `text_metrics.dart`: `snapFontSize`, `withFontLineHeight`,
    `lineHeightForTextScaler`, `capHeightCentringShift`,
    `capHeightShiftForTextStyle`.
  - `monet_fonts.dart`: `MonetFonts.install()`, the one font transform, and
    `loadMonetFont` for tests.
  - `fonts/tooling/google_fonts_source.dart` (not exported; dart:io): the
    reader of the google_fonts package, from `tool/generate_fonts.dart`.
  - `crypto` is now a dependency.
- Font data: the font's `cmap` decides whether it has Latin letters, not the
  catalog's `latin` subset. 111 more families get a line height, among them
  the 104 Playwrite families and the math fonts.
- Font data: a font that maps an accented letter to an empty glyph is
  measured from A–Z and a–z (Knewave).
- Font data: a family with only italics is measured from its italic (Molle).
  It gets a visual-height scale.

## 1.0.1

- Add `MonetGdtRule20261030` (`extract/monet_gdt_rule_2026_10_30.dart`):
  the color rule that monet_gdt 2026.10.30 is trained on. It chooses
  colorful colors before large areas, and needs 128 `QuantizerCelebi`
  clusters. It is slower than `ScorerTriad` and can pick small colorful
  areas; see the file header.

## 1.0.0

- First release on pub.dev, as monet_ui (the repository was libmonet).
  Its library is package:monet_ui/monet_ui.dart.
