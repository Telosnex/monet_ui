// @vitest-environment node
import {readFileSync} from 'node:fs';
import {describe, expect, test} from 'vitest';

import {
  borderedSpec,
  buttonSpec,
  defaultGeometry,
  dropdownSpec,
  expansionSpec,
  segmentedSpec,
  sliderSpec,
  superellipseCss,
} from '../spec.js';
import {
  borderedVars,
  buttonVars,
  expansionVars,
  menuVars,
  segmentedVars,
  sliderVars,
} from '../vars.js';

const css = readFileSync('src/styles.css', 'utf8');

/** Variables that come from the app or the theme, not from a spec. */
const inputs = [
  /^--monet-(primary|secondary|tertiary)-/,
  /^--monet-dp$/,
  /^--monet-font-/,
  /^--monet-type-/,
  /^--monet-slider-value$/,
  /^--monet-corner-scale$/,
];

const set = new Set(
  Object.keys({
    ...buttonVars(buttonSpec(defaultGeometry)),
    ...expansionVars(expansionSpec(defaultGeometry)),
    ...segmentedVars(segmentedSpec(defaultGeometry)),
    ...sliderVars(sliderSpec(defaultGeometry)),
    ...menuVars(dropdownSpec(defaultGeometry)),
    ...borderedVars(borderedSpec(defaultGeometry)),
  })
);

describe('styles.css', () => {
  test('every spec variable it reads is set by a component', () => {
    const read = [...css.matchAll(/var\((--monet-[a-z0-9-]+)/g)].map((m) => m[1]!);
    expect(read.length).toBeGreaterThan(50);
    const missing = [...new Set(read)].filter(
      (name) => !set.has(name as `--${string}`) && !inputs.some((r) => r.test(name))
    );
    expect(missing).toEqual([]);
  });

  test('every spec variable a component sets is read', () => {
    const read = new Set([...css.matchAll(/var\((--monet-[a-z0-9-]+)/g)].map((m) => m[1]!));
    // Selected menu items share the hover and press colours of the others.
    const unused = [...set].filter(
      (name) => !read.has(name) && !/^--monet-menu-selected-item-(hovered|pressed)-/.test(name)
    );
    expect(unused).toEqual([]);
  });

  test('superellipse corners use the values in spec.ts', () => {
    expect(css).toContain(`corner-shape: superellipse(${superellipseCss.shape});`);
    expect(css).toContain(`--monet-corner-scale: ${superellipseCss.radiusScale};`);
    const radii = [...css.matchAll(/border-radius: var\((--monet-[a-z-]+-radius)\)/g)];
    expect(radii.map((m) => m[1])).toEqual([]);
  });
});
