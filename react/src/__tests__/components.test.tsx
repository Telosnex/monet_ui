import {MonetThemeData, argbFromHex} from '@telosnex/monet-ui';
import {act, cleanup, fireEvent, render, screen} from '@testing-library/react';
import React, {useState} from 'react';
import {afterEach, describe, expect, test, vi} from 'vitest';

import {
  Bordered,
  MonetButton,
  MonetDropdown,
  MonetExpansion,
  MonetSegmented,
  MonetSlider,
  MonetThemeScope,
} from '../index.js';

afterEach(cleanup);

// jsdom's pointer events drop the mouse coordinates.
class TestPointerEvent extends MouseEvent {
  readonly pointerId: number;
  constructor(type: string, init: PointerEventInit = {}) {
    super(type, init);
    this.pointerId = init.pointerId ?? 0;
  }
}
window.PointerEvent = TestPointerEvent as unknown as typeof PointerEvent;

const theme = MonetThemeData.fromColor({
  color: argbFromHex('#4B778F'),
  backgroundTone: 93,
  brightness: 'light',
  contrast: 0.5,
});

function inTheme(children: React.ReactNode, props: {scale?: number; radius?: number} = {}) {
  return render(
    <MonetThemeScope theme={theme} corner="superellipse" {...props}>
      {children}
    </MonetThemeScope>
  );
}

function styleVar(el: Element, name: string): string {
  return (el as HTMLElement).style.getPropertyValue(name);
}

