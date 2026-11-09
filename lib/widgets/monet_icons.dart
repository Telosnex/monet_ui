import 'package:pixel_snap_fork/material.dart' show Icons;

/// Icons that Monet controls draw themselves. Apps that need the same icon
/// elsewhere can refer to these, so the two stay the same.
abstract final class MonetIcons {
  /// Goes back.
  static const back = Icons.arrow_back_ios_new;

  /// Done, or copied.
  static const check = Icons.check;
  static const chevronForward = Icons.chevron_right;

  /// Closes or dismisses.
  static const close = Icons.cancel;
  static const copy = Icons.copy;

  /// A handle that reorders an item.
  static const dragToMove = Icons.drag_indicator;
  static const expandLess = Icons.expand_less;
  static const expandMore = Icons.expand_more;

  /// Adds an item to a list.
  static const add = Icons.add_circle_outline;

  /// Opens a menu.
  static const menu = Icons.more_horiz;

  /// Content that is hidden or locked.
  static const lock = Icons.lock_outline;

  /// Removes an item from a list.
  static const remove = Icons.remove_circle_outline;

  /// Opens a tooltip or more information.
  static const info = Icons.info_outline;
}
