import type React from 'react';

export function cx(...names: Array<string | false | null | undefined>): string {
  return names.filter(Boolean).join(' ');
}

export type CssVars = Record<`--${string}`, string>;

/** React accepts custom properties in `style`; its types do not. */
export function withVars(vars: CssVars, style?: React.CSSProperties): React.CSSProperties {
  return {...vars, ...style} as React.CSSProperties;
}
