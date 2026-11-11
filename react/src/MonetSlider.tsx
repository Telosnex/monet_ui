import React, {useEffect, useMemo, useRef, useState} from 'react';

import {cx, withVars} from './classes.js';
import {roundSliderValue, sliderSpec} from './spec.js';
import {useMonetGeometry} from './theme.js';
import {sliderVars} from './vars.js';

export interface MonetSliderProps {
  value: number;
  onChange?: (value: number) => void;
  onChangeStart?: (value: number) => void;
  onChangeEnd?: (value: number) => void;
  min?: number;
  max?: number;
  enabled?: boolean;
  /** Drawn in the thumb at 60% of the track height. */
  thumbIcon?: React.ReactNode;
  'aria-label'?: string;
  'aria-labelledby'?: string;
  /** The value as words for assistive technology. */
  valueToString?: (value: number) => string;
  className?: string;
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

/**
 * Peer of `MonetSlider`: a pill-shaped track with the active part in the
 * colour role, and the thumb's right half outlined.
 */
export function MonetSlider({
  value,
  onChange,
  onChangeStart,
  onChangeEnd,
  min = 0,
  max = 1,
  enabled = true,
  thumbIcon,
  'aria-label': ariaLabel,
  'aria-labelledby': ariaLabelledBy,
  valueToString,
  className,
}: MonetSliderProps): React.ReactElement {
  const geometry = useMonetGeometry();
  const spec = useMemo(() => sliderSpec(geometry), [geometry]);
  const vars = useMemo(() => sliderVars(spec), [spec]);
  const trackRef = useRef<HTMLDivElement>(null);
  const draggingRef = useRef(false);
  const [dragging, setDragging] = useState(false);
  const [current, setCurrent] = useState(value);
  const currentRef = useRef(value);

  // While dragging, the drag owns the value; the parent's value applies
  // when it ends.
  useEffect(() => {
    if (!dragging) {
      currentRef.current = value;
      setCurrent(value);
    }
  }, [dragging, value]);

  const set = (next: number) => {
    if (next === currentRef.current) return;
    currentRef.current = next;
    setCurrent(next);
    onChange?.(next);
  };

  /** `_updateValueFromPosition`: the thumb centre travels one radius in. */
  const valueAt = (clientX: number): number => {
    const rect = trackRef.current?.getBoundingClientRect();
    if (!rect) return currentRef.current;
    const radius = rect.height / 2;
    const inner = rect.width - radius * 2;
    if (inner <= 0) return currentRef.current;
    const x = clamp(clientX - rect.left, radius, rect.width - radius);
    const fraction = clamp((x - radius) / inner, 0, 1);
    return roundSliderValue(min + fraction * (max - min));
  };

  const onPointerDown = (event: React.PointerEvent<HTMLDivElement>) => {
    if (!enabled || draggingRef.current) return;
    event.currentTarget.setPointerCapture?.(event.pointerId);
    event.currentTarget.focus();
    draggingRef.current = true;
    setDragging(true);
    onChangeStart?.(currentRef.current);
    set(valueAt(event.clientX));
  };

  const onPointerMove = (event: React.PointerEvent<HTMLDivElement>) => {
    if (!enabled || !draggingRef.current) return;
    set(valueAt(event.clientX));
  };

  const endDrag = (event: React.PointerEvent<HTMLDivElement>) => {
    if (!draggingRef.current) return;
    if (event.currentTarget.hasPointerCapture?.(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
    draggingRef.current = false;
    setDragging(false);
    onChangeEnd?.(currentRef.current);
  };

  /** `_handleKeyEvent` and `_adjustTo`. */
  const onKeyDown = (event: React.KeyboardEvent<HTMLDivElement>) => {
    if (!enabled || draggingRef.current) return;
    const step = (max - min) * spec.keyStep;
    let next: number;
    switch (event.key) {
      case 'ArrowRight':
      case 'ArrowUp':
        next = currentRef.current + step;
        break;
      case 'ArrowLeft':
      case 'ArrowDown':
        next = currentRef.current - step;
        break;
      case 'Home':
        next = min;
        break;
      case 'End':
        next = max;
        break;
      default:
        return;
    }
    event.preventDefault();
    next = clamp(next, min, max);
    if (next === currentRef.current) return;
    onChangeStart?.(currentRef.current);
    set(next);
    onChangeEnd?.(next);
  };

  const fraction = clamp((current - min) / (max - min), 0, 1);

  return (
    <div
      ref={trackRef}
      className={cx('monet-slider', className)}
      style={withVars({...vars, '--monet-slider-value': String(fraction)})}
      role="slider"
      tabIndex={enabled ? 0 : -1}
      aria-label={ariaLabel}
      aria-labelledby={ariaLabelledBy}
      aria-valuemin={min}
      aria-valuemax={max}
      aria-valuenow={current}
      aria-valuetext={valueToString?.(current)}
      aria-disabled={!enabled || undefined}
      data-dragging={dragging || undefined}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={endDrag}
      onPointerCancel={endDrag}
      onKeyDown={onKeyDown}
    >
      <span className="monet-slider__active" />
      <span className="monet-slider__border" />
      <span className="monet-slider__thumb">
        <span className="monet-slider__thumb-border" />
        {thumbIcon != null && <span className="monet-slider__thumb-content">{thumbIcon}</span>}
      </span>
    </div>
  );
}
