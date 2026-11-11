import {dp, paintCss, round, type PaintValue} from './paint.js';

/**
 * A box shadow. [sigma] is the Gaussian blur's standard deviation, as in
 * Flutter's `BoxShadow.blurSigma`; CSS blur lengths are twice the sigma.
 */
export interface ShadowSpec {
  readonly color: PaintValue;
  readonly opacity: number;
  readonly spread: number;
  readonly sigma: number;
  readonly dx: number;
  readonly dy: number;
}

const radiusToSigma = 0.57735;

/**
 * monet_ui's `blurRadiusForPlatform`, then Flutter's radius-to-sigma: the
 * sigma of a shadow designed with blur radius [spec].
 */
export function sigmaForBlurRadius(spec: number): number {
  if (spec <= 0) return 0;
  const shadowReferencePixelRatio = 2;
  const sigma = (spec * radiusToSigma + 0.5) / shadowReferencePixelRatio;
  return sigma <= 0.5 ? 0 : round(sigma);
}

/** monet_ui's `outlineOnlyShadow`. */
export function outlineShadow(color: PaintValue): ShadowSpec {
  return {color, opacity: 1, spread: 1, sigma: 0, dx: 0, dy: 0};
}

/** monet_ui's `aestheticShadows` with the default blur radius of 4. */
export function aestheticShadows(
  color: PaintValue,
  {includeOutline = true}: {includeOutline?: boolean} = {}
): ShadowSpec[] {
  return [
    ...(includeOutline ? [outlineShadow(color)] : []),
    {color, opacity: 0.3, spread: 1, sigma: sigmaForBlurRadius(2), dx: 0, dy: 0},
    {color, opacity: 0.5, spread: 0, sigma: sigmaForBlurRadius(4), dx: 0, dy: 0},
  ];
}

/**
 * monet_ui's `fabShadows`: Material's elevation-16 blurs at 30% opacity,
 * with no offset or spread.
 */
export function fabShadows(color: PaintValue): ShadowSpec[] {
  return [10, 24, 30].map((blur) => ({
    color,
    opacity: 0.3,
    spread: 0,
    sigma: sigmaForBlurRadius(blur),
    dx: 0,
    dy: 0,
  }));
}

export function shadowsCss(shadows: readonly ShadowSpec[]): string {
  if (shadows.length === 0) return 'none';
  return shadows
    .map(
      (s) =>
        `${dp(s.dx)} ${dp(s.dy)} ${dp(s.sigma * 2)} ${dp(s.spread)} ${paintCss(s.color, s.opacity)}`
    )
    .join(', ');
}
