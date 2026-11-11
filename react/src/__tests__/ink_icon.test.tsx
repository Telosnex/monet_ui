import {cleanup, render} from '@testing-library/react';
import React from 'react';
import {afterEach, describe, expect, test} from 'vitest';

import {InkIcon, svgInk} from '../InkIcon.js';

afterEach(cleanup);

function svgWithBox(box: {x: number; width: number}, viewBox = '0 0 24 24') {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', viewBox);
  (svg as unknown as {getBBox: () => DOMRect}).getBBox = () =>
    ({x: box.x, y: 0, width: box.width, height: 24}) as DOMRect;
  return svg;
}

describe('svgInk', () => {
  test('is the ink as fractions of the viewBox', () => {
    document.body.append(svgWithBox({x: 5, width: 14}));
    expect(svgInk(document.querySelector('svg'))).toEqual({left: 5 / 24, width: 14 / 24});
    document.body.replaceChildren();
  });

  test('adds half the stroke and stays inside the viewBox', () => {
    const svg = svgWithBox({x: 1, width: 22});
    svg.style.stroke = 'black';
    svg.style.strokeWidth = '4';
    document.body.append(svg);
    expect(svgInk(svg)).toEqual({left: 0, width: 1});
    document.body.replaceChildren();
  });

  test('is null without a viewBox or a measurement', () => {
    expect(svgInk(null)).toBeNull();
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    expect(svgInk(svg)).toBeNull();
  });
});

describe('InkIcon', () => {
  test('keeps the square box when the SVG cannot be measured', () => {
    const {container} = render(
      <InkIcon>
        <svg viewBox="0 0 24 24" />
      </InkIcon>
    );
    const box = container.querySelector<HTMLElement>('.monet-icon')!;
    expect(box.style.getPropertyValue('--monet-ink-width')).toBe('');
  });
});
