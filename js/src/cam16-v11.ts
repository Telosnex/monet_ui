// Modified and maintained by open-source contributors, on behalf of libmonet.
//
// Original notice:
// Copyright 2021 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/**
 * CAM16 v11 in any viewing conditions. Port of the Dart
 * `Cam16V11ViewingConditions` and `Cam16V11`
 * (lib/colorspaces/cam16V11/).
 *
 * Hct uses the sRGB viewing conditions only. Use these classes to see a
 * colour under another white point or background, for example a light.
 */
import type {Argb} from './color.js';
import {argbFromXyz, srgbAdaptingLuminance, sanitizeDegreesDouble, yFromLstar} from './hct.js';
import {signum} from './math.js';
import {xyzFromArgb} from './oklch.js';
import {whitePointD65} from './xyz-lab.js';

/** Appendix A and inverse CAM16 v11 use 43. */
const kColorfulnessScale = 43.0;

export interface Cam16V11ViewingConditionsOptions {
  /** XYZ of the white point. Default D65. */
  whitePoint?: readonly [number, number, number];
  /** Default: sRGB's, 200 / π × mid-gray Y / 100. */
  adaptingLuminance?: number;
  /** Default 50. Values below 0.1 are 0.1. */
  backgroundLstar?: number;
  /** 0 to 2: dark to average. Default 2. */
  surround?: number;
  discountingIlluminant?: boolean;
}

export class Cam16V11ViewingConditions {
  private constructor(
    readonly whitePoint: readonly [number, number, number],
    readonly adaptingLuminance: number,
    readonly backgroundLstar: number,
    readonly surround: number,
    readonly discountingIlluminant: boolean,
    readonly backgroundYToWhitePointY: number,
    readonly aw: number,
    readonly nbb: number,
    readonly ncb: number,
    readonly c: number,
    readonly nC: number,
    readonly rgbD: readonly [number, number, number],
    readonly fl: number,
    readonly fLRoot: number,
    readonly z: number,
  ) {}

  static make({
    whitePoint = whitePointD65,
    adaptingLuminance = srgbAdaptingLuminance,
    backgroundLstar = 50.0,
    surround = 2.0,
    discountingIlluminant = false,
  }: Cam16V11ViewingConditionsOptions = {}): Cam16V11ViewingConditions {
    // Pure black is non-physical and leads to infinities.
    backgroundLstar = Math.max(0.1, backgroundLstar);
    const [x, y, z] = whitePoint;
    const rW = x * 0.401288 + y * 0.650173 + z * -0.051461;
    const gW = x * -0.250268 + y * 1.204414 + z * 0.045854;
    const bW = x * -0.002079 + y * 0.048952 + z * 0.953127;
    if (!(surround >= 0.0 && surround <= 2.0)) {
      throw new RangeError(`surround must be in [0, 2], was ${surround}`);
    }
    const f = 0.8 + surround / 10.0;
    const c =
      f >= 0.9 ? lerp(0.59, 0.69, (f - 0.9) * 10.0) : lerp(0.525, 0.59, (f - 0.8) * 10.0);
    let d = discountingIlluminant
      ? 1.0
      : f * (1.0 - (1.0 / 3.6) * Math.exp((-adaptingLuminance - 42.0) / 92.0));
    d = d > 1.0 ? 1.0 : d < 0.0 ? 0.0 : d;
    const nc = f;
    const rgbD: [number, number, number] = [
      d * (100.0 / rW) + 1.0 - d,
      d * (100.0 / gW) + 1.0 - d,
      d * (100.0 / bW) + 1.0 - d,
    ];
    const k = 1.0 / (5.0 * adaptingLuminance + 1.0);
    const k4 = k * k * k * k;
    const k4F = 1.0 - k4;
    const fl = k4 * adaptingLuminance + 0.1 * k4F * k4F * Math.pow(5.0 * adaptingLuminance, 1.0 / 3.0);
    const n = yFromLstar(backgroundLstar) / whitePoint[1];
    const zz = 1.48 + Math.sqrt(n);
    const nbb = 0.725 / Math.pow(n, 0.2);
    const rgbAFactors = [
      Math.pow((fl * rgbD[0] * rW) / 100.0, 0.42),
      Math.pow((fl * rgbD[1] * gW) / 100.0, 0.42),
      Math.pow((fl * rgbD[2] * bW) / 100.0, 0.42),
    ];
    const rgbA = rgbAFactors.map((v) => (400.0 * v) / (v + 27.13));
    const aw = 2.0 * rgbA[0]! + rgbA[1]! + 0.05 * rgbA[2]!;
    return new Cam16V11ViewingConditions(
      whitePoint,
      adaptingLuminance,
      backgroundLstar,
      surround,
      discountingIlluminant,
      n,
      aw,
      nbb,
      nbb,
      c,
      nc,
      rgbD,
      fl,
      Math.pow(fl, 0.25),
      zz,
    );
  }

