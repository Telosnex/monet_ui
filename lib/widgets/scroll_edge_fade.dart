// ignore_for_file: prefer-single-widget-per-file

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/widgets.dart' show ScrollController;

import 'package:pixel_snap_fork/material.dart' hide ScrollController;

import 'package:monet_ui/widgets/padding.dart';

/// Signature for [ScrollEdgeFade.builder]: build the scroll view with
/// [controller], which the fade owns and tracks.
typedef ScrollEdgeFadeBuilder = Widget Function(
  BuildContext context,
  ScrollController controller,
);

/// Fades the edges of a scroll view, but only the edges that have content
/// scrolled past them.
///
/// The fade follows the scroll view's [ScrollController], so callers never
/// track scroll offsets themselves:
/// - [ScrollEdgeFade.new] takes the controller already given to the scroll
///   view inside its child.
/// - [ScrollEdgeFade.builder] owns a controller and hands it to the builder,
///   which must give it to the scroll view.
///
/// When no edge needs fading, the child paints directly. A mask always
/// paints the child into an offscreen layer and blends it back, which
/// visibly softens text. Rows at rest, with nothing scrolled past the
/// leading edge and everything fitting, would pay that for no visible fade.
///
/// The mask is applied by the render object, not by switching between
/// `ShaderMask(child: x)` and `x`. Switching changes the tree's shape, which
/// re-inflates the subtree and resets its state, including the scroll
/// position.
class ScrollEdgeFade extends StatefulWidget {
  final ScrollController? _controller;
  final Widget? _child;
  final ScrollEdgeFadeBuilder? _builder;

  /// Length of the fade at the edge where scrolling starts: the left edge for
  /// a left-to-right horizontal scroll view, the top for a vertical one. Zero
  /// disables it.
  final double leading;

  /// Length of the fade at the edge where scrolling ends. Zero disables it.
  final double trailing;

  /// Fades [child], whose scroll view uses [controller].
  const ScrollEdgeFade({
    super.key,
    required ScrollController this._controller,
    this.leading = HorizontalPadding.amount,
    this.trailing = HorizontalPadding.amount,
    required Widget this._child,
  }) : _builder = null;

  /// Fades the scroll view from [builder], which must use the controller it
  /// is given.
  const ScrollEdgeFade.builder({
    super.key,
    this.leading = HorizontalPadding.amount,
    this.trailing = HorizontalPadding.amount,
    required ScrollEdgeFadeBuilder this._builder,
  }) : _controller = null,
       _child = null;

  @override
  State<ScrollEdgeFade> createState() => _ScrollEdgeFadeState();
}

class _ScrollEdgeFadeState extends State<ScrollEdgeFade> {
  ScrollController? _ownedController;

  ScrollController get _controller =>
      widget._controller ?? (_ownedController ??= .new());

  @override
  void didUpdateWidget(ScrollEdgeFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget._controller != null && _ownedController != null) {
      // Switched to a caller's controller; the owned one is no longer used.
      final owned = _ownedController!;
      _ownedController = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => owned.dispose());
    }
  }

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return NotificationListener<ScrollMetricsNotification>(
      // Content and viewport size changes move the edges without moving the
      // offset, so the controller does not report them.
      onNotification: (notification) {
        final renderObject = context.findRenderObject();
        if (renderObject is _RenderScrollEdgeFade) {
          renderObject.syncEdges();
        }
        return false;
      },
      child: _ScrollEdgeFadeMask(
        controller: controller,
        leading: widget.leading,
        trailing: widget.trailing,
        child: widget._builder?.call(context, controller) ?? widget._child,
      ),
    );
  }
}

/// Which edges [renderObject], a [ScrollEdgeFade]'s render object, fades.
@visibleForTesting
ScrollEdgeFades debugScrollEdgeFades(RenderObject renderObject) {
  final fade = renderObject as _RenderScrollEdgeFade;
  return ScrollEdgeFades(
    leading: fade._fadeLeading && fade._leading > 0,
    trailing: fade._fadeTrailing && fade._trailing > 0,
  );
}

class _ScrollEdgeFadeMask extends SingleChildRenderObjectWidget {
  final ScrollController controller;
  final double leading;
  final double trailing;

