import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'package:monet_ui/third_party/flutter/deferred_scrollable_selection_container_delegate.dart';

/// Installs our scroll-aware delegate below Flutter's private delegate, but
/// registers directly with the original parent. See TelosnexScrollBehavior.
///
/// The callback context must belong to the current ScrollableState. In that
/// context, Scrollable.maybeOf would return the OUTER scrollable instead.
Widget buildDeferredScrollableSelection(BuildContext context, Widget child) {
  final registrar = SelectionContainer.maybeOf(context);
  if (registrar == null) return child;
  // A behavior can also be called directly outside Scrollable (for example by
  // a decoration test). Leave those calls alone. This is not a tree search.
  if (context is! StatefulElement || context.state is! ScrollableState) {
    return child;
  }
  final state = context.state as ScrollableState;
  return DeferredScrollableSelection(
    key: ObjectKey(state),
    registrar: registrar,
    scrollable: state,
    child: child,
  );
}

class DeferredScrollableSelection extends StatefulWidget {
  const DeferredScrollableSelection({
    super.key,
    required this.registrar,
    required this.scrollable,
    required this.child,
  });

  final SelectionRegistrar registrar;
  final ScrollableState scrollable;
  final Widget child;

  @override
  State<DeferredScrollableSelection> createState() =>
      _DeferredScrollableSelectionState();
}

class _DeferredScrollableSelectionState
    extends State<DeferredScrollableSelection> {
  late final _delegate = DeferredScrollableSelectionContainerDelegate(
    state: widget.scrollable,
    position: widget.scrollable.position,
  );

  @override
  void didUpdateWidget(DeferredScrollableSelection oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(identical(oldWidget.scrollable, widget.scrollable));
    // Physics/controller changes can replace the position without replacing
    // ScrollableState. The delegate must stop listening to the old position.
    _delegate.position = widget.scrollable.position;
  }

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SelectionContainer(
    registrar: widget.registrar,
    delegate: _delegate,
    child: widget.child,
  );
}
