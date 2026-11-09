/// At-most-one-selection coordination for the app's selection regions.
///
/// # The problem
///
/// Every `SelectionArea` creates its own `SelectableRegion`, and a region owns
/// exactly one selection that only its own gestures can clear. The framework
/// never clears region A when the user starts selecting in region B (only web
/// clears on focus loss). The app intentionally uses multiple regions — the
/// conversation-level markdown region, plus isolated regions for tool headers,
/// JSON tables, search tiles, and mods (isolation keeps Select All and copy
/// serialization scoped to the widget). The cost was that two regions could
/// show two highlighted selections at once: select part of a tool header, then
/// drag-select a message, and the header stays highlighted. Flutter's own
/// DevTools exhibits the same artifact for the same reason.
///
/// # The fix
///
/// Native platforms and browsers maintain one visible text selection per
/// window: pressing the pointer to begin a new interaction dissolves the old
/// highlight. This file enforces that invariant. Each selection region is
/// created through [ExclusiveSelectionArea] or a subclass of
/// [ExclusiveSelectionMemberState] that wraps another selection area. Members
/// register with a process-wide registry and wrap their region in a
/// translucent [Listener]. On pointer-down inside a member, every *other*
/// member's selection is cleared immediately — at press time, not first-drag
/// time, so there is no transient dual highlight.
///
/// Members nest (a tool header's region sits inside the conversation region).
/// Pointer events dispatch deepest-first, so the innermost member under the
/// press claims it and outer members skip their own clear pass; the enclosing
/// region therefore cannot clear the selection the user is about to make, and
/// the press still clears the enclosing region's old selection.
library;

import 'package:flutter/rendering.dart'
    show ClearSelectionEvent, Selectable, SelectedContent, SelectionRegistrar;
import 'package:monet_ui/widgets/deferred_selection_order.dart';
import 'package:monet_ui/widgets/selection_interaction_scope.dart';
import 'package:pixel_snap_fork/material.dart';

/// A Material [SelectionArea] that participates in app-wide
/// exclusive-selection coordination.
///
/// Drop-in replacement for [SelectionArea]; only the parameters the app uses
/// are surfaced.
class ExclusiveSelectionArea extends StatefulWidget {
  const ExclusiveSelectionArea({
    super.key,
    this.focusNode,
    this.contextMenuBuilder,
    this.onSelectionChanged,
    required this.child,
  });

  final FocusNode? focusNode;

  /// Defaults to [SelectionArea]'s default (the adaptive selectable-region
  /// toolbar) when null.
  final SelectableRegionContextMenuBuilder? contextMenuBuilder;

  final ValueChanged<SelectedContent?>? onSelectionChanged;
  final Widget child;

  @override
  State<ExclusiveSelectionArea> createState() => _ExclusiveSelectionAreaState();
}

class _ExclusiveSelectionAreaState
    extends ExclusiveSelectionMemberState<ExclusiveSelectionArea> {
  final GlobalKey<SelectionAreaState> _areaKey =
      GlobalKey<SelectionAreaState>();

  /// Mirrors [SelectionArea]'s private default, which cannot be referenced
  /// once an explicit `contextMenuBuilder` argument is passed.
  static Widget _defaultContextMenuBuilder(
    BuildContext context,
    SelectableRegionState selectableRegionState,
  ) {
    return AdaptiveTextSelectionToolbar.selectableRegion(
      selectableRegionState: selectableRegionState,
    );
  }

  @override
  ValueChanged<SelectedContent?>? get downstreamSelectionChanged =>
      widget.onSelectionChanged;

  @override
  void clearMemberSelection() {
    final area = _areaKey.currentState;
    if (area == null) return;
    area.selectableRegion
      ..hideToolbar()
      ..clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    return buildWithInteractionPolicy(
      context,
      widget.child,
      (child) => SelectionArea(
        key: _areaKey,
        focusNode: widget.focusNode,
        contextMenuBuilder:
            widget.contextMenuBuilder ?? _defaultContextMenuBuilder,
        onSelectionChanged: handleSelectionChanged,
        child: SelectionContainer(
          delegate: rootSelectionDelegate,
          child: child,
        ),
      ),
    );
  }
}

