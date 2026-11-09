import 'package:flutter/scheduler.dart';

/// One tick of a spring-animating render object's paint loop.
class SpringFrameTick {
  final double dt;
  final bool snapToTargets;
  const SpringFrameTick({required this.dt, required this.snapToTargets});
}

/// Frame bookkeeping for render objects that spring their children from one
/// layout to the next (`RenderReorderableWrap`, `RenderSpaceFlow`).
///
/// Those render objects tick their springs inside `paint` rather than from a
/// [Ticker], so they need two things from the scheduler:
///
/// 1. `dt` — the time between the frames they actually painted.
/// 2. Whether the layout they are about to spring *away from* was ever on
///    screen.
///
/// (2) is the subtle one. A render object is laid out in plenty of frames
/// where it never paints:
///
///  * A route covered by an opaque route stays mounted (`maintainState`), so
///    a `MediaQuery` change — a macOS window resize! — still rebuilds and
///    re-lays out its whole subtree. `_RenderTheater` only paints onstage
///    children, so the covered route's layers are detached and
///    `PipelineOwner.flushPaint` skips it entirely.
///  * `Offstage`, `Visibility`, `Opacity(0)` and viewports culling children
///    scrolled out of view all lay out without painting.
///  * `SnapshotWidget` keeps drawing a cached raster while its child is
///    frozen mid-transition.
///
/// In every one of those cases the user never saw the positions the springs
/// are holding, so animating to the new layout on the first painted frame is
/// pure noise: content shuffles into place *after* it becomes visible instead
/// of simply being there. Callers consult [isLastLayoutUnseen] during layout
/// and [SpringFrameTick.snapToTargets] during paint, and jump straight to the
/// new positions when either says the motion would be invisible anyway.
///
/// ## What counts as "seen"
///
/// A layout pass is seen when the render object painted in the same frame it
/// laid out. `RenderObject.layout` ends with `markNeedsPaint`, so a render
/// object that is genuinely on screen always repaints in its own layout
/// frame; if it didn't, it wasn't being drawn. Repeat layout passes inside a
/// single frame (sliver scroll corrections — see
/// `AnchoredSliverToBoxAdapter` — intrinsic sizing, `LayoutBuilder`) are a
/// continuation of that frame's pass, not new hidden passes, so only the
/// first pass in a frame forms a verdict.
class SpringFrameClock {
  /// Springs advance by at most this much per painted frame.
  ///
  /// Without a cap, a long gap between paints (backgrounded app, hidden
  /// route, a stretch of dropped frames) would integrate the spring most of
  /// the way to its target in a single step, which reads as a teleport.
  static const double maxStepSeconds = 1.0 / 30.0;

  /// Frame timestamp of the most recent paint, or null before the first one.
  Duration? _lastPaintFrame;

  /// Frame timestamp of the most recent layout, or null before the first one
  /// (also null for layout driven outside of a frame).
  Duration? _lastLayoutFrame;

  /// Whether a paint has happened since [recordLayout] last formed a verdict.
  /// Starts true so the very first layout isn't mistaken for a hidden one.
  bool _paintedSinceLastLayout = true;

  bool _isLastLayoutUnseen = false;

  /// Whether this render object has painted at least one frame.
  ///
  /// Before the first paint there is no visual state to animate away from, so
  /// the first layout should adopt its positions instantly.
  bool get hasEverPainted => _lastPaintFrame != null;

  /// Whether the layout immediately preceding the current one never reached
  /// the screen. Read during `performLayout`, after [recordLayout].
  bool get isLastLayoutUnseen => _isLastLayoutUnseen;

  /// Call once at the top of `performLayout`, before spring targets are set.
  void recordLayout() {
    final frame = _currentFrameTimeStampOrNull();
    if (frame != null && frame == _lastLayoutFrame) {
      // Second (or third...) layout pass within one frame: a continuation of
      // the pass this frame already accounted for, so keep its verdict.
      return;
    }
    _isLastLayoutUnseen = _lastLayoutFrame != null && !_paintedSinceLastLayout;
    _lastLayoutFrame = frame;
    _paintedSinceLastLayout = false;
  }

  /// Call once at the top of `paint`, before ticking springs.
  ///
  /// [SpringFrameTick.snapToTargets] is true when this is the first paint
  /// after a layout that happened in an *earlier* frame: nothing was drawn in
  /// that frame, so the render object moved while it was hidden and the
  /// springs must adopt their targets instead of animating to them.
  SpringFrameTick recordPaint() {
    final frame = SchedulerBinding.instance.currentFrameTimeStamp;
    final elapsedSeconds = _lastPaintFrame == null
        ? 0.0
        : (frame - _lastPaintFrame!).inMicroseconds /
              Duration.microsecondsPerSecond;
    final snapToTargets =
        !_paintedSinceLastLayout &&
        _lastLayoutFrame != null &&
        _lastLayoutFrame != frame;

    _lastPaintFrame = frame;
    _paintedSinceLastLayout = true;
    _isLastLayoutUnseen = false;

    return SpringFrameTick(
      dt: elapsedSeconds.clamp(0.0, maxStepSeconds),
      snapToTargets: snapToTargets,
    );
  }

  /// `currentFrameTimeStamp` asserts when read outside of a frame, and layout
  /// can be driven by hand (tests calling `layout()` directly, tooling). Null
  /// means "no frame context", which [recordLayout] treats conservatively:
  /// no verdict, so springs keep animating exactly as they do today.
  static Duration? _currentFrameTimeStampOrNull() {
    final binding = SchedulerBinding.instance;
    return binding.schedulerPhase == .idle
        ? null
        : binding.currentFrameTimeStamp;
  }
}
