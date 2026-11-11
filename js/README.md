# @telosnex/monet-ui

The colour and theme part of the Dart `monet_ui` package, in TypeScript:
colour spaces, contrast, palettes, `MonetThemeData`, image colour
extraction and CSS variables. It has no framework dependency. The React
controls are in `@telosnex/monet-ui-react`.

```ts
import {
  MonetThemeData,
  argbFromHex,
  themeCssVars,
  applyCssVars,
} from '@telosnex/monet-ui';

const theme = MonetThemeData.fromColor({
  color: argbFromHex('#1177AA'),
  backgroundTone: 93,
  brightness: 'light',
  contrast: 0.5,
});

applyCssVars(themeCssVars(theme));
```

Image extraction:

```ts
import {MonetThemeData, quantizeImage} from '@telosnex/monet-ui';

const result = await quantizeImage(imgElement, 128, 96);
const theme = MonetThemeData.fromQuantizerResult({
  result,
  backgroundTone: 93,
  brightness: 'light',
});
```

Runtime animation:

```ts
import {PaletteLerped, paletteCssVars, applyCssVars} from '@telosnex/monet-ui';

const lerped = new PaletteLerped(oldTheme.primary, newTheme.primary, 0.5, 'polar');
applyCssVars(paletteCssVars('primary', lerped.toRecord()));
```

The implementation lives next to the Dart code so parity fixtures/tests can be generated from the Dart source of truth.

Parity workflow:

```sh
npm run test:parity:generate # regenerates fixtures/libmonet_parity.json from Dart
npm run check                # TypeScript build + Vitest, including Dart fixture parity
npm run check:parity         # regenerate fixtures, fail on fixture diff, then run check
```

Current parity note: JS now includes direct CAM16 v1.1/HCT, TemperatureCache, and Celebi/Wu/WSMeans quantizer ports validated by focused tests and Dart fixtures. Palette/theme/scorer parity is checked against Dart-generated fixtures with a tiny channel-drift budget for solver-edge rounding.