  static readonly sRgb: Cam16V11ViewingConditions = Cam16V11ViewingConditions.make();
  static readonly standard: Cam16V11ViewingConditions = Cam16V11ViewingConditions.sRgb;
}

function lerp(start: number, stop: number, amount: number): number {
  return (1.0 - amount) * start + amount * stop;
}

export class Cam16V11 {
  constructor(
    /** Hue in degrees. */
    readonly hue: number,
    readonly chroma: number,
    /** Lightness. */
    readonly j: number,
    /** Brightness. */
    readonly q: number,
    /** Colorfulness. */
    readonly m: number,
    /** Saturation. */
    readonly s: number,
    readonly jstar: number,
    readonly astar: number,
    readonly bstar: number,
  ) {}

  static hueEccentricity(hueRadians: number): number {
    const h = hueRadians;
    return (
      1.0 +
      -0.0582 * Math.cos(h) -
      0.0258 * Math.cos(2.0 * h) -
      0.1347 * Math.cos(3.0 * h) +
      0.0289 * Math.cos(4.0 * h) -
      0.1475 * Math.sin(h) -
      0.0308 * Math.sin(2.0 * h) +
      0.0385 * Math.sin(3.0 * h) +
      0.0096 * Math.sin(4.0 * h)
    );
  }

  static fromInt(argb: Argb): Cam16V11 {
    return Cam16V11.fromIntInViewingConditions(argb, Cam16V11ViewingConditions.sRgb);
  }

  static fromIntInViewingConditions(argb: Argb, viewingConditions: Cam16V11ViewingConditions): Cam16V11 {
    const [x, y, z] = xyzFromArgb(argb);
    return Cam16V11.fromXyzInViewingConditions(x, y, z, viewingConditions);
  }

  static fromXyzInViewingConditions(
    x: number,
    y: number,
    z: number,
    vc: Cam16V11ViewingConditions,
  ): Cam16V11 {
    const rC = 0.401288 * x + 0.650173 * y - 0.051461 * z;
    const gC = -0.250268 * x + 1.204414 * y + 0.045854 * z;
    const bC = -0.002079 * x + 0.048952 * y + 0.953127 * z;
    const rD = vc.rgbD[0] * rC;
    const gD = vc.rgbD[1] * gC;
    const bD = vc.rgbD[2] * bC;
    const rAF = Math.pow((vc.fl * Math.abs(rD)) / 100.0, 0.42);
    const gAF = Math.pow((vc.fl * Math.abs(gD)) / 100.0, 0.42);
    const bAF = Math.pow((vc.fl * Math.abs(bD)) / 100.0, 0.42);
    const rA = (signum(rD) * 400.0 * rAF) / (rAF + 27.13);
    const gA = (signum(gD) * 400.0 * gAF) / (gAF + 27.13);
    const bA = (signum(bD) * 400.0 * bAF) / (bAF + 27.13);
    const a = (11.0 * rA + -12.0 * gA + bA) / 11.0;
    const b = (rA + gA - 2.0 * bA) / 9.0;
    const hue = sanitizeDegreesDouble((Math.atan2(b, a) * 180.0) / Math.PI);
    const hueRadians = (hue * Math.PI) / 180.0;
    const ac = 2.0 * rA + gA + 0.05 * bA;
    const J = 100.0 * Math.pow(ac / vc.aw, vc.c * vc.z);
    const Q = (2.0 / vc.c) * (J / 100.0) * vc.aw;
    const eHue = Cam16V11.hueEccentricity(hueRadians);
    const M = kColorfulnessScale * vc.nC * eHue * Math.sqrt(a * a + b * b);
    const C = (35.0 * M) / vc.aw;
    const saturation = Q === 0.0 ? 0.0 : (100.0 * M) / Q;
    const [jstar, astar, bstar] = relativeUcsFromJch(J, C, hueRadians);
    return new Cam16V11(hue, C, J, Q, M, saturation, jstar, astar, bstar);
  }

