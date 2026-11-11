# @telosnex/monet-ui-react

React versions of the monet_ui controls: `MonetButton`, `MonetSegmented`,
`MonetSlider`, `SliderRow`, `MonetExpansion`, `MonetDropdown` and
`Bordered`, inside a
`MonetThemeScope`. Colours come from `@telosnex/monet-ui`.

```tsx
import {MonetThemeScope, MonetButton} from '@telosnex/monet-ui-react';
import '@telosnex/monet-ui-react/styles.css';

<MonetThemeScope theme={theme} radius={9} corner="superellipse">
  <MonetButton kind="fill">Save</MonetButton>
</MonetThemeScope>;
```

`theme` is a `MonetThemeData` from `@telosnex/monet-ui`. `scale`, `radius` and `corner` are
the Dart theme's `scale` and `MonetShapeTheme`. The defaults are Dart's
`MonetThemeData` defaults: scale 1, radius 8, superellipse corners. The
Telosnex app uses radius 9. For plain rounded corners, pass
`corner="rounded"` here and `borderBuilder: RoundedRectangleBorder.new` in
Dart.

Apps may set `--monet-dp` (one logical pixel), `--monet-font-label`,
`--monet-font-mono` and the text sizes `--monet-type-label-large`,
`--monet-type-label-medium`, `--monet-type-body-large` and
`--monet-type-headline-small`. Unset text sizes are the Dart theme's for
Roboto: 17, 15, 19 and 24 logical pixels, scaled as the theme's lengths
are. For another font, multiply by Dart's correction for it
(`visualHeightScaleForFontFamily`).

## Parity with Dart

`src/spec.ts` says what each control resolves to: palette roles and
logical pixels. `test/react/controls_parity_fixture_test.dart` writes what
the Dart controls resolve to into `fixtures/monet_controls_parity.json`.
`src/__tests__/parity.test.ts` compares the two (ADR 003 D5).

```bash
npm ci
npm run check          # typecheck, build, tests
npm run check:parity   # regenerate the fixture, fail if it changed, check
npm run demo           # every control in three themes
```

npm 10.9 crashes (`edgesOut`) when it resolves this package's dependencies
without the lockfile. `npm ci` works. To change dependencies, use npm 11:
`npx npm@11 install`.

## Publishing

Publish `@telosnex/monet-ui` (`../js`) first when it changed, then this
package. Bump `version` in each, and the `@telosnex/monet-ui` peer range
here when it needs a newer release. `prepublishOnly` runs `npm run check`.

```bash
cd ../js && npm publish
cd ../react && npm publish
```

Web-only additions, not in the Dart controls: a focus ring in the tertiary
colour role, and keyboard handling for the segmented control and the menu.
