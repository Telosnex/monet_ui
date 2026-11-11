import React, {useMemo, useRef} from 'react';

import {cx, withVars} from './classes.js';
import {InkIcon} from './InkIcon.js';
import type {MonetFamily} from './paint.js';
import {segmentedSpec} from './spec.js';
import {useMonetGeometry} from './theme.js';
import {segmentedVars} from './vars.js';

export interface MonetSegment<T extends string> {
  value: T;
  label: string;
  icon?: React.ReactNode;
  tooltip?: string;
}

export interface MonetSegmentedProps<T extends string> {
  options: readonly MonetSegment<T>[];
  value: T;
  onChange: (value: T) => void;
  /** Narrower segment edges. Defaults to true, as in Dart. */
  isSmall?: boolean;
  family?: MonetFamily;
  'aria-label'?: string;
  className?: string;
}

/**
 * Peer of `MonetSegmented`: one row of segments. The selected segment is in
 * the fill role; a 1px divider separates two unselected neighbours.
 */
export function MonetSegmented<T extends string>({
  options,
  value,
  onChange,
  isSmall = true,
  family = 'primary',
  'aria-label': ariaLabel,
  className,
}: MonetSegmentedProps<T>): React.ReactElement {
  const geometry = useMonetGeometry();
  const vars = useMemo(
    () => segmentedVars(segmentedSpec(geometry, {family, isSmall})),
    [geometry, family, isSmall]
  );
  const buttons = useRef<Array<HTMLButtonElement | null>>([]);
  const selectedIndex = options.findIndex((o) => o.value === value);

  const selectRelative = (index: number, direction: -1 | 1) => {
    const next = (index + direction + options.length) % options.length;
    onChange(options[next]!.value);
    buttons.current[next]?.focus();
  };

  return (
    <div
      className={cx(
        'monet-segmented',
        geometry.corner === 'superellipse' && 'monet-superellipse',
        className
      )}
      style={withVars(vars)}
      role="radiogroup"
      aria-label={ariaLabel}
    >
      {options.map((option, index) => {
        const selected = index === selectedIndex;
        // `_RenderSegmentedRow.paint`: no divider beside the selected one.
        const dividerAfter =
          index < options.length - 1 && index !== selectedIndex && index + 1 !== selectedIndex;
        return (
          <button
            key={option.value}
            ref={(el) => {
              buttons.current[index] = el;
            }}
            type="button"
            className="monet-segmented__segment"
            role="radio"
            aria-checked={selected}
            tabIndex={selected || (selectedIndex < 0 && index === 0) ? 0 : -1}
            title={option.tooltip}
            data-selected={selected || undefined}
            data-divider-after={dividerAfter || undefined}
            onClick={() => onChange(option.value)}
            onKeyDown={(event) => {
              if (event.key === 'ArrowRight' || event.key === 'ArrowDown') {
                event.preventDefault();
                selectRelative(index, 1);
              } else if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') {
                event.preventDefault();
                selectRelative(index, -1);
              }
            }}
          >
            <span className="monet-segmented__content">
              {option.icon != null && (
                <InkIcon className="monet-segmented__icon">{option.icon}</InkIcon>
              )}
              <span className="monet-segmented__label">{option.label}</span>
            </span>
          </button>
        );
      })}
    </div>
  );
}