  const _ScrollEdgeFadeMask({
    required this.controller,
    required this.leading,
    required this.trailing,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScrollEdgeFade(
        controller: controller,
        leading: leading,
        trailing: trailing,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderScrollEdgeFade renderObject,
  ) {
    renderObject
      ..controller = controller
      ..leading = leading
      ..trailing = trailing;
  }
}

class _RenderScrollEdgeFade extends RenderProxyBox {
  /// Content past an edge must exceed this before the edge fades, so
  /// rounding noise at rest does not switch the mask on.
  static const _edgeThreshold = 0.5;

  ScrollController _controller;
  double _leading;
  double _trailing;
  bool _fadeLeading = false;
  bool _fadeTrailing = false;

  /// Read when edges sync, so painting never needs a live controller.
  AxisDirection _axisDirection = .right;

  _RenderScrollEdgeFade({
    required this._controller,
    required this._leading,
    required this._trailing,
  });

  @override
  ShaderMaskLayer? get layer => super.layer as ShaderMaskLayer?;

  set controller(ScrollController value) {
    if (identical(value, _controller)) return;
    if (attached) _controller.removeListener(syncEdges);
    _controller = value;
    if (attached) _controller.addListener(syncEdges);
    syncEdges();
  }

  set leading(double value) {
    if (value == _leading) return;
    _leading = value;
    _markMaskChanged();
  }

  set trailing(double value) {
    if (value == _trailing) return;
    _trailing = value;
    _markMaskChanged();
  }

  bool get _masking =>
      (_fadeLeading && _leading > 0) || (_fadeTrailing && _trailing > 0);

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(syncEdges);
    // The scroll view lays out after this attaches; read its edges then.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached) syncEdges();
    });
  }

  @override
  void detach() {
    _controller.removeListener(syncEdges);
    super.detach();
  }

  /// Rereads which edges have content past them.
  void syncEdges() {
    var fadeLeading = false;
    var fadeTrailing = false;
    if (_controller.hasClients && _controller.positions.length == 1) {
      final position = _controller.position;
      if (position.hasContentDimensions && position.hasPixels) {
        fadeLeading = position.extentBefore > _edgeThreshold;
        fadeTrailing = position.extentAfter > _edgeThreshold;
        if (position.axisDirection != _axisDirection) {
          _axisDirection = position.axisDirection;
          if (fadeLeading || fadeTrailing) _markMaskChanged();
        }
      }
    }
    if (fadeLeading == _fadeLeading && fadeTrailing == _fadeTrailing) return;
    _fadeLeading = fadeLeading;
    _fadeTrailing = fadeTrailing;
    _markMaskChanged();
  }

  void _markMaskChanged() {
    if (!attached) return;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => child != null && _masking;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) {
      layer = null;
      return;
    }
    if (!_masking) {
      layer = null;
      context.paintChild(child, offset);
      return;
    }
    final rect = offset & size;
    layer ??= ShaderMaskLayer();
    layer!
      ..shader = _gradient().createShader(Offset.zero & size)
      ..maskRect = rect
      ..blendMode = .dstIn;
    context.pushLayer(layer!, super.paint, offset);
  }

  /// Opaque in the middle, transparent at each faded edge.
  LinearGradient _gradient() {
    final extent = axisDirectionToAxis(_axisDirection) == .horizontal
        ? size.width
        : size.height;
    final leadingStop = _fadeLeading && extent > 0
        ? (_leading / extent).clamp(0.0, 1.0)
        : 0.0;
    // Fades longer than the view meet rather than cross.
    final trailingStop = _fadeTrailing && extent > 0
        ? (1 - _trailing / extent).clamp(leadingStop, 1.0)
        : 1.0;

    // Gradients run from the edge where scrolling starts.
    final Alignment begin = switch (_axisDirection) {
      .right => .centerLeft,
      .left => .centerRight,
      .down => .topCenter,
      .up => .bottomCenter,
    };
    final end = -begin;
    return LinearGradient(
      begin: begin,
      end: end,
      colors: [
        _fadeLeading ? Colors.transparent : Colors.white,
        Colors.white,
        Colors.white,
        _fadeTrailing ? Colors.transparent : Colors.white,
      ],
      stops: [0.0, leadingStop, trailingStop, 1.0],
    );
  }
}

/// Which edges a [ScrollEdgeFade] fades.
@visibleForTesting
final class const ScrollEdgeFades({
  required final bool leading,
  required final bool trailing,
}) {
  @override
  bool operator ==(Object other) =>
      other is ScrollEdgeFades &&
      other.leading == leading &&
      other.trailing == trailing;

  @override
  int get hashCode => Object.hash(leading, trailing);

  @override
  String toString() =>
      'ScrollEdgeFades(leading: $leading, trailing: $trailing)';
}
