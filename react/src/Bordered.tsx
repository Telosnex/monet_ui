import React, {useMemo} from 'react';

import {cx, withVars} from './classes.js';
import type {MonetFamily} from './paint.js';
import {borderedSpec} from './spec.js';
import {useMonetGeometry} from './theme.js';
import {borderedVars} from './vars.js';

export interface BorderedProps extends React.HTMLAttributes<HTMLDivElement> {
  /** The palette whose background and border colour the panel. */
  family?: MonetFamily;
  /** Round the top corners. Defaults to true. */
  isTopRound?: boolean;
  /** Round the bottom corners. Defaults to true. */
  isBottomRound?: boolean;
  /** Clip the content to the shape. */
  clip?: boolean;
}

/**
 * Peer of `Bordered`: a panel in the background role with a 1px border in
 * its border role, at the theme's corner radius.
 */
export function Bordered({
  family = 'primary',
  isTopRound = true,
  isBottomRound = true,
  clip = false,
  className,
  style,
  children,
  ...rest
}: BorderedProps): React.ReactElement {
  const geometry = useMonetGeometry();
  const vars = useMemo(() => borderedVars(borderedSpec(geometry, {family})), [geometry, family]);
  return (
    <div
      {...rest}
      className={cx(
        'monet-bordered',
        geometry.corner === 'superellipse' && 'monet-superellipse',
        !isTopRound && 'monet-bordered--square-top',
        !isBottomRound && 'monet-bordered--square-bottom',
        clip && 'monet-bordered--clip',
        className
      )}
      style={withVars(vars, style)}
    >
      {children}
    </div>
  );
}
