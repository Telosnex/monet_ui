# Flux: Spring Animations with Velocity Handoff

## What This Is

A port of the animation system from Fuchsia's Mondrian story shell. The core
idea: **animations carry velocity**. When you transition from one animation to
another (drag → spring, spring → spring), the new animation picks up from the
old one's velocity. No jerk.

## Origin

```
topaz/shell/mondrian_story_shell/lib/anim/flux.dart  — FluxAnimation, ManualAnimation, etc.
topaz/shell/mondrian_story_shell/lib/anim/sim.dart   — Sim<T>, SimDouble, Independent2DSim, etc.
```

Mondrian used Flux for everything: surface layout transitions, drag-to-dismiss,
card resize, overview zoom. Every animation that involved user input used
`ManualAnimation` for the gesture phase and a spring `Sim` for the settle phase.

## Files

| File | What |
|------|------|
| `sim.dart` | `Sim<T>` — generic simulation base class (like Flutter's `Simulation` but generic) |
| `flux_animation.dart` | `FluxAnimation<T>` — Animation with velocity. `SimAnimationController`, `ManualAnimation`, `MovingTargetAnimation`, `ChainedAnimation` |
| `spring.dart` | `FluxSpring` — named spring presets. `springSimDouble()` convenience constructor |
| `flux_curve.dart` | `FluxCurve` — Curve adapter for implicit animations (`AnimatedContainer`, etc.) |
| `hooks.dart` | `useFluxSpring()`, `useFluxManual()` — Flutter Hooks integration |
| `spring_frame_clock.dart` | `SpringFrameClock` — `dt` for render objects that tick springs in `paint`, plus "was this layout ever on screen?" so hidden relayouts snap instead of animating |
| `flux.dart` | Barrel export |

## Current Wiring

### Active (using Flux today)

| Widget | Before | After |
|--------|--------|-------|
| `ai_controls_button.dart` | Hand-rolled `SpringCurve` class (~35 lines of manual spring math) | `FluxCurve(spring: FluxSpring.snappy)` — 1 line, real `SpringSimulation` |
| `animated_expandable.dart` | `Curves.easeOutCirc` | `FluxCurve(spring: FluxSpring.snappy)` — all 8 callers (MCP, loom, script picker, search) get springs |
| `collapsible_text_section.dart` | Default `Curves.linear` on `AnimatedContainer` | `FluxCurve(spring: FluxSpring.gentle)` |
| `home_scrollable_overlay.dart` | `Curves.easeInOutQuint` on scroll-to-top/bottom and arrow animations | `FluxCurve(spring: FluxSpring.responsive)` — 5 curve replacements |

### Next Targets (not yet wired)

| Widget | Current | Flux Approach |
|--------|---------|---------------|
| `custom_cupertino_page_route.dart` | `Curves.fastLinearToSlowEaseIn` for back swipe | `ManualAnimation` during drag → spring on release. Highest-traffic animation. |
| `monet_slider.dart` | Velocity discarded on drag end | `ManualAnimation` → spring settle at gesture velocity |
| `trackpad_dismiss_gesture_detector.dart` | Pops instantly above velocity threshold | Spring-driven slide-out, pop on completion |

## Spring Presets

All springs use friction=50 (Fuchsia's universal damping). Settle times are
measured with the RK4 sim including the soft-onset acceleration ramp.

| Name | Tension | Character | RK4 Settle |
|------|---------|-----------|------------|
| `theatrical` | 250 | Very overdamped, cinematic | ~1600ms |
| `gentle` | 450 | Overdamped, smooth (Fuchsia default) | ~680ms |
| `responsive` | 600 | Near-critically damped | ~600ms |
| `snappy` | 750 | Subtle overshoot at ~280ms | ~480ms |
| `snappiest` | 900 | Slightly more overshoot | ~420ms |

> **Duration trap:** The settle times above are in _simulation_ time.
> `FluxCurve` exposes `duration` (a `Duration`) derived from the settle time.
> Always pass `curve.duration` to the widget's `duration:` parameter.
> Otherwise the spring shape gets time-compressed and the overshoot is invisible.

## Architecture

### Three tiers of usage

**Tier 1: Gesture → velocity → spring** (the whole point)
Use `ManualAnimation<T>` during the drag, call `.done()` on release.
The builder creates a spring from final value + velocity.

**Tier 2: Programmatic → spring**
Use `useFluxSpring()` hook or `SimAnimationController` directly.
Value goes from A to B on a real spring. No fixed duration.

**Tier 3: Implicit animation curve swap**
Use `FluxCurve(spring: ...)` as a drop-in for any `Curve` parameter.
Pragmatic bridge — the spring is time-clamped to fit Flutter's
fixed-duration model, but the overshoot and settle are real physics.

**⚠️ Critical:** always pair `curve: fluxCurve` with `duration: fluxCurve.duration`.
The curve maps `t ∈ [0,1]` to spring position at `t * settleTime`. If the
controller's duration doesn't match the settle time, the spring plays at the
wrong speed. A 700ms spring in a 200ms controller = 3.5× speed = invisible
overshoot.

### Key types

```
FluxAnimation<T> extends Animation<T>
  + T get velocity

Sim<T>
  + T value(double time)
  + T velocity(double time)
  + bool isDone(double time)

SimAnimationController<T> extends FluxAnimation<T>
  - drives a Sim<T> with a Ticker
  - value range is the simulation's, not 0.0–1.0

ManualAnimation<T> extends FluxAnimation<T>
  - .update(value, velocity) during gesture
  - .done() → builder creates spring from final state

MovingTargetAnimation<T> extends FluxAnimation<T>
  - chases a moving target (layout changes)
  - re-creates spring on target change, picks up from current velocity

ChainedAnimation<T> extends FluxAnimation<T>
  - runs animations in sequence: A → B → C
```

## Differences from Fuchsia Original

| Aspect | Fuchsia | Our Port |
|--------|---------|----------|
| Null safety | `@required` + `assert(x != null)` | `required` keyword, sound null safety |
| `new` keyword | `new Foo()` everywhere | Dropped (Dart 2+) |
| Transform typedef | `Transform<T>` | `FluxTransform<T>` (avoids Flutter widget name collision) |
| Hooks | N/A (stateful widgets) | `useFluxSpring`, `useFluxManual` |
| Curve adapter | N/A (Mondrian never needed it) | `FluxCurve` for implicit animations |
| Spring presets | Hardcoded per-widget | Named `FluxSpring` constants |
