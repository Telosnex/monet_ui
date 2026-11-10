import 'package:flutter/widgets.dart';

extension TextEditingControllerExtensions on TextEditingController {
  /// Safely updates the text and selection of the controller.
  /// It ensures selection offsets are within bounds and schedules the update appropriately.
  void safelyUpdateText(String newText) {
    // Schedule the update in a microtask to avoid disrupting the current frame.
    Future.microtask(() {
      final int textLength = newText.length;

      // Get current selection offsets.
      int baseOffset = value.selection.baseOffset;
      int extentOffset = value.selection.extentOffset;

      // Clamp offsets to [0, textLength].
      baseOffset = baseOffset.clamp(0, textLength);
      extentOffset = extentOffset.clamp(0, textLength);

      // Ensure baseOffset <= extentOffset.
      if (baseOffset > extentOffset) {
        final int temp = baseOffset;
        baseOffset = extentOffset;
        extentOffset = temp;
      }

      final TextSelection correctedSelection = TextSelection(
        baseOffset: baseOffset,
        extentOffset: extentOffset,
      );

      // Update the controller's value.
      value = TextEditingValue(
        text: newText,
        selection: correctedSelection,
        composing: .empty,
      );
    });
  }
}
