import {themeCssVars, type MonetThemeData} from '@telosnex/libmonet';
import React, {createContext, useContext, useMemo} from 'react';

import {defaultGeometry, type MonetCorner, type MonetGeometry} from './spec.js';

const GeometryContext = createContext<MonetGeometry>(defaultGeometry);

/** The geometry of the nearest `MonetThemeScope`, or the Dart defaults. */
export function useMonetGeometry(): MonetGeometry {
  return useContext(GeometryContext);
}

export interface MonetThemeScopeProps {
  /**
   * The colours. Undefined leaves the palette variables unset, for example
   * while a wallpaper is still being quantized; `styles.css` then uses
   * fallbacks.
   */
  theme?: MonetThemeData | undefined;
  /** `MonetThemeData.scale`. Defaults to 1. */
  scale?: number;
  /** The `MonetShapeTheme` corner radius at scale 1. Defaults to 8. */
  radius?: number;
  /** Defaults to `superellipse`, as `MonetShapeTheme()`. The Telosnex app
   * uses radius 9 (`kMonetFallbackShapeTheme`). */
  corner?: MonetCorner;
  className?: string;
  style?: React.CSSProperties;
  children?: React.ReactNode;
}

/**
 * Peer of `MonetTheme`: a div that sets the `--monet-*` palette variables
 * and gives the controls inside it the theme's scale and corners.
 */
export function MonetThemeScope({
  theme,
  scale = defaultGeometry.scale,
  radius = defaultGeometry.radius,
  corner = defaultGeometry.corner,
  className,
  style,
  children,
}: MonetThemeScopeProps): React.ReactElement {
  const geometry = useMemo(() => ({scale, radius, corner}), [scale, radius, corner]);
  const vars = useMemo(() => (theme ? themeCssVars(theme) : {}), [theme]);
  return (
    <GeometryContext.Provider value={geometry}>
      <div
        className={className ? `monet-theme ${className}` : 'monet-theme'}
        style={{...vars, ...style} as React.CSSProperties}
      >
        {children}
      </div>
    </GeometryContext.Provider>
  );
}
