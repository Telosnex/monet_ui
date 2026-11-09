import 'package:flutter/widgets.dart';

/// Neutralizes ancestor paint-transform scale for selection context menus.
///
/// The framework mounts `SelectionArea`'s context menu (the faux-platform
/// cut/copy/paste toolbar) in the root overlay, but positions it with a
/// `CompositedTransformFollower` whose leader lives *inside* the selectable
/// subtree. A `FollowerLayer` inherits the leader's full paint transform, so
/// any ancestor paint-time scale — `ScaleUpLayout` on the Mod screen — scales
/// the toolbar up with the mod content. System chrome should render at UI
/// scale, not mod-content scale.
///
/// Geometry: for leader screen-origin `O` and uniform ancestor scale `s`, the
/// follower paints toolbar-local point `p` at `O + s·(p − O)` (the framework's
/// `-renderBox.localToGlobal(Offset.zero)` link offset cancels the
/// translation, not the scale). The toolbar lays out against global anchor
/// coordinates expecting `screen = p`, so both its size and its anchor
/// placement are wrong by `s` around `O`. Wrapping the toolbar in the inverse
/// scale about `O` — `translate(O)·scale(1/s)·translate(−O)` — restores
/// `screen = p` exactly: native-sized toolbar, correctly anchored.
///
/// A no-op (returns [child] untransformed) when no ancestor scale is present,
/// so it is safe to install unconditionally.
class UnscaledSelectionToolbar extends StatelessWidget {
  /// State of the [SelectableRegion] that is showing this toolbar; its render
  /// box is the follower link's leader, which defines `O` and `s` above.
  final SelectableRegionState selectableRegionState;

  final Widget child;

  const UnscaledSelectionToolbar({
    super.key,
    required this.selectableRegionState,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final renderObject = selectableRegionState.context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return child;

    final transform = renderObject.getTransformTo(null);
    final scale = transform.getMaxScaleOnAxis();
    // Guard against fp noise from ancestor matrices; identity is the common
    // case (mods at natural width, all non-mod selection areas).
    if ((scale - 1.0).abs() < 0.001 || scale <= 0) return child;

    final origin = MatrixUtils.transformPoint(transform, .zero);
    final inverse = Matrix4.translationValues(origin.dx, origin.dy, 0)
      ..scaleByDouble(1 / scale, 1 / scale, 1, 1)
      ..translateByDouble(-origin.dx, -origin.dy, 0, 1);
    return Transform(transform: inverse, child: child);
  }
}
