import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Avoids screen transforms during idle selectable registration.
///
/// Flutter sorts additions even without a selection. It sorts the complete list
/// again before the first non-clear selection event. The idle order can therefore
/// be arbitrary, but the real comparator must be restored BEFORE that event.
/// Keep it active until ClearSelectionEvent, including collapsed selections and
/// selections whose lazy children temporarily leave the viewport.
///
/// This relies on MultiSelectableSelectionContainerDelegate's event-time sort.
/// Tests must verify that contract after Flutter upgrades. Do not use this mixin
/// with a delegate that consumes child order before a selection event.
/// The remaining selection, ordering, and content methods stay unchanged.
mixin DeferredSelectionOrder on MultiSelectableSelectionContainerDelegate {
  bool _selectionActive = false;
  int _debugScreenOrderComparisons = 0;

  /// Debug-only diagnostic. No counter work is done in release/profile builds.
  @visibleForTesting
  int get debugScreenOrderComparisons => _debugScreenOrderComparisons;

  @override
  Comparator<Selectable> get compareOrder => _compare;

  int _compare(Selectable a, Selectable b) {
    if (!_selectionActive) return 0;
    assert(() {
      _debugScreenOrderComparisons++;
      return true;
    }());
    return super.compareOrder(a, b);
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    if (event is! ClearSelectionEvent) _selectionActive = true;
    try {
      return super.dispatchSelectionEvent(event);
    } finally {
      if (event is ClearSelectionEvent) _selectionActive = false;
    }
  }
}

/// Root grouping for an exclusive selection region. Scrollables need their own
/// scroll-aware delegate; see TelosnexScrollBehavior for the two-level design.
class DeferredSelectionContainerDelegate
    extends StaticSelectionContainerDelegate
    with DeferredSelectionOrder {}
