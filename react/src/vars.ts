/**
 * Specs as CSS variables. `styles.css` reads these names; the styles test
 * checks that every name it reads is set here.
 */
import type {CssVars} from './classes.js';
import {dp, paintCss} from './paint.js';
import {shadowsCss} from './shadow.js';
import type {
  BorderSpec,
  BorderedSpec,
  ButtonSpec,
  DropdownSpec,
  ExpansionSpec,
  MenuItemSpec,
  SegmentStates,
  SegmentedSpec,
  SliderPaints,
  SliderSpec,
  StatePaints,
} from './spec.js';

function statePaints(prefix: string, paints: StatePaints): CssVars {
  return {
    [`${prefix}-background`]: paintCss(paints.background),
    [`${prefix}-foreground`]: paintCss(paints.foreground),
    [`${prefix}-icon`]: paintCss(paints.icon),
  };
}

function border(prefix: string, b: BorderSpec | null): CssVars {
  return {
    [`${prefix}-color`]: b ? paintCss(b.color) : 'transparent',
    [`${prefix}-width`]: dp(b?.width ?? 0),
  };
}

export function buttonVars(spec: ButtonSpec): CssVars {
  const p = '--monet-button';
  return {
    ...statePaints(`${p}-rest`, spec.states.rest),
    ...statePaints(`${p}-hovered`, spec.states.hovered),
    ...statePaints(`${p}-focused`, spec.states.focused),
    ...statePaints(`${p}-pressed`, spec.states.pressed),
    ...statePaints(`${p}-disabled`, spec.states.disabled),
    ...border(`${p}-border`, spec.border),
    [`${p}-shadows`]: shadowsCss(spec.shadows),
    [`${p}-min-height`]: dp(spec.minHeight),
    [`${p}-min-width`]: dp(spec.minWidth),
    [`${p}-padding-x`]: dp(spec.paddingX),
    [`${p}-padding-y`]: dp(spec.paddingY),
    [`${p}-radius`]: dp(spec.radius),
  };
}

export function expansionVars(spec: ExpansionSpec): CssVars {
  const p = '--monet-expansion';
  const part = (name: 'collapsed' | 'expanded') => ({
    [`${p}-${name}-background`]: paintCss(spec[name].background),
    [`${p}-${name}-icon`]: paintCss(spec[name].icon),
    ...border(`${p}-${name}-border`, spec[name].border),
  });
  return {
    ...part('collapsed'),
    ...part('expanded'),
    [`${p}-header-min-height`]: dp(spec.headerMinHeight),
    [`${p}-header-padding-start`]: dp(spec.headerPaddingStart),
    [`${p}-radius`]: dp(spec.radius),
  };
}

function segmentStates(prefix: string, states: SegmentStates): CssVars {
  return {
    ...statePaints(`${prefix}-rest`, states.rest),
    ...statePaints(`${prefix}-hovered`, states.hovered),
    ...statePaints(`${prefix}-pressed`, states.pressed),
  };
}

export function segmentedVars(spec: SegmentedSpec): CssVars {
  const p = '--monet-segmented';
  return {
    ...segmentStates(`${p}-selected`, spec.selected),
    ...segmentStates(`${p}-unselected`, spec.unselected),
    ...border(`${p}-divider`, spec.divider),
    [`${p}-shadows`]: shadowsCss(spec.shadows),
    [`${p}-min-segment-width`]: dp(spec.minSegmentWidth),
    [`${p}-padding-x`]: dp(spec.paddingX),
    [`${p}-radius`]: dp(spec.radius),
  };
}

function sliderPaints(prefix: string, paints: SliderPaints): CssVars {
  // `_MonetSliderPainter` applies the opacity to each colour, not to the
  // slider as a group.
  return {
    [`${prefix}-active-track`]: paintCss(paints.activeTrack, paints.opacity),
    [`${prefix}-inactive-track`]: paintCss(paints.inactiveTrack, paints.opacity),
    [`${prefix}-border`]: paintCss(paints.border, paints.opacity),
    [`${prefix}-thumb-content`]: paintCss(paints.thumbContent, paints.opacity),
  };
}

export function sliderVars(spec: SliderSpec): CssVars {
  const p = '--monet-slider';
  return {
    ...sliderPaints(`${p}-rest`, spec.rest),
    ...sliderPaints(`${p}-focused`, spec.focused),
    ...sliderPaints(`${p}-disabled`, spec.disabled),
    [`${p}-height`]: dp(spec.trackHeight),
    [`${p}-border-width`]: dp(spec.borderWidth),
    [`${p}-glow`]: dp(spec.glowSigma * 2),
    [`${p}-thumb-content-size`]: `${spec.thumbContentFraction * 100}%`,
  };
}

function menuItem(prefix: string, spec: MenuItemSpec): CssVars {
  return {
    ...statePaints(`${prefix}-rest`, spec.rest),
    ...statePaints(`${prefix}-hovered`, spec.hovered),
    ...statePaints(`${prefix}-pressed`, spec.pressed),
  };
}

/** The menu's variables. The trigger is a `MonetButton` with its own. */
export function menuVars(spec: DropdownSpec): CssVars {
  const p = '--monet-menu';
  return {
    [`${p}-background`]: paintCss(spec.menu.background),
    ...border(`${p}-border`, spec.menu.border),
    [`${p}-shadows`]: shadowsCss(spec.menu.shadows),
    [`${p}-padding-y`]: dp(spec.menu.paddingY),
    [`${p}-radius`]: dp(spec.menu.radius),
    ...menuItem(`${p}-item`, spec.item),
    ...menuItem(`${p}-selected-item`, spec.selectedItem),
  };
}

export function borderedVars(spec: BorderedSpec): CssVars {
  const p = '--monet-bordered';
  return {
    [`${p}-background`]: paintCss(spec.background),
    ...border(`${p}-border`, spec.border),
    [`${p}-radius`]: dp(spec.radius),
  };
}
