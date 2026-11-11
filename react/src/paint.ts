import type {PaletteRole} from '@telosnex/libmonet';

/** One of the theme's three palettes. */
export type MonetFamily = 'primary' | 'secondary' | 'tertiary';

/** A palette role in one family: what a control paints with. */
export interface Paint {
  readonly family: MonetFamily;
  readonly role: PaletteRole;
}

/** No colour. Dart's `Colors.transparent`. */
export const transparent = Object.freeze({transparent: true as const});
export type Transparent = typeof transparent;

export type PaintValue = Paint | Transparent;

export function paint(family: MonetFamily, role: PaletteRole): Paint {
  return {family, role};
}

export function isPaint(value: unknown): value is PaintValue {
  return (
    typeof value === 'object' &&
    value !== null &&
    (('family' in value && 'role' in value) || 'transparent' in value)
  );
}

function kebab(input: string): string {
  return input.replace(/[A-Z]/g, (m) => `-${m.toLowerCase()}`);
}

/**
 * The CSS variable that `MonetThemeScope` sets for [value]. The names match
 * libmonet's `themeCssVars`.
 */
export function paintCss(value: PaintValue, opacity = 1): string {
  if ('transparent' in value) return 'transparent';
  const color = `var(--monet-${value.family}-${kebab(value.role)})`;
  if (opacity >= 1) return color;
  return `color-mix(in srgb, ${color} ${round(opacity * 100)}%, transparent)`;
}

/** A length in logical pixels, scaled by `--monet-dp` (default 1px). */
export function dp(value: number): string {
  return `calc(${round(value)} * var(--monet-dp, 1px))`;
}

export function round(value: number): number {
  return Math.round(value * 1000) / 1000;
}
