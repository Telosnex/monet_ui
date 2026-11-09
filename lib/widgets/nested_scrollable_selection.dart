/// Support for hiding a nested [Scrollable] from the selection system while
/// keeping its contents selectable.
///
/// # The bug this works around
///
/// [Scrollable] silently opts into selection whenever a selection registrar is
/// above it: it wraps its subtree in a `SelectionContainer` whose delegate
/// (`_ScrollableSelectionContainerDelegate`) auto-scrolls during drag-select
/// and remaps selection edges into scroll-origin space.
///
/// Nesting two of those delegates trips an upstream framework bug. That
/// nesting is the norm here, not an edge case: the conversation's
/// `SelectionArea` wraps the conversation `ListView`, and every code fence,
/// table, mermaid diagram, and chip row inside a message adds a horizontal
/// scroll view underneath it.
///
/// 1. A selection edge lands outside the outer (vertical) scrollable, so the
///    outer delegate records `_selectionStartsInScrollable = false` and
///    *snaps* the out-of-bounds edge to its own top-left corner before
///    forwarding the event to its children.
/// 2. The inner (horizontal) scroller occupying that top-left corner receives
///    a position inside its own bounds and concludes - incorrectly - that the
///    selection started inside it, arming its auto-scroller
///    (`_selectionStartsInScrollable = true`).
/// 3. Later the same drag leaves the outer scrollable past its bottom/right
///    edge. This time the outer delegate forwards `Offset.infinite` instead of
///    snapping. The inner delegate feeds that straight into
///    [EdgeDraggingAutoScroller.startAutoScrollIfNecessary], where
///    `Rect.fromCenter(center: Offset.infinite, width: 0, height: 0)` has
///    `NaN` dimensions, and `NaN >= NaN` is false:
///
///    ```text
///    'package:flutter/src/widgets/scrollable_helpers.dart': Failed assertion:
///    line 241 pos 7: '(globalRect.size.width + precisionErrorTolerance) >=
///    transformedDragTarget.size.width && ...': Drag target size is larger
///    than scrollable size, which may cause bouncing
///    ```
///
/// Tracked upstream as https://github.com/flutter/flutter/issues/181169 (open;
/// the `isFinite` guard in flutter/flutter#183079 was closed without landing
/// because it papers over the wrong `_selectionStartsInScrollable` rather than
/// fixing it). In release builds the assert is compiled out and `_scroll()`
/// no-ops, because every comparison against `NaN` is false - so this is
/// debug/profile-only noise, but it surfaces as an uncaught zone error that
/// buries real ones.
///
/// # The workaround
///
/// Hide the ambient registrar from the inner [Scrollable] so it never builds
/// its selection delegate, then re-expose that same registrar to the scroll
/// view's content so the content's [Selectable]s register directly with the
/// ancestor container:
///
/// ```dart
/// final registrar = detachedSelectionRegistrarFor(context);
/// if (registrar != null) {
///   content = SelectionRegistrarScope(registrar: registrar, child: content);
/// }
/// Widget scrollable = Scrollable(/* ... */);
/// if (registrar != null) {
///   scrollable = SelectionContainer.disabled(child: scrollable);
/// }
/// ```
///
/// [SingleChildScrollView2] does exactly this, so most callers get it for
/// free.
///
/// Cost: drag-selecting past the edge of that inner scroller no longer
/// auto-scrolls it. Selection, copy, and the selection highlight are
/// unchanged.
///
/// Only safe for scroll views that lay out their whole child (i.e.
/// [SingleChildScrollView]-shaped ones). The scrollable's selection delegate
/// is also what keeps lazily built children in sync with an active selection,
/// so a `ListView`/sliver must keep it.
library;

import 'package:flutter/rendering.dart' show SelectionRegistrar;
import 'package:flutter/widgets.dart';

/// The registrar an inner scroll view should re-host its content on, or null
/// if this scroll view is not the nested case and should keep its own
/// selection delegate.
///
/// Returns non-null only when both are true:
///  * there is a selection registrar above [context], and
///  * the nearest ancestor `Scrollable` is itself selection-aware, i.e. it
///    built the selection container that would become this scroll view's
///    parent container. That is precisely the nested pair described above.
///
/// A top-level scroll view under a `SelectionArea` therefore keeps the
/// framework behavior, including auto-scroll while drag-selecting.
SelectionRegistrar? detachedSelectionRegistrarFor(BuildContext context) {
  final registrar = SelectionContainer.maybeOf(context);
  if (registrar == null) {
    return null;
  }

  final ancestorScrollable = Scrollable.maybeOf(context);
  if (ancestorScrollable == null) {
    return null;
  }

  // Read (without depending on) the registrar visible *above* the ancestor
  // Scrollable. If it has one, that Scrollable registered a selection
  // container of its own, and ours would nest inside it.
  final ancestorScope = ancestorScrollable.context
      .getInheritedWidgetOfExactType<SelectionRegistrarScope>();
  if (ancestorScope?.registrar == null) {
    return null;
  }

  return registrar;
}
