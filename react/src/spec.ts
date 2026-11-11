/**
 * What each control resolves to, as palette roles and logical pixels. These
 * mirror the Dart controls; `react/fixtures/monet_controls_parity.json`
 * records what the Dart controls resolve to, and the parity test compares
 * the two (ADR 003 D5).
 *
 * Components turn a spec into CSS variables; `styles.css` reads them.
 */
import {paint, transparent, type MonetFamily, type PaintValue} from './paint.js';
import {aestheticShadows, fabShadows, type ShadowSpec} from './shadow.js';

/** Corner shapes: Flutter's `RoundedRectangleBorder` and
 * `RoundedSuperellipseBorder`. */
export type MonetCorner = 'rounded' | 'superellipse';

/**
 * How CSS draws Flutter's `RoundedSuperellipseBorder`. Flutter's corner
 * meets a circle of the radius on the diagonal and blends into the edges
 * over about 3 × the radius. CSS `corner-shape: squircle` at the same
 * radius is much squarer. `superellipse(log2 3)` at √2 × the radius is
 * within 0.75% of the radius of Flutter's curve. Without `corner-shape`,
 * a plain circle at the radius is within 1.7%.
 */
export const superellipseCss = {
  /** The `corner-shape: superellipse()` parameter: log2 of the exponent. */
  shape: 1.585,
  /** Multiplies the Flutter radius for `border-radius`. */
  radiusScale: 1.4142,
} as const;

/** The geometry part of a Monet theme. */
export interface MonetGeometry {
  /** The UI size preference, as `MonetThemeData.scale`. */
  readonly scale: number;
  /** The theme's corner radius at scale 1, as `MonetShapeTheme`. */
  readonly radius: number;
  readonly corner: MonetCorner;
}

/** `MonetThemeData`'s defaults: `MonetShapeTheme()` at scale 1. */
export const defaultGeometry: MonetGeometry = {
  scale: 1,
  radius: 8,
  corner: 'rounded',
};

/** `MonetThemeData.touchSize`. */
export const touchSize = 36;

/** `SizeScale.sizeScale`: lengths scale by the square root of the scale. */
export function linearScale(scale: number): number {
  return Math.sqrt(scale);
}

/** `minimumSizeForScale`. */
export function touchSizeFor(scale: number): number {
  return touchSize * linearScale(scale);
}

/** The theme radius with the scale applied, as `MonetShapes.border()`. */
export function themeRadius(geometry: MonetGeometry, factor = 1): number {
  return geometry.radius * factor * linearScale(geometry.scale);
}

export interface StatePaints {
  readonly background: PaintValue;
  readonly foreground: PaintValue;
  readonly icon: PaintValue;
}

export interface BorderSpec {
  readonly color: PaintValue;
  readonly width: number;
}

export interface ShapeSpec {
  readonly radius: number;
  readonly corner: MonetCorner;
}

function shape(radius: number, corner: MonetCorner): ShapeSpec {
  return {radius, corner};
}

// ── MonetButton ────────────────────────────────────────────────────────────

/** `MonetButtonKind`: which libmonet button style colours the button. */
export type MonetButtonKind = 'color' | 'fill' | 'background' | 'outline';

/** `MonetButtonPreset`: size, edges and corners. */
export type MonetButtonPreset = 'regular' | 'tool' | 'compact';

export interface ButtonSpec extends ShapeSpec {
  readonly states: {
    readonly rest: StatePaints;
    readonly hovered: StatePaints;
    readonly focused: StatePaints;
    readonly pressed: StatePaints;
    readonly disabled: StatePaints;
  };
  readonly border: BorderSpec | null;
  readonly shadows: readonly ShadowSpec[];
  readonly minHeight: number;
  readonly minWidth: number;
  readonly paddingX: number;
  readonly paddingY: number;
}

/** `colorButtonStyle`, `fillButtonStyle` and `backgroundButtonStyle`. */
function kindPaints(family: MonetFamily, kind: MonetButtonKind) {
  const p = (role: Parameters<typeof paint>[1]) => paint(family, role);
  switch (kind) {
    case 'color':
      return {
        normal: {background: p('color'), foreground: p('colorText'), icon: p('colorIcon')},
        hover: {background: p('colorHovered'), foreground: p('colorHoveredText'), icon: p('colorHoveredIcon')},
        splash: {background: p('colorSplashed'), foreground: p('colorSplashedText'), icon: p('colorSplashedIcon')},
        shadow: p('colorBorder'),
      };
    case 'fill':
      return {
        normal: {background: p('fill'), foreground: p('fillText'), icon: p('fillIcon')},
        hover: {background: p('fillHovered'), foreground: p('fillHoveredText'), icon: p('fillHoveredIcon')},
        splash: {background: p('fillSplashed'), foreground: p('fillSplashedText'), icon: p('fillSplashedIcon')},
        shadow: p('fillBorder'),
      };
    case 'background':
    case 'outline':
      return {
        normal: {background: p('background'), foreground: p('backgroundText'), icon: p('backgroundFill')},
        hover: {background: p('backgroundHovered'), foreground: p('backgroundHoveredText'), icon: p('backgroundHoveredFill')},
        splash: {background: p('backgroundSplashed'), foreground: p('backgroundSplashedText'), icon: p('backgroundSplashedFill')},
        shadow: p('backgroundBorder'),
      };
  }
}

