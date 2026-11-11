import React, {useEffect, useId, useMemo, useRef, useState} from 'react';

import {cx, withVars} from './classes.js';
import {MonetButton} from './MonetButton.js';
import {dropdownSpec} from './spec.js';
import {useMonetGeometry} from './theme.js';
import {menuVars} from './vars.js';

export interface MonetDropdownProps<T> {
  items: readonly T[];
  value: T;
  /** Called when the user picks another item; not for the current one. */
  onChange: (value: T) => void;
  itemLabel: (item: T) => string;
  /** Replaces the label inside an item. */
  renderItem?: (item: T) => React.ReactNode;
  itemIcon?: (item: T) => React.ReactNode;
  isItemEnabled?: (item: T) => boolean;
  /** The trigger's text. Defaults to the value's label. */
  selectedLabel?: string;
  /** Names the menu for assistive technology. */
  'aria-label'?: string;
  className?: string;
}

function Chevron(): React.ReactElement {
  return (
    <svg className="monet-dropdown__chevron" viewBox="0 0 24 24" aria-hidden="true">
      <path d="M7 10l5 5 5-5z" fill="currentColor" />
    </svg>
  );
}

/**
 * Peer of `MonetDropdown`: a primary `MonetButton` that opens a menu of
 * items. The current item rests in the splashed colours.
 */
export function MonetDropdown<T>({
  items,
  value,
  onChange,
  itemLabel,
  renderItem,
  itemIcon,
  isItemEnabled,
  selectedLabel,
  'aria-label': ariaLabel,
  className,
}: MonetDropdownProps<T>): React.ReactElement {
  const geometry = useMonetGeometry();
  const vars = useMemo(() => menuVars(dropdownSpec(geometry)), [geometry]);
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement & HTMLAnchorElement>(null);
  const optionRefs = useRef<Array<HTMLDivElement | null>>([]);
  const listboxId = useId();
  const selectedIndex = items.findIndex((item) => Object.is(item, value));
  const enabled = (item: T) => isItemEnabled?.(item) ?? true;

  const close = (refocus: boolean) => {
    setOpen(false);
    if (refocus) triggerRef.current?.focus();
  };

  // Open: focus the current item, else the first enabled one.
  useEffect(() => {
    if (!open) return;
    const start = selectedIndex >= 0 ? selectedIndex : items.findIndex((item) => enabled(item));
    optionRefs.current[Math.max(0, start)]?.focus();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  useEffect(() => {
    if (!open) return undefined;
    const onPointerDown = (event: MouseEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', onPointerDown);
    return () => document.removeEventListener('mousedown', onPointerDown);
  }, [open]);

  const choose = (item: T) => {
    if (!enabled(item)) return;
    close(true);
    if (!Object.is(item, value)) onChange(item);
  };

  const moveFocus = (from: number, direction: 1 | -1) => {
    for (let step = 1; step <= items.length; step++) {
      const index = (from + direction * step + items.length) % items.length;
      if (enabled(items[index]!)) {
        optionRefs.current[index]?.focus();
        return;
      }
    }
  };

  const onMenuKeyDown = (event: React.KeyboardEvent<HTMLDivElement>, index: number) => {
    switch (event.key) {
      case 'ArrowDown':
        moveFocus(index, 1);
        break;
      case 'ArrowUp':
        moveFocus(index, -1);
        break;
      case 'Home':
        moveFocus(-1, 1);
        break;
      case 'End':
        moveFocus(items.length, -1);
        break;
      case 'Enter':
      case ' ':
        choose(items[index]!);
        break;
      case 'Escape':
        close(true);
        break;
      case 'Tab':
        close(false);
        return;
      default:
        return;
    }
    event.preventDefault();
  };

  return (
    <div className={cx('monet-dropdown', className)} ref={rootRef}>
      <MonetButton
        ref={triggerRef}
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={open ? listboxId : undefined}
        onClick={() => setOpen((o) => !o)}
        onKeyDown={(event) => {
          if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
            event.preventDefault();
            setOpen(true);
          }
        }}
      >
        <span className="monet-dropdown__trigger">
          <span className="monet-dropdown__selected">
            {selectedLabel ?? (selectedIndex >= 0 ? itemLabel(value) : '')}
          </span>
          <Chevron />
        </span>
      </MonetButton>
      {open && (
        <div
          id={listboxId}
          className={cx(
            'monet-menu',
            geometry.corner === 'superellipse' && 'monet-superellipse'
          )}
          style={withVars(vars)}
          role="listbox"
          aria-label={ariaLabel}
        >
          {items.map((item, index) => {
            const selected = index === selectedIndex;
            const itemEnabled = enabled(item);
            const icon = itemIcon?.(item);
            return (
              <div
                key={index}
                ref={(el) => {
                  optionRefs.current[index] = el;
                }}
                className="monet-menu__item"
                role="option"
                tabIndex={-1}
                aria-selected={selected}
                aria-disabled={!itemEnabled || undefined}
                data-selected={selected || undefined}
                onClick={() => choose(item)}
                onKeyDown={(event) => onMenuKeyDown(event, index)}
              >
                {icon != null && (
                  <span className="monet-menu__icon" aria-hidden="true">
                    {icon}
                  </span>
                )}
                <span className="monet-menu__label">
                  {renderItem ? renderItem(item) : itemLabel(item)}
                </span>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
