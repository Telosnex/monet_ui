/** A page with every control in three themes, for looking at the CSS. */
import {argbFromHex, MonetThemeData} from '@telosnex/monet-ui';
import React, {useEffect, useState} from 'react';
import {createRoot} from 'react-dom/client';

import {
  Bordered,
  MonetButton,
  MonetDropdown,
  MonetExpansion,
  MonetSegmented,
  MonetSlider,
  MonetThemeScope,
  SliderRow,
  type MonetCorner,
} from '../src/index.js';
import '../src/styles.css';

const plus = (
  <svg viewBox="0 0 24 24">
    <path d="M11 5h2v6h6v2h-6v6h-2v-6H5v-2h6z" fill="currentColor" />
  </svg>
);

function Panel({
  name,
  color,
  tone,
  brightness,
  scale,
  radius,
  corner,
}: {
  name: string;
  color: string;
  tone: number;
  brightness: 'light' | 'dark';
  scale: number;
  radius: number;
  corner: MonetCorner;
}) {
  const theme = MonetThemeData.fromColor({
    color: argbFromHex(color),
    backgroundTone: tone,
    brightness,
    contrast: 0.5,
  });
  const [mode, setMode] = useState('b');
  const [value, setValue] = useState(0.4);
  const [item, setItem] = useState('Two');
  return (
    <MonetThemeScope theme={theme} scale={scale} radius={radius} corner={corner} className="panel bg">
      <h2>{name}</h2>
      <div className="line">
        <MonetButton>Color</MonetButton>
        <MonetButton kind="fill">Fill</MonetButton>
        <MonetButton kind="background">Background</MonetButton>
        <MonetButton kind="outline">Outline</MonetButton>
      </div>
      <div className="line">
        <MonetButton icon={plus}>Icon</MonetButton>
        <MonetButton preset="tool" icon={plus}>Tool</MonetButton>
        <MonetButton preset="compact">Compact</MonetButton>
        <MonetButton family="secondary">Secondary</MonetButton>
        <MonetButton family="tertiary">Tertiary</MonetButton>
        <MonetButton disabled>Disabled</MonetButton>
        <MonetButton selected>Selected</MonetButton>
      </div>
      <MonetSegmented
        aria-label="Mode"
        options={[
          {value: 'a', label: 'Auto'},
          {value: 'b', label: 'Light', icon: plus},
          {value: 'c', label: 'Dark'},
          {value: 'd', label: 'x'},
        ]}
        value={mode}
        onChange={setMode}
      />
      <MonetSegmented
        aria-label="Big"
        isSmall={false}
        options={[
          {value: 'a', label: 'One'},
          {value: 'b', label: 'Two'},
          {value: 'c', label: 'Three'},
        ]}
        value="a"
        onChange={() => {}}
      />
      <MonetSlider aria-label="Value" value={value} onChange={setValue} thumbIcon={plus} />
      <MonetSlider aria-label="Disabled" value={0.7} enabled={false} />
      <SliderRow
        label="Contrast"
        tooltip="How far apart the tones are"
        value={value}
        valueToString={(v) => `${Math.round(v * 100)}%`}
        thumbIcon={plus}
        onChangeEnd={setValue}
      />
      <SliderRow
        label="Size"
        tooltip="Size of everything"
        value={value}
        valueToString={(v) => `${Math.round(v * 100)}%`}
        thumbIcon={plus}
        prominent
        onChangeEnd={setValue}
      />
      <SliderRow
        label="Small layout"
        value={value}
        thumbIcon={plus}
        forceSmallWidth
        trailing={<MonetButton preset="compact" onClick={() => setValue(0.5)}>Reset</MonetButton>}
        onChangeEnd={setValue}
      />
      <MonetExpansion title="Collapsed">
        <p>Hidden</p>
      </MonetExpansion>
      <MonetExpansion title="Expanded" initiallyExpanded>
        <p style={{margin: 8}}>Body text inside the expansion.</p>
      </MonetExpansion>
      <Bordered style={{padding: 12}}>Bordered panel</Bordered>
      <div className="dropdown-host">
        <MonetDropdown
          aria-label="Numbers"
          items={['One', 'Two', 'Three', 'Four']}
          value={item}
          itemLabel={(v) => v}
          itemIcon={() => plus}
          onChange={setItem}
        />
      </div>
    </MonetThemeScope>
  );
}

function App() {
  // Open each dropdown so a screenshot shows the menus.
  useEffect(() => {
    if (location.hash !== '#open') return;
    document
      .querySelectorAll<HTMLButtonElement>('.dropdown-host .monet-button')
      .forEach((b) => b.click());
  }, []);
  return (
    <div className="row">
      <Panel name="light, superellipse 9" color="#4B778F" tone={93} brightness="light" scale={1} radius={9} corner="superellipse" />
      <Panel name="dark, rounded 8" color="#4B778F" tone={10} brightness="dark" scale={1} radius={8} corner="rounded" />
      <Panel name="scale 0.64" color="#D29C57" tone={93} brightness="light" scale={0.64} radius={9} corner="superellipse" />
    </div>
  );
}

createRoot(document.getElementById('root')!).render(<App />);