/** Compact and tool corners are fractions of the theme radius. */
const compactCornerScale = 0.5;
const toolCornerScale = 0.75;

/**
 * `MonetButton` with `MonetButtonCore`. Material's compact visual density
 * takes 8 from the minimum size and the 4px vertical padding.
 */
export function buttonSpec(
  geometry: MonetGeometry,
  {
    family = 'primary',
    kind = 'color',
    preset = 'regular',
  }: {family?: MonetFamily; kind?: MonetButtonKind; preset?: MonetButtonPreset} = {}
): ButtonSpec {
  const paints = kindPaints(family, kind);
  const touch = touchSizeFor(geometry.scale);
  const minimum =
    preset === 'compact'
      ? {width: 16, height: 16}
      : preset === 'tool'
        ? {width: 0, height: touch * toolCornerScale}
        : {width: 0, height: touch};
  const densityAdjustment = 8;
  const cornerScale =
    preset === 'compact' ? compactCornerScale : preset === 'tool' ? toolCornerScale : 1;
  const hasShadow = kind !== 'outline';
  return {
    states: {
      rest: paints.normal,
      hovered: paints.hover,
      focused: paints.hover,
      pressed: paints.splash,
      // `widgetPropertyByState` has no disabled colours.
      disabled: paints.normal,
    },
    border: {color: paints.shadow, width: 1},
    shadows: hasShadow ? aestheticShadows(paints.shadow, {includeOutline: false}) : [],
    minHeight: Math.max(0, minimum.height - densityAdjustment),
    minWidth: Math.max(0, minimum.width - densityAdjustment),
    paddingX: preset === 'compact' ? 4 : preset === 'tool' ? 6 : 8,
    paddingY: 0,
    ...shape(themeRadius(geometry, cornerScale), geometry.corner),
  };
}

// ── MonetExpansion ─────────────────────────────────────────────────────────

export interface ExpansionSpec extends ShapeSpec {
  readonly collapsed: {background: PaintValue; icon: PaintValue; border: BorderSpec};
  readonly expanded: {background: PaintValue; icon: PaintValue; border: BorderSpec};
  readonly headerMinHeight: number;
  readonly headerPaddingStart: number;
}

/** `MonetExpansion`. The header height is the unscaled touch size. */
export function expansionSpec(
  geometry: MonetGeometry,
  {hasTitle = true, showExpandedBorder = true}: {hasTitle?: boolean; showExpandedBorder?: boolean} = {}
): ExpansionSpec {
  const background = paint('primary', 'background');
  const icon = paint('primary', 'fill');
  return {
    collapsed: {background, icon, border: {color: transparent, width: 0}},
    expanded: {
      background,
      icon,
      border: showExpandedBorder
        ? {color: paint('primary', 'backgroundBorder'), width: 1}
        : {color: transparent, width: 0},
    },
    headerMinHeight: touchSize,
    headerPaddingStart: hasTitle ? 8 : 4,
    ...shape(themeRadius(geometry), geometry.corner),
  };
}

// ── MonetSegmented ─────────────────────────────────────────────────────────

export interface SegmentStates {
  readonly rest: StatePaints;
  readonly hovered: StatePaints;
  readonly pressed: StatePaints;
}

export interface SegmentedSpec extends ShapeSpec {
  readonly selected: SegmentStates;
  readonly unselected: SegmentStates;
  readonly divider: BorderSpec;
  readonly shadows: readonly ShadowSpec[];
  readonly minSegmentWidth: number;
  readonly paddingX: number;
}

/** `MonetSegmented`. Icons take the text colour. */
export function segmentedSpec(
  geometry: MonetGeometry,
  {family = 'primary', isSmall = true}: {family?: MonetFamily; isSmall?: boolean} = {}
): SegmentedSpec {
  const p = (role: Parameters<typeof paint>[1]) => paint(family, role);
  const same = (background: PaintValue, text: PaintValue): StatePaints => ({
    background,
    foreground: text,
    icon: text,
  });
  return {
    selected: {
      rest: same(p('fill'), p('fillText')),
      hovered: same(p('fillHovered'), p('fillHoveredText')),
      pressed: same(p('fillSplashed'), p('fillSplashedText')),
    },
    unselected: {
      rest: same(p('background'), p('text')),
      hovered: same(p('backgroundHovered'), p('backgroundHoveredText')),
      pressed: same(p('backgroundSplashed'), p('backgroundSplashedText')),
    },
    divider: {color: p('fillBorder'), width: 1},
    shadows: aestheticShadows(p('fillBorder')),
    minSegmentWidth: touchSize,
    paddingX: isSmall ? 4 : 8,
    ...shape(themeRadius(geometry), geometry.corner),
  };
}

