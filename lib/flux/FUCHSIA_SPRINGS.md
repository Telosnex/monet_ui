# Fuchsia Spring Usage Map

Every RK4 spring in Armadillo/Mondrian. Friction is always 50 (except two
Flutter `SpringDescription` outliers noted at the bottom).

## RK4 Springs (tension / friction=50)

| Tension | UI | Source file |
|---------|----|-------------|
| **100** | Suggestion splash sweep | `splash_suggestion.dart` |
| **100** | Suggestion splash clear | `splash_suggestion.dart` |
| **250** | Story cluster entrance transition | `story_cluster_entrance_transition_model.dart` |
| **250** | Idle model (screen dimming) | `idle_model.dart` |
| **450** | Suggestion card expand height | `expand_suggestion.dart` |
| **450** | Suggestion card expand opacity | `expand_suggestion.dart` |
| **450** | Quick settings icon spring | `quick_settings.dart` |
| **450** | Story bar height | `story_bar.dart` |
| **450** | Story bar focus indicator | `story_bar.dart` |
| **450** | Drag target panel scale | `panel_drag_targets.dart` |
| **450** | Drag feedback settle | `armadillo_drag_target.dart` |
| **450** | Story fractionally-sized box | `simulated_fractionally_sized_box.dart` |
| **450** | SpringModel default (base class) | `spring_model.dart` |
| **450** | TracingSpringModel default | `tracing_spring_model.dart` |
| **450** | TickingDoubleState default | `ticking_double_state.dart` |
| **450** | Mondrian inset manager | `inset_manager.dart` (Mondrian) |
| **600** | Quick settings progress (pull %) | `quick_settings_progress_model.dart` |
| **600** | Now bar minimization | `now_minimization_model.dart` |
| **750** | Story cluster focus transition | `focus_model.dart` |
| **750** | Panel resize | `panel_resizing_model.dart` |
| **750** | Rearrangement scrim opacity | `story_rearrangement_scrim_model.dart` |
| **750** | Story drag transition | `story_drag_transition_model.dart` |
| **750** | SimulatedTransform default (pos+scale) | `simulated_transform.dart` |
| **750** | SimulatedFractional default (layout) | `simulated_fractional.dart` |
| **750** | SimulatedSizedBox default (size) | `simulated_sized_box.dart` |
| **750** | Inline preview hint scale | `story_cluster.dart` |
| **900** | Inline preview progress | `story_cluster.dart` |

## Flutter SpringDescription (analytical, no soft onset)

These two used Flutter's built-in `SpringSimulation`, not the RK4 sim.
No acceleration ramp.

| Stiffness | Damping | UI | Source |
|-----------|---------|-----|--------|
| 120 | 19 | SimulatedPositioned drag (lib_widgets) | `simulated_positioned.dart` |
| 220 | 29 | Mondrian surface stage layout | `surface_stage.dart` (Mondrian) |

## Summary by tier

| Tier | Tension | Count | Used for |
|------|---------|-------|----------|
| Theatrical | 100 | 2 | Splash effects |
| Slow | 250 | 2 | Entrance, idle/dim |
| Default | 450 | 10 | Most things: bars, cards, drag settle, sizing |
| Responsive | 600 | 2 | Now bar, quick settings |
| Snappy | 750 | 8 | Focus, resize, scrim, layout, drag, transforms |
| Snappiest | 900 | 1 | Inline preview |