describe('MonetThemeScope', () => {
  test('sets the palette variables', () => {
    const {container} = inTheme(null);
    const scope = container.firstElementChild!;
    expect(styleVar(scope, '--monet-primary-color')).toMatch(/^#[0-9A-F]{6}$/);
  });
});

describe('MonetButton', () => {
  test('has superellipse corners by default, as MonetShapeTheme()', () => {
    render(
      <MonetThemeScope theme={theme}>
        <MonetButton>Plain</MonetButton>
      </MonetThemeScope>
    );
    expect(screen.getByRole('button', {name: 'Plain'}).className).toContain('monet-superellipse');
  });

  test('reads its colours, size and corners from the spec', () => {
    inTheme(<MonetButton kind="fill">Go</MonetButton>, {scale: 0.64, radius: 9});
    const button = screen.getByRole('button', {name: 'Go'});
    expect(styleVar(button, '--monet-button-rest-background')).toBe('var(--monet-primary-fill)');
    expect(styleVar(button, '--monet-button-min-height')).toBe('calc(20.8 * var(--monet-dp, 1px))');
    expect(styleVar(button, '--monet-button-radius')).toBe('calc(7.2 * var(--monet-dp, 1px))');
    expect(button.className).toContain('monet-superellipse');
  });

  test('links, disables and selects', () => {
    const onClick = vi.fn();
    inTheme(
      <>
        <MonetButton href="/a">Link</MonetButton>
        <MonetButton href="/b" disabled>
          Off link
        </MonetButton>
        <MonetButton disabled onClick={onClick}>
          Off
        </MonetButton>
        <MonetButton selected>On</MonetButton>
      </>
    );
    expect(screen.getByRole('link', {name: 'Link'}).getAttribute('href')).toBe('/a');
    expect(screen.getByText('Off link').closest('a')!.hasAttribute('href')).toBe(false);
    fireEvent.click(screen.getByRole('button', {name: 'Off'}));
    expect(onClick).not.toHaveBeenCalled();
    expect(screen.getByRole('button', {name: 'On'}).getAttribute('aria-pressed')).toBe('true');
  });
});

describe('MonetSegmented', () => {
  function Harness({onChange}: {onChange?: (v: string) => void}) {
    const [value, setValue] = useState('b');
    return (
      <MonetSegmented
        aria-label="Mode"
        options={[
          {value: 'a', label: 'A'},
          {value: 'b', label: 'B'},
          {value: 'c', label: 'C'},
          {value: 'd', label: 'D'},
        ]}
        value={value}
        onChange={(v) => {
          setValue(v);
          onChange?.(v);
        }}
      />
    );
  }

  test('draws dividers only between unselected neighbours', () => {
    inTheme(<Harness />);
    const radios = screen.getAllByRole('radio');
    expect(radios.map((r) => r.hasAttribute('data-divider-after'))).toEqual([
      false,
      false,
      true,
      false,
    ]);
    expect(radios[1]!.getAttribute('aria-checked')).toBe('true');
  });

  test('arrow keys move the selection', () => {
    const onChange = vi.fn();
    inTheme(<Harness onChange={onChange} />);
    fireEvent.keyDown(screen.getByRole('radio', {name: 'B'}), {key: 'ArrowRight'});
    expect(onChange).toHaveBeenLastCalledWith('c');
    fireEvent.keyDown(screen.getByRole('radio', {name: 'C'}), {key: 'ArrowLeft'});
    expect(onChange).toHaveBeenLastCalledWith('b');
  });
});

describe('MonetSlider', () => {
  test('keys move by a twentieth of the range, as in Dart', () => {
    const onChange = vi.fn();
    const onChangeStart = vi.fn();
    const onChangeEnd = vi.fn();
    inTheme(
      <MonetSlider
        aria-label="Size"
        value={10}
        min={0}
        max={20}
        onChange={onChange}
        onChangeStart={onChangeStart}
        onChangeEnd={onChangeEnd}
      />
    );
    const slider = screen.getByRole('slider', {name: 'Size'});
    fireEvent.keyDown(slider, {key: 'ArrowRight'});
    expect(onChangeStart).toHaveBeenLastCalledWith(10);
    expect(onChange).toHaveBeenLastCalledWith(11);
    expect(onChangeEnd).toHaveBeenLastCalledWith(11);
    fireEvent.keyDown(slider, {key: 'End'});
    expect(onChange).toHaveBeenLastCalledWith(20);
    onChange.mockClear();
    fireEvent.keyDown(slider, {key: 'ArrowUp'});
    expect(onChange).not.toHaveBeenCalled();
    fireEvent.keyDown(slider, {key: 'Home'});
    expect(slider.getAttribute('aria-valuenow')).toBe('0');
  });

  test('a disabled slider ignores keys and dims each colour', () => {
    const onChange = vi.fn();
    inTheme(<MonetSlider aria-label="Off" value={0.5} enabled={false} onChange={onChange} />);
    const slider = screen.getByRole('slider', {name: 'Off'});
    fireEvent.keyDown(slider, {key: 'ArrowRight'});
    expect(onChange).not.toHaveBeenCalled();
    expect(slider.getAttribute('aria-disabled')).toBe('true');
    expect(styleVar(slider, '--monet-slider-disabled-active-track')).toBe(
      'color-mix(in srgb, var(--monet-primary-color) 60%, transparent)'
    );
  });

  test('pointer drags round to thousandths', () => {
    const onChange = vi.fn();
    inTheme(<MonetSlider aria-label="Drag" value={0} onChange={onChange} />);
    const slider = screen.getByRole('slider', {name: 'Drag'});
    slider.getBoundingClientRect = () =>
      ({left: 0, top: 0, width: 136, height: 36, right: 136, bottom: 36}) as DOMRect;
    fireEvent.pointerDown(slider, {clientX: 51.123, pointerId: 1});
    expect(onChange).toHaveBeenLastCalledWith(0.331);
    fireEvent.pointerUp(slider, {pointerId: 1});
  });
});

describe('MonetExpansion', () => {
  test('toggles and keeps collapsed content inert', () => {
    const onChange = vi.fn();
    inTheme(
      <MonetExpansion title="More" onExpansionChanged={onChange}>
        <button type="button">Inside</button>
      </MonetExpansion>
    );
    const header = screen.getByRole('button', {name: 'More'});
    const body = document.getElementById(header.getAttribute('aria-controls')!)!;
    expect(header.getAttribute('aria-expanded')).toBe('false');
    expect(body.inert).toBe(true);
    fireEvent.click(header);
    expect(onChange).toHaveBeenLastCalledWith(true);
    expect(header.getAttribute('aria-expanded')).toBe('true');
    expect(body.inert).toBe(false);
  });
});

describe('MonetDropdown', () => {
  function Harness({onChange}: {onChange: (v: string) => void}) {
    const [value, setValue] = useState('Two');
    return (
      <MonetDropdown
        aria-label="Numbers"
        items={['One', 'Two', 'Three']}
        value={value}
        itemLabel={(v) => v}
        onChange={(v) => {
          setValue(v);
          onChange(v);
        }}
      />
    );
  }

  test('opens on the current item and picks with the keyboard', () => {
    const onChange = vi.fn();
    inTheme(<Harness onChange={onChange} />);
    const trigger = screen.getByRole('button', {name: 'Two'});
    fireEvent.click(trigger);
    const listbox = screen.getByRole('listbox', {name: 'Numbers'});
    expect(document.activeElement?.textContent).toBe('Two');
    expect(screen.getByRole('option', {name: 'Two'}).getAttribute('aria-selected')).toBe('true');
    fireEvent.keyDown(document.activeElement!, {key: 'ArrowDown'});
    expect(document.activeElement?.textContent).toBe('Three');
    fireEvent.keyDown(document.activeElement!, {key: 'Enter'});
    expect(onChange).toHaveBeenLastCalledWith('Three');
    expect(listbox.isConnected).toBe(false);
    expect(document.activeElement).toBe(screen.getByRole('button', {name: 'Three'}));
  });

  test('picking the current item only closes; Escape and outside clicks close', () => {
    const onChange = vi.fn();
    inTheme(<Harness onChange={onChange} />);
    const trigger = screen.getByRole('button', {name: 'Two'});
    fireEvent.click(trigger);
    fireEvent.click(screen.getByRole('option', {name: 'Two'}));
    expect(onChange).not.toHaveBeenCalled();
    expect(screen.queryByRole('listbox')).toBeNull();
    fireEvent.click(trigger);
    fireEvent.keyDown(document.activeElement!, {key: 'Escape'});
    expect(screen.queryByRole('listbox')).toBeNull();
    fireEvent.click(trigger);
    act(() => {
      document.body.dispatchEvent(new MouseEvent('mousedown', {bubbles: true}));
    });
    expect(screen.queryByRole('listbox')).toBeNull();
  });
});

describe('Bordered', () => {
  test('uses the family background and border', () => {
    const {container} = inTheme(<Bordered family="secondary">x</Bordered>);
    const panel = container.querySelector('.monet-bordered')!;
    expect(styleVar(panel, '--monet-bordered-background')).toBe('var(--monet-secondary-background)');
    expect(styleVar(panel, '--monet-bordered-border-color')).toBe(
      'var(--monet-secondary-background-border)'
    );
  });
});
