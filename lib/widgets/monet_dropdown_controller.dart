import 'package:material_ui/material_ui.dart';

/// Controller for MonetDropdown that allows external widgets to show the dropdown
class MonetDropdownController {
  void Function()? _show;
  void Function(Offset)? _showFromPosition;
  bool _isAttached = false;

  /// Whether the controller is currently attached to a dropdown widget
  bool get isAttached => _isAttached;

  void _setShowCallback(void Function() show) {
    _show = show;
    _isAttached = true;
  }

  void _setShowFromPositionCallback(void Function(Offset) showFromPosition) {
    _showFromPosition = showFromPosition;
  }

  /// Show the dropdown menu
  void show() {
    if (!_isAttached) {
      debugPrint(
        'MonetDropdownController: Cannot show dropdown - controller not attached',
      );
      return;
    }
    _show?.call();
  }

  /// Show the dropdown menu from a specific position
  void showFromPosition(Offset position) {
    if (!_isAttached) {
      debugPrint(
        'MonetDropdownController: Cannot show dropdown - controller not attached',
      );
      return;
    }
    _showFromPosition?.call(position);
  }

  /// Dispose of the controller and clear callbacks
  void dispose() {
    _show = null;
    _showFromPosition = null;
    _isAttached = false;
  }

  /// Internal method to attach the controller to a dropdown
  void attach(void Function() show, void Function(Offset) showFromPosition) {
    _setShowCallback(show);
    _setShowFromPositionCallback(showFromPosition);
  }

  /// Internal method to detach the controller
  void detach() {
    dispose();
  }
}