// ── MonetSlider ────────────────────────────────────────────────────────────

export interface SliderPaints {
  readonly activeTrack: PaintValue;
  readonly inactiveTrack: PaintValue;
  readonly border: PaintValue;
  readonly thumbContent: PaintValue;
  readonly opacity: number;
}

export interface SliderSpec {
  readonly rest: SliderPaints;
  readonly focused: SliderPaints;
  readonly disabled: SliderPaints;
  readonly trackHeight: number;
  readonly borderWidth: number;
  readonly glowSigma: number;
  readonly thumbContentFraction: number;
  /** Arrow keys move by this fraction of the range. */
  readonly keyStep: number;
}

/** `MonetSlider`. Focus colours the border like the active track. */
export function sliderSpec(geometry: MonetGeometry): SliderSpec {
  const rest: SliderPaints = {
    activeTrack: paint('primary', 'color'),
    inactiveTrack: paint('primary', 'background'),
    border: paint('primary', 'colorBorder'),
    thumbContent: paint('primary', 'colorIcon'),
    opacity: 1,
  };
  return {
    rest,
    focused: {...rest, border: rest.activeTrack},
    disabled: {...rest, opacity: 0.6},
    trackHeight: touchSizeFor(geometry.scale),
    borderWidth: 1,
    glowSigma: 2,
    thumbContentFraction: 0.6,
    keyStep: 1 / 20,
  };
}

/** `_MonetSliderState._roundToNearestFraction(value, 1000)`. */
export function roundSliderValue(value: number): number {
  return Math.round(value * 1000) / 1000;
}

// ── MonetDropdown ──────────────────────────────────────────────────────────

export interface MenuItemSpec {
  readonly rest: StatePaints;
  readonly hovered: StatePaints;
  readonly pressed: StatePaints;
}

export interface DropdownSpec {
  readonly trigger: ButtonSpec;
  readonly menu: ShapeSpec & {
    readonly background: PaintValue;
    readonly border: BorderSpec;
    readonly shadows: readonly ShadowSpec[];
    readonly paddingY: number;
  };
  readonly item: MenuItemSpec;
  readonly selectedItem: MenuItemSpec;
}

/** `MenuEntry.create` in a dropdown. A selected entry rests splashed. */
export function menuItemSpec(selected: boolean, family: MonetFamily = 'primary'): MenuItemSpec {
  const p = (role: Parameters<typeof paint>[1]) => paint(family, role);
  const splashed: StatePaints = {
    background: p('backgroundSplashed'),
    foreground: p('backgroundSplashedText'),
    icon: p('backgroundSplashedFill'),
  };
  return {
    rest: selected
      ? splashed
      : {background: p('background'), foreground: p('backgroundText'), icon: p('fill')},
    hovered: {
      background: p('backgroundHovered'),
      foreground: p('backgroundHoveredText'),
      icon: p('backgroundHoveredFill'),
    },
    pressed: splashed,
  };
}

/** `MonetDropdown`: a primary colour button that opens a menu. */
export function dropdownSpec(geometry: MonetGeometry): DropdownSpec {
  const border = paint('primary', 'backgroundBorder');
  return {
    trigger: buttonSpec(geometry),
    menu: {
      background: paint('primary', 'background'),
      border: {color: border, width: 2},
      shadows: fabShadows(border),
      paddingY: 4,
      ...shape(themeRadius(geometry), geometry.corner),
    },
    item: menuItemSpec(false),
    selectedItem: menuItemSpec(true),
  };
}

// ── Bordered ───────────────────────────────────────────────────────────────

export interface BorderedSpec extends ShapeSpec {
  readonly background: PaintValue;
  readonly border: BorderSpec;
}

/**
 * `Bordered` with the colours most callers pass: the background role, and
 * its border at `kTelosnexBorderWidth`.
 */
export function borderedSpec(
  geometry: MonetGeometry,
  {family = 'primary'}: {family?: MonetFamily} = {}
): BorderedSpec {
  return {
    background: paint(family, 'background'),
    border: {color: paint(family, 'backgroundBorder'), width: 1},
    ...shape(themeRadius(geometry), geometry.corner),
  };
}
