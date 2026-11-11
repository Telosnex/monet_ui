import React, {useLayoutEffect, useRef} from 'react';

import {cx} from './classes.js';

/** The horizontal ink of an icon, as fractions of its square box. */
export interface IconInk {
  left: number;
  width: number;
}

/**
 * The horizontal ink of an inline SVG, from its geometry and viewBox. Half
 * the stroke width is added for stroked icons. Null if it can't be measured,
 * for example without a viewBox or before layout.
 */
export function svgInk(svg: SVGSVGElement | null): IconInk | null {
  if (svg == null || typeof svg.getBBox !== 'function') return null;
  const view = svg.viewBox?.baseVal;
  if (view == null || !(view.width > 0)) return null;
  let box: DOMRect;
  try {
    box = svg.getBBox();
  } catch {
    return null;
  }
  if (!(box.width > 0)) return null;
  const style = getComputedStyle(svg);
  const stroke = style.stroke && style.stroke !== 'none' ? parseFloat(style.strokeWidth) || 0 : 0;
  const left = Math.max(view.x, box.x - stroke / 2);
  const right = Math.min(view.x + view.width, box.x + box.width + stroke / 2);
  if (!(right > left)) return null;
  return {left: (left - view.x) / view.width, width: (right - left) / view.width};
}

/**
 * An icon box one font size high. With `trim`, the box is as wide as the
 * icon's ink, so the padding beside it is the visible space, as
 * `MonetButtonIcon` does with `MaterialIconInk` in Dart. Only an inline
 * `<svg>` child is trimmed; other children keep the square box.
 */
export function InkIcon({
  className,
  trim = true,
  children,
}: {
  className?: string;
  trim?: boolean;
  children: React.ReactNode;
}) {
  const ref = useRef<HTMLSpanElement>(null);
  useLayoutEffect(() => {
    const el = ref.current;
    if (el == null) return;
    const ink = trim ? svgInk(el.querySelector<SVGSVGElement>(':scope > svg')) : null;
    if (ink == null) {
      el.style.removeProperty('--monet-ink-left');
      el.style.removeProperty('--monet-ink-width');
    } else {
      el.style.setProperty('--monet-ink-left', String(ink.left));
      el.style.setProperty('--monet-ink-width', String(ink.width));
    }
  }, [children, trim]);
  return (
    <span ref={ref} className={cx('monet-icon', className)} aria-hidden="true">
      {children}
    </span>
  );
}
