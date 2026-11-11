// @vitest-environment node
import {readFileSync} from 'node:fs';
import {argbFromHex, hexFromArgb, MonetThemeData} from '@telosnex/monet-ui';
import {describe, expect, test} from 'vitest';

import {isPaint, round, type PaintValue} from '../paint.js';
import {
  borderedSpec,
  buttonSpec,
  dropdownSpec,
  expansionSpec,
  segmentedSpec,
  sliderRowSpec,
  sliderSpec,
  superellipseCss,
  linearScale,
  textSizes,
  type MonetButtonKind,
  type MonetButtonPreset,
  type MonetCorner,
  type MonetGeometry,
} from '../spec.js';
import type {MonetFamily} from '../paint.js';

interface ThemeFixture {
  color: string;
  backgroundTone: number;
  brightness: 'light' | 'dark';
  contrast: number;
  scale: number;
  radius: number;
  corner: MonetCorner;
}

interface CaseFixture {
  control: string;
  theme: string;
  props: Record<string, unknown>;
  values: unknown;
}

interface Fixture {
  schema: number;
  themes: Record<string, ThemeFixture>;
  cases: CaseFixture[];
  superellipseCorner: {radius: number; points: Array<[number, number]>};
  textSizes: Record<string, Record<keyof typeof textSizes, number>>;
}

const fixture = JSON.parse(
  readFileSync(new URL('../../fixtures/monet_controls_parity.json', import.meta.url), 'utf8')
) as Fixture;

/** Replaces paints with the theme's colours, as the fixture records them. */
function resolve(value: unknown, theme: MonetThemeData): unknown {
  if (isPaint(value)) {
    const p = value as PaintValue;
    if ('transparent' in p) return '#00000000';
    return hexFromArgb(theme[p.family].toRecord()[p.role]);
  }
  if (typeof value === 'number') return round(value);
  if (Array.isArray(value)) return value.map((v) => resolve(v, theme));
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([k, v]) => [k, resolve(v, theme)])
    );
  }
  return value;
}

function spec(c: CaseFixture, geometry: MonetGeometry): unknown {
  const props = c.props;
  switch (c.control) {
    case 'MonetButton':
      return buttonSpec(geometry, {
        family: props.family as MonetFamily,
        kind: props.kind as MonetButtonKind,
        preset: props.preset as MonetButtonPreset,
      });
    case 'MonetExpansion':
      return expansionSpec(geometry, {hasTitle: props.title !== ''});
    case 'MonetSegmented':
      return segmentedSpec(geometry, {isSmall: props.isSmall as boolean});
    case 'MonetSlider':
      return sliderSpec(geometry);
    case 'MonetDropdown':
      return dropdownSpec(geometry);
    case 'Bordered':
      return borderedSpec(geometry);
    case 'SliderRow': {
      const prominent = props.prominent as boolean;
      const s = sliderRowSpec(geometry, {prominent});
      const colors = {label: s.label, value: s.value, info: s.info, icon: s.icon};
      if (props.small) {
        return {
          ...colors,
          sliderGap: s.smallSliderGap,
          sliderInset: s.smallSliderInset,
          sliderInsetEnd: s.smallSliderInset,
          bottom: s.smallBottom,
        };
      }
      return {
        ...colors,
        valueLeft: s.labelWidth + s.gap,
        sliderLeft: s.labelWidth + s.gap + s.valueWidth + s.gap,
        ...(prominent ? {minHeight: s.minHeight} : {}),
      };
    }
    default:
      throw new Error(`No React spec for ${c.control}`);
  }
}

describe('React controls match the Dart controls', () => {
  test('fixture schema', () => {
    expect(fixture.schema).toBe(1);
    expect(fixture.cases.length).toBeGreaterThan(0);
  });

  for (const c of fixture.cases) {
    test(`${c.control} ${JSON.stringify(c.props)} / ${c.theme}`, () => {
      const t = fixture.themes[c.theme]!;
      const theme = MonetThemeData.fromColor({
        color: argbFromHex(t.color),
        backgroundTone: t.backgroundTone,
        brightness: t.brightness,
        contrast: t.contrast,
      });
      const geometry: MonetGeometry = {scale: t.scale, radius: t.radius, corner: t.corner};
      expect(resolve(spec(c, geometry), theme)).toEqual(resolve(c.values, theme));
    });
  }
});

/**
 * The largest distance from Flutter's corner points to a CSS corner of
 * radius `radius` and `corner-shape: superellipse(shape)`, which is
 * |x|^e + |y|^e = 1 with e = 2^shape, followed by straight edges.
 */
function cssCornerError(radius: number, shape: number): number {
  const e = 2 ** shape;
  const curve: Array<[number, number]> = [];
  for (let i = 0; i <= 2000; i++) {
    const t = (i / 2000) * (Math.PI / 2);
    curve.push([
      radius - radius * Math.cos(t) ** (2 / e),
      radius - radius * Math.sin(t) ** (2 / e),
    ]);
  }
  let worst = 0;
  for (const [x, y] of fixture.superellipseCorner.points) {
    let d: number;
    if (x >= radius) d = y;
    else if (y >= radius) d = x;
    else d = Math.min(...curve.map(([cx, cy]) => Math.hypot(x - cx, y - cy)));
    worst = Math.max(worst, d);
  }
  return worst;
}

describe('superellipse corners', () => {
  const {radius, points} = fixture.superellipseCorner;

  test('the fixture covers the corner', () => {
    expect(points.length).toBeGreaterThan(100);
  });

  test('the CSS superellipse is within 1% of the radius of Flutter\'s', () => {
    const error = cssCornerError(radius * superellipseCss.radiusScale, superellipseCss.shape);
    expect(error / radius).toBeLessThan(0.01);
  });

  test('the fallback circle is within 2%; a same-radius squircle is not', () => {
    expect(cssCornerError(radius, 1) / radius).toBeLessThan(0.02);
    expect(cssCornerError(radius, 2) / radius).toBeGreaterThan(0.1);
  });
});

describe('text sizes', () => {
  const css = readFileSync('src/styles.css', 'utf8');
  const kebab = (name: string): string => name.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`);

  for (const [name, size] of Object.entries(textSizes)) {
    test(`styles.css defaults ${name} to textSizes`, () => {
      const pattern = new RegExp(
        `var\\(--monet-type-${kebab(name)}, calc\\(([0-9.]+) \\* var\\(--monet-size-scale, 1\\)`,
        'g'
      );
      const found = [...css.matchAll(pattern)].map((m) => Number(m[1]));
      expect(found.length).toBeGreaterThan(0);
      expect(new Set(found)).toEqual(new Set([size]));
    });
  }

  for (const [themeName, sizes] of Object.entries(fixture.textSizes)) {
    test(`textSizes are the Dart theme's / ${themeName}`, () => {
      const scale = linearScale(fixture.themes[themeName]!.scale);
      for (const [name, size] of Object.entries(textSizes)) {
        expect(round(size * scale), name).toBe(sizes[name as keyof typeof textSizes]);
      }
    });
  }

  test('every --monet-type- variable has a default from textSizes', () => {
    const read = new Set([...css.matchAll(/var\((--monet-type-[a-z-]+)/g)].map((m) => m[1]));
    expect(read).toEqual(new Set(Object.keys(textSizes).map((n) => `--monet-type-${kebab(n)}`)));
  });
});
