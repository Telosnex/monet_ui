import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'package:monet_ui/widgets/monet_perf_debug_switches.dart';

/// [object]'s paint transform to its view: the matrix that
/// `object.getTransformTo(null)` returns, bit for bit.
///
/// Call it only from [object]'s paint. In a frame's paint phase, the
/// transforms of some ancestors are kept until the frame ends (see
/// [PaintTransformMemo]). Leaves that share ancestors then walk only to the
/// nearest kept ancestor, not to the root. Outside a frame's paint phase,
/// this is `getTransformTo(null)`.
Matrix4 paintTransformToView(RenderObject object) =>
    PaintTransformMemo._toView(object);

/// [object]'s paint transform to its view, as the current
/// [MonetPerfDebugSwitches.paintPlacement] finds it. Call it only from
/// [object]'s paint.
///
/// - [PaintPlacement.measured]: [paintTransformToView].
/// - [PaintPlacement.trustLayout]: a uniform [declaredScale], no
///   translation. Layout is trusted to put [object]'s origin on the
///   device-pixel grid, so only its own coordinates set the pixel phase.
Matrix4 paintTransformForPlacement(
  RenderObject object, {
  double declaredScale = 1,
}) {
  switch (MonetPerfDebugSwitches.paintPlacement) {
    case .measured:
      return paintTransformToView(object);
    case .trustLayout:
      PaintTransformMemo._trusted++;
      return Matrix4.diagonal3Values(declaredScale, declaredScale, 1);
  }
}

/// Ancestor paint transforms, kept for the rest of one frame's paint phase.
///
/// The paint phase does not change layout or paint transforms. Thus a
/// transform that is read in it stays correct until the frame ends. Each
/// frame starts empty, because scrolling, layout and transform changes
/// occur between paint phases. A picture that a repaint boundary keeps
/// without a repaint keeps the transform of its last paint, as with
/// `getTransformTo`.
///
/// A walk keeps the transform of each ancestor whose depth is a multiple of
/// [_stride]. A later leaf thus walks fewer than [_stride] levels past the
/// deepest ancestor that it shares with an earlier leaf of the frame.
/// (`RenderObject.depth` can skip values after a move in the tree. Then
/// some walks are longer.) Repaint boundaries are not kept for their own
/// sake: a call of `isRepaintBoundary` on each level cost more than it
/// saved (`test/perf/paint_transform_memo_perf_test.dart`).
///
/// Each kept transform continues the root-first product of
/// `getTransformTo`, in the same order. The result is identical, not an
/// approximation.
abstract final class PaintTransformMemo {
  static const _stride = 8;

  static final _kept = HashMap<RenderObject, Matrix4>.identity();
  static bool _frameOpen = false;

  /// The nodes of the current walk, reused between walks.
  static var _path = List<RenderObject?>.filled(128, null);
  static bool _walking = false;

  static int _calls = 0;
  static int _direct = 0;
  static int _steps = 0;
  static int _frames = 0;
  static int _trusted = 0;

  /// Process-wide counters for the paint cache logger.
  ///
  /// - `calls`: calls of [paintTransformToView].
  /// - `direct`: calls that `getTransformTo` answered, outside a frame's
  ///   paint phase or with the memo off.
  /// - `steps`: ancestor transforms that the other calls applied. A walk to
  ///   the root applies one for each ancestor below the root's child.
  /// - `frames`: frames with at least one call that used the memo.
  /// - `trusted`: paints that trusted layout and did not walk
  ///   ([PaintPlacement.trustLayout]).
  static Map<String, int> snapshot() => {
    'transform.trusted': _trusted,
    'transform.calls': _calls,
    'transform.direct': _direct,
    'transform.steps': _steps,
    'transform.frames': _frames,
  };

  /// Kept transforms in the current frame, for tests.
  @visibleForTesting
  static int get debugKeptCount => _kept.length;

  /// Forgets the kept transforms, as the end of a frame does. A benchmark
  /// can then time the walks of many frames in one paint phase.
  @visibleForTesting
  static void debugForgetFrame() => _kept.clear();

  static Matrix4 _toView(RenderObject object) {
    _calls++;
    final root = object.owner?.rootNode;
    if (root == null ||
        _walking ||
        !MonetPerfDebugSwitches.memoizePaintTransforms ||
        SchedulerBinding.instance.schedulerPhase != .persistentCallbacks) {
      _direct++;
      return object.getTransformTo(null);
    }
    assert(
      object.owner!.debugDoingPaint,
      'paintTransformToView is only for paint. Before the paint phase, '
      'layout can still move ancestors, and a kept transform goes stale.',
    );
    if (identical(object, root)) return Matrix4.identity();
    _openFrame();
    _walking = true;
    try {
      return _walk(object, root);
    } finally {
      _walking = false;
    }
  }

  static Matrix4 _walk(RenderObject object, RenderObject root) {
    // [object], then each ancestor up to the nearest one whose transform is
    // known. The root's child has the identity: the root's own transform
    // maps to physical pixels, and `getTransformTo(null)` leaves it out.
    var path = _path;
    var length = 0;
    var node = object;
    Matrix4 transform;
    while (true) {
      final parent = node.parent;
      if (parent == null) {
        path.fillRange(0, length, null);
        // Not below the owner's root. getTransformTo reports the error.
        return object.getTransformTo(null);
      }
      if (identical(parent, root)) {
        transform = Matrix4.identity();
        break;
      }
      if (length == path.length) {
        path = List.filled(2 * length, null)..setAll(0, path);
        _path = path;
      }
      path[length++] = node;
      if (parent.depth % _stride == 0) {
        final kept = _kept[parent];
        if (kept != null) {
          transform = kept.clone();
          break;
        }
      }
      node = parent;
    }

    _steps += length;
    for (var i = length - 1; i >= 0; i--) {
      final child = path[i]!;
      path[i] = null;
      child.parent!.applyPaintTransform(child, transform);
      // [object] paints once per frame, so its own transform is not kept.
      if (i > 0 && child.depth % _stride == 0) {
        _kept[child] = transform.clone();
      }
    }
    return transform;
  }

  static void _openFrame() {
    if (_frameOpen) return;
    _frameOpen = true;
    _frames++;
    // Post-frame callbacks added during the paint phase run in this frame.
    SchedulerBinding.instance.addPostFrameCallback(
      _closeFrame,
      debugLabel: 'PaintTransformMemo',
    );
  }

  static void _closeFrame(Duration _) {
    _kept.clear();
    _frameOpen = false;
  }
}