/// Shared membership behavior: registry lifetime, selection tracking, and the
/// pointer-down listener that triggers clearing of other members.
///
/// Extend this to make another selection area exclusive: build it with
/// [buildWithInteractionPolicy], pass [handleSelectionChanged] as its
/// `onSelectionChanged`, wrap its child in a [SelectionContainer] using
/// [rootSelectionDelegate], and clear it in [clearMemberSelection].
abstract class ExclusiveSelectionMemberState<T extends StatefulWidget>
    extends State<T> {
  /// Owns direct text and child groups, not all descendant text. Scrollables
  /// receive separate deferred, scroll-aware delegates from the app's scroll
  /// behavior. A wrapping region can flatten this delegate to preserve leaf
  /// copy metadata. Selection scope and exclusive-region coordination do not
  /// change.
  @protected
  final rootSelectionDelegate = DeferredSelectionContainerDelegate();

  /// Tracked so that clearing other members is a no-op walk for the common
  /// case (most members have no selection). Kept accurate by
  /// [handleSelectionChanged] regardless of how the selection was cleared
  /// (own gestures, Escape, registry).
  bool _hasSelection = false;

  @protected
  ValueChanged<SelectedContent?>? get downstreamSelectionChanged;

  /// Clears this member's region. Only called while [_hasSelection].
  @protected
  void clearMemberSelection();

  @override
  void initState() {
    super.initState();
    _ExclusiveSelectionRegistry.register(this);
  }

  @override
  void dispose() {
    _ExclusiveSelectionRegistry.unregister(this);
    rootSelectionDelegate.dispose();
    super.dispose();
  }

  @protected
  void handleSelectionChanged(SelectedContent? content) {
    _hasSelection = content != null;
    downstreamSelectionChanged?.call(content);
  }

  void _clearIfSelected() {
    if (!mounted || !_hasSelection) return;
    _hasSelection = false;
    clearMemberSelection();
  }

  GlobalKey? _switchableContentKey;

  @protected
  Widget buildWithInteractionPolicy(
    BuildContext context,
    Widget child,
    Widget Function(Widget child) buildArea,
  ) {
    final enabled = SelectionInteractionScope.maybeOf(context);
    // No extra key or widget in ordinary app regions. Once opted in, retain
    // the key even if the subtree moves outside the scope entirely.
    if (enabled != null) _switchableContentKey ??= GlobalKey();
    final key = _switchableContentKey;
    final content = key == null ? child : KeyedSubtree(key: key, child: child);
    if (enabled == false) {
      // This delegate outlives the region while its body moves into preview.
      // Reset its cached edges and idle ordering before it receives new content.
      rootSelectionDelegate.dispatchSelectionEvent(const ClearSelectionEvent());
      _hasSelection = false;
      // Keep an inert registrar rather than advertising "no selection owner":
      // MarkdownColumn uses that distinction to choose its wrapper ancestry.
      // It must not remount its body merely because the preview became active.
      return SelectionRegistrarScope(
        registrar: const _PreviewSelectionRegistrar(),
        child: content,
      );
    }
    return wrapWithCoordination(buildArea(content));
  }

  @protected
  Widget wrapWithCoordination(Widget area) {
    return Listener(
      behavior: .translucent,
      onPointerDown: (event) =>
          _ExclusiveSelectionRegistry.handlePointerDown(this, event),
      child: area,
    );
  }
}

abstract final class _ExclusiveSelectionRegistry {
  static final Set<ExclusiveSelectionMemberState<StatefulWidget>> _members = {};

  /// The physical press currently being dispatched, identified by the
  /// untransformed root event. Nested members receive the same press
  /// (translucent listeners), innermost first; only the innermost claims it.
  static PointerEvent? _claimedPress;

  static void register(ExclusiveSelectionMemberState<StatefulWidget> member) {
    _members.add(member);
  }

  static void unregister(ExclusiveSelectionMemberState<StatefulWidget> member) {
    _members.remove(member);
  }

  static void handlePointerDown(
    ExclusiveSelectionMemberState<StatefulWidget> member,
    PointerDownEvent event,
  ) {
    // Listeners along the hit-test path may receive transformed copies of the
    // same press; `original` recovers the shared root event.
    final press = event.original ?? event;
    if (identical(_claimedPress, press)) return;
    _claimedPress = press;
    // Copy: clearing can synchronously notify listeners that rebuild.
    for (final other in List.of(_members)) {
      if (identical(other, member)) continue;
      other._clearIfSelected();
    }
  }
}

/// No listeners, retained selectables, gestures, or leader layers. A selectable
/// arriving from the open Space may still hold a highlight/handle link; clear
/// those when it joins the passive preview, before that frame paints.
class _PreviewSelectionRegistrar implements SelectionRegistrar {
  const _PreviewSelectionRegistrar();

  @override
  void add(Selectable selectable) {
    selectable
      ..pushHandleLayers(null, null)
      ..dispatchSelectionEvent(const ClearSelectionEvent());
  }

  // No membership was retained by add, so there is nothing to release.
  @override
  // ignore: no-empty-block
  void remove(Selectable selectable) {}
}
