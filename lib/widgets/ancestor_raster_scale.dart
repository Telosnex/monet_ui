// ignore_for_file: prefer-single-widget-per-file

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Diagnostics for the legacy render-root raster-scale query.
///
/// Production cached-raster paint must not call [ancestorRasterScaleFor]. This
/// counter lets focused tests and profiles enforce that invariant while the
/// query remains available as a debug validation oracle.
class AncestorRasterScaleDiagnostics {
  const AncestorRasterScaleDiagnostics._();

  @visibleForTesting
  static int queryCount = 0;

  /// Enables the one-shot declared-versus-observed validator in focused tests.
  /// Ordinary debug paint leaves this false so profiling does not reintroduce
  /// the root walk this feature removes.
  @visibleForTesting
  static bool validateDeclarations = false;

  @visibleForTesting
  static void reset() {
    queryCount = 0;
    validateDeclarations = false;
  }
}

/// Samples the effective ancestor paint scale for debug validation.
///
/// This performs an O(depth) render-root walk. Cached text and icon paint must
/// consume [AncestorRasterScaleSignal.quantizedScale] instead of calling this
/// function. It remains available temporarily to detect an under-declared
/// scale while producers migrate to [AncestorRasterScaleScope].
double ancestorRasterScaleFor(RenderObject renderObject) {
  if (kDebugMode) {
    AncestorRasterScaleDiagnostics.queryCount++;
  }
  return quantizeAncestorRasterScale(
    renderObject.getTransformTo(null).getMaxScaleOnAxis(),
  );
}

/// Debug-only migration guard for an under-declared scale producer.
void debugValidateDeclaredAncestorRasterScale(
  RenderObject renderObject,
  double declaredScale,
) {
  assert(() {
    if (!AncestorRasterScaleDiagnostics.validateDeclarations) return true;
    final observedScale = ancestorRasterScaleFor(renderObject);
    if (observedScale > declaredScale) {
      throw FlutterError.fromParts([
        ErrorSummary('Ancestor raster scale was under-declared.'),
        ErrorDescription(
          '${renderObject.runtimeType} declared $declaredScale but its '
          'render-root transform requires $observedScale.',
        ),
        ErrorHint(
          'Publish the paint scale with AncestorRasterScaleScope, or use an '
          'existing direct-paint path for this transformed subtree.',
        ),
        DiagnosticsProperty('consumer', renderObject),
      ]);
    }
    return true;
  }());
}

/// Publishes a local paint scale and composes it with an ancestor signal.
///
/// Public listeners are notified only when the composed quantized bucket
/// changes. Descendant signals also observe raw composed-scale changes so
/// nested scales are quantized after composition rather than multiplying
/// already-quantized parent buckets.
class AncestorRasterScaleSignal extends ChangeNotifier {
  AncestorRasterScaleSignal({double localScale = 1.0})
    : _localScale = _validScale(localScale) {
    _recompute(notify: false);
  }

  AncestorRasterScaleSignal._identity()
    : _isIdentity = true,
      _localScale = 1.0,
      _effectiveScale = 1.0,
      _quantizedScale = 1.0;

  /// Shared no-op signal used outside an explicit scale scope.
  static final AncestorRasterScaleSignal identity =
      AncestorRasterScaleSignal._identity();

  AncestorRasterScaleSignal? _parent;
  double _localScale;
  double _effectiveScale = 1.0;
  double _quantizedScale = 1.0;
  int _revision = 0;
  bool _isIdentity = false;
  final Set<VoidCallback> _scaleDependents = <VoidCallback>{};

  /// Exact composed scale before raster-bucket quantization.
  double get effectiveScale => _effectiveScale;

  double get quantizedScale => _quantizedScale;
  int get revision => _revision;
  bool get isIdentity => _isIdentity;

  @visibleForTesting
  bool get debugHasListeners => hasListeners;

  /// Reparents this local scale beneath [parent].
  void updateParentSignal(AncestorRasterScaleSignal parent) {
    _checkMutable();
    final nextParent = parent.isIdentity ? null : parent;
    if (identical(_parent, nextParent)) return;
    assert(() {
      AncestorRasterScaleSignal? ancestor = nextParent;
      while (ancestor != null) {
        if (identical(ancestor, this)) {
          throw FlutterError(
            'Ancestor raster-scale signals cannot form cycles.',
          );
        }
        ancestor = ancestor._parent;
      }
      return true;
    }());
    _parent?._removeScaleDependent(_handleParentScaleChanged);
    _parent = nextParent;
    nextParent?._addScaleDependent(_handleParentScaleChanged);
    _recompute();
  }

