import React, {useEffect, useId, useMemo, useRef, useState} from 'react';

import {cx, withVars} from './classes.js';
import {expansionSpec} from './spec.js';
import {useMonetGeometry} from './theme.js';
import {expansionVars} from './vars.js';

export interface MonetExpansionProps {
  /** The header label. Empty shows no label and a narrower inset. */
  title: string;
  /** Shown after the title in the header. Dart's `titleChildren`. */
  titleAccessory?: React.ReactNode;
  initiallyExpanded?: boolean;
  /** Controls the state from outside. */
  expanded?: boolean;
  onExpansionChanged?: (expanded: boolean) => void;
  /** Outline the panel while expanded. Defaults to true. */
  showExpandedBorder?: boolean;
  /** CSS padding around the children. Defaults to none, as in Dart. */
  childrenPadding?: string;
  className?: string;
  children?: React.ReactNode;
}

/**
 * Peer of `MonetExpansion`: a header with a chevron in the fill role. The
 * panel is outlined in the background border role once expanded.
 */
export function MonetExpansion({
  title,
  titleAccessory,
  initiallyExpanded = false,
  expanded: controlled,
  onExpansionChanged,
  showExpandedBorder = true,
  childrenPadding,
  className,
  children,
}: MonetExpansionProps): React.ReactElement {
  const geometry = useMonetGeometry();
  const [uncontrolled, setUncontrolled] = useState(initiallyExpanded);
  const expanded = controlled ?? uncontrolled;
  const bodyId = useId();
  const bodyRef = useRef<HTMLDivElement>(null);
  const vars = useMemo(
    () => expansionVars(expansionSpec(geometry, {hasTitle: title !== '', showExpandedBorder})),
    [geometry, title, showExpandedBorder]
  );

  // Collapsed content stays in the layout for the animation; keep it out
  // of the tab order and the accessibility tree.
  useEffect(() => {
    if (bodyRef.current) bodyRef.current.inert = !expanded;
  }, [expanded]);

  const toggle = () => {
    const next = !expanded;
    if (controlled === undefined) setUncontrolled(next);
    onExpansionChanged?.(next);
  };

  return (
    <div
      className={cx(
        'monet-expansion',
        expanded && 'monet-expansion--expanded',
        geometry.corner === 'superellipse' && 'monet-superellipse',
        className
      )}
      style={withVars(vars)}
    >
      <button
        type="button"
        className="monet-expansion__header"
        aria-expanded={expanded}
        aria-controls={bodyId}
        onClick={toggle}
      >
        {title !== '' && <span className="monet-expansion__title">{title}</span>}
        {titleAccessory}
        <svg
          className="monet-expansion__icon"
          viewBox="0 0 24 24"
          width="20"
          height="20"
          aria-hidden="true"
        >
          <path
            d="M6 9l6 6 6-6"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </svg>
      </button>
      <div id={bodyId} ref={bodyRef} className="monet-expansion__body" aria-hidden={!expanded}>
        <div
          className="monet-expansion__content"
          style={childrenPadding === undefined ? undefined : {padding: childrenPadding}}
        >
          {children}
        </div>
      </div>
    </div>
  );
}
