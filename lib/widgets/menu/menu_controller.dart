import 'package:material_ui/material_ui.dart';

/// Controller for MenuButton that allows external widgets to show the menu
class MenuButtonController {
  void Function()? _show;
  void Function(Offset)? _showFromPosition;

  void setShowCallback(void Function() show) {
    _show = show;
  }

  void setShowFromPositionCallback(void Function(Offset) showFromPosition) {
    _showFromPosition = showFromPosition;
  }

  void show() {
    _show?.call();
  }

  void showFromPosition(Offset position) {
    _showFromPosition?.call(position);
  }

  void dispose() {
    _show = null;
    _showFromPosition = null;
  }
}