  static fromJch(j: number, c: number, h: number): Cam16V11 {
    return Cam16V11.fromJchInViewingConditions(j, c, h, Cam16V11ViewingConditions.sRgb);
  }

  static fromJchInViewingConditions(
    J: number,
    C: number,
    h: number,
    vc: Cam16V11ViewingConditions,
  ): Cam16V11 {
    const Q = (2.0 / vc.c) * (J / 100.0) * vc.aw;
    const M = (C * vc.aw) / 35.0;
    const s = Q === 0.0 ? 0.0 : (100.0 * M) / Q;
    const [jstar, astar, bstar] = relativeUcsFromJch(J, C, (h * Math.PI) / 180.0);
    return new Cam16V11(h, C, J, Q, M, s, jstar, astar, bstar);
  }

  toInt(): Argb {
    return this.viewed(Cam16V11ViewingConditions.sRgb);
  }

  /** The sRGB colour that looks like this one in `viewingConditions`. */
  viewed(viewingConditions: Cam16V11ViewingConditions): Argb {
    const [x, y, z] = this.xyzInViewingConditions(viewingConditions);
    return argbFromXyz(x, y, z);
  }

  xyzInViewingConditions(vc: Cam16V11ViewingConditions): [number, number, number] {
    const hRad = (this.hue * Math.PI) / 180.0;
    const M = (this.chroma * vc.aw) / 35.0;
    const eHue = Cam16V11.hueEccentricity(hRad);
    const opponentMagnitude =
      M === 0.0 || eHue === 0.0 ? 0.0 : M / (kColorfulnessScale * vc.nC * eHue);
    const a = opponentMagnitude * Math.cos(hRad);
    const b = opponentMagnitude * Math.sin(hRad);
    const p2 = vc.aw * Math.pow(this.j / 100.0, 1.0 / vc.c / vc.z);
    const rA = (460.0 * p2 + 451.0 * a + 288.0 * b) / 1403.0;
    const gA = (460.0 * p2 - 891.0 * a - 261.0 * b) / 1403.0;
    const bA = (460.0 * p2 - 220.0 * a - 6300.0 * b) / 1403.0;
    const rF = inverseAdaptedResponse(rA, vc.fl) / vc.rgbD[0];
    const gF = inverseAdaptedResponse(gA, vc.fl) / vc.rgbD[1];
    const bF = inverseAdaptedResponse(bA, vc.fl) / vc.rgbD[2];
    return [
      1.86206786 * rF - 1.01125463 * gF + 0.14918677 * bF,
      0.38752654 * rF + 0.62144744 * gF - 0.00897398 * bF,
      -0.0158415 * rF - 0.03412294 * gF + 1.04996444 * bF,
    ];
  }
}

function relativeUcsFromJch(J: number, C: number, hueRadians: number): [number, number, number] {
  const jstar = (1.7 * J) / (1.0 + 0.007 * J);
  const cstar = (2.4 * Math.log(1.0 + 0.098 * C)) / 0.098;
  return [jstar, cstar * Math.cos(hueRadians), cstar * Math.sin(hueRadians)];
}

function inverseAdaptedResponse(adapted: number, fl: number): number {
  const adaptedAbs = Math.abs(adapted);
  const denominator = 400.0 - adaptedAbs;
  if (denominator <= 0.0) return 0.0;
  const base = Math.max(0.0, (27.13 * adaptedAbs) / denominator);
  return signum(adapted) * (100.0 / fl) * Math.pow(base, 1.0 / 0.42);
}