  /// Updates this producer's local paint scale.
  void updateLocalScale(double scale) {
    _checkMutable();
    final validScale = _validScale(scale);
    if (_localScale == validScale) return;
    _localScale = validScale;
    _recompute();
  }

  void _handleParentScaleChanged() {
    _recompute();
  }

  void _recompute({bool notify = true}) {
    final nextEffectiveScale = (_parent?._effectiveScale ?? 1.0) * _localScale;
    final nextQuantizedScale = quantizeAncestorRasterScale(nextEffectiveScale);
    final effectiveChanged = nextEffectiveScale != _effectiveScale;
    final bucketChanged = nextQuantizedScale != _quantizedScale;
    if (!effectiveChanged && !bucketChanged) return;

    _effectiveScale = nextEffectiveScale;
    _quantizedScale = nextQuantizedScale;
    if (effectiveChanged) {
      for (final dependent in List.of(_scaleDependents)) {
        dependent();
      }
    }

    // Expose a revision only for changes published after construction. The
    // initial value is revision zero, which makes consumer bookkeeping clear.
    if (bucketChanged && notify) {
      _revision++;
      notifyListeners();
    }
  }

  void _addScaleDependent(VoidCallback callback) {
    if (_isIdentity) return;
    _scaleDependents.add(callback);
  }

  void _removeScaleDependent(VoidCallback callback) {
    if (_isIdentity) return;
    _scaleDependents.remove(callback);
  }

  void _checkMutable() {
    if (_isIdentity) {
      throw StateError(
        'The identity ancestor raster-scale signal is immutable.',
      );
    }
  }

  static double _validScale(double scale) {
    assert(
      scale.isFinite && scale > 0,
      'Ancestor raster scale must be finite and greater than zero.',
    );
    return scale.isFinite && scale > 0 ? scale : 1.0;
  }

  @override
  void dispose() {
    if (_isIdentity) return;
    _parent?._removeScaleDependent(_handleParentScaleChanged);
    _parent = null;
    _scaleDependents.clear();
    super.dispose();
  }
}

/// Exposes a stable [AncestorRasterScaleSignal] identity to descendants.
///
/// Numeric scale updates notify render objects directly through the signal;
/// they do not rebuild widgets through inherited notification.
class AncestorRasterScaleScope extends InheritedWidget {
  const AncestorRasterScaleScope({
    super.key,
    required this.signal,
    required super.child,
  });

  final AncestorRasterScaleSignal signal;

  static AncestorRasterScaleSignal of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<AncestorRasterScaleScope>()
            ?.signal ??
        .identity;
  }

  @override
  bool updateShouldNotify(AncestorRasterScaleScope oldWidget) =>
      !identical(signal, oldWidget.signal);
}

/// Declares a fixed local raster scale around an arbitrary paint transform.
///
/// App-owned render objects should normally own their signal and publish their
/// computed scale directly. This widget is useful for framework [Transform]
/// sites and focused tests where no custom render object exists to publish it.
class AncestorRasterScale extends StatefulWidget {
  const AncestorRasterScale({
    super.key,
    required this.scale,
    required this.child,
  });

  final double scale;
  final Widget child;

  @override
  State<AncestorRasterScale> createState() => _AncestorRasterScaleState();
}

class _AncestorRasterScaleState extends State<AncestorRasterScale> {
  late final AncestorRasterScaleSignal _signal = AncestorRasterScaleSignal(
    localScale: widget.scale,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _signal.updateParentSignal(AncestorRasterScaleScope.of(context));
  }

  @override
  void didUpdateWidget(AncestorRasterScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    _signal.updateLocalScale(widget.scale);
  }

  @override
  Widget build(BuildContext context) {
    return AncestorRasterScaleScope(signal: _signal, child: widget.child);
  }

  @override
  void dispose() {
    _signal.dispose();
    super.dispose();
  }
}

/// Quantizes an ancestor paint scale into coarse raster buckets.
///
/// - `<= 1` (identity, fp noise, scaled-*down* previews) returns exactly 1.0
///   so unscaled content keeps byte-identical DPR rasters (golden stability)
///   and downscaled contexts never thrash the cache.
/// - Upscales snap to the next 0.25 step, so a continuously animated ancestor
///   scale causes a bounded handful of re-rasterizations instead of one per
///   frame. Rounding *up* keeps the mask at least as dense as the screen
///   needs; src/dst rect mapping stays exact at any bucket.
/// - Capped at 4× to bound mask memory (masks grow with the square of this).
double quantizeAncestorRasterScale(double scale) {
  if (scale <= 1.001) return 1.0;
  const step = 0.25;
  const maxScale = 4.0;
  if (scale >= maxScale) return maxScale;
  return (scale / step).ceilToDouble() * step;
}
