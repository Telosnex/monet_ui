import React, {useId, useMemo, useState} from 'react';

import {cx, withVars} from './classes.js';
import {MonetSlider, type MonetSliderProps} from './MonetSlider.js';
import {sliderRowSpec} from './spec.js';
import {useMonetGeometry} from './theme.js';
import {sliderRowVars} from './vars.js';

export interface SliderRowProps
  extends Omit<MonetSliderProps, 'aria-label' | 'aria-labelledby' | 'className'> {
  label: string;
  /** Shown on hover over the label and value. */
  tooltip?: string;
  /** Formats the value beside the label. Defaults to two decimals. */
  valueToString?: (value: number) => string;
  /**
   * A top-level settings row: a headline-size label, the value in body
   * text, and no thumb icon beside the label. `SliderRow.prominent`.
   */
  prominent?: boolean;
  /**
   * Always uses the small layout. Without it, the row stacks on screens
   * at most 480px wide, as Dart's `ScreenBreakpoints.isScreenSmallWidth`.
   */
  forceSmallWidth?: boolean;
  /** Replaces the label and its info icon. */
  header?: React.ReactNode;
  /** The header's width in the wide layout, in dp. Defaults to the label's. */
  headerWidth?: number;
  /** Beside the slider, in both layouts. */
  trailing?: React.ReactNode;
  className?: string;
  style?: React.CSSProperties;
}

/** `MonetIcons.info`: Material's info_outline (Apache License 2.0). */
function InfoIcon(): React.ReactElement {
  return (
    <svg className="monet-slider-row__info" viewBox="0 0 24 24" aria-hidden="true">
      <path
        fill="currentColor"
        d="M11 7h2v2h-2zm0 4h2v6h-2zm1-9C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8z"
      />
    </svg>
  );
}

/**
 * Peer of `SliderRow`: a labelled slider. Wide, it reads label, value,
 * slider. Small, the label and value sit above the slider.
 */
export function SliderRow({
  label,
  tooltip,
  valueToString = (value) => value.toFixed(2),
  prominent = false,
  forceSmallWidth = false,
  header,
  headerWidth,
  trailing,
  className,
  style,
  value,
  min = 0,
  max = 1,
  thumbIcon,
  onChange,
  onChangeEnd,
  ...slider
}: SliderRowProps): React.ReactElement {
  const geometry = useMonetGeometry();
  const vars = useMemo(
    () => sliderRowVars(sliderRowSpec(geometry, {prominent})),
    [geometry, prominent]
  );
  const labelId = useId();
  // The value follows the drag; the parent's value applies when it ends.
  const [dragged, setDragged] = useState<number | undefined>(undefined);
  const shown = Math.min(max, Math.max(min, dragged ?? value));

  const labelStyle =
    headerWidth == null
      ? undefined
      : withVars({'--monet-slider-row-label-width': `calc(${headerWidth} * var(--monet-dp, 1px))`});

  return (
    <div
      className={cx('monet-slider-row', className)}
      style={withVars(vars, style)}
      data-prominent={prominent || undefined}
      data-small={forceSmallWidth || undefined}
    >
      <div className="monet-slider-row__header" title={tooltip}>
        <span className="monet-slider-row__label" style={labelStyle}>
          {header ?? (
            <>
              <span className="monet-slider-row__name">
                {!prominent && thumbIcon != null && (
                  <span className="monet-slider-row__icon" aria-hidden="true">
                    {thumbIcon}
                  </span>
                )}
                <span id={labelId} className="monet-slider-row__text">
                  {label}
                </span>
              </span>
              <InfoIcon />
            </>
          )}
        </span>
        <output className="monet-slider-row__value" aria-hidden="true">
          {valueToString(shown)}
        </output>
      </div>
      <div className="monet-slider-row__track">
        <MonetSlider
          {...slider}
          value={value}
          min={min}
          max={max}
          thumbIcon={thumbIcon}
          valueToString={valueToString}
          {...(header == null ? {'aria-labelledby': labelId} : {'aria-label': label})}
          onChange={(next) => {
            setDragged(next);
            onChange?.(next);
          }}
          onChangeEnd={(next) => {
            setDragged(undefined);
            onChangeEnd?.(next);
          }}
        />
        {trailing}
      </div>
    </div>
  );
}
